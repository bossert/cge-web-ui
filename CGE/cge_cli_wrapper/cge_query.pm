#!/usr/bin/env perl

package CGE::cge_cli_wrapper::cge_query;

use strict;
use 5.016;
use IPC::Cmd qw(can_run run);
use Carp qw(croak cluck carp);
use Net::EmptyPort qw(check_port);
use File::Tail;
use POSIX;
use Mojo::JSON qw(decode_json encode_json);
require Exporter;
use Data::Dumper;
our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(cge_select cge_construct cge_insert cge_ask cge_describe);
our %EXPORT_TAGS = (ALL => [ qw(cge_select cge_construct cge_insert cge_ask cge_describe) ]);

#=+ This module will wrap the cge-cli query command-line application
my $cge_cli    = can_run('cge-cli') or croak $!;

sub cge_select {
  my ($arg_ref) = @_;
  my %arguments = (
    dbhost           => undef,
    dbport           => 3750,
    identity         => undef,
    nvp              => undef,                              #=+ must be passed as CSV
    'opt-disable'    => undef,                              #=+ must be passed as CSV
    'opt-enable'     => undef,                              #=+ must be passed as CSV
    'path-expansion' => undef,
    trace            => 0,                                  #=+ binary
    stream           => 'application/sparql-results+json',  #=+ See below END block for valid options
    'trust-keys'     => 1                                   #=+ binary
  );
  
  my $qtype = $arg_ref->{'qtype'};
  
  #=+ iterate over provided config and replace defaults
  while(my($k,$v) = each %$arg_ref) {
    #=+ Replace each default value if the key exists.  Perhaps paranoid, but prevent arbitrary/unexpected settings
    $arguments{$k} = $v if (exists $arguments{$k} && $v ne '' && defined $v);
  }

  #=+ Get rid of any binary arguments that are not wanted (e.g. a zero)
  foreach my $binary('path-expansion','trace','trust-keys') {
    if($arguments{$binary} == 1) {
      $arguments{$binary} = '';
    }
    else {
      $arguments{$binary} = undef;
    }
  }

  #=+ Iterate over values that need to be split into repeating list of the same command-line switch
  my $partial_string = '';
  foreach my $rep('opt-disable','opt-enable') {
    next unless (exists $arguments{$rep} && defined $arguments{$rep});
    my @reps;
    my @inners = split(/,/,$arguments{$rep});
    foreach my $inner(@inners) {
      push @reps, '--'.$rep.' '.$inner.' ';
    }
    $partial_string .= join('',@reps);
    delete $arguments{$rep};
  }

  #=+ Now for NVP's, same process but the string is a bit different since these are key/value pairs
  if(exists $arguments{nvp} and defined $arguments{nvp}) {
    my @reps;
    my @inners = split(/,/,$arguments{nvp});
    foreach my $inner(@inners) {
      my($k,$v) = split(/\=/,$inner);
      push @reps, '--nvp '.$k.' '.$v.' ';
    }
    $partial_string .= join('',@reps);
    delete $arguments{nvp};
  }

  #=+ Concatenate all the non-blank command line arguments
  my @args;
  while(my($k,$v) = each %arguments) {
    push @args, '--'.$k.' '.$v.' ' if defined $v;
  }
  my $arg_string = join('',@args).' '.$partial_string;

  $arg_ref->{current_database} .= '/' unless $arg_ref->{current_database} =~ /\/$/;
  
  open(my $TF,'>',$arg_ref->{current_database}.'.cge_web_ui/temp/query.rq');
  print {$TF} $arg_ref->{query};
  close($TF);

  my($success,$error_message,$full_buf,$stdout_buf,$stderr_buf) = run(command => $cge_cli.' query '.$arg_string.' '.$arg_ref->{current_database}.'.cge_web_ui/temp/query.rq' , verbose => 1);
  if($success) {
    unlink $arg_ref->{current_database}.'.cge_web_ui/temp/query.rq';
    
    my $json_response = join('',@$stdout_buf);
    my $json = decode_json($json_response);
    my %results = ('qtype' => $qtype,
                   'results' => $json);
    return (1,\%results);
  }
  else {
    unlink $arg_ref->{current_database}.'.cge_web_ui/temp/query.rq';
    
    my $error = '';
    foreach my $line(@$stderr_buf) {
      $error .= $line unless $line =~ /^\d+ \[main\]|^com\.|^\s+at com\.|^\s*$/;
    }
    chomp $error;
    
    $error =~ s/\x1b.*?[mGKH]//g;
    return (0,$error);
  }
}

