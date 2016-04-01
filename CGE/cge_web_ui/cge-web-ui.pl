#!/usr/bin/env perl

use strict;
use warnings;
use 5.016;
use Carp qw(cluck carp croak);
use Data::Dumper;
use Net::LDAP;
use YAML::AppConfig;
use IO::Compress::Gzip 'gzip';
use POSIX;
use Digest::MD5 qw(md5_hex);
use Math::Random::Secure qw(irand);
use Mojolicious::Lite;
use Mojolicious::Sessions;
use Mojo::Log;
use Mojo::JSON qw(decode_json encode_json);
use Try::Tiny;
use Net::EmptyPort;
use Tie::Hash::Expire;
use IPC::Run3::Shell;
## no critic qw(RegularExpressions::RequireExtendedFormatting)

#========================================#
# Directory structures ('-' == category, #
# '+' == folder, '=' == file)            #
#========================================#

#========================================#
# - Master:                              #
#========================================#
#   + [root_dir]                      :: Root application directory
#      + log                          :: This is directory that logs are stored
#      + templates                    :: This is the directory where Mojolicious HTML templates reside
#      + databases                    :: This is a central repository for databases, especially those that will be shared
#         + [database_name]           :: Each database is stored in its own directory
#            + log                    :: CGE log directory
#            + queries                :: stored queries specific to "this" database
#            + keys                   :: stored keys for the purposes of sharing a database with other users
#      + queries                      :: General purpose queries are stored here...not database dependent
#      + public                       :: Directory for public files/folders for the Mojolicious app
#         + js                        :: Javascript files
#         + styles                    :: CSS files
#         + images                    :: Image files
#         + graph_icons               :: Image files used by cytoscape for node images
#         + typescript                :: Typescript files/folders used by Kendo UI
#         + fonts                     :: Font files used by the web application
#   = analytics_ui_config.yaml        :: Master configuration file; will be superseded by the user's config file
#   = blacklist.txt                   :: This file will be automatically created the first time it is used.  Blacklisted users who have failed 5 logins in a row
#   = analytics_ui.pl                 :: This application

#========================================#
# - User:                                #
#========================================#
#   + [additional_database_directory] :: Additional database directory provided by the user in their config file
#      + [database_name]              :: Each database is stored in its own directory
#         + log                       :: CGE log directory
#         + queries                   :: stored queries specific to "this" database
#         + keys                      :: stored keys for the purposes of sharing a database with other users
#   + [user_home_directory]           :: User's home directory
#      = analytics_ui_config.yaml     :: User's personal configuration file; overrides master settings

#========================================#
# App setup                              #
#========================================#
#=+ Setting the root directory as the absolute path where the executable resides
use Cwd 'abs_path';
my $root_directory = abs_path().'/';

#=+ Set up logging
my $logLevel = 'debug';
my $ts = strftime("%Y-%m-%d", localtime(time));
my $log = Mojo::Log->new(path => $root_directory.'log/analytics_ui_log_'.$ts.'.log', level => $logLevel);

#=+ Check the root directory and any other needed directories
_checkDirectories($root_directory);

#=+ Need to initialize the application based on the configuration file
my $config = _config_init();

#=+ Set a much more secure key for our signed cookies using Math::Random::Secure irand function, which IS
#   suitable for cryptographic functions.  We are using signed cookies that are tamper-resistant as well
#   as forcing all traffic over SSL (https)
app->secrets([md5_hex(irand)]);

#=+ set up session(cookies) defaults
app->sessions(Mojolicious::Sessions->new);
app->sessions->cookie_name('Graph_Engine');
app->sessions->default_expiration($config->config->{'session_timeout'});
#=+ Force cookies to only be sent over SSL connection
app->sessions->secure(1);

#=+ Set environment variables
$ENV{'MOJO_MAX_MESSAGE_SIZE'}   = $config->config->{'MOJO_MAX_MESSAGE_SIZE'};
$ENV{'MOJO_USERAGENT_DEBUG'}    = $config->config->{'MOJO_USERAGENT_DEBUG'};
$ENV{'MOJO_CONNECT_TIMEOUT'}    = $config->config->{'MOJO_CONNECT_TIMEOUT'};
$ENV{'MOJO_IOLOOP_DEBUG'}       = $config->config->{'MOJO_IOLOOP_DEBUG'};
$ENV{'MOJO_WEBSOCKET_DEBUG'}    = $config->config->{'MOJO_WEBSOCKET_DEBUG'};
$ENV{'MOJO_INACTIVITY_TIMEOUT'} = $config->config->{'MOJO_INACTIVITY_TIMEOUT'};

