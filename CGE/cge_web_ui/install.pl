#!/usr/bin/env perl

use strict;
use warnings;
use Carp qw(cluck carp croak);
use IPC::Cmd qw(can_run run);
use CPAN;

#=+ We will use a hash to keep track of errors so that we can spit them out at the end.  It's better
#   to get through the whole thing before we croak
my %errors;

#=+ First, let's check that we are using a recent enough Perl
my $perl_version = $];
unless($perl_version >= 5.016) {
  $errors{perl_version} = $perl_version;
}

#=+ Next, let's check if we have permissions to write to the Perl install directory


#=+ The very first thing we need to do is make sure that cpanminus is installed
my $cpanminus = can_run('cpanm');
unless(defined $cpanminus) {
  
}

#=+ Here is the list of dependencies.  We will add minimum versions later, but check the CPAN modules are there for now
my %dependencies = ('EV'                   => 4.22,
                    'File::Path::Tiny'     => 0.8,
                    'File::Slurp'          => 9999.19,
                    'File::Tail'           => '',
                    'Math::Random::Secure' => 0.06,
                    'Mojolicious'          => 7.08,
                    'Try::Tiny'            => 0.27,
                    'Net::EmptyPort'       => '',
                    'Net::LDAP'            => 0.65,
                    'Net::OpenSSH'         => 0.73,
                    'Test::Deep::NoTest'   => '',
                    'Tie::Hash::Expire'    => 0.03,
                    'YAML::AppConfig'      => 0.19);

while(my ($k,$v) = each %dependencies) {
  eval( "use $k $v");
  if($@) {
    print $@;
    push @{$errors{missing_modules}}, $k;
  }
}

1;

__END__