sub cge_construct {
  my ($arg_ref) = @_;
  my %arguments = (
    dbhost           => undef,
    dbport           => 3750,
    identity         => undef,
    nvp              => undef,                              #=+ must be passed as CSV
    'opt-disable'    => undef,                              #=+ must be passed as CSV
    'opt-enable'     => undef,                              #=+ must be passed as CSV
    'path-expansion' => undef,
    trace            => 0,                                  #=+ binary
    stream           => 'application/n-triples',            #=+ See below END block for valid options
    'trust-keys'     => 1                                   #=+ binary
  );

  my $qtype = $arg_ref->{'qtype'};
  
  #=+ iterate over provided config and replace defaults
  while(my($k,$v) = each %$arg_ref) {
    #=+ Replace each default value if the key exists.  Perhaps paranoid, but prevent arbitrary/unexpected settings
    $arguments{$k} = $v if (exists $arguments{$k} && $v ne '' && defined $v);
  }

  #=+ Get rid of any binary arguments that are not wanted (e.g. a zero)
  foreach my $binary('path-expansion','trace','trust-keys') {
    if($arguments{$binary} == 1) {
      $arguments{$binary} = '';
    }
    else {
      $arguments{$binary} = undef;
    }
  }

  #=+ Iterate over values that need to be split into repeating list of the same command-line switch
  my $partial_string = '';
  foreach my $rep('opt-disable','opt-enable') {
    next unless (exists $arguments{$rep} && defined $arguments{$rep});
    my @reps;
    my @inners = split(/,/,$arguments{$rep});
    foreach my $inner(@inners) {
      push @reps, '--'.$rep.' '.$inner.' ';
    }
    $partial_string .= join('',@reps);
    delete $arguments{$rep};
  }

  #=+ Now for NVP's, same process but the string is a bit different since these are key/value pairs
  if(exists $arguments{nvp} and defined $arguments{nvp}) {
    my @reps;
    my @inners = split(/,/,$arguments{nvp});
    foreach my $inner(@inners) {
      my($k,$v) = split(/\=/,$inner);
      push @reps, '--nvp '.$k.' '.$v.' ';
    }
    $partial_string .= join('',@reps);
    delete $arguments{nvp};
  }

  #=+ Concatenate all the non-blank command line arguments
  my @args;
  while(my($k,$v) = each %arguments) {
    push @args, '--'.$k.' '.$v.' ' if defined $v;
  }
  my $arg_string = join('',@args).' '.$partial_string;

  $arg_ref->{current_database} .= '/' unless $arg_ref->{current_database} =~ /\/$/;
  open(my $TF,'>',$arg_ref->{current_database}.'.cge_web_ui/temp/query.rq');
  print {$TF} $arg_ref->{query};
  close($TF);

  my($success,$error_message,$full_buf,$stdout_buf,$stderr_buf) = run(command => $cge_cli.' query '.$arg_string.' '.$arg_ref->{current_database}.'.cge_web_ui/temp/query.rq' , verbose => 1);
  if($success) {
    unlink $arg_ref->{current_database}.'.cge_web_ui/temp/query.rq';
    #=+ Join the stdout buffer into one array and split on newlines so we have one line per element
    my @stdout_array = split(/\n/,join('',@$stdout_buf));
    my (%results,%nodes,@nodesArray,@edges);

    foreach my $line(@stdout_array) {
      my ($s,$p,$o,$st,$pt,$ot,$languageTag);
      #=+ URI URI URI
      if ($line =~ m/^<(.[^<>]+)>\s+<(.[^<>]+)>\s+<(.[^<>]+)>\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'URI'; $pt = 'URI'; $ot = 'URI';
      }
      #=+ URI URI BNODE
      elsif ($line =~ m/^<(.[^<>]+)>\s+<(.[^<>]+)>\s+(\_\:.+[^\s])\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'URI'; $pt = 'URI'; $ot = 'BNODE';
      }
      #=+ URI BNODE URI
      elsif ($line =~ m/^<(.[^<>]+)>\s+(\_\:.+[^\s])\s+<(.[^<>]+)>\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'URI'; $pt = 'BNODE'; $ot = 'URI';
      }
      #=+ URI BNODE BNODE
      elsif ($line =~ m/^<(.[^<>]+)>\s+(\_\:.+[^\s])\s+(\_\:.+[^\s])\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'URI'; $pt = 'BNODE'; $ot = 'BNODE';
      }
      #=+ BNODE BNODE BNODE
      elsif ($line =~ m/^(\_\:.+[^\s])\s+(\_\:.+[^\s])\s+(\_\:.+[^\s])\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'BNODE'; $pt = 'BNODE'; $ot = 'BNODE';
      }
      #=+ BNODE BNODE URI
      elsif ($line =~ m/^(\_\:.+[^\s])\s+(\_\:.+[^\s])\s+<(.[^<>]+)>\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'BNODE'; $pt = 'BNODE'; $ot = 'URI';
      }
      #=+ BNODE URI URI
      elsif ($line =~ m/^(\_\:.+[^\s])\s+<(.[^<>]+)>\s+<(.[^<>]+)>\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'BNODE'; $pt = 'URI'; $ot = 'URI';
      }
      #=+ BNODE URI BNODE
      elsif ($line =~ m/^(\_\:.+[^\s])\s+<(.[^<>]+)>\s+(\_\:.+[^\s])\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'BNODE'; $pt = 'URI'; $ot = 'BNODE';
      }
      #=+ URI URI STRING
      elsif ($line =~ m/^<(.[^<>]+)>\s+<(.[^<>]+)>\s+\"(.+)\"\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'URI'; $pt = 'URI'; $ot = 'string';
      }
      #=+ URI URI LANG STRING
      elsif ($line =~ m/^<(.[^<>]+)>\s+<(.[^<>]+)>\s+\"(.+)\"\@(.+)\s+\./) {
        $s = $1; $p = $2; $o = $3; $languageTag = $4;
        $st = 'URI'; $pt = 'URI'; $ot = 'string';
      }
      #=+ URI URI TYPED LITERAL
      elsif ($line =~ m/^<(.[^<>]+)>\s+<(.[^<>]+)>\s+\"(.+)\"\^\^<(.+)>\s+\./) {
        $s = $1; $p = $2; $o = $3; my $type = $4; $type =~ s/.+\/(.[^\/]+)$/$1/;
        $st = 'URI'; $pt = 'URI'; $ot = $type;
      }
      #=+ URI BNODE STRING
      elsif ($line =~ m/^<(.[^<>]+)>\s+(\_\:.+[^\s])\s+\"(.+)\"\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'URI'; $pt = 'BNODE'; $ot = 'string';
      }
      #=+ URI BNODE LANG STRING
      elsif ($line =~ m/^<(.[^<>]+)>\s+(\_\:.+[^\s])\s+\"(.+)\"\@(.+)\s+\./) {
        $s = $1; $p = $2; $o = $3; $languageTag = $4;
        $st = 'URI'; $pt = 'BNODE'; $ot = 'string';
      }
      #=+ URI BNODE TYPE LITERAL
      elsif ($line =~ m/^<(.[^<>]+)>\s+(\_\:.+[^\s])\s+\"(.+)\"\^\^<(.+)>\s+\./) {
        $s = $1; $p = $2; $o = $3; my $type = $4; $type =~ s/.+\/(.[^\/]+)$/$1/;
        $st = 'URI'; $pt = 'BNODE'; $ot = $type;
      }
      #=+ BNODE URI STRING
      elsif ($line =~ m/^(\_\:.+[^\s])\s+<(.[^<>]+)>\s+\"(.+)\"\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'BNODE'; $pt = 'URI'; $ot = 'string';
      }
      #=+ BNODE URI LANG STRING
      elsif ($line =~ m/^(\_\:.+[^\s])\s+<(.[^<>]+)>\s+\"(.+)\"\@(.+)\s+\./) {
        $s = $1; $p = $2; $o = $3; $languageTag = $4;
        $st = 'BNODE'; $pt = 'URI'; $ot = 'string';
      }
      #=+ BNODE URI TYPE LITERAL
      elsif ($line =~ m/^(\_\:.+[^\s])\s+<(.[^<>]+)>\s+\"(.+)\"\^\^<(.+)>\s+\./) {
        $s = $1; $p = $2; $o = $3; my $type = $4; $type =~ s/.+\/(.[^\/]+)$/$1/;
        $st = 'BNODE'; $pt = 'URI'; $ot = $type;
      }
      #=+ BNODE BNODE STRING
      elsif ($line =~ m/^(\_\:.+[^\s])\s+(\_\:.+[^\s])\s+\"(.+)\"\s+\./) {
        $s = $1; $p = $2; $o = $3;
        $st = 'BNODE'; $pt = 'BNODE'; $ot = 'string';
      }
      #=+ BNODE BNODE LANG STRING
      elsif ($line =~ m/^(\_\:.+[^\s])\s+(\_\:.+[^\s])\s+\"(.+)\"\@(.+)\s+\./) {
        $s = $1; $p = $2; $o = $3; $languageTag = $4;
        $st = 'BNODE'; $pt = 'BNODE'; $ot = 'string';
      }
      #=+ BNODE BNODE TYPE LITERAL
      elsif ($line =~ m/^(\_\:.+[^\s])\s+(\_\:.+[^\s])\s+\"(.+)\"\^\^<(.+)>\s+\./) {
        $s = $1; $p = $2; $o = $3; my $type = $4; $type =~ s/.+\/(.[^\/]+)$/$1/;
        $st = 'BNODE'; $pt = 'BNODE'; $ot = $type;
      }
      else {
        say 'Need to get a regex for this type of triple: '.$line;
      }

      my $sid = 'G'.$s; $sid =~ s/[^a-zA-Z0-9]//g;
      my $oid = 'G'.$o; $oid =~ s/[^a-zA-Z0-9]//g;
      my $eid = 'G'.$sid.$oid;

      #=+ Need to get the labels if they are there
      #TODO: This would be a great place to have a config file that contains a list of all known label predicates...
      if($p eq 'http://www.w3.org/2000/01/rdf-schema#label' ||
         $p eq 'http://rdf.alchemyapi.com/rdf/v1/s/aapi-schema#Name' ||
         $p eq 'http://rdf.alchemyapi.com/rdf/v1/s/aapi-schema#DocText') {
        $nodes{$s}->{'label'} = $o;
      }
      #=+ Now, let's do a bit of automagic and capture a magic prefix (for now...could change it later) "http://www.cray.com/analysisUI/node-property/" in order to allow users to specify how the graph is displayed by controlling those things that are properties of a node vs. a triple
      elsif($p =~ m/http:\/\/www\.cray\.com\/analysisUI\/node-property\/(.+)/) {
        my $property = $1;
        $nodes{$s}->{'crayProp:'.$property} = $o;
      }
      else {
        $nodes{$s}->{'id'} = $sid;
        $nodes{$s}->{'nodeType'} = $st;
        $nodes{$o}->{'id'} = $oid;
        $nodes{$o}->{'nodeType'} = $ot;
        $nodes{$o}->{'language'} = $languageTag if defined $languageTag;

        push @edges, {'group' => 'edges',
                      'data'  => {
                        'id'          => $eid,
                        'label'       => $p,
                        'source'      => $sid,
                        'source_name' => $s,
                        'target'      => $oid,
                        'target_name' => $o
                      }};
      }
    }

    #=+ Now, still ugly double work, but need to convert the hash of nodes to an array
    while (my ($k,$v) = each %nodes) {
      my $tempV;
      $tempV->{'group'} = 'nodes';
      unless(exists $v->{'label'}) {
        $v->{'label'} = $k;
      }

      while(my ($ki,$vi) = each %{$v}) {
        $tempV->{'data'}->{$ki} = $vi;
      }

      push @nodesArray, $tempV;
    }

    $results{'qtype'} = $qtype;
    $results{'elements'}->{'nodes'} = \@nodesArray;
    $results{'elements'}->{'edges'} = \@edges;
    return (1,\%results);
  }
  else {
    unlink $arg_ref->{current_database}.'.cge_web_ui/temp/query.rq';
    
    my $error = '';
    foreach my $line(@$stderr_buf) {
      $error .= $line unless $line =~ /^\d+ \[main\]|^com\.|^\s+at com\.|^\s*$/;
    }
    
    $error =~ s/\x1b.*?[mGKH]//g;
    return (0,$error);
  }
}