#=+ Hypnotoad configuration.  This does no harm if we are just running morbo
app->config('hypnotoad' => {
              'listen'       => ['https://*:'.$config->config->{'port'}],
              'workers'      => $config->config->{'workers'},
              'multi_accept' => $config->config->{'multi_accept'}
            });

#=+ Set up and tie our blacklist hash, which automatically expires after 1 hour, perhaps this should be configurable?
my %blacklist;
tie %blacklist, 'Tie::Hash::Expire', { 'expire_seconds' => 3600 };

#========================================#
# Helpers                                #
#========================================#
#=+ Automatically gzip responses if the user agent will accept gzip
hook after_render => sub {
  my ($self, $output, $format) = @_;
  
  #=+ Check if "gzip => 1" has been set in the stash
  return unless $self->stash->{gzip};
  
  #=+ Check if user agent accepts GZip compression
  return unless ($self->req->headers->accept_encoding // '') =~ /gzip/i;
  
  #=+ Compress content with GZip
  $self->res->headers->content_encoding('gzip');
  gzip $output, \my $compressed;
  $$output = $compressed;
};

#========================================#
# Routes                                 #
#========================================#

#=+ Main login page.  This and '/' are the only routes that don't require authentication to access
get '/login' => sub {
  my $self = shift;
  $self->stash(title => 'CGE Log-in');
  $self->stash(gzip => 1);
} => 'login';

#=+ If someone goes to https://app.com:[port]/, then redirect them to the login page automatically
get '/' => sub {
  my $self = shift;
  $self->flash(message => 'Redirecting to login page.');
  $self->redirect_to('login');
};

post '/bonafides' => sub {
  my $self = shift;
  
  #=+ Grab the form elements from the POST form
  my $creds = $self->req->body_params->to_hash;
  
  #=+ Weed out anyone on the blacklist
  if (exists $blacklist{$creds->{'user'}}) {
    $self->flash(message => 'User has been blocked due to excessive failed login attempts, try again in an hour or so!');
    $self->session(expires => 1);
    $self->rendered(404);
  }
  #=+ Now check credentials
  elsif (_authenticate($creds->{'user'},$creds->{'pass'}) == 1) {
    $self->session('failcount' => 0, 'uid' => $creds->{'user'}, 'last_login' => time);
    $self->rendered(200);
  }
  else {
    my $failCount = 1;
    if ($self->session('failcount')) {
      $failCount = $self->session('failcount');
    }
    #=+ So long as the user has not tried 5 times in a row, let them keep trying
    if($failCount <= 5) {
      $failCount++;
      $self->session('failcount' => $failCount);
      $self->rendered(401);
    }
    #=+ Otherwise, blacklist the user and boot them
    else {
      $self->session(expires => 1);
      $blacklist{$creds->{'user'}} = time;
      $self->rendered(401);
    }
  }
};

#=+ All routes in this group require authentication
group {
  under sub {
    my $self = shift;
    return 1 if $self->session('uid');
    $self->redirect_to('login');
  };
  
  #=+ Get to the main page once logged in
  get '/main' => sub {
    my $self = shift;
    $self->stash(title => 'Cray Graph Engine (CGE) web-interface');
    $self->stash(gzip => 1);
  } => 'main';
  
  #=+ A quick way to ensure we are grabbing the prefix file from a secure location with a current copy and
  #   also add our own prefixes
  get '/yasqe_prefixes/all.file.json' => sub {
    my $self = shift;
    my $prefixUrl = 'https://prefix.cc/popular/all.file.json';
    my $prefixUA = Mojo::UserAgent->new;
    my $prefixTX = $prefixUA->get($prefixUrl);
    if($prefixTX->success) {
      my $jsonHash = $prefixTX->res->json;
      $jsonHash->{'afq'} = 'http://jena.hpl.hp.com/ARQ/function#';
      $jsonHash->{'yd'}  = 'http://yarcdata.com/';
      $jsonHash->{'cray-prop'} = 'http://www.cray.com/analysisUI/node-property/';
      $self->render(json => $jsonHash);
    }
    else {
      $log->error('Unable to retrieve prefixes from https://prefix.cc/popular/all.file.json (response code: '.$prefixTX->res->code.')');
      $self->rendered(500);
    }
  };
  
  #=+ Let the app see how many nodes are available
  websocket '/sinfo' => sub{
    my $self = shift;
    $self->stash('gzip' => 1);
    
    #=+ Set retrieve interval for the loop
    my $interval = 5;
    
    my $id = Mojo::IOLoop->recurring($interval => sub {
      
      $self->send('something');
    });
    
    $self->on(finish => sub {
      $log->info('[sinfo] websocket connection closed');
      Mojo::IOLoop->remove($id);
    });
  };
};

#========================================#
# Data maps                              #
#========================================#
#=+ reference: https://www.centos.org/docs/5/html/CDS/cli/8.0/Configuration_Command_File_Reference-Access_Log_and_Connection_Code_Reference-LDAP_Result_Codes.html
my %ldap_error_codes = (0  => 'success',
                        1  => 'operation_error',
                        2  => 'protocol_error',
                        3  => 'time_limit_exceeded',
                        4  => 'size_limit_exceeded',
                        5  => 'compare_false',
                        6  => 'compare_true',
                        7  => 'auth_method_not_supported',
                        8  => 'strong_auth_required',
                        9  => 'ldap_partial_results',
                        10 => 'referral_ldap_v3',
                        11 => 'admin_limit_exceeded_ldap_v3',
                        12 => 'unavailable_critical_extension_ldap_v3',
                        13 => 'confidentiality_required_ldap_v3',
                        14 => 'sasl_bind_in_progress',
                        16 => 'no_such_attribute',
                        17 => 'undefined_attribute_type',
                        18 => 'inappropriate_matching',
                        19 => 'constraint_violation',
                        20 => 'attribute_or_value_exists',
                        21 => 'invalid_attribute_syntax',
                        32 => 'no_such_object',
                        33 => 'alias_problem',
                        34 => 'invalid_dn_syntax',
                        35 => 'is_leaf',
                        36 => 'alias_dereferencing_problem',
                        48 => 'inappropriate_authentication',
                        49 => 'invalid_credentials',
                        50 => 'insufficient_access_rights',
                        51 => 'busy',
                        52 => 'unavailable',
                        53 => 'unwilling_to_perform',
                        54 => 'loop_defect',
                        64 => 'naming_violation',
                        65 => 'object_class_violation',
                        66 => 'not_allowed_on_nonleaf',
                        67 => 'not_allowed_on_rdn',
                        68 => 'entry_already_exists',
                        69 => 'object_class_mods_prohibited',
                        71 => 'affects_multiple_dsas_ldap_v3',
                        80 => 'other',
                        81 => 'server_down',
                        85 => 'ldap_timeout',
                        89 => 'param_error',
                        91 => 'connect_error',
                        92 => 'ldap_not_supported',
                        93 => 'control_not_found',
                        94 => 'no_results_returned',
                        95 => 'more_results_to_return',
                        96 => 'client_loop',
                        97 => 'referral_limit_exceeded');


#========================================#
# Subroutines                            #
#========================================#

#=+ Set up connection to the LDAP server...doing this separately do avoid duplicate code
sub _ldap_connect {
  my $ldap_connection;
  try {
    $ldap_connection = Net::LDAP->new($config->config->{'ldap_host'});
  }
  catch {
    $log->fatal('Could not connect to LDAP server: '.$config->config->{'ldap_host'});
    croak $_;
  };
  return $ldap_connection;
}

#=+ Authenticate users against LDAP
sub _authenticate {
  my ($user,$pass) = @_;
  
  my $ldap = _ldap_connect();
  my $mesg = $ldap->bind;
  $mesg = $ldap->search(base => $config->config->{'search_base'},filter => '(&(uid='.$user.'))', attrs => ['dn']);
  
  #=+ First, did we get a response?
  if (!$mesg) {
    $ldap->unbind;
    $log->fatal('Unknown LDAP error');
    croak $_;
  }
  #=+ Did we find the user?
  elsif ($mesg->code == 0) {
    my $dn = $mesg->entry->dn;
    $mesg = $ldap->bind($dn, password => $pass);
    
    #=+ Does the user's password match?
    if ($mesg->code == 0) {
      $ldap->unbind;
      return 1;
    }
    else {
      $ldap->unbind;
      $log->error('Authentication failed for user: '.$user.' ERROR: '.$mesg->code.'('.$ldap_error_codes{$mesg->code}.')');
      return 0;
    }
  }
  else {
    $ldap->unbind;
    $log->error('Authentication failed for user: '.$user.' ERROR: '.$mesg->code.'('.$ldap_error_codes{$mesg->code}.')');
    return 0;
  }
}

#=+ For the purposes of looking up system users in order to share database access
sub _user_lookup {
  my($value) = @_;
  my @results;
  my $ldap = _ldap_connect();
  my $mesg = $ldap->bind;
  
  #=+ We are doing a wildcard search such that * represents zero or more characters on either end, which is really just
  #   the equivalent of CONTAINS.  Later, we may decide that a fuzzy/approximate match is desired...in which case, change
  #   (for example) uid=*searchterm* to uid~=*searchterm*
  $mesg = $ldap->search(base => $config->config->{'search_base'},filter => '(|(uid=*'.$value.'*)(cn=*'.$value.'*))');
  
  #=+ Each LDAP record entry is returned with the attributes stored in an array of anonymous hashes, therefore,
  #   we have to iterate over each entry and the array of attributes to grab the values we are interested in
  foreach my $entry($mesg->entries) {
    my %temp;
    foreach my $kv(@{$entry->{'asn'}->{'attributes'}}) {
      #=+ The regext here is looking for a value that is EXACTLY cn, uid, or homeDirectory (case-sensitive).  Feel free to add more values if they are useful
      if ($kv->{'type'} =~ m/^(:?cn|uid|homeDirectory)$/) {
        $temp{$kv->{'type'}} = $kv->{'vals'}->[0];
      }
    }
    push @results, \%temp;
  }
  return \@results;
}

#=+ Check to make sure any supplied directories exist, are readable, and writeable
sub _checkDirectories {
  my @input = @_;
  foreach my $dir(@input) {
    unless(-d $dir) {
      $log->fatal('Directory does not exist: '.$dir);
      croak $dir.' : Directory does not exist.';
    }
    unless(-r $dir) {
      $log->fatal('Directory is not readable: '.$dir);
      croak $dir.' : Directory is not readable';
    }
    unless(-w $dir) {
      $log->fatal('Directory is not writable: '.$dir);
      croak $dir.' : Directory is not writable.';
    }
  }
  return 1;
}

#=+ Read in our configuration file
sub _config_init {
  #=+ no options to the init routine for now...may revisit later
  #=+ First, load up the master config file
  my $yaml_config;
  my $config_file_name = $root_directory.'analytics_ui_config.yaml';
  if(-e $config_file_name && -r _) {
    $yaml_config = YAML::AppConfig->new(file => $config_file_name);
  }
  else {
    $log->fatal('Could not initialize application: config file does not exist or has permissions issues: '.$config_file_name);
    croak 'Could not initialize application: config file does not exist or has permissions issues: '.$config_file_name;
  }
  
  #=+ Now, load the local/user's config file and merge it with the master if it exists
  #   The user's settings will take precedence over the master config.
  #   For now, the location and file name are hard-coded.  If anyone thinks this should be configurable, go for it
  if(-e (getpwuid $>)[7].'/analytics_ui_config.yaml' && -r _) {
    $yaml_config->merge(file => (getpwuid $>)[7].'/analytics_ui_config.yaml');
  }
  
  #=+ Need to check if config file sets listen port explicitly and if it is available
  if (!exists $yaml_config->config->{'port'}) {
    #=+ Force the search for a free port to start at 3000.  This is completely arbitrary and was chosen because that
    #   is the default port that Mojolicious shows in the docs.  You could set this to any valid port
    my $freePort = 3000;
    while(check_port($freePort)) {
      $freePort++;
    }
    $yaml_config->config->{'port'} = $freePort;
  }
  elsif(check_port($yaml_config->config->{'port'})) {
    my $oldPort = $yaml_config->config->{'port'};
    my $freePort = $oldPort + 1;
    
    #=+ Find the next available port
    while(check_port($freePort)) {
      $freePort++;
    }
    
    #=+ Use next available port
    #say 'Port '.$oldPort.' is already in use, will use the next available port: '.$freePort;
    $yaml_config->config->{'port'} = $freePort;
  }
  
  
  
  #=+ Need to alter the main javascript file to use the desired backend server name and port
  #my $javascript_file_name = $root_directory.'public/js/analytics_ui.js';
  #if(-e $javascript_file_name && -r _ && -w _) {
  #  my $javascript_file = read_file($javascript_file_name);
  #  my $host_port = $yaml_config->config->{'host'}.':'.$yaml_config->config->{'port'};
  #  $javascript_file =~ s/var backend \= \"[^"]+\"/var backend \= \"$host_port\"/;
  #  open(my $JS_FILE,'>',$javascript_file_name);
  #  say {$JS_FILE} $javascript_file;
  #  close($JS_FILE);
  #}
  #else {
  #  $log->fatal('Could not initialize application: javascript file does not exist or has permissions issues: '.$javascript_file_name);
  #  croak 'Could not initialize application: javascript file does not exist or has permissions issues: '.$javascript_file_name;
  #}
  return $yaml_config;
}

#=+ Finally, let's get started!
app->start;