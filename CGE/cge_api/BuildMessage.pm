#!/usr/bin/env perl

package CGE::cge_api::BuildMessage;

use strict;
use 5.016;
use Carp qw(croak cluck carp);
use Rpn qw(compile2rpn);
use Constants qw(:ALL);

require Exporter;

our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (ALL => [ qw() ]);

sub buildMessage {
  my ($messageType) = @_;
}

1;