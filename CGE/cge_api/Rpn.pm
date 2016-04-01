#!/usr/bin/env perl

package CGE::cge_api::Rpn;

use strict;
use 5.016;
use IPC::Cmd qw(can_run run);
use Carp qw(croak cluck carp);
require Exporter;

our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(compile2rpn);
our %EXPORT_TAGS = (ALL => [ qw(compile2rpn) ]);

#=+ In a future version, we will construct the RPN entirely from scratch, but in the interest of time, we will simply wrap
#   the existing command-line version.  This should be transparent to users of the library
my $cge_cli = can_run('cge-cli') or croak $@;

sub compile2rpn {
  my ($query) = @_;
  my $hex;
  
  #=+ Wouldn't it be nice if cge-cli accepted input on STDIN?
  open(my $TEMP, '>', 'test.rq') or croak $@;
  print {$TEMP} $query;
  close($TEMP);
  
  my ($success,$error,$full_buf,$stdout,$stderr) = run(command => $cge_cli.' compile -c rpn test.rq');
  if ($success) {
    $hex = unpack('H*',join('',@$stdout));
    unlink('test.rq');
  }
  else {
    $hex = undef;
  }
  return $hex;
}

1;