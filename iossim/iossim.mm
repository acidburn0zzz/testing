// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Foundation/Foundation.h>
#include <asl.h>
#include <libgen.h>
#include <stdarg.h>
#include <stdio.h>

// An executable (iossim) that runs an app in the iOS Simulator.
// Run 'iossim -h' for usage information.
//
// For best results, the iOS Simulator application should not be running when
// iossim is invoked.
//
// Headers for the iPhoneSimulatorRemoteClient framework used in this tool are
// generated by class-dump, via GYP.
// (class-dump is available at http://www.codethecode.com/projects/class-dump/)
//
// However, there are some forward declarations required to get things to
// compile. Also, the DTiPhoneSimulatorSessionDelegate protocol is referenced
// by the iPhoneSimulatorRemoteClient framework, but not defined in the object
// file, so it must be defined here before importing the generated
// iPhoneSimulatorRemoteClient.h file.

@class DTiPhoneSimulatorApplicationSpecifier;
@class DTiPhoneSimulatorSession;
@class DTiPhoneSimulatorSessionConfig;
@class DTiPhoneSimulatorSystemRoot;

@protocol DTiPhoneSimulatorSessionDelegate
- (void)session:(DTiPhoneSimulatorSession*)session
    didEndWithError:(NSError*)error;
- (void)session:(DTiPhoneSimulatorSession*)session
       didStart:(BOOL)started
      withError:(NSError*)error;
@end

#import "iPhoneSimulatorRemoteClient.h"

// An undocumented system log key included in messages from launchd. The value
// is the PID of the process the message is about (as opposed to launchd's PID).
#define ASL_KEY_REF_PID "RefPID"

namespace {

// Name of environment variables that control the user's home directory in the
// simulator.
const char* const kUserHomeEnvVariable = "CFFIXED_USER_HOME";
const char* const kHomeEnvVariable = "HOME";

// Device family codes for iPhone and iPad.
const int kIPhoneFamily = 1;
const int kIPadFamily = 2;

// Max number of seconds to wait for the simulator session to start.
// This timeout must allow time to start up iOS Simulator, install the app
// and perform any other black magic that is encoded in the
// iPhoneSimulatorRemoteClient framework to kick things off. Normal start up
// time is only a couple seconds but machine load, disk caches, etc., can all
// affect startup time in the wild so the timeout needs to be fairly generous.
// If this timeout occurs iossim will likely exit with non-zero status; the
// exception being if the app is invoked and completes execution before the
// session is started (this case is handled in session:didStart:withError).
const NSTimeInterval kDefaultSessionStartTimeoutSeconds = 30;

// While the simulated app is running, its stdout is redirected to a file which
// is polled by iossim and written to iossim's stdout using the following
// polling interval.
const NSTimeInterval kOutputPollIntervalSeconds = 0.1;

// The path within the developer dir of the private Simulator frameworks.
NSString* const kSimulatorFrameworkRelativePath =
    @"Platforms/iPhoneSimulator.platform/Developer/Library/PrivateFrameworks/"
    @"iPhoneSimulatorRemoteClient.framework";
NSString* const kDevToolsFoundationRelativePath =
    @"../OtherFrameworks/DevToolsFoundation.framework";
NSString* const kSimulatorRelativePath =
    @"Platforms/iPhoneSimulator.platform/Developer/Applications/"
    @"iPhone Simulator.app";

// Simulator Error String Key. This can be found by looking in the Simulator's
// Localizable.strings files.
NSString* const kSimulatorAppQuitErrorKey = @"The simulated application quit.";

const char* gToolName = "iossim";

void LogError(NSString* format, ...) {
  va_list list;
  va_start(list, format);

  NSString* message =
      [[[NSString alloc] initWithFormat:format arguments:list] autorelease];

  fprintf(stderr, "%s: ERROR: %s\n", gToolName, [message UTF8String]);
  fflush(stderr);

  va_end(list);
}

void LogWarning(NSString* format, ...) {
  va_list list;
  va_start(list, format);

  NSString* message =
      [[[NSString alloc] initWithFormat:format arguments:list] autorelease];

  fprintf(stderr, "%s: WARNING: %s\n", gToolName, [message UTF8String]);
  fflush(stderr);

  va_end(list);
}

}  // namespace

// A delegate that is called when the simulated app is started or ended in the
// simulator.
@interface SimulatorDelegate : NSObject <DTiPhoneSimulatorSessionDelegate> {
 @private
  NSString* stdioPath_;
  NSString* developerDir_;
  NSThread* outputThread_;
  NSBundle* simulatorBundle_;
  BOOL appRunning_;
}
@end

