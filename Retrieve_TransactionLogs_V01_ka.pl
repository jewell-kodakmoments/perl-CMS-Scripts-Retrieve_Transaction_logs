#!/usr/bin/perl
#
# Written by: Jacqueline Ewell
# Copyright Kodak alaris 2015
#
# This script will connect to the RBM Production database and look for and diag disks that were generated int he previous 4 hour window.
#perl2exe_info CompanyName=Kodak Alaris
#perl2exe_info FileVersion=2014.01.27.ver 01
#perl2exe_include "unicore/Heavy.pl";
#perl2exe_include "XML/Parser/Style/Tree.pm";
##perl2exe_include "Encode/ConfigLocal.pm";
#perl2exe_include utf8;
#perl2exe_include "unicore/lib/Perl/Word.pl";
#perl2exe_include "unicore/To/Digit.pl";
#perl2exe_include "unicore/lib/Perl/SpacePer.pl";
#perl2exe_include "unicore/To/Lower.pl";
#perl2exe_include "unicore/To/Upper.pl";
#perl2exe_include "unicore/To/Digit.pl";
#perl2exe_include "unicore/To/Fold.pl";
#perl2exe_include "unicore/To/Title.pl";

# C:\Perl64\bin\perl.exe \\W525IISP01\kiosksupport\TechOps\Retrieve_TransactionLogs\Retrieve_TransactionLogs_V01_ka.pl > \\W525IISP01\kiosksupport\TechOps\Retrieve_TransactionLogs\je.txt 2>&1

use strict;
#use Spreadsheet::ParseExcel;
use Spreadsheet::ParseXLSX;
use Excel::Writer::XLSX;
use Excel::Writer::XLSX::Chart::Column;
use Excel::Writer::XLSX::Chart::Line;
use Excel::Writer::XLSX::Chart::Pie;
use Encode;
use Encode::Unicode;
use DBI;
use DBD::ODBC; 
use Date::Calc qw(:all);
use OLE::Storage_Lite;
use Win32::Process::Info;
use Math::BigInt; 
use Math::BigInt::Calc; 
use Mail::Sender;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Copy;	

$Win32::OLE::Warn = 3;

my $AMPM; 
my $appname; 
my $atime; 
my $blksize; 
my $blocks;
my $configfile; 
my $ctime; 
my $day; 
my $dbh1; 
my $dbName;
my $dev; 
my $devfolder; 
my $docsfolder; 
my $DSNrbm; 
my $filedate; 
my $filetime; 
my $gid; 
my $hour; 
my $in_path;
my $ino; 
my $logfilelocal; 
my $logfilename;
my $logpath; 
my $logtext; 
my $logtime; 
my $Minute; 
my $min; 
my $mode; 
my $month; 
my $monthend; 
my $monthstart; 
my $mtime; 
my $nlink; 
my $omonth; 
my $order_d; 
my $order_m; 
my $order_y; 
my $output; 
my $oweek; 
my $rbmUserID; 
my $rbmUserPW; 
my $rdev; 
my $sec; 
my $Seconds; 
my $size; 
my $tempdir; 
my $timenow; 
my $timenow_a; 
my $today; 
my $todaydate; 
my $uid; 
my $ver; 
my $Weekday; 
my $workingpath; 
my $year; 
my %CFG; 
my @Months; 
my @Now; 
my @time; 
my @timeend; 
my @timestart; 
my @Weekdays; 
my $logfilesizelimit;
my $sql_retrieveblob;
my $t1;
my $t2;
my $orgid;
my @devicesfound;
my $TransactionLogfolder;
my $spreadsheet_tag;
my %orgs;
my %orgnames;
my %regions;
my $days2keep;
my $FileAge;
my $webLogPath;
my $DNSrbm;

get_working_directory();	#Call first to get the expected config file name
				#File handle is LOGFILELOCAL	
get_config();			#Call the get_config subroutine

	$output = $CFG{'output'};
	$in_path = $CFG{'in_path'};		
	$logpath = $CFG{'logpath'};	
	$tempdir = $CFG{'tempdir'};
	$DNSrbm = $CFG{'DNSrbm'};
			
	$rbmUserID = $CFG{'rbmUserID'};
	$dbName = $CFG{'dbName'};
	$logfilesizelimit = $CFG{'logfilesizelimit'};
	$logfilename = $CFG{'logfilename'};
	$webLogPath = $CFG{'webLogPath'};
	$days2keep = $CFG{'days2keep'};		

	if ($rbmUserID eq "stage_rbm"){$rbmUserPW = "p2ck2get3st";}
	elsif ($rbmUserID eq "PROD_RBM"){$rbmUserPW = "s8mm3r_t1m3";}
	elsif ($rbmUserID eq "QA_RBM"){$rbmUserPW = "rbm101";}
	else{}

