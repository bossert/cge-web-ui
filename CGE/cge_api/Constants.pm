#!/usr/bin/env perl

package CGE::cge_api::Constants;

use strict;
use 5.016;
require Exporter;

our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(%protocol %messageTypes_num2str %messageTypes_str2num %errorCodes_num2str %errorCodes_str2num);
our %EXPORT_TAGS = (ALL => [ qw(%protocol %messageTypes_num2str %messageTypes_str2num %errorCodes_num2str %errorCodes_str2num) ]);

#=+ These values need to get calculated within the hash to avoid entering them twice
my $magic_bytes_string = 'SftUrika';
my $ssh_header_string = 'SSH-2.0-';
my $v1_header_length = 2;

my %protocol = ('V1'                        => 1,
                'V2'                        => 2,
                'LOWEST_SUPPORTED_VERSION'  => 1,
                'HIGHEST_SUPPORTED_VERSION' => 2,
                'CURRENT_VERSION'           => 2,
                'MAGIC_BYTES_STRING'        => $magic_bytes_string,
                'MAGIC_BYTES'               => unpack('H*',$magic_bytes_string),
                'MAGIC_BYTES_LENGTH'        => length($magic_bytes_string),
                'SSH_HEADER_STRING'         => $ssh_header_string,
                'SSH_HEADER_BYTES'          => unpack('H*',$ssh_header_string),
                'V1_HEADER_LENGTH'          => $v1_header_length,
                'V2_MIN_HEADER_LENGTH'      => $v1_header_length + 2,
                'V2_MAX_NVPS'               => 255);

my %messageTypes_num2str = (0   => 'ERROR',
                            1   => 'READY_FOR_DATA',
                            2   => 'SUCCESS',
                            10  => 'QUERY_REQUEST',
                            11  => 'QUERY_RESULTS',
                            20  => 'UPDATE_REQUEST',
                            30  => 'CHECKPOINT_REQUEST',
                            200 => 'GET_DEFAULT_NVPS',
                            201 => 'GET_DEFAULT_LOGGING',
                            202 => 'GET_OUTPUT_DIRECTORY',
                            210 => 'SET_DEFAULT_NVPS',
                            211 => 'SET_DEFAULT_LOGGING',
                            212 => 'SET_OUTPUT_DIRECTORY',
                            250 => 'SHUTDOWN_REQUEST',
                            255 => 'ECHO');

#=+ Perhaps this is total overkill, extreme laziness, or both, but the thought process is that in order to avoid
#   writing the values twice in row, thereby doubling the possibility of typos and time needed to add/alter
#   message type code mappings at a later date, we write it once and then simply swap them out.  Sure, swapping them in this
#   way introduces the possibility of having duplicate hash values, but since we are working with string to
#   numeric mappings (and vice versa) of message codes, by definition, each will be unique

my %messageTypes_str2num;

while (my($k,$v) = each %messageTypes_num2str) {
  $messageTypes_str2num{$v} = $k;
}

my %errorCodes_num2str = (1000 => 'BAD_MAGIC_BYTES',
                          1001 => 'INVALID_DATA',
                          1010 => 'UNSUPPORTED_PROTOCOL_VERSION',
                          1011 => 'UNSUPPORTED_PROTOCOL_FEATURE',
                          1021 => 'UNSUPPORTED_MESSAGE_TYPE',
                          1022 => 'UNSUPPORTED_MESSAGE_DIRECTION');

my %errorCodes_str2num;

while (my($k,$v) = each %errorCodes_num2str) {
  $errorCodes_str2num{$v} = $k;
}

1;