// An implementation that copies the simulated app's stdio to stdout of this
// executable. While it would be nice to get stdout and stderr independently
// from iOS Simulator, issues like I/O buffering and interleaved output
// between iOS Simulator and the app would cause iossim to display things out
// of order here. Printing all output to a single file keeps the order correct.
// Instances of this classe should be initialized with the location of the
// simulated app's output file. When the simulated app starts, a thread is
// started which handles copying data from the simulated app's output file to
// the stdout of this executable.
@implementation SimulatorDelegate

// Specifies the file locations of the simulated app's stdout and stderr.
- (SimulatorDelegate*)initWithStdioPath:(NSString*)stdioPath
                           developerDir:(NSString*)developerDir {
  self = [super init];
  if (self) {
    stdioPath_ = [stdioPath copy];
    developerDir_ = [developerDir copy];
  }

  return self;
}

- (void)dealloc {
  [stdioPath_ release];
  [developerDir_ release];
  [simulatorBundle_ release];
  [super dealloc];
}

// Reads data from the simulated app's output and writes it to stdout. This
// method blocks, so it should be called in a separate thread. The iOS
// Simulator takes a file path for the simulated app's stdout and stderr, but
// this path isn't always available (e.g. when the stdout is Xcode's build
// window). As a workaround, iossim creates a temp file to hold output, which
// this method reads and copies to stdout.
- (void)tailOutput {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  // Copy data to stdout/stderr while the app is running.
  NSFileHandle* simio = [NSFileHandle fileHandleForReadingAtPath:stdioPath_];
  NSFileHandle* standardOutput = [NSFileHandle fileHandleWithStandardOutput];
  while (appRunning_) {
    NSAutoreleasePool* innerPool = [[NSAutoreleasePool alloc] init];
    [standardOutput writeData:[simio readDataToEndOfFile]];
    [NSThread sleepForTimeInterval:kOutputPollIntervalSeconds];
    [innerPool drain];
  }

  // Once the app is no longer running, copy any data that was written during
  // the last sleep cycle.
  [standardOutput writeData:[simio readDataToEndOfFile]];

  [pool drain];
}

// Fetches a localized error string from the Simulator.
- (NSString *)localizedSimulatorErrorString:(NSString*)stringKey {
  // Lazy load of the simulator bundle.
  if (simulatorBundle_ == nil) {
    NSString* simulatorPath = [developerDir_
        stringByAppendingPathComponent:kSimulatorRelativePath];
    simulatorBundle_ = [NSBundle bundleWithPath:simulatorPath];
  }
  NSString *localizedStr =
      [simulatorBundle_ localizedStringForKey:stringKey
                                        value:nil
                                        table:nil];
  if ([localizedStr length])
    return localizedStr;
  // Failed to get a value, follow Cocoa conventions and use the key as the
  // string.
  return stringKey;
}

- (void)session:(DTiPhoneSimulatorSession*)session
       didStart:(BOOL)started
      withError:(NSError*)error {
  if (!started) {
    // If the test executes very quickly (<30ms), the SimulatorDelegate may not
    // get the initial session:started:withError: message indicating successful
    // startup of the simulated app. Instead the delegate will get a
    // session:started:withError: message after the timeout has elapsed. To
    // account for this case, check if the simulated app's stdio file was
    // ever created and if it exists dump it to stdout and return success.
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:stdioPath_ isDirectory:NO]) {
      appRunning_ = NO;
      [self tailOutput];
      // Note that exiting in this state leaves a process running
      // (e.g. /.../iPhoneSimulator4.3.sdk/usr/libexec/installd -t 30) that will
      // prevent future simulator sessions from being started for 30 seconds
      // unless the iOS Simulator application is killed altogether.
      [self session:session didEndWithError:nil];

      // session:didEndWithError should not return (because it exits) so
      // the execution path should never get here.
      exit(EXIT_FAILURE);
    }

    LogError(@"Simulator failed to start: \"%@\" (%@:%ld)",
             [error localizedDescription],
             [error domain], static_cast<long int>([error code]));
    exit(EXIT_FAILURE);
  }

  // Start a thread to write contents of outputPath to stdout.
  appRunning_ = YES;
  outputThread_ = [[NSThread alloc] initWithTarget:self
                                          selector:@selector(tailOutput)
                                            object:nil];
  [outputThread_ start];
}

