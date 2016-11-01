#!/usr/bin/env perl

use strict;
use warnings;
use 5.016;
use Carp qw(cluck carp croak);
use Cwd 'abs_path';
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
use Mojo::Util qw(url_unescape b64_encode b64_decode);
use Try::Tiny;
use Net::EmptyPort;
use Tie::Hash::Expire;
use IPC::Cmd qw(can_run run);
use File::Path::Tiny;
use File::Find;
use File::Slurp;
use FindBin;
use Test::Deep::NoTest; 
use lib '/mnt/lustre/bossert/git/cge-web-ui';
use CGE::cge_cli_wrapper::cge_utils qw(:ALL);
use CGE::cge_cli_wrapper::cge_launch qw(:ALL);
use CGE::cge_cli_wrapper::cge_query qw(:ALL);
 
no warnings 'File::Find';
use File::Basename;
## no critic qw(RegularExpressions::RequireExtendedFormatting)

#========================================#
# Directory structures ('-' == category, #
# '+' == folder, '=' == file)            #
#========================================#

#========================================#
# - Master:                              #
#========================================#
#   + [root_dir]                      :: Root application directory
#      + templates                    :: This is the directory where Mojolicious HTML templates reside
#      + queries                      :: General purpose queries are stored here...not database dependent
#      + public                       :: Directory for public files/folders for the Mojolicious app
#         + js                        :: Javascript files
#         + styles                    :: CSS files
#         + images                    :: Image files
#         + graph_icons               :: Image files used by cytoscape for node images
#         + typescript                :: Typescript files/folders used by Kendo UI
#         + fonts                     :: Font files used by the web application
#   = analytics_ui_config.yaml        :: Master configuration file; will be superseded by the user's config file
#   = analytics_ui.pl                 :: This application

#========================================#
# - User:                                #
#========================================#
#   + [database_directories]          :: Arbitrary directories housing CGE databases
#      + [database_name]              :: Each database is stored in its own directory
#         + .cge_web_ui               :: All web UI specific files and directories reside here
#            + queries                :: stored queries specific to "this" database
#            + authorized_users       :: stored keys for the purposes of sharing a database with other users
#               + [username]          :: Each authorized user has a directory with their username
#                  = id_rsa           :: Private key (RSA only for now)
#                  = id_rsa.pub       :: Public key (RSA only for now)
#                  = properties.yaml  :: User permissions and relevant timestamps for first access grant and last modified date/time
#            + temp                   :: Temporary file directory.  All files should be purged each time the application starts
#         + log                       :: CGE log directory
#         = authorized_keys           :: Public keys for users granted access to "this" database
#   + [user_home_directory]           :: User's home directory
#      + .cge_web_ui                  :: Directory for holding web UI files and directories
#         + log                       :: This is directory that web UI logs are stored
#         + queries                   :: This directory should contain user-defined general purpose queries (i.e. not specific to a certain database)
#         = analytics_ui_config.yaml  :: User's personal configuration file; overrides master settings

#========================================#
# App setup                              #
#========================================#
#=+ Setting the root directory as the absolute path where the executable resides
my $root_directory = $FindBin::Bin.'/';

#=+ Check the root directory and any other needed directories
my $home_directory = (getpwuid $>)[7].'/';
_checkDirectories($root_directory,$home_directory.'.cge_web_ui/log');

#=+ Set up logging
my $logLevel = 'debug';
my $ts = strftime("%Y-%m-%d", localtime(time));
my $log = Mojo::Log->new(path => $home_directory.'.cge_web_ui/log/analytics_ui_log_'.$ts.'.log', level => $logLevel);

#=+ Need to initialize the application based on the configuration file
my $config = _config_init();

#=+ Set a much more secure key for our signed cookies using Math::Random::Secure irand function, which IS
#   suitable for cryptographic functions.  We are using signed cookies that are tamper-resistant as well
#   as forcing all traffic over SSL (https)
app->secrets([md5_hex(irand)]);

