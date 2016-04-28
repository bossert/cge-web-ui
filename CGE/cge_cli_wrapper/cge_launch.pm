#!/usr/bin/env perl

package CGE::cge_cli_wrapper::cge_launch;

use strict;
use 5.016;
use IPC::Cmd qw(can_run run);
use Carp qw(croak cluck carp);
use Net::EmptyPort qw(check_port);
use File::Tail;
use POSIX;
require Exporter;

our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(cge_start cge_stop_graceful cge_stop_scancel);
our %EXPORT_TAGS = (ALL => [ qw(cge_start cge_stop_graceful cge_stop_scancel) ]);

#=+ This module will wrap the cge-launch command-line application
my $cge_launch = can_run('cge-launch') or croak $!;
my $cge_cli    = can_run('cge-cli') or croak $!;
my $cge_scancel = can_run('scancel') or croak $!;

sub cge_start {
  my($arg_ref) = @_;

  #=+ We need to put all our command-line arguments in a hash and we are defining the known keys
  my %arguments = (
    dataDir        => '', #=+ mandatory
    resultDir      => '',
    logFile        => '',
    queryPort      => '',
    configFile     => '',
    inRPNmsg       => '',
    inRPNmsgsFile  => '',
    envVarPassList => '',
    servArgs       => '',
    CGEServerPath  => '',
    sessionTimeout => '',
    heapSize       => '',
    imagesPerNode  => '', #=+ mandatory
    nodeCount      => '', #=+ mandatory
    runOpts        => '',
    startupTimeout => '',
    cleanupScript  => '',
    partition      => ''
  );

  #=+ Here are the default file names we will use for logs and temp files
  my $datestring = strftime("%Y%m%d_%H%M%S",localtime(time));
  my $logfileName = 'cge_logfile_'.$datestring.'.log';
  my $launch_stdout_file = 'cge_launch_stdout_stderr.txt';
  my $stop_stdout_file = 'cge_stop_stdout_stderr.txt';
  my $cleanup_script_file = 'cge_launch_cleanup.sh';

  #=+ iterate over provided config and replace defaults
  while(my($k,$v) = each %$arg_ref) {
    #=+ Replace each default value if the key exists.  Perhaps paranoid, but prevent arbitrary/unexpected settings
    $arguments{$k} = $v if exists $arguments{$k};
  }

  #=+ Make sure we have a bare minimum of settings
  return (undef,undef) if $arguments{dataDir} eq '' || !-d $arguments{dataDir} || $arguments{imagesPerNode} eq '' || $arguments{nodeCount} eq '';

  #=+ Create the results directory
  #   make sure that our directory has a trailing slash "/"
  $arguments{dataDir} .= '/' unless $arguments{dataDir} =~ m/\/$/;

  #=+ Create the results directory if it does not exist
  mkdir $arguments{dataDir}.'.cge_web_ui/results', 0744 unless -d $arguments{dataDir}.'.cge_web_ui/results';
  $arguments{resultDir} = $arguments{dataDir}.'.cge_web_ui/results';

  #=+ Create a temporary directory to store all the junk files we create for easy cleanup later
  mkdir $arguments{dataDir}.'.cge_web_ui/temp', 0744 unless-d $arguments{dataDir}.'.cge_web_ui/temp';

  #=+ Create the logfile directory if it doesn't exist
  mkdir $arguments{dataDir}.'.cge_web_ui/log', 0744 unless -d $arguments{dataDir}.'.cge_web_ui/log';
  $arguments{logFile} = $arguments{dataDir}.'.cge_web_ui/log/'.$logfileName;

  #=+ Make sure we have both the number of instances and number of desired nodes
  return (undef,undef) unless $arguments{imagesPerNode} > 0 && $arguments{nodeCount} > 0;

  #=+ Create a cleanup script that we will use to kill "this" server session
  $arguments{cleanupScript} = $arguments{dataDir}.'.cge_web_ui/temp/'.$cleanup_script_file;

  #=+ Make sure we have a free TCP port to use
  my $port = 3750;
  if(check_port($port)) {
    $port++;
    while(check_port($port)) {
      $port++;
    }
  }
  $arguments{queryPort} = $port;

  #=+ Concatenate all the non-blank command line arguments
  my @args;
  while(my($k,$v) = each %arguments) {
    push @args, '--'.$k.' '.$v.' ' unless $v eq '';
  }
  my $arg_string = join('',@args);

  #=+ Run the launcher
  #exec($cge_launch.' '.$arg_string.'> /dev/null 2>&1 &');
  my $success = run(command => $cge_launch.' '.$arg_string.' > '.$arguments{dataDir}.'.cge_web_ui/temp/'.$launch_stdout_file.' 2>&1 &', verbose => 0);

  #=+ Something went wrong, so just return undef
  return (undef,undef) unless $success;

  my $file = File::Tail->new($arguments{dataDir}.'.cge_web_ui/temp/'.$launch_stdout_file);
  while(my $line = $file->read) {
    last if $line =~ /Starting port forwarding/;
  }

  open(my $CU,'<',$arguments{cleanupScript}) or croak $!;
  my $text = <$CU>;
  close($CU);

  my $pid;
  if($text =~ /scancel (\d+)/m) {
    $pid = $1;
  }
  return ($pid,$port);
}