sub cge_insert {
  my ($arg_ref) = @_;

  #=+ In addition to the arguments, we also need the query and database location

  my %arguments = (
    dbhost           => undef,
    dbport           => 3750,
    identity         => undef,
    nvp              => undef,                              #=+ must be passed as CSV
    'opt-disable'    => undef,                              #=+ must be passed as CSV
    'opt-enable'     => undef,                              #=+ must be passed as CSV
    'path-expansion' => undef,
    trace            => 0,                                  #=+ binary
    'trust-keys'     => 1                                   #=+ binary
  );

  #=+ iterate over provided config and replace defaults
  while(my($k,$v) = each %$arg_ref) {
    #=+ Replace each default value if the key exists.  Perhaps paranoid, but prevent arbitrary/unexpected settings
    $arguments{$k} = $v if (exists $arguments{$k} && $v ne '' && defined $v);
  }

  #=+ Get rid of any binary arguments that are not wanted (e.g. a zero)
  foreach my $binary('path-expansion','trace','trust-keys') {
    if($arguments{$binary} == 1) {
      $arguments{$binary} = '';
    }
    else {
      $arguments{$binary} = undef;
    }
  }

  #=+ Iterate over values that need to be split into repeating list of the same command-line switch
  my $partial_string = '';
  foreach my $rep('opt-disable','opt-enable') {
    next unless (exists $arguments{$rep} && defined $arguments{$rep});
    my @reps;
    my @inners = split(/,/,$arguments{$rep});
    foreach my $inner(@inners) {
      push @reps, '--'.$rep.' '.$inner.' ';
    }
    $partial_string .= join('',@reps);
    delete $arguments{$rep};
  }

  #=+ Now for NVP's, same process but the string is a bit different since these are key/value pairs
  if(exists $arguments{nvp} and defined $arguments{nvp}) {
    my @reps;
    my @inners = split(/,/,$arguments{nvp});
    foreach my $inner(@inners) {
      my($k,$v) = split(/\=/,$inner);
      push @reps, '--nvp '.$k.' '.$v.' ';
    }
    $partial_string .= join('',@reps);
    delete $arguments{nvp};
  }

  #=+ Concatenate all the non-blank command line arguments
  my @args;
  while(my($k,$v) = each %arguments) {
    push @args, '--'.$k.' '.$v.' ' if defined $v;
  }
  my $arg_string = join('',@args).' '.$partial_string;

  $arg_ref->{current_database} .= '/' unless $arg_ref->{current_database} =~ /\/$/;
  open(my $TF,'>',$arg_ref->{current_database}.'.cge_web_ui/temp/update.ru');
  print {$TF} $arg_ref->{query};
  close($TF);

  my($success,$error_message,$full_buf,$stdout_buf,$stderr_buf) = run(command => $cge_cli.' update '.$arg_string.' '.$arg_ref->{current_database}.'.cge_web_ui/temp/update.ru' , verbose => 1);
  if($success) {
    unlink $arg_ref->{current_database}.'.cge_web_ui/temp/update.ru';
    return 1;
  }
  else {
    unlink $arg_ref->{current_database}.'.cge_web_ui/temp/update.ru';
    
    my $error = '';
    foreach my $line(@$stderr_buf) {
      $error .= $line unless $line =~ /^\d+ \[main\]|^com\.|^\s+at com\.|^\s*$/;
    }
    $error =~ s/\x1b.*?[mGKH]//g;
    return (0,$error);
  }
}