#=+ set up session(cookies) defaults
app->sessions(Mojolicious::Sessions->new);
app->sessions->cookie_name('Cray_Graph_Engine');
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
  if (exists $blacklist{$creds->{'user'}} ||
      exists $blacklist{$self->tx->remote_address}) {
    $self->session(expires => 1);
    $self->render(text => 'User has been blocked due to excessive failed login attempts, try again in an hour or so!', status => 403);
  }
  #=+ Now check credentials
  elsif (_authenticate($creds->{'user'},$creds->{'pass'}) == 1) {
    $self->session('failcount' => 0, 'username' => $creds->{'user'}, 'last_login' => time);
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
      $blacklist{$self->tx->remote_address} = time;
      $self->rendered(401);
    }
  }
};

#=+ All routes in this group require authentication
group {
  under sub {
    my $self = shift;
    return 1 if $self->session('username');
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

  get 'graph_icon_list' => sub {
    my $self = shift;
    opendir(my $dir, $root_directory.'public/graph_icons');
    my @imageFiles = grep { !/^\./ && /\.(jpg|jpeg|png|svg|gif)$/ } readdir $dir;
    @imageFiles = sort {$a cmp $b} @imageFiles;
    closedir($dir);

    my @filesToSend = ();
    foreach my $file(@imageFiles) {
      my $name=$file; my $url='graph_icons/'.$file;
      $name =~ s/\.[^\.]{3,5}$//;
      push @filesToSend, { 'name' => $name, 'url' => $url };
    }
    $self->render(json => \@filesToSend);
  };
  
  get '/list_databases' => sub {
    my $self = shift;
    my $qparams=$self->req->query_params->to_hash;
    my $root = $config->config->{'database_directory'};
    if(exists $qparams->{search_root}) {
      $root = $qparams->{search_root};
    }

    #my $dirlist = _list_directory($root);
    my $stuff = _list_databases($root,$self->session('username'));
    $self->render(json => $stuff);
  };

  get '/list_NT_files' => sub {
    my $self = shift;
    my $qparams=$self->req->query_params->to_hash;
    my $root = $config->config->{'file_directory'};
    if(exists $qparams->{search_root}) {
      $root = $qparams->{search_root};
    }

    #my $dirlist = _list_directory($root);
    my $stuff = _list_NT_files($root,$self->session('username'));
    $self->render(json => $stuff);
  };
              
  get '/check_pid' => sub {
    my $self = shift;
    my $qparams=$self->req->query_params->to_hash;
    
    if(exists $qparams->{pid}) {
      my $pid = checkPid(url_unescape($qparams->{pid}));
      
      if($pid) {
        $self->rendered(200);
      }
      else {
        $self->rendered(404);
      }
    }
    else {
      $self->render(text => 'Missing PID to check', status => 500);
    }
  };

  #=+ Let the app see how many nodes are available
  websocket '/sinfo_ws' => sub {
    my $self = shift;
    $self->stash('gzip' => 1);

    #=+ Set retrieve interval for the loop
    my $interval = 5;

    my $id = Mojo::IOLoop->recurring($interval => sub {
      my $sinfo = sinfo();
      my $sinfo_json = encode_json($sinfo);
      $self->send($sinfo_json);
    });

    $self->on(finish => sub {
      $log->info('[sinfo] websocket connection closed');
      Mojo::IOLoop->remove($id);
    });
  };

  websocket '/squeue_ws' => sub {
    my $self = shift;
    $self->stash('gzip' => 1);

    #=+ Set retrieve interval for the loop
    my $interval = 5;

    my $id = Mojo::IOLoop->recurring($interval => sub {
      my $queue = squeue();
      my $queue_json = encode_json($queue);
      $self->send($queue_json);
    });

    $self->on(finish => sub {
      $log->info('[squeue] websocket connection closed');
      Mojo::IOLoop->remove($id);
    });
  };

  websocket '/filesystem_changes' => sub {
    my $self = shift;
    $self->stash('gzip' => 1);

    my $old_nt_files = '';
    my $old_databases = '';
    my $interval = 10;
    my $id = Mojo::IOLoop->recurring($interval => sub {
      
      my $root_file = $config->config->{'file_directory'};
      my $root_directory = $config->config->{'database_directory'};
      my $nt_files = _list_NT_files($root_file,$self->session('username'));
      my $databases = _list_databases($root_directory,$self->session('username'));

      if(eq_deeply($nt_files,$old_nt_files)) {
        $old_nt_files = $nt_files;
        $self->send('no change');
      }
      else {
        $old_nt_files = $nt_files;
        $self->send('nt file changes');
      }

      if(eq_deeply($databases,$old_databases)) {
        $old_databases = $databases;
        $self->send('no change');
      }
      else {
        $old_databases = $databases;
        $self->send('database changes');
      }
    });

    $self->on(finish => sub {
      $log->info('[filesystem_changes] websocket connection closed');
      Mojo::IOLoop->remove($id);
    });
  };

  post 'start_db' => sub {
    my $self = shift;
    my $qparams = $self->req->body_params->to_hash;

    if(exists $qparams->{dataDir} && exists $qparams->{imagesPerNode} && exists $qparams->{nodeCount}) {
      #=+ If we have a startup timeout, go ahead and adjust the session timeout accordingly
      if(exists $qparams->{startupTimeout} && $qparams->{startupTimeout} ne '') {
        Mojo::IOLoop->stream($self->tx->connection)->timeout($qparams->{startupTimeout});
      }

      my($pid,$port) = cge_start($qparams);
      if($pid && $port) {
        $self->session(current_pid => $pid, 'db-port' => $port, current_database => $qparams->{dataDir});
        $self->render(json => {pid => $pid, port => $port});
      }
      else {
        $log->error('[start_db] Failed to start database.');
        $self->rendered(text => 'Failed to start database',status => 500);
      }
    }
    else {
      $log->error('[start_db] Missing required parameters to build database.');
      $self->render(text => 'Missing required parameters to build database.', status => 500);
    }
  };

  get 'stop_db' => sub {
    my $self = shift;
    my $qparams=$self->req->query_params->to_hash;
    my ($current_database,$db_port);
    if($qparams->{current_database} && $qparams->{'db-port'}) {
      $self->session(current_database => $qparams->{current_database},'db-port' => $qparams->{'db-port'});
    }

    if($self->session('current_database') && $self->session('db-port')) {
      my $success = cge_stop_graceful($self->session('db-port'),$self->session('current_database'));
      if($success) {
        $self->rendered(200);
      }
      else {
        $log->error('[stop_db] Failed to stop database: '.$self->session('current_database'));
        $self->render(text => 'Failed to stop database',status => 500);
      }
    }
    else {
      $log->error('[stop_db] Failed to stop database');
      $self->render(text => 'Failed to stop database',status => 500);
    }
  };

  post 'build_db' => sub {
    my $self = shift;
    my $qparams = $self->req->body_params->to_hash;

    if($self->session('username') eq (getpwuid($<))[0]) {

      if(exists $qparams->{'name'} && exists $qparams->{'imagesPerNode'} && exists $qparams->{'nodeCount'}) {
        #=+ Create the needed directories if they don't exist
        mkdir '/mnt/lustre/'.$self->session('username') unless -d '/mnt/lustre/'.$self->session('username');
        mkdir '/mnt/lustre/'.$self->session('username').'/'.$qparams->{name} unless -d '/mnt/lustre/'.$self->session('username').'/'.$qparams->{name};
        $qparams->{dataDir} = '/mnt/lustre/'.$self->session('username').'/'.$qparams->{name};
        open(my $FH,'>','/mnt/lustre/'.$self->session('username').'/'.$qparams->{name}.'/graph.info');

        if(ref($qparams->{'files[]'}) eq 'ARRAY') {
          foreach my $file(@{$qparams->{'files[]'}}) {
            say {$FH} $file;
          }
        }
        elsif($qparams->{'files[]'} ne '') {
          say {$FH} $qparams->{'files[]'};
        }
        else {
          $self->render(text => 'No input files provided to build database.',status => 500);
        }
        close($FH);

        #=+ If we have a startup timeout, go ahead and adjust the session timeout accordingly
        if(exists $qparams->{startupTimeout} && $qparams->{startupTimeout} ne '') {
          Mojo::IOLoop->stream($self->tx->connection)->timeout($qparams->{startupTimeout});
        }

        my($pid,$port) = cge_start($qparams);
        if($pid && $port) {
          $self->session(current_pid => $pid, 'db-port' => $port, current_database => $qparams->{dataDir});
          $self->render(json => {pid => $pid, port => $port, current_database => $qparams->{dataDir}});
        }
        else {
          $log->error('[build_db] Failed to start database.');
          $self->rendered(text => 'Failed to start database',status => 500);
        }
      }
      else {
        $log->error('[build_db] Missing required parameters to build database.');
        $self->render(text => 'Missing required parameters to build database.', status => 500);
      }
    }
    else {
      $log->error('[build_db] user '.$self->session('username').' was prevented from creating a database ('.$qparams->{'name'}.').  Only the the user who launched the web-application may build a new database.');
      $self->render(text => 'Unauthorized:  Only the the user who launched the web-application may build a new database.', status => 403);
    }
  };

  #=+ Later on the roadmap, we will revisit alowing users to admin databases in a session not started by them.
  get 'UAC_CRUD_service' => sub {
    my $self = shift;
    my $qparams=$self->req->query_params->to_hash;
    if($self->session('username') eq (getpwuid($<))[0]) {
      my $output_ref = _list_database_permissions();
      $self->render(json => $output_ref);
    }
    else {
      $log->error('[UAC_CRUD_service] user '.$self->session('username').' was prevented from accessing database permissions.  Only the the user who launched the web-application may alter database permissions.');
      $self->render(text => 'Unauthorized:  Only the the user who launched the web-application may alter database permissions.', status => 403);
    }
  };
  post 'UAC_CRUD_service_create' => sub {
    my $self = shift;
    my $p = $self->req->body_params->to_hash;
    my $json = decode_json($p->{models});
    my $qparams = $json->[0];
    if($self->session('username') eq (getpwuid($<))[0]) {
      $qparams->{database} .= '/' unless $qparams->{database} =~ /\/$/;
      my %newuser = (
        username    => $qparams->{username},
        database    => $qparams->{database},
        permissions => $qparams->{permissions}->{permissions}
      );
      my $success = add_user(\%newuser);

      if($success) {
        $self->render(json => []);
      }
      else {
        $self->render(text => 'Could not create new user.', status => 500);
      }
    }
    else {
      $log->error('[UAC_CRUD_service_create] user '.$self->session('username').' was prevented from accessing database permissions.  Only the the user who launched the web-application may alter database permissions.');
      $self->render(text => 'Unauthorized:  Only the the user who launched the web-application may alter database permissions.', status => 403);
    }
  };
  post 'UAC_CRUD_service_update' => sub {
    my $self = shift;
    my $p = $self->req->body_params->to_hash;
    my $json = decode_json($p->{models});
    my $qparams = $json->[0];
    if($self->session('username') eq (getpwuid($<))[0]) {
      $qparams->{database}->{path} .= '/' unless $qparams->{database}->{path} =~ /\/$/;
      my %changes = (
        action      => 'modify',
        username    => $qparams->{username},
        database    => $qparams->{database}->{path},
        permissions => $qparams->{permissions}->{permissions}
      );

      my $success = modify_user(\%changes);
      if($success) {
        $self->render(json => []);
      }
      else {
        $self->render(text => 'Could not modify user.', status => 500);
      }
    }
    else {
      $log->error('[UAC_CRUD_service_update] user '.$self->session('username').' was prevented from accessing database permissions.  Only the the user who launched the web-application may alter database permissions.');
      $self->render(text => 'Unauthorized:  Only the the user who launched the web-application may alter database permissions.', status => 403);
    }
  };
  post 'UAC_CRUD_service_destroy' => sub {
    my $self = shift;
    my $p = $self->req->body_params->to_hash;
    my $json = decode_json($p->{models});
    my $qparams = $json->[0];
    if($self->session('username') eq (getpwuid($<))[0]) {
      $qparams->{database}->{path} .= '/' unless $qparams->{database}->{path} =~ /\/$/;
      my %delete = (
        action   => 'revoke',
        username => $qparams->{username},
        database => $qparams->{database}->{path}
      );

      my $success = modify_user(\%delete);
      if($success) {
        $self->render(json => []);
      }
      else {
        $self->render(text => 'Could not modify user.', status => 500);
      }
    }
    else {
      $log->error('[UAC_CRUD_service_destroy] user '.$self->session('username').' was prevented from accessing database permissions.  Only the the user who launched the web-application may alter database permissions.');
      $self->render(text => 'Unauthorized:  Only the the user who launched the web-application may alter database permissions.', status => 403);
    }
  };

  websocket 'sparqlQueryWs' => sub {
    my $ws = shift;
    
    $ws->on(message => sub {
      my ($self,$msg) = @_;
      my $qparams = decode_json($msg);
      
      if($qparams->{qtype} eq 'select' ) {
        my ($success,$results_ref) = cge_select($qparams);
    
        if($success == 1) {
          $self->send(encode_json($results_ref));
        }
        else {
          $self->send(encode_json({error_code => $results_ref}));
        }
      }
      elsif($qparams->{qtype} eq 'ask' ) {
        my ($success,$results_ref) = cge_select($qparams);
    
        if($success == 1) {
          $self->send(encode_json($results_ref));
        }
        else {
          $self->send(encode_json({error_code => $results_ref}));
        }
      }
      elsif($qparams->{qtype} eq 'construct' ) {
        my ($success,$results_ref) = cge_construct($qparams);
        if($success == 1) {
          $self->send(encode_json($results_ref));
        }
        else {
          $self->send(encode_json({error_code => $results_ref}));
        }
      }
      elsif($qparams->{qtype} eq 'describe' ) {
        my ($success,$results_ref) = cge_construct($qparams);
        if($success == 1) {
          $self->send(encode_json($results_ref));
        }
        else {
         $self->send(encode_json({error_code => $results_ref}));
        }
      }
      else {
        $log->error('invalid query type: '.$qparams->{qtype});
      }
    });
    
    $ws->on(finish => sub {
    my ($self, $code, $reason) = @_;
      $log->info('sparqlSelectWs closed with status code: '.$code);
    });
  };
  
  websocket 'sparqlInsertWs' => sub {
    my $ws = shift;
    
    $ws->on(message => sub {
      my ($self,$msg) = @_;
      my $qparams = decode_json($msg);
      
      if($self->session('username') eq (getpwuid($<))[0]) {
        #=+ Need to toss in the database directory
        $qparams->{current_database} = $self->session('current_database');
  
        my ($success,$results_ref) = cge_insert($qparams);
        if($success == 1) {
          $self->send(encode_json($results_ref));
        }
        else {
          $self->send(encode_json({error_code => $results_ref}));
        }
      }
      else {
        $log->error('[sparqlInsert] user '.$self->session('username').' was prevented from altering a database.  Only the the user who launched the web-application may alter databases.');
        $self->render(text => 'Unauthorized:  Only the the user who launched the web-application may alter a database.', status => 403);
      }
    });
    
    $ws->on(finish => sub {
    my ($self, $code, $reason) = @_;
      $log->info('sparqlSelectWs closed with status code: '.$code);
    });
  };
  
  websocket 'dbStartStopWs' => sub {
    my $ws = shift;
    
    $ws->on(message => sub {
      my ($self,$msg) = @_;
      my $qparams = decode_json($msg);
      
      if($qparams->{action} eq 'start') {
        if(exists $qparams->{dataDir} && exists $qparams->{imagesPerNode} && exists $qparams->{nodeCount}) {
          #=+ If we have a startup timeout, go ahead and adjust the session timeout accordingly
          if(exists $qparams->{startupTimeout} && $qparams->{startupTimeout} ne '') {
            Mojo::IOLoop->stream($self->tx->connection)->timeout($qparams->{startupTimeout});
          }
    
          my($pid,$port) = cge_start($qparams);
          if($pid && $port) {
            $self->session(current_pid => $pid, 'db-port' => $port, current_database => $qparams->{dataDir});
            $self->send(encode_json({ pid => $pid, port => $port, success => 'started' }));
          }
          else {
            $log->error('[start_db] Failed to start database.');
            $self->send(encode_json({ error_code => 'Failed to start database', status => 500 }));
          }
        }
        else {
          $log->error('[start_db] Missing required parameters to build database.');
          $self->send(encode_json({ error_code => 'Missing required parameters to build database.', status => 500 }));
        }
      }
      elsif($qparams->{action} eq 'stop') {
        my ($current_database,$db_port);
        if($qparams->{current_database} && $qparams->{'db-port'}) {
          $self->session(current_database => $qparams->{current_database},'db-port' => $qparams->{'db-port'});
        }
    
        if($self->session('current_database') && $self->session('db-port')) {
          my $success = cge_stop_graceful($self->session('db-port'),$self->session('current_database'));
          if($success) {
            $self->send(encode_json({ success => 'stopped' }));
          }
          else {
            $log->error('[stop_db] Failed to stop database: '.$self->session('current_database'));
            $self->send(encode_json({ error_code => 'Failed to stop database', status => 500 }));
          }
        }
        else {
          $log->error('[stop_db] Failed to stop database');
          $self->send(encode_json({ error_code => 'Failed to stop database', status => 500 }));
        }
      }
    });
    
    $ws->on(finish => sub {
    my ($self, $code, $reason) = @_;
      $log->info('sparqlSelectWs closed with status code: '.$code);
    });
  };
  
  get 'query_list' => sub {
    my $self = shift;
    my $qparams = $self->req->query_params->to_hash;
    
    my @databases = (
      (getpwnam $self->session('username'))[7].'/.cge_web_ui/queries/',
      $root_directory.'queries/'
    );
    
    if(exists $qparams->{current_database}) {
      $qparams->{current_database} .= '/' unless $qparams->{current_database} =~ /\/$/;
      push @databases, $qparams->{current_database}.'.cge_web_ui/queries/';
    }
    
    my $querylist_ref = loadQueries(\@databases);
    $self->render(json => $querylist_ref);
  };
  
  post 'saveQuery' => sub {
    my $self = shift;
    my $qparams = $self->req->body_params->to_hash;
    my $filename = $qparams->{'title'};
    my $shared = $qparams->{'general'};
    my $counter = 1;
  
    my $which_directory;
    if($shared eq 'general_purpose') {
      $which_directory = (getpwnam $self->session('username'))[7].'/.cge_web_ui/queries/';
      mkdir $which_directory unless -d $which_directory;
    }
    elsif($shared eq 'specific') {
      $which_directory = $self->session('current_database').'/.cge_web_ui/queries/';
      mkdir $which_directory unless -d $which_directory;
    }
    else {
      $self->render(text => '[ERROR] Unknown option: '.$shared, status => 500);
    }
  
    if (-f $which_directory.$filename.'.rq') {
      while (-f $which_directory.$filename.'_'.$counter.'.rq') {
        $counter++;
      }
      $filename .= '_'.$counter;
    }
    open(my $OF, '>', $which_directory.$filename.'.rq') or croak;
    close($OF);
  
    if (!-z $which_directory.$filename.'_'.$counter.'.rq') {
      $self->rendered(200);
    }
    else {
      $self->rendered(500);
    }
  };
  
  post 'saveExcel' => sub {
    my $self = shift;
    Mojo::IOLoop->stream($self->tx->connection)->timeout(3000);
    my $qparams = $self->req->body_params->to_hash;
    $self->stash('gzip' => 1);

    my $contentType = $qparams->{'contentType'};
    my $b64 = $qparams->{'base64'};
    my $file = b64_decode $b64;
    my $fileName = $qparams->{'fileName'};
    $self->res->headers->header('Content-Type' => $contentType);
    $self->res->headers->header('Content-Disposition' => 'attachment; filename="'.$fileName.'"');
    $self->render(data => $file);
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
      #=+ The regex here is looking for a value that is EXACTLY cn, uid, or homeDirectory (case-sensitive).  Feel free to add more values if they are useful
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
      File::Path::Tiny::mk($dir);
      chmod 0700, $dir;
    }
    unless(-r $dir) {
      croak $dir.' : Directory is not readable';
    }
    unless(-w $dir) {
      croak $dir.' : Directory is not writable.';
    }
  }
  return 1;
}

