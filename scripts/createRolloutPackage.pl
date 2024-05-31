#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper qw(Dumper);
use Getopt::Std;
use lib "./scripts";
use Cwd;
use File::Path;
use File::Path qw(make_path);
use File::Spec::Functions;
use Text::ParseWords;
use IPC::Open2;
use File::Basename;
use File::Copy;
use File::Find;
use Time::localtime;

my %opts = ();
my $LESDIR =  "";
my $RPTPATH = "reports"; # by default
my $LBLPATH = "";
my $MOCAPATH = "";
my $JARPATH = "";
my $CSVPATH = "";
my $MSQLPATH = "";
my $HMSQLPATH = "";
my $LMSQLPATH = "";
my $MTFPATH = "";
my $INTPATH = "";
my $customer;
my $loaddatatext= "# Load any data affected.  NOTE the assumption is that\n# the control file will be in the db/data/load directory.\n";
my $replacetext = "# Replacing files affected by extension.\n";
my $loadexist=0;
my $mocaexist=0;
my $intexist=0;
my $ro_dir;
my $ro_tar_dir;
my $git_branch_name;
my $ro;
my $s;
my $rotext="";
my $rebuildtext="";
my $logfile;
my $detailed_output;
my $ro_name;
my $force_delete;
my $ro_dir_parm;
my $logfile_parm;
my $detailed_output_parm ="";
my $ro_name_parm;
my $pack;
my $build_script;
my $orig_dir;
my $warning_text = "WARNINGS EXIST:\n";
my $warnings_exist = 0;
my $error_text = "ERRORS EXIST:\n";
my $errors_exist = 0;
my $readme;
my $build_readme;
my $readme_parm;
my $issue_text = "Issue(s):\n";
my $notes_text = "Release Notes:\n";
my $component_text = "Affected Files:\n";
my $remove_text = "Removed Files:\n";
my $remove_ro_text = "# Removing files removed by extension.\n";
my $log = "";
my $SrcInputFile ="";
my $CustomerFile;
my $vOutputFile;

#####################################################################
# show usage()
#####################################################################

#perl /home/runner/work/SWBYDEMO/SWBYDEMO/scripts/createRolloutPackageManual.pl -g "A src/cmdsrc/usrint/add_Lc_XML_tag.mcmd M src/cmdsrc/usrint/add_lc_file_to_xml.mcmd" -t "/home/runner/work/SWBYDEMO/SWBYDEMO" -n "B6-v1.1.2" -d rollout -r inputFile.txt -f -l B6.log -p -o -m
sub show_usage {
  die "Correct usage for $0 is as follows:\n"   
        . "$0\n"
		. "\t-g <List of modified files>\n"
        . "\t-t <Workspace path of GIT repository, replaces LESDIR>\n"
		. "\t-c <Customer Name>\n"
        . "\t-n <Rollout Name>\n"
        . "\t-d <Rollout Directory - path from \$LESDIR where the rollout package will be created>\n"
        . "\t-r <Rollout Input File>\n"
		. "\t-z <Rollout Tar Final Directory>\n"
		. "\t-b <Git Branch Name>\n"
        . "\t-f <Force delete of package if it already exists>\n"
        . "\t-p <Create the rollout script and package this to a tar file after pulling all components>\n"
        . "\t-u <Create the rollout script>\n"
        . "\t-m <Create a readme file>\n"
        . "\t-l <Log File - file will be written to LESDIR/log directory>\n"
        . "\t-o Show detailed output\n"
        . "\t-h <Help - this screen>\n";
}#show_usage

sub trim($)
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}
#####################################################################
# write_log()
#
# simply writes the $log parameter that we have been writing to during 
# processing to the $logfile file
#####################################################################
sub write_log{
	if($logfile)
	{
		if($detailed_output){printf("Writing to log file $LESDIR/log/$logfile\n\n");}
		$log = $log . "Writing to log file $LESDIR/log/$logfile\n\n";

		open(OUTLOG, ">>$LESDIR/log/$logfile");
		print OUTLOG $log;
		close(OUTLOG);
		$log = "";
	}
}#write_log

#####################################################################
# create_ro_dir($fulldir)
#	$fulldir - this is the full directory path for the directory to
#				be created.
#
# this function will create the lowest level directory, and any missing
# parent directories defined in the $fulldir parameter
#####################################################################
sub create_ro_dir
{
	my($fulldir) = @_;
	my $done = 0;
	my $curdir = $fulldir;
	
	if($detailed_output){printf( "Create RO directory - $fulldir\n\n");}
	$log = $log . "Create RO directory - $fulldir\n";
	
	while(!$done)
	{
		if(-d $fulldir)
		{
			$done = 1;
		}
		else
		{
			if(-d dirname($curdir))
			{
				mkdir($curdir);
				$curdir = $fulldir;
			}
			else
			{
				$curdir = dirname($curdir);
			}
		}
	}
}#create_ro_dir

#####################################################################
# copy_ctl_ro_file($filedir, $filename, $new_filedir)
#	$filedir - current path of file to be copied
#	$filename - current control filename of file to be copied
#	$new_filedir - new path to copy to
#
# this will copy an existing control file from one location to another
#####################################################################
sub copy_ctl_ro_file
{
	# takes arguments
	# filedir - directory the control file will be copied from
	# filename - control filename to be copied from
	# new_filedir - directory to copy to
	my($filedir,$filename,$new_filedir) = @_;
	
    my $full_control_path = $filedir;
    
    
	if(!-e $full_control_path)
	{
		if($detailed_output){printf( "Cannot find control file\n\t$filedir/$filename\n  Control File will not be copied \n\n");}
		$log = $log .  "Cannot find file\n\t$filedir/$filename\n  File will not be copied \n\n";
		$error_text = $error_text .  "- Cannot find file $filedir/$filename.  File will not be copied!\n";
		$errors_exist = 1;
	}
	if(!-e $new_filedir )
	{
		if($detailed_output){printf( "Directory to copy control file to ($new_filedir) does not exist. Control File will not be copied \n\n");}
		$log = $log . "Directory to copy control file to ($new_filedir) does not exist. Control File will not be copied \n\n";
		$error_text = $error_text .  "- Directory to copy control file to ($new_filedir) does not exist. Control File will not be copied!\n";
		$errors_exist = 1;
	}
	else
	{
		copy($full_control_path, $new_filedir . "/" . $filename)
	}
	# Copy the control file of the file name 
	
	
}#copy_ctl_ro_file

#####################################################################
# copy_ro_file($filedir, $filename, $new_filedir, $new_filename)
#	$filedir - current path of file to be copied
#	$filename - current filename of file to be copied
#	$new_filedir - new path to copy to
#	$new_filename - new filename to copy to
#
# this will copy an existing file from one location to another
#####################################################################
sub copy_ro_file
{
	# takes arguments
		# filedir - directory the file will be copied from
		# filename - filename to be copied from
		# new_filedir - directory to copy to
		# new_filename - filename to copy to - if this argument is not included, we will use the original filename
	my($filedir,$filename,$new_filedir,$new_filename) = @_;
	if(!$new_filename)
	{
		$new_filename = $filename
	}
	
    my $full_path = $filedir . "/". $filename;
    
    
	if(!-e $full_path)
	{
		if($detailed_output){printf( "Cannot find file\n\t$filedir/$filename\n  File will not be copied \n\n");}
		$log = $log .  "Cannot find file\n\t$filedir/$filename\n  File will not be copied \n\n";
		$error_text = $error_text .  "- Cannot find file $filedir/$filename.  File will not be copied!\n";
		$errors_exist = 1;
	}
	if(!-e $new_filedir )
	{
		if($detailed_output){printf( "Directory to copy file to ($new_filedir) does not exist.  File will not be copied \n\n");}
		$log = $log . "Directory to copy file to ($new_filedir) does not exist.  File will not be copied \n\n";
		$error_text = $error_text .  "- Directory to copy file to ($new_filedir) does not exist.  File will not be copied!\n";
		$errors_exist = 1;
	}
	else
	{
		copy($full_path, $new_filedir . "/" . $new_filename)
	}
	
}#copy_ro_file

#####################################################################
# get_load_directory($table)
#	$table - table name
#
# this will take a table as a parameter and determine if the load directory should be 
# safetoload or bootstraponly and return that value
#####################################################################
sub get_load_directory
{
    my ($table) = @_;
	my $loaddir;
    
	if(-d $LESDIR . "/$CSVPATH/safetoload/$table")
	{
		$loaddir = 'safetoload';
	}
	elsif(-d $LESDIR . "/$CSVPATH/bootstraponly/$table")
	{
		$loaddir = 'bootstraponly';
	}
	else
	{
		if($detailed_output){printf( "No control file for table $table, this table will not be included\n\n");}
		$log = $log .  "No control file for table $table, this table will not be included\n\n";
		$warning_text = $warning_text .  "- No control file for table $table, this table will not be included!\n";
		$warnings_exist = 1;
	}
	return $loaddir;
}#get_load_directory

