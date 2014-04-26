<?
session_start();
$db_user = "calvin69_gkapur";
$db_password = "12345";

if (!isset($user_to_add_un))
    $user_to_add_un = $HTTP_COOKIE_VARS['user_to_add_un'];
if (!isset($user_to_add_pw))
    $user_to_add_pw = $HTTP_COOKIE_VARS['user_to_add_pw'];

if (@mysql_connect('localhost:3306', $db_user, $db_password) and 
    	@mysql_select_db("calvin69_affiliates")) {

    $result0 = @mysql_query("SELECT * FROM user_table WHERE user_name='$user_to_add_un' AND user_pass='$user_to_add_pw'");
    $row0    = @mysql_fetch_row($result0);
    if ($user_to_add_un && ! $row0[0]) 
    {
    	header("Location: http://$HTTP_HOST/login.php?url=".urlencode($HTTP_HOST.$REQUEST_URI));
     	exit;
    }
} else {
    echo 'Cannot connect to database';
    exit;
}

if ($ID)
    $I = $ID;

if ($I == "") {
    if (isset($HTTP_COOKIE_VARS['member_id'])) 
        $I = $HTTP_COOKIE_VARS['member_id'];
//    else 
//	$I = "12345";
}

include_once('refer.php');

$Searchword = ExtractKeywords($_SERVER["HTTP_REFERER"]);
$Keyword = ExtractKeywords($_SERVER["HTTP_REFERER"]);
$BACK    = History($_SERVER["HTTP_REFERER"]);
//$URL     = urlencode($_SERVER["HTTP_REFERER"]);
//list(,,$URL,) = split("/","http://www.google.com/scripts/search?keywords",4);
list(,,$URL,) = split("/",$_SERVER["HTTP_REFERER"],4);
$Keyword = str_replace("\"","\\\"",$Keyword);
$Searchword = str_replace("\"","",$Searchword);

if (!isset($I) || $I == "")
	$I = '12345';