sub _list_database_permissions {
  my $root = $config->config->{'database_directory'};
  my @userperms;

  find(sub {
    if($File::Find::name =~ /dbQuads$/ && -O $File::Find::name) {
      my $authorized_users_dir = $File::Find::dir.'/.cge_web_ui/authorized_users/';
      my $dbname = $1 if $File::Find::dir =~ /\/([^\/]+)$/;
      my @auth_users;
      if(-d $authorized_users_dir) {
        opendir(my $directory, $authorized_users_dir);
        while(my $f = readdir $directory) {
          next unless -d $authorized_users_dir.$f;
          if(-e $authorized_users_dir.$f.'/properties.yaml') {
            my $perms_config = YAML::AppConfig->new(file => $authorized_users_dir.$f.'/properties.yaml');
            my %permissions;
            if($perms_config->config->{permissions} eq 'ro') {
              %permissions = (permissionsString => 'Read-Only', permissions => 'ro');
            }
            elsif($perms_config->config->{permissions} eq 'rw') {
              %permissions = (permissionsString => 'Read-Write', permissions => 'rw');
            }
            
            my %temp_user = (
              id            => $perms_config->config->{database}.$perms_config->config->{username},
              username      => $perms_config->config->{username},
              permissions   => \%permissions,
              created       => $perms_config->config->{created},
              last_modified => $perms_config->config->{last_modified},
              database      => { path => $perms_config->config->{database} }
            );
            push @userperms, \%temp_user;
          }
        }
        closedir($directory);
      }
    }
  },$root);
  return \@userperms;
}