#####################################################################
# get_file_load_directory($file)
#	$file - file name
#
# this will take a file as a parameter and determine if the load directory should be 
# safetoload or bootstraponly and return that value
#####################################################################
sub get_file_load_directory
{
    my ($file) = @_;
	my $loaddir;
    
	printf( "get_file_load_directory for $file \n\n");
	if($LESDIR . "/$CSVPATH/safetoload/$file")
	{
		$loaddir = 'safetoload';
	}
	elsif($LESDIR . "/$CSVPATH/bootstraponly/$file")
	{
		$loaddir = 'bootstraponly';
	}
	else
	{
		if($detailed_output){printf( "This $file will not be included\n\n");}
		$log = $log .  "This $file will not be included\n\n";
		$warning_text = $warning_text .  "- This $file will not be included!\n";
		$warnings_exist = 1;
	}
	printf( "$file in $loaddir\n\n");
	return $loaddir;
}#get_file_load_directory

#####################################################################
# pull_files($cmd_string)
#	$cmd_string - command line parameters from the ro input file
#
# this will take a line of parameters from the rollout input file and pull files/data as needed
# 
# this initially started as a separate perl script, so it is expecting
# parameters as -a, -b, etc. in a string
#####################################################################
sub pull_files{

	my %opts = ();
	my $ro_dir;
	my $logfile;
	my $detailed_output;
	my $force_delete;
	my $data_type;
	my $table;
	my $sql_text;
	my $component_dir;
	my $file;
	my $grp_nam;
	my $ro_name;
	my $ifd_list;
	my $event_list;
	my $unload;
	my $replacetextp="";
	
	
	printf "--------------------PULL FILES----------------------\n\n\n"; 
	#first we will reset the arguments parameter to be the string passed in so we can pull the parameters
	#using the standard logic
	my $cmd_string = shift;
	if(substr($cmd_string,0,5) ne "ISSUE" && substr($cmd_string,0,5) ne "NOTES")
	{
		$cmd_string =~ s/\\/\//g;
	}
	else
	{
		$cmd_string =~ s/\\n/*LINEFEED*/g;
		$cmd_string =~ s/\\t/*TAB*/g;
	}
	
	local @ARGV = shellwords($cmd_string);
	
	#get options
	getopts('r:i:l:on:c:s:d:t:f:e:p:uh', \%opts);

	# get the arguments
	$ro_name = $opts{r} if defined($opts{r});
	$ro_dir = $opts{p} if defined($opts{p});
	$logfile = $opts{l} if defined($opts{l});
	$detailed_output = $opts{o} if defined($opts{o});
	$grp_nam = $opts{n} if defined($opts{n});
	$data_type = $opts{c} if defined($opts{c});
	$sql_text = $opts{s} if defined($opts{s});
	$component_dir = $opts{d} if defined($opts{d});
	$table = $opts{t} if defined($opts{t});
	$file = $opts{f} if defined($opts{f});
	$ifd_list = $opts{i} if defined($opts{i});
	$event_list = $opts{e} if defined($opts{e});
	$unload = $opts{u} if defined($opts{u});
	my $help = $opts{h} if defined($opts{h});
				
	if($detailed_output){printf( "pull_files: Pulling Components\n\n");}
	$log = $log . "pull_files: Pulling Components\n\n";
	#printf "--------------------table:$table----------------------\n\n\n"; 
	printf "--------------------Pulling Components----------------------\n\n\n"; 
	# create RO directory if it doesn't exist
	if(!-d $ro_dir.$ro_name)
	{
		if($detailed_output){printf( "$ro_name folder does not exist - creating it\n");}
		$log = $log . "$ro_name folder does not exist - creating it\n";
		mkdir($ro_dir . $ro_name);
	}


	#####################################################################
	# CSV
	#####################################################################
	# if this is for a csv command, copy file
	if(uc($data_type) eq "SQL")
	{
		printf "--------------------Handling a CSV FILE----------------------\n\n\n"; 
		$component_dir = get_load_directory($table);
		#if(uc($table) eq "POLDAT"){$component_dir = "bootstraponly";}
		if($detailed_output){printf( "CSV\nPulling CSV file: $file\n");}
		$log = $log . "CSV\nPulling CSV file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$CSVPATH/$component_dir/$table");
		copy_ro_file($LESDIR . "/$CSVPATH/$component_dir/$table",$file,$ro_dir.$ro_name . "/pkg/$CSVPATH/$component_dir/$table");
		copy_ctl_ro_file($LESDIR . "/$CSVPATH/$component_dir",$table.".ctl",$ro_dir.$ro_name . "/pkg/$CSVPATH/$component_dir");
	}

	#####################################################################
	# CTL
	#####################################################################
	# if this is for an CTL file, copy file
	elsif(uc($data_type) eq "CTL")
	{
		$component_dir = get_file_load_directory($file);
		
		if($detailed_output){printf( "CTL\nPulling CTL file: $file\n");}
		$log = $log . "CTL\nPulling CTL file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$CSVPATH/$component_dir");
		copy_ro_file($LESDIR . "/$CSVPATH/$component_dir",$file,$ro_dir.$ro_name . "/pkg/$CSVPATH/$component_dir");
	}
	
	#####################################################################
	# MOCA
	#####################################################################
	# if this is for a moca command, copy file
	elsif(uc($data_type) eq "MOCA")
	{
		
		if(!$component_dir){$component_dir = "usrint";}
		if($detailed_output){printf( "MOCA\nPulling Moca file: $file\n");}
		$log = $log . "MOCA\nPulling Moca file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$MOCAPATH/$component_dir");
		copy_ro_file($LESDIR . "/$MOCAPATH/$component_dir",$file,$ro_dir.$ro_name . "/pkg/$MOCAPATH/$component_dir");
	}

	#####################################################################
	# MLVL
	#####################################################################
	# if this is for an mlvl file, copy file
	elsif(uc($data_type) eq "MLVL")
	{
		
		if($detailed_output){printf( "MLVL\nPulling MLVL file: $file\n");}
		$log = $log . "MLVL\nPulling MLVL file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$MOCAPATH");
		copy_ro_file($LESDIR . "/$MOCAPATH",$file,$ro_dir.$ro_name . "/pkg/$MOCAPATH");
	}

	#####################################################################
	# REPORT
	#####################################################################
	# if this is for a report, copy file
	elsif(uc($data_type) eq "REPORT")
	{
		if($detailed_output){printf( "REPORT\nPulling Report file: $file\n");}
		$log = $log . "REPORT\nPulling Report file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$RPTPATH/$component_dir");
		copy_ro_file($LESDIR . "/$RPTPATH/$component_dir",$file,$ro_dir.$ro_name . "/pkg/$RPTPATH/$component_dir");
	}

	#####################################################################
	# LABEL
	#####################################################################
	# if this is for a label, copy file
	elsif(uc($data_type) eq "LABEL")
	{
		if($detailed_output){printf( "LABEL\nPulling Label file: $file\n");}
		$log = $log . "LABEL\nPulling Label file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$LBLPATH/$component_dir");
		copy_ro_file($LESDIR . "/$LBLPATH/$component_dir",$file,$ro_dir.$ro_name . "/pkg/$LBLPATH/$component_dir");
	}

	#####################################################################
	# DDL
	#####################################################################
	# if this is for a dll, copy file
	elsif(uc($data_type) eq "DDL")
	{
		if($detailed_output){printf( "DDL\nPulling DDL file: $file\n");}
		$log = $log . "DDL\nPulling DDL file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$MSQLPATH/$component_dir");
		copy_ro_file($LESDIR . "/$MSQLPATH/$component_dir",$file,$ro_dir.$ro_name . "/pkg/$MSQLPATH/$component_dir");
	}

	#####################################################################
	# INT
	#####################################################################
	# if this is for an integrator file, copy file
	elsif(uc($data_type) eq "INT")
	{
		if($detailed_output){printf( "INT\nPulling Integration file: $file\n");}
		$log = $log . "INT\nPulling Integration file: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$INTPATH");
		copy_ro_file($LESDIR . "/$INTPATH",$file,$ro_dir.$ro_name . "/pkg/$INTPATH");
	}

	#####################################################################
	# README
	#####################################################################
	# if this is for a README file copy the file
	elsif(uc($data_type) eq "README")
	{
		if($detailed_output){printf( "README\nPulling README file: $file\n");}
		$log = $log ."README\nPulling README file: $file\n";
		
		copy_ro_file($ro_dir,$file,$ro_dir.$ro_name);

	}

	#####################################################################
	# FILE
	#####################################################################
	# if this is for a file, copy file
	elsif(uc($data_type) eq "FILE")
	{
		if($detailed_output){printf( "FILE\nPulling File: $file\n");}
		$log = $log . "FILE\nPulling File: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$component_dir");
		copy_ro_file($LESDIR . "/$component_dir",$file,$ro_dir.$ro_name . "/pkg/$component_dir");
		
		
		#write rollout script
		if($detailed_output){printf("Creating line for rollout script for adding file\n");}
		$log = $log . "Creating line for rollout script for adding file\n";

		$replacetextp = $replacetextp . "REPLACE pkg/$component_dir/$file \$LESDIR/$component_dir\n";
		
		$component_text = $component_text . "\t$component_dir/$file\n";

	}

	#####################################################################
	# REMOVE
	#####################################################################
	# if this is to remove a file, write the line
	elsif(uc($data_type) eq "REMOVE")
	{
		if($detailed_output){printf( "REMOVE\nWriting line to remove file: $file\n");}
		$log = $log . "REMOVE\nWriting line to remove file: $file\n";
		
		#write rollout script
		if($detailed_output){printf("Creating line for rollout script for removing file\n");}
		$log = $log . "Creating line for rollout script for removing file\n";

		$remove_ro_text = $remove_ro_text . "REMOVE \$LESDIR/$component_dir/$file\n";
		
		$remove_text = $remove_text . "\t$component_dir/$file\n";

	}
	
	#####################################################################
	# MTF
	#####################################################################
	# if this is for an MTF file, copy file
	elsif(uc($data_type) eq "MTF")
	{
		$component_dir = "$MTFPATH";
		if($detailed_output){printf( "MTF\nPulling MTF File: $file\n");}
		$log = $log . "MTF\nPulling MTF File: $file\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$component_dir");
		copy_ro_file($LESDIR . "/$component_dir",$file,$ro_dir.$ro_name . "/pkg/$component_dir");
		
	}

	#####################################################################
	# ISSUE
	#####################################################################
	# if this is for Issue text, set the text to the issue_text variable
	
	elsif(uc($data_type) eq "ISSUE")
	{
		if($detailed_output){printf( "ISSUE\nSetting Issue text for README file: $table\n");}
		$log = $log . "ISSUE\nSetting Issue text for README file: $table\n";
		$table =~ s/\*LINEFEED\*/\n/g;
		$table =~ s/\*TAB\*/\t/g;
		$issue_text = $issue_text . $table;
	}
	
	#####################################################################
	# NOTES
	#####################################################################
	# if this is for release notes text, set the text to the notes_text variable
	
	elsif(uc($data_type) eq "NOTES")
	{
		if($detailed_output){printf( "NOTES\nSetting Release Notes text for README file: $table\n");}
		$log = $log . "NOTES\nSetting Release Notes text for README file: $table\n";
		$table =~ s/\*LINEFEED\*/\n/g;
		$table =~ s/\*TAB\*/\t/g;
		$notes_text = $notes_text . $table;		
	}
	
	#####################################################################
	# DIR
	#####################################################################
	# if this is for a directory, copy directory
	elsif(uc($data_type) eq "DIR")
	{
		if($detailed_output){printf( "DIR\nCreating Directory: $component_dir\n");}
		$log = $log . "DIR\nCreating Directory: $component_dir\n";
		create_ro_dir($ro_dir.$ro_name . "/pkg/$component_dir");
		
		
		#write rollout script
		if($detailed_output){printf("Creating line for rollout script for adding directory\n");}
		$log = $log . "Creating line for rollout script for directory file\n";

		$replacetextp = $replacetextp . "CREATEDIR \$LESDIR/$component_dir\n";

	}

	else
	{
		if($detailed_output){printf( "Invalid option for component type: $data_type\n\n");}
		$log = $log . "Invalid option for component type: $data_type\n\n";	
		$error_text = $error_text .  "- Invalid option for component type: $data_type. No components will be pulled for this line.\n";
		$errors_exist = 1;
	}

	write_log();

	# write rollout script
	open(OUTF, ">>$ro_dir$ro_name/$ro_name");
	print OUTF  $replacetextp;
	close(OUTF);
	
}#pull_files