- (void)session:(DTiPhoneSimulatorSession*)session
    didEndWithError:(NSError*)error {
  appRunning_ = NO;
  // Wait for the output thread to finish copying data to stdout.
  if (outputThread_) {
    while (![outputThread_ isFinished]) {
      [NSThread sleepForTimeInterval:kOutputPollIntervalSeconds];
    }
    [outputThread_ release];
    outputThread_ = nil;
  }

  if (error) {
    // There appears to be a race condition where sometimes the simulator
    // framework will end with an error, but the error is that the simulated
    // app cleanly shut down; try to trap this error and don't fail the
    // simulator run.
    NSString* localizedDescription = [error localizedDescription];
    NSString* ignorableErrorStr =
        [self localizedSimulatorErrorString:kSimulatorAppQuitErrorKey];
    if ([ignorableErrorStr isEqual:localizedDescription]) {
      LogWarning(@"Ignoring that Simulator ended with: \"%@\" (%@:%ld)",
                 localizedDescription, [error domain],
                 static_cast<long int>([error code]));
    } else {
      LogError(@"Simulator ended with error: \"%@\" (%@:%ld)",
               localizedDescription, [error domain],
               static_cast<long int>([error code]));
      exit(EXIT_FAILURE);
    }
  }

  // Check if the simulated app exited abnormally by looking for system log
  // messages from launchd that refer to the simulated app's PID. Limit query
  // to messages in the last minute since PIDs are cyclical.
  aslmsg query = asl_new(ASL_TYPE_QUERY);
  asl_set_query(query, ASL_KEY_SENDER, "launchd",
                ASL_QUERY_OP_EQUAL | ASL_QUERY_OP_SUBSTRING);
  asl_set_query(query, ASL_KEY_REF_PID,
                [[[session simulatedApplicationPID] stringValue] UTF8String],
                ASL_QUERY_OP_EQUAL);
  asl_set_query(query, ASL_KEY_TIME, "-1m", ASL_QUERY_OP_GREATER_EQUAL);

  // Log any messages found.
  aslresponse response = asl_search(NULL, query);
  BOOL entryFound = NO;
  aslmsg entry;
  while ((entry = aslresponse_next(response)) != NULL) {
    entryFound = YES;
    LogWarning(@"Console message: %s", asl_get(entry, ASL_KEY_MSG));
  }

  // launchd only sends messages if the process crashed or exits with a
  // non-zero status, so if the query returned any results iossim should exit
  // with non-zero status.
  if (entryFound) {
    LogError(@"Simulated app crashed or exited with non-zero status");
    exit(EXIT_FAILURE);
  }
  exit(EXIT_SUCCESS);
}
@end

