#!/usr/bin/env perl

package CGE::cge_api::Constants;

use strict;
use 5.016;
require Exporter;

our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw($V1 $V2 $LOWEST_SUPPORTED_VERSION $HIGHEST_SUPPORTED_VERSION $CURRENT_VERSION $MAGIC_BYTES_STRING $SSH_HEADER_STRING $V1_HEADER_LENGTH $V2_MIN_HEADER_LENGTH $V2_MAX_NVPS %CGE_MESSAGE_CODES %CGE_ERROR_CODES);
our %EXPORT_TAGS = (ALL => [ qw($V1 $V2 $LOWEST_SUPPORTED_VERSION $HIGHEST_SUPPORTED_VERSION $CURRENT_VERSION $MAGIC_BYTES_STRING $SSH_HEADER_STRING $V1_HEADER_LENGTH $V2_MIN_HEADER_LENGTH $V2_MAX_NVPS %CGE_MESSAGE_CODES %CGE_ERROR_CODES) ]);

our $V1                        = 1;
our $V2                        = 2;
our $LOWEST_SUPPORTED_VERSION  = 1;
our $HIGHEST_SUPPORTED_VERSION = 2;
our $CURRENT_VERSION           = 2;
our $MAGIC_BYTES_STRING        = 'SftUrika';
our $SSH_HEADER_STRING         = 'SSH-2.0-';
our $V1_HEADER_LENGTH          = 2;
our $V2_MIN_HEADER_LENGTH      = $V1_HEADER_LENGTH + 2;
our $V2_MAX_NVPS               = 255;

our %CGE_MESSAGE_CODES =(0   => 'ERROR',
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
                         255 => 'ECHO',
                         'ERROR'                => 0,
                         'READY_FOR_DATA'       => 1,
                         'SUCCESS'              => 2,
                         'QUERY_REQUEST'        => 10,
                         'QUERY_RESULTS'        => 11,
                         'UPDATE_REQUEST'       => 20,
                         'CHECKPOINT_REQUEST'   => 30,
                         'GET_DEFAULT_NVPS'     => 200,
                         'GET_DEFAULT_LOGGING'  => 201,
                         'GET_OUTPUT_DIRECTORY' => 202,
                         'SET_DEFAULT_NVPS'     => 210,
                         'SET_DEFAULT_LOGGING'  => 211,
                         'SET_OUTPUT_DIRECTORY' => 212,
                         'SHUTDOWN_REQUEST'     => 250,
                         'ECHO'                 => 255);

our %CGE_ERROR_CODES = (1000 => 'BAD_MAGIC_BYTES',
                        1001 => 'INVALID_DATA',
                        1010 => 'UNSUPPORTED_PROTOCOL_VERSION',
                        1011 => 'UNSUPPORTED_PROTOCOL_FEATURE',
                        1021 => 'UNSUPPORTED_MESSAGE_TYPE',
                        1022 => 'UNSUPPORTED_MESSAGE_DIRECTION',
                        BAD_MAGIC_BYTES               => 1000,
                        INVALID_DATA                  => 1001,
                        UNSUPPORTED_PROTOCOL_VERSION  => 1010,
                        UNSUPPORTED_PROTOCOL_FEATURE  => 1011,
                        UNSUPPORTED_MESSAGE_TYPE      => 1021,
                        UNSUPPORTED_MESSAGE_DIRECTION => 1022);

1;