#####################################################################
# package_rollout($cmd_string)
#	$cmd_string - command line parameters from the ro input file
#
# this will look through a directory to determine what components are 
# included in the rollout and build the rollout script and potentially
# tar up the directory
# 
# this initially started as a separate perl script, so it is expecting
# parameters as -a, -b, etc. in a string
#####################################################################
sub package_rollout{

	
	my $force_delete;
	my $data_type;
	my $table;
	my $sql_text;
	my $component_dir;
	my $file;
	my $grp_nam;
	my $ifd_list;
	my $event_list;
	my $readme_text;
	
	#first we will reset the arguments parameter to be the string passed in so we can pull the parameters
	#using the standard logic
	my $cmd_string = shift;
	$cmd_string =~ s/\\/\//g;
	local @ARGV = shellwords($cmd_string);
	
  	#####################################################################
	# Initial variable declaration and validations
	#####################################################################

	my %opts = ();
	my $logfile;

	
	my $runhighsqltext = "# Run any High Priority SQL, MSQL and other scripts\n";
	my $runlowsqltext = "# Run any Low Priority SQL, MSQL and other scripts\n";
	
	my $importsldatatext = "# Import any Integrator data affected\n";
	my $mbuildtext = "# Perform any environment rebuilds if necessary\n";
	my $rebuildpretext = "# Perform any environment rebuilds if necessary.";
	my $pack;
	my $readme;
        my $ro_script = "# Extension $ro_name\n#\n# This script has been built specifically to deploy patch $ro_name\n";
	#get options
	getopts('d:l:ohpm', \%opts);

	# get the arguments
	$ro_dir = $opts{d} if defined($opts{d});
	$logfile = $opts{l} if defined($opts{l});
	$detailed_output = $opts{o} if defined($opts{o});
	$pack = $opts{p} if defined($opts{p});
	$readme = $opts{m} if defined($opts{m});
	my $help = $opts{h} if defined($opts{h});

	if($help)
	{
		show_usage();
	}

	#validate ro directory argument passed in
	if(!$ro_dir)
	{
		printf("ERROR! -d rollout directory option must be defined!\n\n");
		$log = "ERROR! -d rollout directory option must be defined!\n\n";
		if($logfile)
		{
			open(OUTF, ">>$LESDIR/log/$logfile");
			print OUTF $log;
		}
		show_usage();
		
		exit 0;
	}

	#validate ro directory is a valid directory
	if (!-d "$LESDIR/$ro_dir")
	{
		printf("ERROR! rollout directory ($ro_dir) does not exist\n\n");
		$log = "ERROR! rollout directory ($ro_dir) does not exist\n\n";
		if($logfile)
		{
			open(OUTF, ">>$LESDIR/log/$logfile");
			print OUTF $log;
		}
		show_usage();
		
		exit 0;
	}

	#get ro name - last directory in ro_dir
	$ro_name = basename($ro_dir);

	#printf("Building Rollout Package \n");

	if($detailed_output){printf( "Building Rollout Package \n\nCurrent Time: " . localtime() . "\n\nOptions\nRO_DIR = $ro_dir\nlogfile = $logfile\n\nEnvironment:\nLESDIR = $LESDIR\nLog directory=$LESDIR\log\nRollout Name = $ro_name\n\n");}
	$log = "Building Rollout Package \n\nCurrent Time: " . localtime() . "\n\nOptions\nRO_DIR = $ro_dir\nlogfile = $logfile\n\nEnvironment:\nLESDIR = $LESDIR\nLog directory=$LESDIR\log\nRollout Name = $ro_name\n\n";

	#copy rollout script to directory
	copy("$LESDIR/scripts/rollout.pl","$LESDIR/$ro_dir/rollout.pl");
	if($detailed_output){printf("Copying rollout.pl - from $LESDIR/scripts/rollout.pl   to $LESDIR/$ro_dir/rollout.pl\n\n");}
	$log = $log . "Copying rollout.pl - from $LESDIR/scripts/rollout.pl   to $LESDIR/$ro_dir/rollout.pl\n\n";

	#####################################################################
	# Current rollout script
	#####################################################################
	# we may have already written lines to a rollout script for adding files 
	# or directories.  Read in file - if any line starts with a # then we assume
	# it is a full script and we will delete.  Otherwise we will save of the lines 
	# and write to script later
    if($detailed_output){printf( "Checking for existing text from rollout script (file copy, directory creation, etc.)\n");}
	$log = $log . "Checking for existing text from rollout script (file copy, directory creation, etc.)\n";
	open (ROFILE,"$LESDIR/$ro_dir/$ro_name");
	my $dontinclude;
    my $roexist;
	while (<ROFILE>)
	{
		chomp;
		# don't read line if it starts with #
		if(substr($_,1,1) ne "#")
		{
			if($detailed_output){printf( "Found rollout Text:$_\n");}
			$log = $log .  "Found rollout Text:$_\n";
            $roexist = 1;
			$rotext = $rotext . $_ . "\n";
        }
		else
		{
			$dontinclude = 1;
		}
	}
	if($dontinclude)
	{
		$rotext = "";
	}
	close(ROFILE);
    
    if(!$roexist)
	{
		if($detailed_output){printf("No existing rollout script text found...Continuing\n\n");}
		$log = $log . "No existing rollout script text found...Continuing\n\n";
	}

	#####################################################################
	# MSQL for High Priority scripts
	#####################################################################
	if($detailed_output){printf( "Checking for High Priority MSQL (database changes) files\n");}
	$log = $log . "Checking for High Priority MSQL (database changes) files\n";
	my $msqlexist;
	my $hmsqldir = "$LESDIR/$ro_dir/pkg/$HMSQLPATH";
	#find({ wanted => \&writehighmsql, preprocess => \&preprocess, no_chdir} => \&nochdir, $msqlhighdir);
	#validate $msqlhighdir exist
	if (-e "$hmsqldir")
	{
		#find(\&writehighmsql, \&preprocess, $hmsqldir);
		find({preprocess => \&before, wanted => \&writehighmsql}, $hmsqldir);
		#sub preprocess
		#{ 
		#	sort { uc $a cmp uc $b } @_ ;
		#}
		sub before
		{
		  print "Sorting files ";
		  sort @_
		}
		
		sub writehighmsql
		{
			if(!-d $File::Find::name)
			{
				my $msqlfile = $_;
				my $msqldir = basename($File::Find::dir);
			
				if($detailed_output){printf("Found MSQL: \n\tfile = $msqlfile\n\tdirectory = $msqldir\nWriting REPLACE and RUNSQL lines to rollout script for $msqlfile\n\n");}
				$log = $log . "Found Priority MSQL: \n\tfile = $msqlfile\n\tdirectory = $msqldir\nWriting REPLACE and RUNSQL lines to rollout script for $msqlfile \n\tREPLACE pkg/$MSQLPATH/$msqldir/$msqlfile \$LESDIR/$MSQLPATH/$msqldir\n\trunsql \$LESDIR/$MSQLPATH/$msqldir/$msqlfile\n\n";
				$replacetext = $replacetext . "REPLACE pkg/$MSQLPATH/$msqldir/$msqlfile \$LESDIR/$MSQLPATH/$msqldir\n";
				#don't want to run docs - they get run from inside other scripts
				if(uc($msqldir) ne "DOCS") 
				{
					$runhighsqltext = $runhighsqltext . "RUNSQL \$LESDIR/$MSQLPATH/$msqldir/$msqlfile\n";
				}
				$msqlexist = 1;
				$component_text = $component_text . "\t$MSQLPATH/$msqldir/$msqlfile\n";
				
			}
		}
	}
	if(!$msqlexist)
	{
		if($detailed_output){printf("No Priority MSQLs found...Continuing\n\n");}
		$log = $log . "No Priority MSQLs found...Continuing\n\n";
	}
	
	#####################################################################
	# Replace for Control File
	#####################################################################
	if($detailed_output){printf( "Checking for Control files\n");}
	$log = $log . "Checking for Control files\n";
	my $ctrlexist;
	my $ctldir = "$LESDIR/$ro_dir/pkg/$CSVPATH";
	
	#validate $ctldir exist
	if (-e "$ctldir")
	{
		find(\&writectrl, $ctldir);
	
		sub writectrl
		{
			if(!-d $File::Find::name)
			{
				my $ctrlfile = $_;
				my $pointPos = rindex($ctrlfile, "."); 			
			    my $fileExt = substr($ctrlfile,$pointPos+1); 
				if ($fileExt eq "ctl") {
					my $ctrldir = basename($File::Find::dir);
				
					if($detailed_output){printf("Found Control File: \n\tfile = $ctrlfile\n\tdirectory = $ctrldir\nWriting REPLACE to rollout script for $ctrlfile\n\n");}
					$log = $log . "Found Control File: \n\tfile = $ctrlfile\n\tdirectory = $ctrldir\nWriting REPLACE to rollout script for $ctrlfile \n\tREPLACE pkg/$CSVPATH/$ctrldir/$ctrlfile \$LESDIR/$CSVPATH/$ctrldir\n\n";
					$replacetext = $replacetext . "REPLACE pkg/$CSVPATH/$ctrldir/$ctrlfile \$LESDIR/$CSVPATH/$ctrldir\n";
					$ctrlexist = 1;
					$component_text = $component_text . "\t$CSVPATH/$ctrldir/$ctrlfile\n";
				}
				
			}
		}
	}
	if(!$ctrlexist)
	{
		if($detailed_output){printf("No Priority CTRLs found...Continuing\n\n");}
		$log = $log . "No CTRLs found...Continuing\n\n";
	}
	
	
	#####################################################################
	# MLOADS
	#####################################################################
	if($detailed_output){printf( "Checking for MLOADS\n");}
	$log = $log . "Checking for MLOADS\n";
	
	my $mloaddir = "$LESDIR/$ro_dir/pkg/$CSVPATH";
	#find({ wanted => \&writemload, no_chdir} => \&nochdir, $mloaddir);
	find(\&writemload, $mloaddir);
	sub writemload
	{
		#my $detailed_output;
		#my $log ;
		#my $replacetext;
		#my $loaddatatext;
		if(!-d $File::Find::name)
		{
			my $mloadfile = $_;
			my $pointPos = rindex($mloadfile, "."); 			
			my $fileExt = substr($mloadfile,$pointPos+1); 
			if ($fileExt eq "csv") {
				my $mloadtable = basename($File::Find::dir);
				my $mloaddir = basename(dirname($File::Find::dir));
				
				if($detailed_output){printf("Found MLOAD: \n\tfile = $mloadfile\n\ttable = $mloadtable\n\tload directory = $mloaddir\nWriting REPLACE and LOADDATA lines to rollout script for $mloadfile\n\n");}
				$log = $log . "Found MLOAD: \n\tfile = $mloadfile\n\ttable = $mloadtable\n\tload directory = $mloaddir\nWriting lines to rollout script \n\tREPLACE pkg/$CSVPATH/$mloaddir/$mloadtable/$mloadfile \$LESDIR/$CSVPATH/$mloaddir/$mloadtable\n\tLOADDATA \$LESDIR/$CSVPATH/$mloaddir/$mloadtable.ctl $mloadfile\n\n";
				$replacetext = $replacetext . "REPLACE pkg/db/data/load/base/$mloaddir/$mloadtable/$mloadfile \$LESDIR/db/data/load/base/$mloaddir/$mloadtable\n";
				# check if mloadfile is a control file or CSV one, if it is a CSV one we need to include LOADDATA command 
				my $pointPos = rindex($mloadfile, ".");
				my $fileExt = substr($mloadfile,$pointPos+1); 
				if ($fileExt eq "csv"){
					$loaddatatext = $loaddatatext . "LOADDATA \$LESDIR/$CSVPATH/$mloaddir/$mloadtable.ctl $mloadfile\n";
				}
				$loadexist = 1;
				$component_text = $component_text . "\t$CSVPATH/$mloaddir/$mloadtable/$mloadfile\n";
			}
		}
	}

	if(!$loadexist)
	{
		if($detailed_output){printf("No MLOADS found...Continuing\n\n");}
		$log = $log . "No MLOADS found...Continuing\n\n";
	}

    #####################################################################
	# Integrator Loads
	#####################################################################
	if($detailed_output){printf( "Checking for Integrator Loads\n");}
	$log = $log . "Checking for Integrator Loads\n";
	
	my $intdir = "$LESDIR/$ro_dir/pkg/$INTPATH";
	#find({ wanted => \&writeint, no_chdir} => \&nochdir, $intdir);
	find(\&writeint, $intdir);
   
	sub writeint
	{
		if(!-d $File::Find::name)
		{
			my $intfile = $_;
			
			if($detailed_output){printf("Found Integraotr Load: \n\tfile = $intfile\n\tdirectory = $intdir\nWriting REPLACE and IMPORTSLDATA lines to rollout script for $intfile\n\n");}
			$log = $log . "Found Integraotr Load: \n\tfile = $intfile\n\tdirectory = $intdir\nWriting REPLACE and IMPORTSLDATA lines to rollout script for $intfile \n\tREPLACE pkg/$intdir/$intfile \$LESDIR/$intdir\n\tUPDATESLDATA \$LESDIR/$intdir/$intfile\n\n";
			$replacetext = $replacetext . "REPLACE pkg/$INTPATH/$intfile \$LESDIR/$INTPATH\n";
			#$importsldatatext = $importsldatatext . "IMPORTSLDATA \$LESDIR/db/data/integrator/$intfile\n";
			$importsldatatext = $importsldatatext . "UPDATESLDATA \$LESDIR/$INTPATH/$intfile\n";
			
			$intexist = 1;
			$component_text = $component_text . "\t$INTPATH/$intfile\n";
		}
	}

	if(!$intexist)
	{
		if($detailed_output){printf("No Integrator Loads found...Continuing\n\n");}
		$log = $log . "No Integrator Loads found...Continuing\n\n";
	}

	#####################################################################
	# MOCA commands
	#####################################################################
	if($detailed_output){printf( "Checking for MOCA commands\n");}
	$log = $log . "Checking for MOCA commands\n";
	
	my $mocadir = "$LESDIR/$ro_dir/pkg/$MOCAPATH";
	#find({ wanted => \&writemoca, no_chdir} => \&nochdir, $mocadir);
	find(\&writemoca, $mocadir);
	sub writemoca
	{
		if(!-d $File::Find::name)
		{
			my $mocafile = $_;
			my $pointPos = rindex($mocafile, "."); 			
			my $fileExt = substr($mocafile,$pointPos+1); 
			if ($fileExt eq "mcmd" || $fileExt eq "mtrg") {
				my $mocadir = basename($File::Find::dir);
				
				if($detailed_output){printf("Found MOCA: \n\tfile = $mocafile\n\tdirectory = $mocadir\nWriting REPLACE and MBUILD lines to rollout script for $mocafile\n\n");}
				$log = $log . "Found MOCA: \n\tfile = $mocafile\n\tdirectory = $mocadir\nWriting REPLACE and MBUILD lines to rollout script for $mocafile\n\n";
				$replacetext = $replacetext . "REPLACE pkg/$MOCAPATH/$mocadir/$mocafile \$LESDIR/$MOCAPATH/$mocadir\n";
				$mocaexist = 1;
				$component_text = $component_text . "\t$MOCAPATH/$mocadir/$mocafile\n";
			}
			elsif ($fileExt eq "mlvl"){
				if($detailed_output){printf("Found MOCA: \n\tfile = $mocafile\n\tdirectory = $MOCAPATH\nWriting REPLACE and MBUILD lines to rollout script for $mocafile\n\n");}
				$log = $log . "Found MOCA: \n\tfile = $mocafile\n\tdirectory = $MOCAPATH\nWriting REPLACE and MBUILD lines to rollout script for $mocafile\n\n";
				$replacetext = $replacetext . "REPLACE pkg/$MOCAPATH/$mocafile \$LESDIR/$MOCAPATH\n";
				$mocaexist = 1;
				$component_text = $component_text . "\t$MOCAPATH/$mocafile\n";
			}
		}
	}

	if(!$mocaexist)
	{
		if($detailed_output){printf("No MOCA commands found...Continuing\n\n");}
		$log = $log . "No MOCA commands found...Continuing\n\n";
	}
	else
	{
		$mbuildtext = $mbuildtext . "MBUILD\n";
	}
	
	#####################################################################
	# Labels
	#####################################################################
	if($detailed_output){printf( "Checking for Labels\n");}
	$log = $log . "Checking for Labels\n";
	my $labelexist;
	my $labeldir = "$LESDIR/$ro_dir/pkg/$LBLPATH";
	#find({ wanted => \&writelabel, no_chdir} => \&nochdir, $labeldir);
	find(\&writelabel, $labeldir);
	sub writelabel
	{
		if(!-d $File::Find::name)
		{
			my $labelfile = $_;
			my $labeldir = basename($File::Find::dir);
			
			if($detailed_output){printf("Found Label: \n\tfile = $labelfile\n\tdirectory = $labeldir\nWriting REPLACE line to rollout script for $labelfile\n\n");}
			$log = $log . "Found Label: \n\tfile = $labelfile\n\tdirectory = $labeldir\nWriting REPLACE line to rollout script for $labelfile \n\tREEPLACE pkg/$LBLPATH/$labeldir/$labelfile \$LESDIR/$LBLPATH/$labeldir\n\n";
			$replacetext = $replacetext . "REPLACE pkg/$LBLPATH/$labeldir/$labelfile \$LESDIR/$LBLPATH/$labeldir\n";
			$labelexist = 1;
			$component_text = $component_text . "\tlabels/$labeldir/$labelfile\n";
		}
	}

	if(!$labelexist)
	{
		if($detailed_output){printf("No labels found...Continuing\n\n");}
		$log = $log . "No labels commands found...Continuing\n\n";
	}


	#####################################################################
	# Reports
	#####################################################################
	if($detailed_output){printf( "Checking for reports\n");}
	$log = $log . "Checking for reports\n";
	my $reportexist;
	my $reportdir = "$LESDIR/$ro_dir/pkg/$RPTPATH";
	#find({ wanted => \&writereport, no_chdir} => \&nochdir, $reportdir);
	find(\&writereport, $reportdir);
	sub writereport
	{
		if(!-d $File::Find::name)
		{
			my $reportfile = $_;
			my $reportdir = basename($File::Find::dir);
			
			if($detailed_output){printf("Found report: \n\tfile = $reportfile\n\tdirectory = $reportdir\nWriting REPLACE line to rollout script for $reportfile\n\n");}
			$log = $log . "Found report: \n\tfile = $reportfile\n\tdirectory = $reportdir\nWriting REPLACE line to rollout script for $reportfile \n\tREEPLACE pkg/$RPTPATH/$reportdir/$reportfile \$LESDIR/$RPTPATH/$reportdir\n\n";
			$replacetext = $replacetext . "REPLACE pkg/$RPTPATH/$reportdir/$reportfile \$LESDIR/$RPTPATH/$reportdir\n";
			$reportexist = 1;
			$component_text = $component_text . "\t$RPTPATH/$reportdir/$reportfile\n";
		}
	}

	if(!$reportexist)
	{
		if($detailed_output){printf("No reports found...Continuing\n\n");}
		$log = $log . "No reports commands found...Continuing\n\n";
	}



	
	#####################################################################
	# MSQL for Low Priority scripts
	#####################################################################
	if($detailed_output){printf( "Checking for Low Priority MSQL (database changes) files\n");}
	$log = $log . "Checking for Low Priority MSQL (database changes) files\n";
	my $msqlexist;
	my $lmsqldir = "$LESDIR/$ro_dir/pkg/$LMSQLPATH";
	#find({ wanted => \&writemsql, preprocess => \&preprocess, no_chdir} => \&nochdir, $msqldir);
	#validate $msqldir exist
	if (-e "$lmsqldir")
	{
		#find(\&writemsql, \&preprocess, $lmsqldir);
		find({preprocess => \&before, wanted => \&writemsql}, $lmsqldir);
		#sub preprocess
		#{ 
		#	sort { uc $a cmp uc $b } @_ ;
		#}
		sub before
		{
		  print "Sorting files ";
		  sort @_
		}
		
		sub writemsql
		{
			if(!-d $File::Find::name)
			{
				my $msqlfile = $_;
				my $msqldir = basename($File::Find::dir);
			
				if($detailed_output){printf("Found Low Priority MSQL: \n\tfile = $msqlfile\n\tdirectory = $msqldir\nWriting REPLACE and RUNSQL lines to rollout script for $msqlfile\n\n");}
				$log = $log . "Found Low Priority MSQL: \n\tfile = $msqlfile\n\tdirectory = $msqldir\nWriting REPLACE and RUNSQL lines to rollout script for $msqlfile \n\tREPLACE pkg/$MSQLPATH/$msqldir/$msqlfile \$LESDIR/$MSQLPATH/$msqldir\n\trunsql \$LESDIR/$MSQLPATH/$msqldir/$msqlfile\n\n";
				$replacetext = $replacetext . "REPLACE pkg/$MSQLPATH/$msqldir/$msqlfile \$LESDIR/$MSQLPATH/$msqldir\n";
				#don't want to run docs - they get run from inside other scripts
				if(uc($msqldir) ne "DOCS" )
				{
					$runlowsqltext = $runlowsqltext . "RUNSQL \$LESDIR/$MSQLPATH/$msqldir/$msqlfile\n";
				}
				$msqlexist = 1;
				$component_text = $component_text . "\t$MSQLPATH/$msqldir/$msqlfile\n";
				
			}
		}
	}
	if(!$msqlexist)
	{
		if($detailed_output){printf("No Low Priority MSQLs found...Continuing\n\n");}
		$log = $log . "No Low Priority MSQLs found...Continuing\n\n";
	}

    #####################################################################
	# MTF files
	#####################################################################
	if($detailed_output){printf( "Checking for MTF files\n");}
	$log = $log . "Checking for MTF files\n";
	my $mtfexist;
	my $mtfdir = "$LESDIR/$ro_dir/pkg/$MTFPATH";
	#find({ wanted => \&writemtf, no_chdir} => \&nochdir, $mtfdir);
	find(\&writemtf, $mtfdir);
	sub writemtf
	{
		if(!-d $File::Find::name)
		{
			my $mtffile = $_;
			
			if($detailed_output){printf("Found MTF File: \n\tfile = $mtffile\nWriting REPLACE and REBUILD LES lines to rollout script for $mtffile\n\n");}
			$log = $log . "Found MTF File: \n\tfile = $mtffile\nWriting REPLACE and REBUILD LES lines to rollout script for $mtffile\n\n";
			$replacetext = $replacetext . "REPLACE pkg/$MTFPATH/$mtffile \$LESDIR/$MTFPATH\n";
			$mtfexist = 1;
			$component_text = $component_text . "\t$MTFPATH/$mtffile\n";
		}
	}

	if(!$mtfexist)
	{
		if($detailed_output){printf("No MTF files found...Continuing\n\n");}
		$log = $log . "No MTF files found...Continuing\n\n";
	}
	else
	{
		$rebuildtext = $rebuildtext . "REBUILD LES\n";
	}

	#####################################################################
	# README file
	#####################################################################

	if($readme)
	{
		#remove any previous creations of readme file
		if($detailed_output){printf("Removing any previous creations of readme file\n\n");}
		$log = $log . "Removing any previous creations of readme file\n\n";
		unlink("$LESDIR/$ro_dir/README.txt");

		#write rollout script
		if($detailed_output){printf("Creating README file\n\n");}
		$log = $log . "Creating README file\n\n";
		$readme_text = "================================================================================\n";
		my $curdate = localtime;
		$curdate = sprintf "%d-%02d-%02d", $curdate->year+1900, ($curdate->mon)+1, $curdate->mday;

		my $next_line = "Extension: $ro_name";
		$next_line .= (" " x (70 - length($next_line)));
		$next_line = $next_line . $curdate;
		$readme_text = $readme_text . $next_line . "\n================================================================================\n";
		$readme_text = $readme_text . "\n" . $issue_text . "\n\n" . $component_text . "\n\n" . $remove_text . "\n\n" . $notes_text . "\n\n";
		$readme_text = $readme_text . "================================================================================\n               W I N D O W S   I N S T A L L A T I O N   N O T E S             \n================================================================================\n\n    1.  Start a Windows command prompt as an Administrator user\n\n    2.  Set Visual C++ environment variables.\n\n        You will first have to change to the Visual C++ bin directory if it \n       isn't in your search path.\n\n        vcvars32.bat\n\n    3.  Set RedPrairie environment variables.\n\n        cd %LESDIR%\\data\n        ..\\moca\\bin\\servicemgr /env=<environment name> /dump\n        env.bat\n\n        Note: If you know your env.bat file is current you can omit this step,\n              if you are not sure then rebuild one.\n\n    4.  Shutdown the RedPrairie instance:  \n\n        NON-CLUSTERED Environment\n\n        *** IMPORTANT ***\n        If you are on a production system, make sure the development system \n        whose drive has been mapped to the system being modified has also been \n        shutdown to avoid sharing violations.\n\n        net stop moca.<environment name>\n\n        (Or use the Windows Services snap-in to stop the RedPrairie service.\n\n        CLUSTERED Environment\n       \n        If you are running under a Windows Server Cluster, you must use the\n        Microsoft Cluster Administrator to stop the RedPrairie Service.\n\n    5.  Copy the rollout distribution file into the environment's rollout \n        directory.\n\n        cd -d %LESDIR%\\rollouts\n        copy <SOURCE_DIR>\\".$ro_name.".zip .\n\n    6.  Uncompress the distribution file using your preferred unzip utility  \n\n        Make sure you extract all the files to a folder called ".$ro_name.".\n\n    7.  Install the rollout.\n\n        perl -S rollout.pl ".$ro_name."\n\n    8.  Start up the RedPrairie instance:\n\n        NON-CLUSTERED Environment\n       \n        net start moca.<environment name>\n\n        (Or use the Windows Services snap-in to restart the RedPrairie service.\n\n        CLUSTERED Environment\n\n        If you are running under a Windows Server Cluster, you must use the\n        Microsoft Cluster Administrator to start the RedPrairie Service.\n\n\n================================================================================\n                 U N I X   I N S T A L L A T I O N   N O T E S             \n================================================================================\n\n    1.  Login as the Logistics Suite environment's administrator.\n\n        ssh <user>@<hostname>\n\n    2.  Shutdown the RedPrairie instance:\n\n        rp stop\n  \n    3.  Copy the rollout distribution file into the environment's rollout \n        directory.\n\n        cd $LESDIR/rollouts\n        cp <SOURCE_DIR>//".$ro_name.".tar .\n\n    4.  Untar the rollout archive file using tar.\n\n        tar -xvfz ".$ro_name.".tar \n\n    5.  Install the rollout.\n\n        perl -S rollout.pl ".$ro_name."\n\n    6.  Start up the RedPrairie instance:\n\n        rp start\n\n================================================================================\n";
		open(OUTF, ">>$LESDIR/$ro_dir/README.txt");
		print OUTF $readme_text;
		close(OUTF);
		$log = $log . "Created README file in $LESDIR/$ro_dir \n\n";
		printf("Created README file in $LESDIR/$ro_dir \n\n");
	}
    
    
    # if we are removing a moca command, write MBUILD
    if($remove_ro_text =~ /.*REMOVE.*mcmd.*/ || $remove_ro_text =~ /.*REMOVE.*mtrg.*/)
    {
        $mbuildtext = $mbuildtext . "MBUILD\n";
    }

	#####################################################################
	# Create rollout script
	#####################################################################

	#remove any previous creations of rollout script
	if($detailed_output){printf("Removing any previous creations of rollout script $ro_name\n\n");}
	$log = $log . "Removing any previous creations of rollout script $ro_name\n\n";
	unlink("$LESDIR/$ro_dir/$ro_name");

	#write rollout script
	if($detailed_output){printf("Creating rollout script $ro_name\n\n");}
	$log = $log . "Creating rollout script $ro_name\n\n";
	open(OUTF, ">>$LESDIR/$ro_dir/$ro_name");
	print OUTF $ro_script . "\n" . $remove_ro_text . "\n" . $runhighsqltext . "\n" .  $replacetext . "\n". $rotext . "\n" . $loaddatatext . "\n" . $importsldatatext . "\n" . $runlowsqltext . "\n" . $rebuildpretext . "\n" . $rebuildtext . "\n" . $mbuildtext . "\n" ."#END OF SCRIPT";
	close(OUTF);
	
	$log = $log . "Created Rollout file $ro_name in $LESDIR/$ro_dir \n\n";
	printf("Created Rollout file $ro_name in $LESDIR/$ro_dir \n\n");

	#####################################################################
	# Tar up directory - if -p parameter passed in
	#####################################################################
	if($pack)
	{
		#remove any previous creations of tar file
		my $rodirup = dirname($ro_dir);

		if($detailed_output){printf("Removing any previous creations of tar file $ro_name.tar\n\n");}
		$log = $log . "Removing any previous creations of tar file $ro_name.tar\n\n";
		unlink("$LESDIR/$rodirup/$ro_name.tar");
					
		if($detailed_output){printf("Tarring directory <$ro_dir> to $ro_name.tar\n\n");}
		$log = $log . "Tarring directory <$ro_dir> to $ro_name.tar\n\n";

		chdir("$LESDIR/$rodirup");
		system("tar -cvf $ro_name.tar $ro_name>>tmp.txt");
		unlink("tmp.txt");
		
		$log = $log . "Created Tar file $ro_name.tar in $LESDIR/$rodirup \n\n";
		printf("Created Tar file $ro_name.tar in $LESDIR/$rodirup \n\n");
	
		my $finaldir = $ro_tar_dir.$git_branch_name;
		
		create_ro_dir($finaldir);
		# delete old tar files 
		printf("Delete old TAR files from $finaldir\n\n");
		system("rm $finaldir/*.tar");
		printf("Move Tar file to its final directory into $finaldir\n\n");
		system("mv $ro_name.tar $finaldir");
		
		#Cleaning the working directory 
		chdir("$LESDIR/$rodirup");
		system("rm -r $LESDIR/$ro_dir");
		system("rm $LESDIR/$rodirup/$SrcInputFile");
	}
	
	if($logfile)
	{
		if($detailed_output){printf("Writing to log file $LESDIR/log/$logfile\n\n");}
		$log = $log . "Writing to log file $LESDIR/log/$logfile\n\n";

		open(OUTLOG, ">>$LESDIR/log/$logfile");
		print OUTLOG $log;
		close(OUTLOG);
	}
}#package_rollout