namespace {

// Finds the developer dir via xcode-select or the DEVELOPER_DIR environment
// variable.
NSString* FindDeveloperDir() {
  // Check the env first.
  NSDictionary* env = [[NSProcessInfo processInfo] environment];
  NSString* developerDir = [env objectForKey:@"DEVELOPER_DIR"];
  if ([developerDir length] > 0)
    return developerDir;

  // Go look for it via xcode-select.
  NSTask* xcodeSelectTask = [[[NSTask alloc] init] autorelease];
  [xcodeSelectTask setLaunchPath:@"/usr/bin/xcode-select"];
  [xcodeSelectTask setArguments:[NSArray arrayWithObject:@"-print-path"]];

  NSPipe* outputPipe = [NSPipe pipe];
  [xcodeSelectTask setStandardOutput:outputPipe];
  NSFileHandle* outputFile = [outputPipe fileHandleForReading];

  [xcodeSelectTask launch];
  NSData* outputData = [outputFile readDataToEndOfFile];
  [xcodeSelectTask terminate];

  NSString* output =
      [[[NSString alloc] initWithData:outputData
                             encoding:NSUTF8StringEncoding] autorelease];
  output = [output stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([output length] == 0)
    output = nil;
  return output;
}

// Loads the Simulator framework from the given developer dir.
NSBundle* LoadSimulatorFramework(NSString* developerDir) {
  // The Simulator framework depends on some of the other Xcode private
  // frameworks; manually load them first so everything can be linked up.
  NSString* devToolsFoundationPath = [developerDir
      stringByAppendingPathComponent:kDevToolsFoundationRelativePath];
  NSBundle* devToolsFoundationBundle =
      [NSBundle bundleWithPath:devToolsFoundationPath];
  if (![devToolsFoundationBundle load])
    return nil;
  NSString* simBundlePath = [developerDir
      stringByAppendingPathComponent:kSimulatorFrameworkRelativePath];
  NSBundle* simBundle = [NSBundle bundleWithPath:simBundlePath];
  if (![simBundle load])
    return nil;
  return simBundle;
}

// Helper to find a class by name and die if it isn't found.
Class FindClassByName(NSString* nameOfClass) {
  Class theClass = NSClassFromString(nameOfClass);
  if (!theClass) {
    LogError(@"Failed to find class %@ at runtime.", nameOfClass);
    exit(EXIT_FAILURE);
  }
  return theClass;
}

// Converts the given app path to an application spec, which requires an
// absolute path.
DTiPhoneSimulatorApplicationSpecifier* BuildAppSpec(NSString* appPath) {
  Class applicationSpecifierClass =
      FindClassByName(@"DTiPhoneSimulatorApplicationSpecifier");
  if (![appPath isAbsolutePath]) {
    NSString* cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    appPath = [cwd stringByAppendingPathComponent:appPath];
  }
  appPath = [appPath stringByStandardizingPath];
  return [applicationSpecifierClass specifierWithApplicationPath:appPath];
}

// Returns the system root for the given SDK version. If sdkVersion is nil, the
// default system root is returned.  Will return nil if the sdkVersion is not
// valid.
DTiPhoneSimulatorSystemRoot* BuildSystemRoot(NSString* sdkVersion) {
  Class systemRootClass = FindClassByName(@"DTiPhoneSimulatorSystemRoot");
  DTiPhoneSimulatorSystemRoot* systemRoot = [systemRootClass defaultRoot];
  if (sdkVersion)
    systemRoot = [systemRootClass rootWithSDKVersion:sdkVersion];

  return systemRoot;
}

// Builds a config object for starting the specified app.
DTiPhoneSimulatorSessionConfig* BuildSessionConfig(
    DTiPhoneSimulatorApplicationSpecifier* appSpec,
    DTiPhoneSimulatorSystemRoot* systemRoot,
    NSString* stdoutPath,
    NSString* stderrPath,
    NSArray* appArgs,
    NSDictionary* appEnv,
    NSNumber* deviceFamily) {
  Class sessionConfigClass = FindClassByName(@"DTiPhoneSimulatorSessionConfig");
  DTiPhoneSimulatorSessionConfig* sessionConfig =
      [[[sessionConfigClass alloc] init] autorelease];
  sessionConfig.applicationToSimulateOnStart = appSpec;
  sessionConfig.simulatedSystemRoot = systemRoot;
  sessionConfig.localizedClientName = @"chromium";
  sessionConfig.simulatedApplicationStdErrPath = stderrPath;
  sessionConfig.simulatedApplicationStdOutPath = stdoutPath;
  sessionConfig.simulatedApplicationLaunchArgs = appArgs;
  sessionConfig.simulatedApplicationLaunchEnvironment = appEnv;
  sessionConfig.simulatedDeviceFamily = deviceFamily;
  return sessionConfig;
}

// Builds a simulator session that will use the given delegate.
DTiPhoneSimulatorSession* BuildSession(SimulatorDelegate* delegate) {
  Class sessionClass = FindClassByName(@"DTiPhoneSimulatorSession");
  DTiPhoneSimulatorSession* session =
      [[[sessionClass alloc] init] autorelease];
  session.delegate = delegate;
  return session;
}

// Creates a temporary directory with a unique name based on the provided
// template. The template should not contain any path separators and be suffixed
// with X's, which will be substituted with a unique alphanumeric string (see
// 'man mkdtemp' for details). The directory will be created as a subdirectory
// of NSTemporaryDirectory(). For example, if dirNameTemplate is 'test-XXX',
// this method would return something like '/path/to/tempdir/test-3n2'.
//
// Returns the absolute path of the newly-created directory, or nill if unable
// to create a unique directory.
NSString* CreateTempDirectory(NSString* dirNameTemplate) {
  NSString* fullPathTemplate =
      [NSTemporaryDirectory() stringByAppendingPathComponent:dirNameTemplate];
  char* fullPath = mkdtemp(const_cast<char*>([fullPathTemplate UTF8String]));
  if (fullPath == NULL)
    return nil;

  return [NSString stringWithUTF8String:fullPath];
}

// Creates the necessary directory structure under the given user home directory
// path.
// Returns YES if successful, NO if unable to create the directories.
BOOL CreateHomeDirSubDirs(NSString* userHomePath) {
  NSFileManager* fileManager = [NSFileManager defaultManager];

  // Create user home and subdirectories.
  NSArray* subDirsToCreate = [NSArray arrayWithObjects:
                              @"Documents",
                              @"Library/Caches",
                              nil];
  for (NSString* subDir in subDirsToCreate) {
    NSString* path = [userHomePath stringByAppendingPathComponent:subDir];
    NSError* error;
    if (![fileManager createDirectoryAtPath:path
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&error]) {
      LogError(@"Unable to create directory: %@. Error: %@",
               path, [error localizedDescription]);
      return NO;
    }
  }

  return YES;
}

// Creates the necessary directory structure under the given user home directory
// path, then sets the path in the appropriate environment variable.
// Returns YES if successful, NO if unable to create or initialize the given
// directory.
BOOL InitializeSimulatorUserHome(NSString* userHomePath) {
  if (!CreateHomeDirSubDirs(userHomePath))
    return NO;

  // Update the environment to use the specified directory as the user home
  // directory.
  // Note: the third param of setenv specifies whether or not to overwrite the
  // variable's value if it has already been set.
  if ((setenv(kUserHomeEnvVariable, [userHomePath UTF8String], YES) == -1) ||
      (setenv(kHomeEnvVariable, [userHomePath UTF8String], YES) == -1)) {
    LogError(@"Unable to set environment variables for home directory.");
    return NO;
  }

  return YES;
}

// Prints the usage information to stderr.
void PrintUsage() {
  fprintf(stderr, "Usage: iossim [-d device] [-s sdkVersion] [-u homeDir] "
      "[-e envKey=value]* [-t startupTimeout] <appPath> [<appArgs>]\n"
      "  where <appPath> is the path to the .app directory and appArgs are any"
      " arguments to send the simulated app.\n"
      "\n"
      "Options:\n"
      "  -d  Specifies the device (either 'iPhone' or 'iPad')."
      " Defaults to 'iPhone'.\n"
      "  -s  Specifies the SDK version to use (e.g '4.3')."
      " Will use system default if not specified.\n"
      "  -u  Specifies a user home directory for the simulator."
      " Will create a new directory if not specified.\n"
      "  -e  Specifies an environment key=value pair that will be"
      " set in the simulated application's environment.\n"
      "  -t  Specifies the session startup timeout (in seconds)."
      " Defaults to %d.\n",
      static_cast<int>(kDefaultSessionStartTimeoutSeconds));
}

}  // namespace

int main(int argc, char* const argv[]) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  // basename() may modify the passed in string and it returns a pointer to an
  // internal buffer. Give it a copy to modify, and copy what it returns.
  char* worker = strdup(argv[0]);
  char* toolName = basename(worker);
  if (toolName != NULL) {
    toolName = strdup(toolName);
    if (toolName != NULL)
      gToolName = toolName;
  }
  if (worker != NULL)
    free(worker);