//if (@mysql_connect('207.142.133.184:3306', $db_user, $db_password) and 
if (@mysql_connect('localhost:3306', $db_user, $db_password) and 
    @mysql_select_db("calvin69_affiliates")) {

	$result0 = @mysql_query("SELECT * FROM user_table WHERE user_name='$user_to_add_un' AND user_pass='$user_to_add_pw'");
	$row0    = @mysql_fetch_row($result0, MYSQL_ASSOC);
	if (! $row0[0]) 
	    $header = "Location: http://$HTTP_HOST\login.php";
	

	$result = @mysql_query("SELECT * FROM scriptlance_data WHERE MA='$I'");
	$row    = @mysql_fetch_array($result, MYSQL_ASSOC);

	$result1 = @mysql_query("SELECT * FROM scriptlance_data WHERE MA='12345'");
	$row1 = @mysql_fetch_array($result1, MYSQL_ASSOC);

	if (!$row) {
		$row = $row1;
		$I = '12345';
		$invalid_member_id = 1;
	}

	if ($row) {
		
		$member_nickname = $row["member_nickname"];


$subs_1 = $row["subs_1"];
$subs_15 = $row["subs_15"];	
$subs_30 = $row["subs_30"];	
$subs_60 = $row["subs_60"];	
$subs_90 = $row["subs_90"];		
$subs_total = $row["subs_total"];	

$subs_optin_1 = $row["subs_optin_1"];	
$subs_optin_7 = $row["subs_optin_7"];	
$subs_optin_15 = $row["subs_optin_15"];	
$subs_optin_30 = $row["subs_optin_30"];	
$subs_optin_60 = $row["subs_optin_60"];	
$subs_optin_90 = $row["subs_optin_90"];	
$subs_optin_total = $row["subs_optin_total"];	

$subs_cancel_1 = $row["subs_cancel_1"];
$subs_cancel_15 = $row["subs_cancel_15"];	
$subs_cancel_30 = $row["subs_cancel_30"];	
$subs_cancel_60 = $row["subs_cancel_60"];	
$subs_cancel_90 = $row["subs_cancel_90"];		
$subs_cancel_total = $row["subs_cancel_total"];

$member_level = $row["member_level"];

$member_trial_1 = $row["member_trial_1"];
$member_trial_7 = $row["member_trial_7"];
$member_trial_15 = $row["member_trial_15"];
$member_trial_30 = $row["member_trial_30"];
$member_trial_60 = $row["member_trial_60"];
$member_trial_90 = $row["member_trial_90"];
$member_trial_total = $row["member_trial_total"];

$member_paid_1 = $row["member_paid_1"];
$member_paid_7 = $row["member_paid_7"];
$member_paid_15 = $row["member_paid_15"];
$member_paid_30 = $row["member_paid_30"];
$member_paid_60 = $row["member_paid_60"];
$member_paid_90 = $row["member_paid_90"];
$member_paid_total = $row["member_paid_total"];

$pledge = $row["pledge"];
$pledge_date = $row["pledge_date"];
$pledge_perc = $row["pledge_perc"];

$alert = $row["alert"];
$I   = $row["MA"];		
		$MA   = $row["MA"];
		$SF  = $row["SF"] == "" ? $row1["SF"] : $row["SF"];
		$SF2 = $row["SF"];
		$filtermy  = $row["filtermy"] == "" ? $row1["filtermy"] : $row["filtermy"];
		$analytics  = $row["analytics"] == "" ? $row1["analytics"] : $row["analytics"];
		$Count  = $row["123count"];
		$google_api  = $row["google_api"];
		$adwords_id  = $row["adwords_id"];
		$SFM = $row["SFM"]== "" ? $row1["SFM"] : $row["SFM"];
		$CGI = $row["CGI"]== "" ? $row1["CGI"] : $row["CGI"];
		$CB  = $row["CB"]== ""  ? $row1["CB"] : $row["CB"];
		$CJ  = $row["CJ"]== ""  ? $row1["CJ"] : $row["CJ"];
		$Roulette  = $row["roulette"]== ""  ? $row1["roulette"] : $row["roulette"];
		$NetQuote  = $row["netquote"]== ""  ? $row1["netquote"] : $row["netquote"];
		$AMZN= $row["AMZN"]== "" ? $row1["AMZN"] : $row["AMZN"];
		$Rocket= $row["Rocket"]== "" ? $row1["Rocket"] : $row["Rocket"];
		$optinstorm= $row["optinstorm"]== "" ? $row1["optinstorm"] : $row["optinstorm"];
		$NMH = $row["NMH"]=="" ? $row1["NMH"] : $row["NMH"];
		$EZY = $row["EZY"]=="" ? $row1["EZY"] : $row["EZY"];
		$Contest = $row["Contest"]=="" ? $row1["Contest"] : $row["Contest"];
		$SiteSell= $row["SiteSell"]=="" ? $row1["SiteSell"] : $row["SiteSell"];


		$PayPal  = $row["PayPal"]=="" ? $row1["PayPal"] : $row["PayPal"];
		$PayPal_M  = $row["PayPal_M"]=="" ? $row1["PayPal_M"] : $row["PayPal_M"];
		$NewWebsite = $row["NewWebsite"]=="" ? $row1["NewWebsite"] : $row["NewWebsite"];
		$aweber = $row["aweber"]=="" ? $row1["aweber"] : $row["aweber"];
		$myaffprog = $row["myaffprog"]=="" ? $row1["myaffprog"] : $row["myaffprog"];
		$audio = $row["audio"]=="" ? $row1["audio"] : $row["audio"];
		$EzineBlaze = $row["EzineBlaze"]=="" ? $row1["EzineBlaze"] : $row["EzineBlaze"];
		$member_alert = $row["alert"];
		$Status = $row["member_status"];
		$stats = $row["stats"]=="" ? $row1["stats"] : $row["stats"];

$AdSense = $row["AdSense"]=="" ? $row1["AdSense"] : $row["AdSense"];
$readyrecruit = $row["readyrecruit"]=="" ? $row1["readyrecruit"] : $row["readyrecruit"];
$netrition = $row["netrition"]=="" ? $row1["netrition"] : $row["netrition"];
$sendfree = $row["sendfree"]=="" ? $row1["sendfree"] : $row["sendfree"];
$Count_aff = $row["Count_aff"]=="" ? $row1["Count_aff"] : $row["Count_aff"];
$linkshare = $row["linkshare"]=="" ? $row1["linkshare"] : $row["linkshare"];
$wordtracker = $row["wordtracker"]=="" ? $row1["wordtracker"] : $row["wordtracker"];
$harris = $row["harris"]=="" ? $row1["harris"] : $row["harris"];
$acop = $row["acop"]=="" ? $row1["acop"] : $row["acop"];
$getyourprofts = $row["getyourprofts"]=="" ? $row1["getyourprofts"] : $row["getyourprofts"];
$amazon_api = $row["amazon_api"]=="" ? $row1["amazon_api"] : $row["amazon_api"];
$iwhiz = $row["iwhiz"]=="" ? $row1["iwhiz"] : $row["iwhiz"];
$scriptlance = $row["scriptlance"]=="" ? $row1["scriptlance"] : $row["scriptlance"];
$element5 = $row["element5"]=="" ? $row1["element5"] : $row["element5"];
$experiment = $row["experiment"]=="" ? $row1["experiment"] : $row["experiment"];
$adwords_user  = $row["adwords_user"];
$adwords_password  = $row["adwords_password"];
$richwebmedia = $row["richwebmedia"]=="" ? $row1["richwebmedia"] : $row["richwebmedia"];
$hostgator = $row["hostgator"]=="" ? $row1["hostgator"] : $row["hostgator"];
$fusionquest = $row["fusionquest"]=="" ? $row1["fusionquest"] : $row["fusionquest"];
		
	} else {
		$Count = 'calvin69';
 	}

	// DB 01/24/04
        $pl = @mysql_query("SELECT date AS odate, DATE_FORMAT(date,'%m/%d') AS date, TIME_FORMAT(time,'%r') AS time, amount FROM pledge ORDER BY odate DESC,time DESC LIMIT 5");
	$pledges = "<table>\n";
	while ($row = @mysql_fetch_array($pl, MYSQL_ASSOC)) 
	{
	   if (!isset($lastpledge))
		$lastpledge = round($row['amount'],0);
  	   $pledges .= "<tr>\n<td align='right' class='small'>\$".$row['amount']."</td>\n";
    	   $pledges .= "<td class='small2'>".$row['date']."<SPAN CLASS='small_italic'> ".$row['time']."</span></td>\n</tr>\n";
	}
	$pledges .= "</table>\n";
	/////

	@mysql_free_result($result);
	@mysql_free_result($result1);
} else {
    $I = "12345";
    echo 'Cannot connect to database';
    exit;
}


/////
if($ID == '') {
$ID = $member_id;
}

if (empty($T) && $adwords > 0) $T = $adwords;

if ($I == 12345 && $A > 0) $I = $A;
?>