verify_folder($in_path);
verify_folder($output);
verify_folder($logpath);
verify_folder($tempdir);

open_log();
get_time();

define_sql_retrieveblob();

connect_RBM_db();				#Connect to the database  dbh1 = RBM database   <--- Complete
load_org_hash();				
run_sql_retrieveblob();
disconnect_RBM_db();				#Disconnect from the RBM database     <--- Complete

#cleanup();					#Delete old Transaction log files
copyLog();					#copies the log file to the web site.


#----------------------------------------------------#
sub define_sql_retrieveblob
{
#Use the following to get the transaction log blob data (not sure what the attribid is)
$sql_retrieveblob = "	
select 
jobs.organizationid,	-- 0
jobs.dmdcode,		-- 1
jobs.dmdid,		-- 2
jobs.dmdtypeid,		-- 3
results.jobblob,	-- 4
results.jrattribid,	-- 5
jobs.jobcategory,	-- 6
jobs.jobdescription,	-- 7
jobs.performedby,	-- 8
jobs.datestamp		-- 9
from
(SELECT
jrht.DMDID DMDID,
jrht.DMDJOBRESULTID, 
DMD_TBL.DMDCODE DMDCODE, 
DMD_TBL.DMDTYPEID DMDTYPEID,
DMD_TBL.ORGANIZATIONID,
jrht.category jobcategory,
jrht.TASKRESULTHISTORYDESC jobdescription,
jrht.performedby,
jrht.crtupddt datestamp
FROM (CATCORE.JOB_RESULT_HIST_TBL jrht LEFT OUTER JOIN CATCORE.DMD_TBL DMD_TBL ON jrht.DMDID = DMD_TBL.DMDID)
where 
jrht.STATUSCODE = 'COMPLETED' AND 
jrht.crtupddt between to_date('$t2','MM-DD-YYYY HH24.MI.SS') and to_date('$t1','MM-DD-YYYY HH24.MI.SS')
AND jrht.category like 'Data_Retrieval'
AND jrht.PERFORMEDBY like '%TransactionLogCollection%'
) jobs,
(
select sjrt.SCHEDULEJOBRESULTID,sjrt.SCHEDULEJOBRESULTVALUE jobblob, sjrt.jobresultattributeid jrattribid
from CATCORE.SCHEDULE_JOBRSLT_ATTBVALUS_TBL sjrt
) results
where jobs.DMDJOBRESULTID = results.SCHEDULEJOBRESULTID
";	

#----------------------------------------------------#
print "$sql_retrieveblob\n";

}
#----------------------------------------------------#
sub get_working_directory
{

#This routine determine the name of the working directory and determines the name of the log file
#to be used for this run.
#
#...... Step 1  ......(Determine the local log file name)
#
my $scriptname = $0;
# print "scriptname = $scriptname\n";

if ($scriptname =~ m/exe$/g)
	{
	$scriptname =~ s/exe$/log/g;
	}
elsif 	($scriptname =~ m/pl$/g)
	{
	$scriptname =~ s/pl$/log/g;
	}
else {}
$logfilelocal = $scriptname;
# print "logfilelocal  = $logfilelocal\n";

#
#...... Step 2  ......(Determine the Config file name)
#
$scriptname = $0;
# print "scriptname = $scriptname\n";

if ($scriptname =~ m/exe$/g)
	{
	$scriptname =~ s/exe$/ini/g;
	}
elsif 	($scriptname =~ m/pl$/g)
	{
	$scriptname =~ s/pl$/ini/g;
	}
else {}
$configfile = $scriptname;
# print "configfile  = $configfile\n";


#
#...... Step 2  ......(Get the working folder)
#

my @d = split(/\\/,$scriptname);
#
my $elements = $#d;  # Note: $#d returns the length of the array @d
my $col;
my $str;
$workingpath = $d[0];
# print "The number of elements is: $elements\n";

if ($elements > 0)
{
	for($col = 1 ; $col < $elements ; $col++) 
	{
	$str = $d[$col];
	if ($str =~ m/ /)
	{
	$str = "\\" . "\"" . $str . "\"";
	}
	else
	{
	$str = "\\" . $str;
	}
	$workingpath = $workingpath . "\\" . $str;
	}
}
else {}

# print "The working path is: $workingpath\n";

my @a = split(/\\/,$0);
my $elements = $#a;
$appname = $a[$elements];

}
#----------------------------------------------------#
sub get_config
{
# This subroutine will read the configuration ini file
# and extract the variable names and values from the file.  

my @cl;
my @l;
my $line;
my $elements;
my $col;
my $configvalue;
# Check for the file:

if (-e $configfile)
	{

	open (INI, "<$configfile") or warn ("Could not open $configfile.\n");

	while (<INI>)
	{
	chomp($_);
	# If the line contains a = sign, then split.
#	print "$_\n";

		if ($_ =~ m/^;./) {} else
		{
			if ($_ =~ m/=/im)
			{
			@cl = split(/=/,$_);
			#This is a regular config value 
			$CFG{$cl[0]} = $cl[1];
			} 
			else {}
		}
	} #Wnd while
	}else{noconfig($configfile);}
	
close (INI);

}#End of get_config subroutine
#----------------------------------------------------#
sub noconfig
{
my $inifile = shift;
	get_time();
	$logtext = "$today\t$logtime\t*** ERROR CONFIGURATION FILE NOT FOUND ***";
	print "$logtext\n";
	write_log($logtext);
	$logtext = "$today\t$logtime\tThe expected configuration file could not be found";
	print "$logtext\n";
	write_log($logtext);	
	$logtext = "$today\t$logtime\tEXPECTED: $configfile";
	print "$logtext\n";
	write_log($logtext);
	close LOGFILELOCAL;	
	exit;
}
#----------------------------------------------------#
sub verify_folder
{

my $path = shift;
#The routine will verify existence of the specified folder and create it if it does not exist.

print "working on $path\n";

if (-e $path){}
	else
	{
	my $err;
	$err = system ("md $path");
	
	if ($err == 0)		#out folder created successfully
	{
	get_time();
	$logtext = "$today\t$logtime\tCreated path: [$path]";
	write_log($logtext);
	}
	else			#error while attempting to create the folder.
	{
	get_time();
	$logtext = "$today\t$logtime\tUnable to create: [$path] ERROR NO: $err";
	write_log($logtext);
	create_output_error($path, $err);
	}	
	}
}
#----------------------------------------------------#
sub create_output_error
{
	my $out_path = shift;
	my $err = shift;
	system ("cls");
	print "\n\n";
	print "\t\t*** ERROR ***\n\n";
	print "\n\tThe output path [$out_path] could not be created.\n\tDOS ERROR number: $err\n";
	print "\n\tPress Enter to Quit: ";
	chop (my $response = <STDIN>);
		if ($response =~ /.*/i)
			{
			exit;
			}	
}
#----------------------------------------------------#
sub get_time
{

	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	
	while (length($month) < 2){$month = "0" . $month;}
	while (length($day) < 2){$day = "0" . $day;}
	while (length($hour) < 2){$hour = "0" . $hour;}
	while (length($min) < 2){$min = "0" . $min;}
	while (length($sec) < 2){$sec = "0" . $sec;}
				
	
	$today = sprintf ('%02d%02d%04d', $month, $day, $year);

	$todaydate = sprintf ('%02d/%02d/%04d',  $month, $day, $year);
	$filedate = sprintf('%04d%02d%02d', $year,$month,$day);
	$logtime = sprintf ('%02d:%02d:%02d', $hour, $min, $sec);	

#	jrht.crtupddt between to_date('$t1','MM-DD-YYYY HH24.MI.SS') and to_date('$t2','MM-DD-YYYY HH24.MI.SS')

	$t1 = $month . "-" . $day . "-" . $year . " " . $hour . "." . $min . "." . $sec;
	print "t1 is: $t1\n";

      my ($year2,$month2,$day2, $hour2,$min2,$sec2) =  Add_Delta_DHMS($year,$month,$day, $hour,$min,$sec, 0,-24,0,0);

	while (length($month2) < 2){$month2 = "0" . $month2;}
	while (length($day2) < 2){$day2 = "0" . $day2;}
	while (length($hour2) < 2){$hour2 = "0" . $hour2;}
	while (length($min2) < 2){$min2 = "0" . $min2;}
	while (length($sec2) < 2){$sec2 = "0" . $sec2;}


	$t2 = $month2 . "-" . $day2 . "-" . $year2 . " " . $hour2 . "." . $min2 . "." . $sec2;
	
	

	print "t2 is: $t2\n";


}
#----------------------------------------------------#
sub open_log
{

	if (-e $logpath)
	{
	}
	else
	{
	my $err;
	$err = system ("md $logpath");

	if ($err == 0)	#log path created successfully
	{}
	else
	{# Display a message to the user that the log path can't be created.
	create_output_error($logpath, $err);
	}
	}

	my $file = $logpath . "\\" . $logfilename . ".log";
	if (-e $file) #check to see if the file exists
	{
	# if exists, check the file size of the log.  If this is > $logfilesizelimit , rename
	# it and open a new one. 
	get_file_stats($file);
	
#	print "The size is: $size\n";
	
		if ($size > $CFG{logfilesizelimit})
		{

		# The file size is too big, so rename this one and open a new one.
		my $newfile = $logfilename . "_" . $today . "_" .$timenow_a . ".log";
		system ("rename $file $newfile");
		open (LOGFILE, ">$file");
		get_time();
		print LOGFILE "Date\tTime\tEvent\n";
		$logtext = "$today\t$logtime\tStarted: $appname";
		print LOGFILE "$logtext\n";
		close LOGFILE;			
		}
		else
		{
		open (LOGFILE, ">> $file");
		get_time();
		$logtext = "\n$today\t$logtime\tStarted: $appname";
		print LOGFILE "$logtext\n";
		close LOGFILE;			
		}
	} 
	else
	{
	#The does not exist at all, so open it
	open (LOGFILE, "> $file");
	get_time();
	print LOGFILE "Date\tTime\tEvent\n";
	$logtext = "$today\t$logtime\tStarted: $appname";
	print LOGFILE "$logtext\n";
	close LOGFILE;
	}
	#print "logfile is: $file\n";
	#$logfile = "$file";
	#return $logfile;
}
#----------------------------------------------------#
sub write_log
{
my $logline = shift;
my $file = $logpath . "\\" . $logfilename . ".log";
open (LOGFILE, ">> $file");
print LOGFILE "$logline\n";
close LOGFILE;
}
#----------------------------------------------------#
sub get_file_stats
{
my $myfile = shift;
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)= stat($myfile);
}
#----------------------------------------------------#
sub connect_RBM_db
{


get_time();
$logtext = "$today\t$logtime\tStarting SUB 'connect_RBM_db'";
write_log($logtext);

	
	my %attr = (
	PrintError => 1,
	RaiseError => 0,
	);
	
	# Make connection to the database	
	# $dbh1 = DBI->connect("DBI:ODBC:$DSNrbm", "$rbmUserID" , "$rbmUserPW") or die "Can't connect to the ODBC datasource ($DSNrbm) $DBI::errstr\n";	

	$dbh1 = DBI->connect("DBI:ODBC:$DNSrbm", "$rbmUserID" , "$rbmUserPW") or warn;
	if ($DBI::errstr)
		{
		system ("cls");	
		print "\n\n\t *** ERROR ***\n\n\tCannot connect to the database\n\n\tERROR:\n\t$DBI::errstr\n";
		print "\n\n\tPress any key and Enter to Quit: ";
		chop (my $response = <STDIN>);
		if ($response =~ /.*/i)
			{
			close LOGFILELOCAL;
			write_end_file();
			exit;
			}
		}
}
#----------------------------------------------------#
sub disconnect_RBM_db
{
get_time();
$logtext = "$today\t$logtime\tStarting SUB 'disconnect_RBM_db')";
write_log($logtext);

	#Disconnect from the Esprida Database
	$dbh1->disconnect or warn "Can't disconnect to the ODBC datasource ($DNSrbm) $DBI::errstr\n";
}