1;

__END__

NAME
        cge-cli query - Runs SPARQL queries

SYNOPSIS
        cge-cli query [ --agent ] [ {--db-host | --dbhost} <DatabaseHost> ]
                [ {--db-port | --dbport} <DatabasePort> ] [ {--debug | --verbose} ]
                [ {-h | --help} ] [ {-i | --identity} <IdentityDirectory>... ]
                [ {-l | --list} <ListFile> ] [ --log-disable ]
                [ --log-global-keyword <logGlobalKeywords>... ]
                [ --log-keyword-level <logKeywordLevels>... ]
                [ {--log-level | --log-default-level} <defaultLogLevel> ]
                [ --log-string <logGlobalString> ] [ {--non-interactive | --batch} ]
                [ --nvp <nvps>... ] [ {--opt-off | --opt-disable} <Flag>... ]
                [ {--opt-on | --opt-enable} <Flag>... ] [ --path-expansion <MaxLength> ]
                [ --quiet ] [ --stream <ContentType> ] [ --timeout <TimeoutSeconds> ]
                [ --trace ] [ --trust-keys ] [--] [ <File>... ]

OPTIONS
        --agent
            When set will try to connect to your local SSH Agent and use that
            for access to authentication keys

        --db-host <DatabaseHost>, --dbhost <DatabaseHost>
            Sets the host that is used for connecting to Cray Graph Engine (CGE)
            (defaults to localhost). A cge.properties file may also be used to
            specify the cge.cli.db.host property to use a different default
            value. If both a properties file and this argument are present, this
            argument takes precedence.

            This options value cannot be blank (empty or all whitespace)


        --db-port <DatabasePort>, --dbport <DatabasePort>
            Sets the port that is used for connecting to CGE (defaults to 3750).
            A cge.properties file may also be used to specify the
            cge.cli.db.port property to use a different default value. If both a
            properties file and this argument are present, this argument takes
            precedence.

            This options value represents a port and must fall in one of the
            following port ranges: 1-1023, 1024-49151, 49152-65535


        --debug, --verbose
            Enables verbose mode, which includes setting the log level to debug.
            This causes more detailed logging information to be printed to
            stderr. If this option and --quiet are specified then this takes
            precedence.

        -h, --help
            Display help information

        -i <IdentityDirectory>, --identity <IdentityDirectory>
            Provides the path to an SSH identity directory to be used for secure
            communications. If not specified then your existing ~/.ssh and
            ~/.cge directories will be used

        -l <ListFile>, --list <ListFile>
            Provides a file containing a list of query files to run, each line
            in the file should be a path to a file containing a SPARQL query to
            run. Note that use of a list file may be combined with specifying
            query files directly, when this is done queries in the list file are
            run first followed by query files specified directly. If neither
            this nor -l/--list is specified a single query is read from stdin

        --log-disable
            Sets log printing to disabled i.e. turns logging off

        --log-global-keyword <logGlobalKeywords>
            Sets a keyword to be global i.e. forces the given keyword to be
            included on all log output. This option may be set multiple times to
            set multiple global keywords

        --log-keyword-level <logKeywordLevels>
            Sets a log level for a specific keyword, specified as a keyword
            index followed by a level value. For example --log-level 41 32 sets
            the log level for keyword 41 (TCP) to level 32 (TRACE). This option
            be specified multiple times to configure levels for multiple
            keywords.

        --log-level <defaultLogLevel>, --log-default-level <defaultLogLevel>
            Sets the default log level for all keywords whose levels are not
            otherwise set via the --log-keyword-level argument

            This options value is restricted to the following set of values:
                0
                1
                2
                4
                8
                16
                32

        --log-string <logGlobalString>
            Sets the global log string to pass. This is a string that will be
            printed as part of all log requests resulting from this command and
            can be used to extract only the relevant log lines from the log when
            necessary

        --non-interactive, --batch
            When set, guarantees that the commands will never prompt the user
            for input, which may mean that some commands fail if they require
            user input beyond the command line arguments

        --nvp <nvps>
            Sets a NVP to send to CGE as part of the request, specified as a
            name followed by a value where the value must be a valid integer
            e.g. --nvp name 123456. This option may be specified multiple times
            to set multiple NVPs.

        --opt-off <Flag>, --opt-disable <Flag>
            Sets a specified ARQ optimization flag to disabled, flags should be
            specified as short names e.g. optFilterPlacement
            Where the same flag is specified to be both enabled and disabled it
            will be disabled. May be specified multiple times to specify
            multiple optimizer flags to disable.

            This options value is restricted to the following set of values:
                optPathFlatten
                optFilterPlacement
                optFilterPlacementBGP
                optFilterPlacementConservative
                optOrderByDistinctApplication
                optFilterEquality
                optFilterInequality
                optFilterImplicitJoin
                optImplicitLeftJoin
                optExprConstantFolding
                optFilterConjunction
                optFilterExpandOneOf
                optFilterDisjunction
                optPromoteTableEmpty
                optMergeBGPs
                optMergeExtends
                optPathExpand
                optMergeQuadPatterns

        --opt-on <Flag>, --opt-enable <Flag>
            Sets a specified ARQ optimization flag to enabled, flags should be
            specified as short names e.g. optFilterPlacement
            Where the same flag is specified to be both enabled and disabled it
            will be disabled. May be specified multiple times to specify
            multiple optimizer flags to enable.

            This options value is restricted to the following set of values:
                optPathFlatten
                optFilterPlacement
                optFilterPlacementBGP
                optFilterPlacementConservative
                optOrderByDistinctApplication
                optFilterEquality
                optFilterInequality
                optFilterImplicitJoin
                optImplicitLeftJoin
                optExprConstantFolding
                optFilterConjunction
                optFilterExpandOneOf
                optFilterDisjunction
                optPromoteTableEmpty
                optMergeBGPs
                optMergeExtends
                optPathExpand
                optMergeQuadPatterns

        --path-expansion <MaxLength>
            When set and path expansion is enabled this is the max length that
            arbitrary length property paths (*, + and ?) will be expanded to. If
            set to a value <= 0 then no path expansion will be performed.

        --quiet
            Enables quiet mode which sets the log level to error, causes
            little/no logging to go stderr. If this and --debug/--verbose are
            specified then verbose mode takes precedence.

        --stream <ContentType>
            When specified the results are streamed to stdout in the specified
            format rather than just returning the output header. This option can
            only be used when running a single query. Most of the allowed values
            refer to specific output formats which may not be applicable for all
            query types. The special values text, json and xml may also be used
            in which case an appropriate output format that is Text, JSON or XML
            based will be used with the exact format determined based on the
            type of query given.

            This options value is restricted to the following set of values:
                text
                json
                xml
                application/ld+json
                application/n-triples
                application/rdf+json
                application/rdf+xml
                text/turtle
                application/sparql-results+json
                application/sparql-results+xml
                text/csv
                text/tab-separated-values

        --timeout <TimeoutSeconds>
            Sets the timeout (in seconds) that is used when trying to establish
            connections to the database (default 5)

            This options value must fall in the following range: value >= 0


        --trace
            Enables trace mode, which includes settings the log level to trace.
            This causes even more detailed logging information to be printed to
            stderr. If this option and --quiet are specified then this takes
            precedence.

        --trust-keys
            When set any unknown host keys will be trusted automatically. Since
            SSH treats each host and port combination as being unique even if
            you have already trusted a specific host key on a system changing
            the port will require trusting a new host key. In non-interactive
            environments where ports may be dynamically selected this can prove
            particularly useful. You can also enable this behaviour by setting
            the cge.cli.trust-keys property to true in your cge.properties

        --
            This option can be used to separate command-line options from the
            list of arguments (useful when arguments might be mistaken for
            command-line options)

        <File>
            Specifies a file containing a SPARQL query to be run, many files may
            be specified to run multiple queries. It may be easier to use a list
            file with the -l/--list option if you have a set of queries you wish
            to run. Note that both the use of filenames directly and a list file
            may be combined in a single command invocation, when this is done
            queries in the list file are run first followed by query files
            specified directly. If neither this nor -l/--list is specified a
            single query is read from stdin