  NSString* appPath = nil;
  NSString* appName = nil;
  NSString* sdkVersion = nil;
  NSString* deviceName = @"iPhone";
  NSString* simHomePath = nil;
  NSMutableArray* appArgs = [NSMutableArray array];
  NSMutableDictionary* appEnv = [NSMutableDictionary dictionary];
  NSTimeInterval sessionStartTimeout = kDefaultSessionStartTimeoutSeconds;

  // Parse the optional arguments
  int c;
  while ((c = getopt(argc, argv, "hs:d:u:e:t:")) != -1) {
    switch (c) {
      case 's':
        sdkVersion = [NSString stringWithUTF8String:optarg];
        break;
      case 'd':
        deviceName = [NSString stringWithUTF8String:optarg];
        break;
      case 'u':
        simHomePath = [[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:optarg length:strlen(optarg)];
        break;
      case 'e': {
        NSString* envLine = [NSString stringWithUTF8String:optarg];
        NSRange range = [envLine rangeOfString:@"="];
        if (range.location == NSNotFound) {
          LogError(@"Invalid key=value argument for -e.");
          PrintUsage();
          exit(EXIT_FAILURE);
        }
        NSString* key = [envLine substringToIndex:range.location];
        NSString* value = [envLine substringFromIndex:(range.location + 1)];
        [appEnv setObject:value forKey:key];
      }
        break;
      case 't': {
        int timeout = atoi(optarg);
        if (timeout > 0) {
          sessionStartTimeout = static_cast<NSTimeInterval>(timeout);
        } else {
          LogError(@"Invalid startup timeout (%s).", optarg);
          PrintUsage();
          exit(EXIT_FAILURE);
        }
      }
        break;
      case 'h':
        PrintUsage();
        exit(EXIT_SUCCESS);
      default:
        PrintUsage();
        exit(EXIT_FAILURE);
    }
  }

  // There should be at least one arg left, specifying the app path. Any
  // additional args are passed as arguments to the app.
  if (optind < argc) {
    appPath = [[NSFileManager defaultManager]
        stringWithFileSystemRepresentation:argv[optind]
                                    length:strlen(argv[optind])];
    appName = [appPath lastPathComponent];
    while (++optind < argc) {
      [appArgs addObject:[NSString stringWithUTF8String:argv[optind]]];
    }
  } else {
    LogError(@"Unable to parse command line arguments.");
    PrintUsage();
    exit(EXIT_FAILURE);
  }

  NSString* developerDir = FindDeveloperDir();
  if (!developerDir) {
    LogError(@"Unable to find developer directory.");
    exit(EXIT_FAILURE);
  }

  NSBundle* simulatorFramework = LoadSimulatorFramework(developerDir);
  if (!simulatorFramework) {
    LogError(@"Failed to load the Simulator Framework.");
    exit(EXIT_FAILURE);
  }

  // Make sure the app path provided is legit.
  DTiPhoneSimulatorApplicationSpecifier* appSpec = BuildAppSpec(appPath);
  if (!appSpec) {
    LogError(@"Invalid app path: %@", appPath);
    exit(EXIT_FAILURE);
  }

  // Make sure the SDK path provided is legit (or nil).
  DTiPhoneSimulatorSystemRoot* systemRoot = BuildSystemRoot(sdkVersion);
  if (!systemRoot) {
    LogError(@"Invalid SDK version: %@", sdkVersion);
    exit(EXIT_FAILURE);
  }

  // Get the paths for stdout and stderr so the simulated app's output will show
  // up in the caller's stdout/stderr.
  NSString* outputDir = CreateTempDirectory(@"iossim-XXXXXX");
  NSString* stdioPath = [outputDir stringByAppendingPathComponent:@"stdio.txt"];

  // Make sure the device name is legit.
  NSNumber* deviceFamily = nil;
  if (!deviceName ||
      [@"iPhone" caseInsensitiveCompare:deviceName] == NSOrderedSame) {
    deviceFamily = [NSNumber numberWithInt:kIPhoneFamily];
  } else if ([@"iPad" caseInsensitiveCompare:deviceName] == NSOrderedSame) {
    deviceFamily = [NSNumber numberWithInt:kIPadFamily];
  } else {
    LogError(@"Invalid device name: %@", deviceName);
    exit(EXIT_FAILURE);
  }

  // Set up the user home directory for the simulator
  if (!simHomePath) {
    NSString* dirNameTemplate =
        [NSString stringWithFormat:@"iossim-%@-%@-XXXXXX", appName, deviceName];
    simHomePath = CreateTempDirectory(dirNameTemplate);
    if (!simHomePath) {
      LogError(@"Unable to create unique directory for template %@",
               dirNameTemplate);
      exit(EXIT_FAILURE);
    }
  }
  if (!InitializeSimulatorUserHome(simHomePath)) {
    LogError(@"Unable to initialize home directory for simulator: %@",
             simHomePath);
    exit(EXIT_FAILURE);
  }

  // Create the config and simulator session.
  DTiPhoneSimulatorSessionConfig* config = BuildSessionConfig(appSpec,
                                                              systemRoot,
                                                              stdioPath,
                                                              stdioPath,
                                                              appArgs,
                                                              appEnv,
                                                              deviceFamily);
  SimulatorDelegate* delegate =
      [[[SimulatorDelegate alloc] initWithStdioPath:stdioPath
                                       developerDir:developerDir] autorelease];
  DTiPhoneSimulatorSession* session = BuildSession(delegate);

  // Start the simulator session.
  NSError* error;
  BOOL started = [session requestStartWithConfig:config
                                         timeout:sessionStartTimeout
                                           error:&error];

  // Spin the runtime indefinitely. When the delegate gets the message that the
  // app has quit it will exit this program.
  if (started) {
    [[NSRunLoop mainRunLoop] run];
  } else {
    LogError(@"Simulator failed request to start:  \"%@\" (%@:%ld)",
             [error localizedDescription],
             [error domain], static_cast<long int>([error code]));
  }

  // Note that this code is only executed if the simulator fails to start
  // because once the main run loop is started, only the delegate calling
  // exit() will end the program.
  [pool drain];
  return EXIT_FAILURE;
}