sub _list_NT_files {
  my($root,$current_user) = @_;
  $root = '/mnt/lustre' unless defined $root;

  my @output;
  find(sub {
    if($File::Find::name =~ /\.nt$/) {
      return unless defined ((stat $File::Find::name)[4]);
      my $user = (getpwuid ((stat $File::Find::name)[4]))[0];
      my $name = $1 if $File::Find::name =~ /\/([^\/]+)$/;
      my $size = -s $File::Find::name;

      my $index = 0;
      my $found;
      foreach my $match(@output) {
        if($match->{name} eq $File::Find::dir) {
          $found = 1;
          last;
        }
        $index++;
      }

      if($found) {
        my %temp = (
          owner         => $user,
          size          => _file_size($size),
          bytes         => $size,
          name          => $name,
          directory     => $File::Find::dir,
          path          => $File::Find::name,
          hasFiles      => 0,
          last_modified => strftime("%Y-%m-%d %H:%M:%S",localtime((stat $File::Find::name)[9]))
        );
        push @{$output[$index]->{files}}, \%temp;
      }
      else {
        my %temp = (
          name      => $File::Find::dir,
          directory => $File::Find::dir,
          hasFiles  => 1,
          files     => [
            {
              owner         => $user,
              size          => _file_size($size),
              bytes         => $size,
              name          => $name,
              directory     => $File::Find::dir,
              path          => $File::Find::name,
              last_modified => strftime("%Y-%m-%d %H:%M:%S",localtime((stat $File::Find::name)[9]))
            }
          ],
        );
        push @output, \%temp;
      }
    }
  },$root);
  return \@output;
}