sub cge_stop_graceful {
  #=+ For the most part, we would want to attempt a graceful shutdown
  my($port) = @_;
  my $success = run(command => $cge_cli.' shutdown --dbport '.$port.' > '.$arguments{dataDir}.'.cge_web_ui/temp/'.$stop_stdout_file.' 2>&1 &', verbose => 0);

  #=+ Something went wrong, so just return undef;
  return undef unless $success;

  my $file = File::Tail->new($arguments{dataDir}.'.cge_web_ui/temp/'.$stop_stdout_file);
  while(my $line = $file->read) {
    last if $line =~ /Server shutdown as requested/;
  }
  return $success;
}

sub cge_stop_scancel {
  #=+ If a graceful shutdown fails, then it may be necessary to just kill the PID
  my($pid) = @_;
  my $success = run(command => $cge_scancel.' '.$pid, verbose => 0);
  return $success;
}

1;

__END__
#=+ Here is the man page for cge-launch
Usage: cge-launch -d path|--dataDir=path -o path|--resultDir=path
             [-h|--help]
             [-p port_num|--queryPort=port_num]
             [-l logfile|--logFile=logfile]
             [-C configFilePath|--configFile=configFilePath]
             [--inRPNmsg=msgFileName]
             [--inRPNmsgsFile=listFileName]
             [-E varList|--envVarPassList=varList]
             [-S args|--servArgs=args]
             [--CGEServerPath=pathname]
             [-T seconds|--sessionTimeout=seconds]
             [-H MBytes|--heapSize=MBytes]
             [-I nImages|--imagesPerNode=nImages]
             [-N nodeCount|--nodeCount=nodeCount]
             [-R options|--runOpts=options]
             [--startupTimeout=seconds]
             [--cleanupScript=scriptfile]
             [--partition=partition_list]