#####################################################################
#####################################################################
# MAIN CreateRolloutPackage
#####################################################################
#####################################################################

#get options
getopts('g:t:c:d:z:b:r:l:ohn:fpum', \%opts);
#perl createRolloutPackage.pl -g  "M javalib/barcode4j-2.2.jar M src/cmdsrc/usrint/remove_load-remove_usr_inventory_asset.mtrg A reports/usrint/usr-rfh001-v0110-ffdeliverynote.jrxml M db/ddl/afterrun/90_Rollout_install_insert.msql A db/ddl/prerun/20_delete_data.msql A db/ddl/afterrun/80_integrator_sys_comm.msql" -t "/y/Docker/MY-GIT/SWBYDEMO" -n RLTEST1 -d rollout -r inputFile.txt -f -l RLTEST1.log -p -o -m

# get the arguments
$s = $opts{g} if defined($opts{g}); #list of modified files
$LESDIR = $opts{t} if defined($opts{t}); #LESDIR
$customer = $opts{c} if defined($opts{c}); #customer name matches the file name where we store some env variables 
$ro = $opts{r} if defined($opts{r}); #-r - required - rollout input file
$ro_dir = $opts{d} if defined($opts{d}); #-d - required - directory where the rollout input file is located
$ro_tar_dir = $opts{z} if defined($opts{z});#-z - required - directory where the tar rollout file will be located
$git_branch_name = $opts{b} if defined($opts{b});#-b - required - branch name
$logfile = $opts{l} if defined($opts{l});
$detailed_output = $opts{o} if defined($opts{o});
$ro_name = $opts{n} if defined($opts{n}); #-n - required - Rollout name
$force_delete = $opts{f} if defined($opts{f});
$pack = $opts{p} if defined($opts{p});
$build_script = $opts{u} if defined($opts{u});
$build_readme = $opts{m} if defined($opts{m});
$SrcInputFile = $ro ;
my $help = $opts{h} if defined($opts{h});