sub _list_databases {
  my($root,$current_user) = @_;
  $root = '/mnt/lustre' unless defined $root;
  return if !defined $current_user;
  my @output;
  find(sub {
    if($File::Find::name =~ /dbQuads$/) {
      return unless defined ((stat $File::Find::dir)[4]);
      my $user = (getpwuid ((stat $File::Find::dir)[4]))[0];
      my $name = $1 if $File::Find::dir =~ /\/([^\/]+)$/;

      #=+ Apart from just having UNIX permissions to read the database, if the database is owned by another user,
      #   then the current user must also have SSH keys set up to allow them to actually run the database.
      return if ($current_user ne $user && !-e $File::Find::dir.'/.cge_web_ui/authorized_users/'.$current_user.'/id_rsa');

      #=+ Would like to know how big the directory contents are
      my $size = 0;
      find(sub {
        if(-f $_ && $_ =~ /^dbQuads$|^string_table_chars.index$|^string_table_chars$/) {
          $size += -s $_;
        }
      },$File::Find::dir);

      #=+ If any authorized uses have been added, then capture that information here
      my $authorized_users_dir = $File::Find::dir.'/.cge_web_ui/authorized_users/';
      my @auth_users;
      if(-d $authorized_users_dir) {
        opendir(my $directory, $authorized_users_dir);
        while(my $f = readdir $directory) {
          next unless -d $authorized_users_dir.$f;
          if(-e $authorized_users_dir.$f.'/properties.yaml') {
            my $perms_config = YAML::AppConfig->new(file => $authorized_users_dir.$f.'/properties.yaml');
            my %temp_user = (
              username      => $perms_config->config->{username},
              permissions   => $perms_config->config->{permissions},
              created       => $perms_config->config->{created},
              last_modified => $perms_config->config->{last_modified},
              database      => $perms_config->config->{database}
            );
            push @auth_users, \%temp_user;
          }
        }
        closedir($directory);
      }

      my %temp = (
        owner            => $user,
        size             => _file_size($size),
        bytes            => $size,
        name             => $name,
        path             => $File::Find::dir,
        hasFiles         => undef,
        authorized_users => \@auth_users,
        last_modified    => strftime("%Y-%m-%d %H:%M:%S",localtime((stat $File::Find::dir)[9]))
      );
      push @output, \%temp;
    }
  },$root);
  return \@output;
}