Where the common options are:

    -d path
    --dataDir=path
        Specify the path to the directory containing the data set to
        be loaded into the server.  This directory must contain all
        input data files for the data set.

    -o path
    --resultDir=path
        Specify the path to the directory where result (output) files
        will be placed.  The files placed in this directory will be
        tab or comma separated data files (.csv or .tsv).

    -h
    --help
        Display this help message

    -p port_num
    --queryPort=port_num
        Specify the publicly visible TCP/IP port number on which
        queries can be presented to the server.  By default this is
        port 3750.

    -l logfile
    --logFile=logfile
        Specify a log file to capture the command output from the run.
        This is distinct from any explicit logging done by the
        database server, though, if the database server is logging to
        'stderr' this log file will capture that information as well.
        There are two special argument values for this: ':1' and ':2'
        which refer to stdout and stderr respectively, so that the log
        can be directed to either of those.

    -C configFilePath
    --configFile=configFilePath
        Specify the pathname of the configuration file to be used by
        the server when setting up persistently configured settings.
        If this option is present, its value is used.  If it is
        absent, the CGE_CONFIG_FILE_NAME variable is taken from the
        invoking environment and used.  In the absence of both the
        option and the variable, cge-launch will search in the data
        directory (as specidied by the -d option), the working
        directory from which cge-launch was executed, and the .cge
        directory in your home directory, in that order, for a file
        called cge.properties, and will use the first one (if any)
        found.  If no configuration file is specified or can be found,
        none is used.

    --inRPNmsg=msgFileName
        Run an RPN message from a file through the query engine
        instead of accepting RPN messages via TCP/IP.  Used primarily
        for testing, this permits the user to run a single RPN message
        contained in a file through the query engine without having to
        connect from a separate client process.  The argument is the
        name of the file containing the RPN message.

    --inRPNmsgsFile=listFileName
        Run a sequence of files containing RPN messages through the
        query instead of accepting RPN messages via TCP/IP.  Used
        primarily for testing, this permits the user to run a sequence
        of RPN messages contained in files through the query engine
        without having to connect from a separate client process.  The
        argument is the name of a file containing a list of RPN
        message files.

    -E varList
    --envVarPassList=varList
        Specify a list of environment variables to pass through from
        the user's shell environment to the server.  The argument is a
        comma separated list of variable names (not assignments).  Any
        variable that is exported from the invoking shell environment
        and present in this list will be exported to the server on
        launch.

    -S args
    --servArgs=args
        Specify additional options and arguments to the database
        server application.

    --CGEServerPath=pathname
        Specify the pathname of an alternative cge-server binary to be
        launched instead of the default.  This is primarily intended
        for a developer audience where an alternate binary may need to
        be run for testing or performance tuning purposes.

And the platform specific options are:

    -T seconds
    --sessionTimeout=seconds
        Sets the timeout value in seconds for the server session.
        This tells the batch system when to time out if the session
        runs too long, and allows the session to exit on server
        timeout.  Withouth this, the server will be killed by the
        batch system whenever the batch system (default) timeout is
        reached, and restarted as though the timeout were an
        unexpected server failure.

    -H MBytes
    --heapSize=MBytes
        Sets the symmetric heap size in megabytes for the application.
        By default this is computed based on the minimum amount of
        memory on any node (-m option) and the number of PEs on each
        node (-N option).  This option allows the user to set it
        explicitly.  If this option is not present, the value of
        XT_SYMMETRIC_HEAP_SIZE from from the invoking environment is
        used.  If neither the -H option nor the environment variable
        is present, the default value, 50% of the required or default
        node memory divided by the number of PEs per node, is used.

        NOTE: the setting for XT_SYMMETRIC_HEAP_SIZE is specified in
        bytes, whereas the argument to the -H option is specified in
        megabytes.

    -I nImages
    --imagesPerNode=nImages
        Sets the number of 'images' per node, meaning the number of
        separate processes on each node that will cooperate in the
        server application. The total number of images in the
        application is the product of this value and the number of
        nodes (see the -N option).  In the absence of this option, a
        heuristic is used to determine the number of images per node
        to be used.

    -N nodeCount
    --nodeCount=nodeCount
        Sets the number of nodes (collections of cores with uniform
        memory access) to use for the application.  This number of
        nodes multiplied by the number of images per node (-I option)
        yields the total number of images (processes) that will make
        up the server application.  The default for this option is one
        node.

    -R options
    --runOpts=options
        Specify additional options to the srun command.

    --startupTimeout=seconds
        Sets the timeout value in seconds for the server to start up.
        If no forward progress is made by cge-server from the time it
        is initiated until it is ready to process requests within this
        timeout period, the session will be declared hung, and killed.

    --cleanupScript=scriptfile
        Specify the name of a file into which to write a script that
        can be executed in case of improper termination to clean up
        the batch session created by this run.

    --partition=partition_list
        Specify a list of partition names for srun to use when
        launching the server.  See the srun(1) and scontrol(1) manual
        pages for details.