#----------------------------------------------------#
sub run_sql_retrieveblob
{
my $rbm = shift;

#if ($rbm == 2){$sql_diagblob = $sql_diagblob_rbm2;}else{$sql_diagblob = $sql_diagblob_rbm3;}

#This routing is exclusively for running the diagnostic disk retrieval
my $org;
my $region;
my @row;
my $row;
my $tabline;		#holds the product list
my $bdline;		#holds the business data array
my $columncount;
my $col;
my $str;
my $str1;		#used for the original array
my $str_type;
my $rcdcount = 0;	# a counter to record the number of rows to return.
my $dmdid;
my $sitekey;
my $blobvalue;
my $line;
$TransactionLogfolder = "";	#Initialize the TransactionLogfolder

print "$sql_retrieveblob\n\n";
		
		get_time();
		$logtext = "$today\t$logtime\tSQL_Query: $sql_retrieveblob";
		write_log($logtext);
		
$dbh1->{LongReadLen} = 40000000;
$dbh1->{LongTruncOk} = 0;
$dbh1->{RaiseError} = 0; 

my $sth = $dbh1->prepare ("
$sql_retrieveblob
" ) or warn "error5: ", $dbh1->errstr(), "\n";

	if ($dbh1->errstr()){
		system ("cls");		
		get_time();
		$logtext = "$today\t$logtime\t*** ERROR *** Cannot get the diag disk data from $DSNrbm";
		write_log($logtext);
		$logtext = "$today\t$logtime\t" . $dbh1->errstr();
		write_log($logtext);
	}
	else{		
		#execute
		$sth->execute() or warn "error2: ", $dbh1->errstr(), "\n";

		if ($dbh1->errstr()){
			get_time();
			$logtext = "$today\t$logtime\t" . $dbh1->errstr();
			write_log($logtext);
		}
		else{
			while (@row = $sth->fetchrow_array)
				{
				$rcdcount++;
				#jobs.organizationid,	-- 0
				#jobs.dmdcode,		-- 1
				#jobs.dmdid,		-- 2
				#jobs.dmdtypeid,	-- 3
				#results.jobblob,	-- 4
				#results.jrattribid,	-- 5
				#jobs.jobcategory,	-- 6
				#jobs.jobdescription,	-- 7
				#jobs.performedby,	-- 8
				#jobs.datestamp		-- 9

				$org = $orgnames{$row[0]};
				print "The org for $row[0] is: $org\n";
				$region = $regions{$org};
				print "The region is: $region\n";
			
				#   region org code    dmdid   typeid
				$line = join "\t",($region,$org,$row[1],$row[2],$row[3]);
				push @devicesfound, ($line);
				# region  org, dmdcode dmdid   type   blob datestamp
				RetrieveTransactionLogs($region,$org,$row[1],$row[2],$row[3],$row[4],$row[9]);
				}
		}
		get_time();
		$logtext = "$today\t$logtime\tTransaction Logs Found: $rcdcount";
		write_log($logtext);
	}
}
#----------------------------------------------------#
sub RetrieveTransactionLogs
{
my $region = shift;
my $org = shift;
my $dmdcode = shift;
my $dmdid = shift;
my $type = shift;
my $dmdjobresultvalue = shift;			# (
my $datestamp = shift;
my @t;

	#print "The datestamp before is: $datestamp\n";

$datestamp =~ s/ /_/img;
$datestamp =~ s/://img;

	#print "The datestamp after is: $datestamp\n";

@t = split(/\./,$datestamp);

	#print "The t[0] after is: $t[0]\n";


	#$diagfolder =  $output . "\\" . $org . "\\" . $spreadsheet_tag ."_" . $filedate . "_" . $filetime;
	$TransactionLogfolder =  $output . "\\" . $region;
	verify_folder($TransactionLogfolder);
	$TransactionLogfolder = $TransactionLogfolder . "\\" . $org;
	verify_folder($TransactionLogfolder);
	
	#print "The diagfolder is: $diagfolder\n";
	#print "The datestamp is: $datestamp\n";

	my $tempfile = $TransactionLogfolder . "\\" . $dmdcode . "_" . $t[0] . "_TransactionLogs.zip";

	if (-e $tempfile){
		#Do nothing - I already have this file
		}
	else{
		
		open (OUTFILE, ">$tempfile");		#open the output file
		binmode (OUTFILE);
		print OUTFILE "$dmdjobresultvalue";
		close OUTFILE;
		get_time();
		$logtext = "$today\t$logtime\tSaved Transaction Logs: $tempfile";
		write_log($logtext);	
	}	
}
#----------------------------------------------------#
sub load_org_hash
{
get_time();
$logtext = "$today\t$logtime\tStarting SUB 'load_org_hash')";
write_log($logtext);

my $ORGNAME;
my $orgname;
my $orgid;
my $desc;
my @row;
my $sth = $dbh1->prepare ("
select UPPER(ot.organizationname) Org,
ot.organizationname orgname,
ot.organizationid OrgCode,
db.dbname,
ot.organizationdesc
from $dbName.organization_tbl ot,$dbName.org_db_tbl db
where ot.organizationid = db.organizationid
and ot.islogicaldelete = 'N'
and ot.parentorganizationid = 1
order by ORG
" ) or warn "error1: ", $dbh1->errstr(), "\n";
	
	if ($dbh1->errstr())
		{
		unexpected_exit("load_org_hash",$dbh1->errstr());
		}
	else
		{		
		#execute
		$sth->execute() or warn "error1: ", $dbh1->errstr(), "\n";
		
		if ($dbh1->errstr())
			{
			get_time();
			$logtext = "$today\t$logtime\t" . $dbh1->errstr();
			write_log($logtext);
			}
		else
			{	
			while (@row = $sth->fetchrow_array)
				{
				# 0 = Org name UPPPER CASE
				# 1 = org name
				# 2 = orgid
				# 3 = dbname
				# 4 = description		
				#print "org = $row[0]\t code = $row[1]\n";
				#UPPER name to ID
				$ORGNAME = $row[0];
				$orgname = $row[1];
				$orgid = $row[2];
				$desc = $row[4];
				
				$orgs{$row[1]}=$row[2];
				get_region($ORGNAME,$orgname,$orgid,$desc);
				
				#id to name 
				$orgnames{$row[2]}=$row[1];
				#to get the correct name
				# $my id = $orgs{"SUPERVALU"};
				# $my name = $orgnames{$orgs{"SUPERVALU"}};
				#print "org = $row[0]\t code = $row[1] config value = $CFG{$row[1]}\n";
				}
		 	}
		}
}
#----------------------------------------------------#
sub get_region
{
my $ORGNAME = shift;
my $orgname = shift;
my $orgid = shift;
my $desc = shift;
my @d;
my $region;

#get_time();
#$logtext = "$today\t$logtime\tStarting SUB 'get_region')";
#write_log($logtext);

@d = split(/ /,$desc);


	if ($d[0] eq 'AMERICAS')
		{
		$region = $d[1];
		}
	else
		{
		$region = $d[0];
		} 

#remove / from US/C
$region =~ s!/!!img;

	if ($region eq "GAR"){
		$region = "APR";
	}
	else{}

$regions{$ORGNAME}=$region;
$regions{$orgname}=$region;
$regions{$orgid}=$region;
}	
#----------------------------------------------------#
sub cleanup
{
	print "Starting Cleanup\n";
	do_dir ($output);

	#----------------------------------------------------#
	sub do_dir {
	my $dir = shift;		#$dir = $top_path
	my @d;	#to get the server name
	my @t;	#to get the server label
	my @elements;

	    opendir(D, $dir);
	    my @f = readdir(D);
	    closedir(D);
	    foreach my $file (@f) {
	    my $filename = $dir . '\\' . $file;

	        if ($file eq '.' || $file eq '..')
		{
	        }
		 elsif (-d $filename) 
			{
			# The file is a directory. Call do_dir again to re-read the directory
			do_dir($filename); 
			} 
		else{
	        	# this is a file, so look to see if it is a zip file
		
	        	if ($filename  =~ /.+zip$/i){
         			print "$filename\n";  
           			print "$file\n";  
		                $FileAge = -M $filename;
				$FileAge = int($FileAge+.5);
				#print "$file\tFile Age is $FileAge\n";
				
					if ($FileAge > $days2keep){
						#print "\tdeleting\t$file\n";
						unlink $filename;
						get_time();
						$logtext = "$today\t$logtime\tFileAge: $FileAge > $days2keep Deleted file:$filename";
						write_log($logtext);
						
					}
					else{
					}
			}	
		}
		}
	}
}
#----------------------------------------------------#
sub copyLog
{
#This routine copies the log file to the web server and renames it to .txt
my $source = $logpath . "\\" . $logfilename . ".log";
my $destination = $webLogPath . "\\" . $logfilename . ".txt";

#print "The source file is: $source\n";
#print "The destination file is: $destination\n";

copy $source, $destination;

}