sub loadQueries {
  my ($directories) = @_;
  my @files = ();
  
  #=+ Just in case we don't get any directories
  return undef if scalar(@$directories) == 0;
  
  foreach my $dir(@$directories) {
    if(-d $dir) {
      $dir .= '/' unless $dir =~ /\/$/;
      my @temp = read_dir $dir;
      foreach my $file(@temp) {
        push @files, $dir.$file if $file =~ m/\.rq$|\.ru$/;
      }
    }
  }
  
  my @queries;
  @files = sort @files;
  
  foreach my $file(@files) {
      my $query = read_file($file);
      $file =~ s/.+\/([^\/]+)\.rq$/$1/;
      push @queries, {'name' => $file, 'query' => $query};
  }
  
  return \@queries;
}

#=+ Read in our configuration file
sub _config_init {
  #=+ no options to the init routine for now...may revisit later
  #=+ First, load up the master config file
  my $yaml_config;
  my $config_file_name = $root_directory.'cge-web-ui-config.yaml';
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
  if(-e (getpwuid $>)[7].'/.cge_web_ui/analytics_ui_config.yaml' && -r _) {
    $yaml_config->merge(file => (getpwuid $>)[7].'/.cge_web_ui/analytics_ui_config.yaml');
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
    $yaml_config->config->{'port'} = $freePort;
  }
  return $yaml_config;
}

sub _file_size {
  my($num) = @_;
  my $string;

  if   ($num >= 1000**5) { $string = sprintf('%.3f',($num / 1000**5)).' PB'; return $string; }
  elsif($num >= 1000**4) { $string = sprintf('%.3f',($num / 1000**4)).' TB'; return $string; }
  elsif($num >= 1000**3) { $string = sprintf('%.3f',($num / 1000**3)).' GB'; return $string; }
  elsif($num >= 1000**2) { $string = sprintf('%.3f',($num / 1000**2)).' MB'; return $string; }
  elsif($num >= 1000)    { $string = sprintf('%.3f',($num / 1000)).' KB'; return $string; }
  else                   { $string .= ' B'; return $num; }
}

#=+ Finally, let's get started!
app->start;