if($help)
{
	show_usage();
}





# Opening a file and reading content  
#if(open($vOutputFile, '<', $SrcInputFile))  
#{  
#    while($vOutputFile)  
#    {  
#        print $_;  
#    }  
#}  
  
# Executes if file not found  
#else
#{  
#  warn "Couldn't Open a file $filename";  
#}  

#close(vOutputFile); 
printf("Input file had been created!\n\n");
#validate ro argument passed in
if(!$ro)
{
	#if a name was specified, we'll try to use ro_name.ro
	if(!$ro_name)
	{
		printf("ERROR! -r rollout file must be defined!\n\n");
		$log = "ERROR! -r rollout file must be defined!\n\n";
		if($logfile)
		{
			open(OUTF, ">>$LESDIR/log/$logfile");
			print OUTF $log;
		}
		show_usage();
        exit 0;
	}
	else
	{
		$ro = $ro_name . ".ro";
	}
}

# rollout directory
if($ro_dir)
{
	$orig_dir = $ro_dir;
	$ro_dir = $LESDIR . "/" . $ro_dir . "/";
}
else
{
	if(!-d $LESDIR . "/" . "rollout")
	{
		$orig_dir = "rollouts";
		$ro_dir = $LESDIR . "/rollouts/";
	}
	else
	{
		$orig_dir = "rollout";
		$ro_dir = $LESDIR . "/rollout/";
	}
}

