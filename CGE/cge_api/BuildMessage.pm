#!/usr/bin/env perl

package CGE::cge_api::BuildMessage;

use strict;
use 5.016;
use Carp qw(croak cluck carp);
use lib '/mnt/lustre/bossert/git';
use CGE::cge_api::Rpn qw(compile2rpn);
use CGE::cge_api::Constants qw(:ALL);
use Net::OpenSSH;
use Data::Dumper;
require Exporter;

our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (ALL => [ qw() ]);

#=+ Here for private and exportable subs, apart from those added to EXPORT_OK,
#   we also use the underscore convention: any subs that start with an
#   underscore are intended for internal use only.

my $query =<<QUERY;
CONSTRUCT {
  ?s ?p ?o .
}
WHERE {
  ?s ?p ?o .
}
LIMIT 100
QUERY

my %test = (
  'message_type' => 'GET_DEFAULT_LOGGING'#,
  #'payload'      => pack('A*','0123456789')#compile2rpn($query)
);

my $header = _buildHeaderBytes(\%test);
my $message = $header.$test{'payload'};

my $ssh = Net::OpenSSH->new('127.0.0.1', user => 'bossert', port => 3750, key_path => '/home/users/bossert/.ssh/id_rsa');
$ssh->error and croak $ssh->error;

my $out = $ssh->capture_tunnel({stdin_data => $message},'127.0.0.1',3750);

say length($out);

my @buf = unpack('A8Q>B8B8A8Q>B8B8A*',$out);
say length($buf[8]);
say Dumper(\@buf);

sub buildMessage {
  my ($messageType) = @_;
}

sub _buildNvpBytes {
  my ($nvp_ref) = @_;
  my $nvp_bytes;

  foreach my $nvp(@{$nvp_ref}) {
    #=+ Store the length as an unsigned Long value (32 bits)
    my $length = pack('L>',length($nvp->{'key'}));
    #=+ Store the name
    my $name = pack('A*',$nvp->{'key'});
    #=+ Store the value as an unsigned Quad (64 bits)
    my $value = pack('Q>',$nvp->{'value'});
    $nvp_bytes .= $length.$name.$value;
  }
  return $nvp_bytes;
}

sub _buildHeaderBytes {
  my ($header_ref) = @_;

  my $magic = pack('A8',$MAGIC_BYTES_STRING);
  my $version = pack('B*',sprintf('%08b',$CURRENT_VERSION - 1));
  my $message_type = pack('B*',sprintf('%08b',$CGE_MESSAGE_CODES{$header_ref->{'message_type'}}));
  my $nvps_present;
  my $nvp_bytes;
  if(exists $header_ref->{'nvp_list'}) {
    $nvps_present = pack('b8',sprintf('%b',@{$header_ref->{'nvp_list'}}));
    $nvp_bytes = _buildNvpBytes($header_ref->{'nvp_list'});
  }
  else {
    $nvps_present = pack('b8','00000000');
    #$nvp_bytes = pack('b8','00000000');
  }

  my $log_config_present;
  my $log_config_bytes;
  if (exists $header_ref->{'log_config'}) {
    $log_config_present = pack('b8','00000001');
  }
  else {
    $log_config_present = pack('b8','00000000');
    #$log_config_bytes = pack('b8','00000000');
  }

  #=+ The length is the second field, but we need to know how long the
  #   message/payload is as well as the entire header, So we calculate as the
  #   last step before building the header bytes.  Also, there are more compact
  #   ways to add up the lengths and to concatenate the header bytes together,
  #   but the slightly more verbose approach should make it easier to read the
  #   code and modify later as needed by someone other than the primary author.
  my $lengthNum = length($header_ref->{'payload'});
  $lengthNum    += length($version);
  $lengthNum    += length($message_type);
  $lengthNum    += length($nvps_present);
  $lengthNum    += length($nvp_bytes) if defined $nvp_bytes;
  $lengthNum    += length($log_config_present);
  $lengthNum    += length($log_config_bytes) if defined $log_config_bytes;

  my $length = pack('Q>',$lengthNum);
  my $header_bytes = $magic.$length.$version.$message_type.$nvps_present;
  $header_bytes .= $nvp_bytes if defined $nvp_bytes;
  $header_bytes .= $log_config_present;
  $header_bytes .= $log_config_bytes if defined $log_config_bytes;
  return $header_bytes;
}

1;