DISCUSSION
        Queries to be run may be specified as individual files, list files
        (files containing lists of other file names) or via stdin (only if no
        other queries are specified). In the event that both list files and
        query files are specified the queries in the list file are executed
        first. Complex queries may take some time to run and the command will
        block until such time as the queries complete.

        The default behaviour of this command is to simply execute the query and
        return information about the results. Users/applications can then use
        this information to retrieve and process the results at their leisure.
        The results information is a header that looks like the following:

        0:28:1756:0:/lus/scratch/username/results/queryResults.22683.2014-127-09T11.58.36Z03.tsv::

        This is a colon separated row where the columns correspond to the
        following information - [0 = Status, 1 = Result Count, 2 = Result Size in bytes, 3 = Execution Time in seconds, 4 = Results file location, 5 = Error]
        - with the status being 0 and the error message being empty for
        successful queries.

        So in the example given we had a successful query with 28 results, 1765
        bytes of results, 0 seconds of execution time and whose results can be
        located at
        /lus/scratch/username/results/queryResults.22683.2014-127-09T11.58.36Z03.tsv

        Note that if the query is an ASK/CONSTRUCT/DESCRIBE then the results
        file on disk is not the final results according to the SPARQL
        specification but rather only the results of the WHERE clause of the
        query. This is because Cray Graph Engine (CGE) does not carry out the
        post-processing necessary to give the final SPARQL results forms of
        these queries.

        Alternatively the --stream option can be used to return the results
        directly to stdout however this may only be used when running a single
        query. It also requires that you are running the command from a machine
        that has mounted the file system to which CGE is outputting results. An
        advantage of the --stream opption is that you always get the final
        results of the query regardless of the query type.

EXAMPLES
        cge-cli query example.rq

            Runs the query contained in example.rq and returns information about
            the results

        cge-cli query --stream text/tab-separated-values example.rq

            Runs the query contained in example.rq and streams the results
            directly to stdout in text/tab-separated-values option

        cge-cli query --list queries.txt

            Runs all the queries listed in queries.txt (where queries.txt is a
            file containing a path to one query file per line) and returns the
            information about the results

        cge-cli query

            Prompts the user to enter a query at stdin and then runs that query
            returning information about the results

EXIT CODES
        This command returns one of the following exit codes:

            0    The requested operation(s) completed successfully
            1    A sub-command that does not exist was requested
            2    An option that is not supported by this command was provided
            3    Unexpected arguments were provided
            4    A required option was not provided
            5    An option that requires a value was given but no value for that option was provided
            6    An option with a restricted set of acceptable values was provided with an illegal value
            7    Required arguments were not provided
            10   An initialization error occurred
            11   An IO error occurred
            12   An error occurred communicating with CGE
            20   An unexpected error occurred

COPYRIGHT
        Copyright (c) Cray Inc 2015-2016