# rollout TAR directory
if($ro_tar_dir)
{
	$ro_tar_dir = $LESDIR . "/" . $ro_tar_dir . "/";
}
else
{
	$ro_tar_dir = $LESDIR . "/rollout_gen/";
}

# rollout directory parameter -  to be passed to pull_files
$ro_dir_parm = "-p " . $ro_dir ;

# logfile parameter -  to be passed to pull_files
if($logfile)
{
	$logfile_parm = "-l " . $logfile;
}

# detailed_output parameter -  to be passed to pull_files
if($detailed_output)
{
	$detailed_output_parm = "-o ";
}

# readme parameter -  to be passed to package_rollout
if($build_readme)
{
	$readme_parm = "-m ";
}



#validate ro_name argument passed in
if(!$ro_name)
{
	#if we 
	if($ro)
	{
		$ro_name = $ro;
		$ro_name =~ s/\.ro//;
	}
	else
	{
		printf("ERROR! -n rollout name must be defined!\n\n");
		$log = "ERROR! -n rollout name must be defined!\n\n";
		if($logfile)
		{
			open(OUTF, ">>$LESDIR/log/$logfile");
			print OUTF $log;
		}
		show_usage();
		exit 0;
	}
}

# logging
if($detailed_output){printf( "Creating Rollout Directory \n\nCurrent Time: " . localtime() . "\n\nOptions\nRollout Directory = $ro_dir$ro_name\nlogfile = $logfile\n\nEnvironment:\nLESDIR = $LESDIR\nLog directory=$LESDIR\log\nRollout Name = $ro_name\n\n");}
$log = $log . "Creating Rollout Directory \n\nCurrent Time: " . localtime() . "\n\nOptions\nRollout Directory = $ro_dir$ro_name\nlogfile = $logfile\n\nEnvironment:\nLESDIR = $LESDIR\nLog directory=$LESDIR\log\nRollout Name = $ro_name\n\n";

#checking customer file exists
printf("Check if Customer File $customer Exists\n");
my $custfilename = $customer.".txt";
my $custfilepth =  $LESDIR . "/scripts/";;
printf("Check if Customer File $custfilename Exists\n");
# Check if the Input File exists

if (!-e  $custfilepth.$custfilename)
{
	printf("Customer File Does Not Exist\n");
}
else
{
	# reading customer data
	open($CustomerFile, '<:encoding(UTF-8)', $custfilepth.$custfilename) or die "Could not open file $custfilename !";
	printf("Customer file is opened for reading\n");
	while (my $line = <$CustomerFile>)
	{
		#printf("Starting reading the Customer file\n");
		chomp $line;
    	#printf("Got Line:$line\n");
		my $pointPos = rindex($line, "="); 
        my $envpath = trim(substr($line,0,$pointPos));
		my $envval = trim(substr($line,$pointPos+1));
		chomp $envval;
		#printf("Current envpath:'$envpath'\n");
		#printf("Current envval:'$envval'\n");
		if($envpath eq "RPTPATH")
		{ 
			$RPTPATH = $envval;
			printf(">>>>>>>>>>>>>Current RPTPATH:'$RPTPATH'\n");
		}
		elsif ($envpath eq "LBLPATH")
		{
			$LBLPATH = $envval;
			printf(">>>>>>>>>>>>>Current LBLPATH:'$LBLPATH'\n");
		}
		elsif ($envpath eq "MOCAPATH")
		{
			$MOCAPATH = $envval;
			printf(">>>>>>>>>>>>>Current MOCAPATH:'$MOCAPATH'\n");
		}
		elsif ($envpath eq "JARPATH")
		{
			$JARPATH = $envval;
			printf(">>>>>>>>>>>>>Current JARPATH:'$JARPATH'\n");
		}
		elsif ($envpath eq "CSVPATH")
		{
			$CSVPATH = $envval;
			printf(">>>>>>>>>>>>>Current CSVPATH:'$CSVPATH'\n");
		}
		elsif ($envpath eq "HMSQLPATH")
		{
			$HMSQLPATH = $envval;
			printf(">>>>>>>>>>>>>Current HMSQLPATH:'$HMSQLPATH'\n");
		}
		elsif ($envpath eq "MSQLPATH")
		{
			$MSQLPATH = $envval;
			printf(">>>>>>>>>>>>>Current MSQLPATH:'$MSQLPATH'\n");
		}
		elsif ($envpath eq "LMSQLPATH")
		{
		    $LMSQLPATH = $envval;
			printf(">>>>>>>>>>>>>Current LMSQLPATH:'$LMSQLPATH'\n");
		}
		elsif ($envpath eq "MTFPATH")
		{
			$MTFPATH = $envval;
			printf(">>>>>>>>>>>>>Current MTFPATH:'$MTFPATH'\n");
		}
		elsif ($envpath eq "INTPATH")
		{
			$INTPATH = $envval;
			printf(">>>>>>>>>>>>>Current INTPATH:'$INTPATH'\n");
		}
	}	
	close($CustomerFile);
	printf("\n");
	


printf("Check if Input File   $ro_dir.$ro Exists\n");
# Check if the Input File exists
if (!-e  $ro_dir.$ro)
{
	printf("Input File Does Not Exist\n");
	#my $s = 'A db/data/load/base/bootstraponly/poldat/lc_be03_otm_poldat_swiftlex-2715.csv M src/cmdsrc/usrint/send_lc_be03_otm_transport_plan.mcmd';
	#my $s = 'A db/data/load/base/bootstraponly/client/client.csv A db/data/load/base/bootstraponly/adrmst/adrmst.csv A db/data/load/base/bootstraponly/client_wh/client_wh.csv';
	#my $s = 'M javalib/barcode4j-2.2.jar M src/cmdsrc/usrint/remove_load-remove_usr_inventory_asset.mtrg A reports/usrint/usr-rfh001-v0110-ffdeliverynote.jrxml M db/ddl/afterrun/90_Rollout_install_insert.msql A db/ddl/prerun/20_delete_data.msql A db/ddl/afterrun/80_integrator_sys_comm.msql';

	print "*******************************\nOriginal files:",$s,"\n*******************************\n";


	my @addModFiles = split /((?:A|M)\s\S*\s*)/, $s;
	my @delFiles = split /(D\s\S*\s*)/, $s;
	#print Dumper \@addModFiles;
	# open destination file for writing 
	open my $vInputFile, '>', $SrcInputFile;
	# EX. A db/data/load/base/bootstraponly/poldat/lc_be03_otm_poldat
	foreach my $file (@addModFiles)  
	{ 
		if($file){
			print "Looking into $file\n\n\n"; 
			my $firstChar = substr($file,0,1);
			#print "firstChar $firstChar\n\n\n"; 
			if($firstChar eq "A" or $firstChar eq "M")
			{
				my $pointPos = rindex($file, "."); 
				print "Position of point: $pointPos\n"; 
				my $slashPos = rindex($file, "/"); 
				print "Right Slash position: $slashPos\n"; 
				my $fileExt = substr($file,$pointPos+1); 
				my $fileFullName = substr($file,$slashPos+1); 
				$fileFullName=~ s/\s+$//;
				$fileExt=~ s/\s+$//;
				print "File Name: *$fileFullName*\n"; 
				print "File extension: *$fileExt*\n"; 
				# Map MOCA and triggers files 
				if ($fileExt eq "mcmd" || $fileExt eq "mtrg") {
					my $mlvl_dir = substr(substr($file,0,$slashPos),rindex(substr($file,0,$slashPos), "/")+1);
					print "mlvl_dir: $mlvl_dir\n";
					#MOCA -d usrint -f "list_usr_1234.mcmd"
					my $fullFileSyntax = "MOCA -d ".$mlvl_dir." -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 		
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map MLVL files 
				elsif ($fileExt eq "mlvl" ){
					#MLVL -f UcTest1.mlvl
					my $fullFileSyntax = "MLVL -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 		
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map CSV files 
				elsif ($fileExt eq "csv"){
					#SQL -t poldat  -f "UC_1234.csv"
					my $table_name = substr(substr($file,0,$slashPos),rindex(substr($file,0,$slashPos), "/")+1);
					#print "table_name: $table_name\n";
					my $fullFileSyntax = "SQL -t ".$table_name." -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 
					
					print {$vInputFile} $fullFileSyntax . "\n";
					
				}
				# Map CTL files 
				elsif ($fileExt eq "ctl" ){
					#CTL -f UcTest1.ctl
					my $fullFileSyntax = "CTL -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 		
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map MSQL files 
				elsif ($fileExt eq "msql"){
					#DDL -d Tables -f prtmst_view-UC_1234.msql
					my $msqldir = substr(substr($file,0,$slashPos),rindex(substr($file,0,$slashPos), "/")+1);
					print "msqldir: $msqldir\n";
					my $fullFileSyntax = "DDL -d ".$msqldir." -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 
					
					print {$vInputFile} $fullFileSyntax . "\n";
				}		
				# Map POF files 
				elsif ($fileExt eq "POF"){
					#LABEL -d z140xiII -f UC_1234.POF
					my $table_name = substr(substr($file,0,$slashPos),rindex(substr($file,0,$slashPos), "/")+1);
					print "table_name: $table_name\n";
					my $fullFileSyntax = "LABEL -d ".$table_name." -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 
					
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map REPORTS files 
				elsif ($fileExt eq "jrxml"){
					#REPORT -d usrint -f UC_1234.jrxml
					my $table_name = substr(substr($file,0,$slashPos),rindex(substr($file,0,$slashPos), "/")+1);
					print "table_name: $table_name\n";
					my $fullFileSyntax = "REPORT -d ".$table_name." -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 
					
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map JAVA files 
				elsif ($fileExt eq "jar"){
					#FILE -d javalib -f UC_1234.jar
					my $table_name = substr($file,2,$slashPos-2);
					print "table_name: $table_name\n";
					my $fullFileSyntax = "FILE -d ".$table_name." -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 
					
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map MTF Java files
				elsif ($fileExt eq "java" ){
					#MTF -f UcTest1.java
					my $fullFileSyntax = "MTF -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 		
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map MTF properties files
				elsif ($fileExt eq "properties" ){
					#MTF -f UcTest1.properties
					my $fullFileSyntax = "MTF -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 		
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				# Map Integrator files  
				elsif ($fileExt eq "slexp" ){
					#INT -f UC_1234.slexp
					my $fullFileSyntax = "INT -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 		
					print {$vInputFile} $fullFileSyntax . "\n";
				}
				print "------------------------------------------\n\n\n"; 
			}
		}
	} # end dealing with added/modified files
	
	foreach my $file (@delFiles)  
	{ 
		if($file){
			print "Looking into $file\n\n\n"; 
			
			my $pointPos = rindex($file, "."); 
			print "Position of point: $pointPos\n"; 
			my $slashPos = rindex($file, "/"); 
			print "Right Slash position: $slashPos\n"; 
			my $fileExt = substr($file,$pointPos+1); 
			my $fileFullName = substr($file,$slashPos+1); 
			$fileFullName=~ s/\s+$//;
			$fileExt=~ s/\s+$//;
			print "File Name: *$fileFullName*\n"; 
			print "File extension: *$fileExt*\n";
			my $firstChar = substr($file,0,1);
			#print "firstChar $firstChar\n\n\n"; 
			if($firstChar eq "D")
			{
				# delete MOCA and triggers files 
				if ($fileExt eq "mcmd" || $fileExt eq "mtrg") {
					#REMOVE -d usrint -f "list_usr_1234.mcmd"
					my $table_name = substr(substr($file,0,$slashPos),rindex(substr($file,0,$slashPos), "/")+1);
					print "table_name: $table_name\n";
					my $fullFileSyntax = "REMOVE -d ".$table_name." -f \"".$fileFullName."\"";
					#my $fullFileSyntax = "REMOVE -d usrint -f \"".$fileFullName."\"";
					print "File syntax: $fullFileSyntax\n"; 		
					print {$vInputFile} $fullFileSyntax . "\n";
				}
			}
		}
	}# end dealing with deleted files
	
	close($vInputFile); 
    printf("Moving $LESDIR/$SrcInputFile into $ro_dir\n");
	#eval { make_path($ro_dir,{mode => 0777}) };
	#if ($@) {
	#  print "Couldn't create $ro_dir: $@";
	#}
        unless( -e $ro_dir ) {  print "Path $ro_dir doesn't exist"; };
	move("$LESDIR/$SrcInputFile", "$ro_dir") or die "Move failed: $!";
        printf("$SrcInputFile moved\n");
} # done creating input file
printf("Validating $SrcInputFile\n");
#validate ro file exist
if (!-e "$ro_dir$ro")
{
	printf("ERROR! rollout file ($ro_dir$ro) does not exist\n\n");
	$log = "ERROR! rollout file ($ro_dir$ro) does not exist\n\n";
	if($logfile)
	{
		open(OUTF, ">>$LESDIR/log/$logfile");
		print OUTF $log;
	}
	show_usage();
	
	exit 0;
}
printf("Checking if $ro_name exists\n");
#if ro directory already exists, stop - need to delete directory first
#we don't want to do this automatically in case it is the wrong ro name
#UNLESS they pass in -f argument to force delete of existing directory
if(-d $ro_dir . $ro_name && !$force_delete)
{
	printf("ERROR! directory $ro_dir$ro_name already exists!  Manually delete the directory or use -f option to force delete.\n\n");
	$log = $log . "ERROR! directory $ro_dir$ro_name already exists!  Manually delete the directory or use -f option to force delete.\n\n";
	$error_text = $error_text .  "- ERROR! directory $ro_dir$ro_name already exists!  Manually delete the directory or use -f option to force delete.\n";
	$errors_exist = 1;
	if($logfile)
	{
		open(OUTF, ">>$LESDIR/log/$logfile");
		print OUTF $log;
	}
	exit 0;
}
elsif (-d $ro_dir . $ro_name)
{
	if($detailed_output){printf( "Rollout directory ($ro_dir.$ro_name) already exists. \n-f option passed in so we will remove it\nRemoving Directory...\n\n");}
	$log = $log . "Rollout directory ($ro_dir.$ro_name) already exists. \n-f option passed in so we will remove it\nRemoving Directory...\n\n";
	rmtree($ro_dir . $ro_name);
}

if($detailed_output){printf( "Reading file $ro to get options for creating rollout directory\n\n");}
$log = $log . "Reading file $ro to get options for creating rollout directory\n\n";


$ro_name_parm = "-r $ro_name ";

my $line_count = 0;
printf(" $ro_dir$ro\n");
 

# Opening a file and reading content  

# Loop through the rollout input file and pass each line to pull_files function

open($vOutputFile, '<:encoding(UTF-8)', $ro_dir.$ro) or die "Could not open file '$ro_dir.$ro' $!";
printf("Input file is opened for reading\n");
while (my $line = <$vOutputFile>)
{
	printf("Starting reading the input file\n");
	# cannot send d, t, f, s, or n parameters to pull_files as these are reserved
	# for use in the ro file
	#chomp;
	# don't read line if it starts with #
	
	chomp $line;
	printf("Got Line:$line\n");
	$line_count = $line_count + 1;
	

	#if($detailed_output){printf("Got Line:$line\n");}
	#$log = $log . "Got Line:$line\n";
	
	my $pull_file_string ="-c $line $ro_name_parm $ro_dir_parm $logfile_parm $detailed_output_parm\n";
	#if($detailed_output){printf( "Calling pull_files function with: $pull_file_string \n\n");}
	$log = $log . "Calling pull_files function with: $pull_file_string \n\n";
	
	#write to log since we may get new info for the log in pull_files
	write_log();
	#call pull files
	printf("Pull Line:$pull_file_string\n");
	pull_files($pull_file_string);
	
}
if($line_count > 0)
{
	$log = $log . "Finished calls to pull_files.  Read in and processed $line_count lines. \n\n";
	printf("Finished calls to pull_files.  Read in and processed $line_count lines. \n\n");
}
# if -p parameter was passed in, we will package the rollout after creating the directory
if($pack or $build_script)
{
	my $pack_parm;
	if($pack)
	{
		$pack_parm = '-p';
	}
	my $pack_cmd = "-d $orig_dir/$ro_name $logfile_parm $detailed_output_parm $pack_parm $readme_parm\n";
	if($detailed_output){printf( "Calling package_rollout function with: $pack_cmd \n\n");}
	$log = $log . "Calling package_rollout function with: $pack_cmd \n\n";
	#write to log since we may get new info for the log in package_rollout
	write_log();
	#call package_rollout
	package_rollout($pack_cmd);
}	
close($vOutputFile);
printf("\n");
if($warnings_exist == 1)
{
	printf($warning_text . "\n");
}
if($errors_exist == 1)
{
	printf($error_text);
}

}
exit 0;
