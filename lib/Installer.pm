package Installer;
# ABSTRACT: Install..... stuff

use strict;
use warnings;
use Exporter 'import';

use Installer::Target;

our @EXPORT = qw(

  install_to

  run
  url
  file
  perl

);

sub install_to {
  my ( $target_directory, $installer_code ) = @_;
  my $installer_target = Installer::Target->new(
    target_directory => $target_directory,
    installer_code => $installer_code,
  );
  $installer_target->installation;
}

sub run {
  die "Not inside installation" unless defined $Installer::Target::current;
  $Installer::Target::current->custom_run(@_);
}

sub url {
  die "Not inside installation" unless defined $Installer::Target::current;
  $Installer::Target::current->install_url(@_);
}

sub file {
  die "Not inside installation" unless defined $Installer::Target::current;
  $Installer::Target::current->install_file(@_);
}

sub perl {
  die "Not inside installation" unless defined $Installer::Target::current;
  $Installer::Target::current->install_perl(@_);
}

1;

=encoding utf8

=head1 DESCRIPTION

B<TOTALLY ALPHA, YOU NEVER SAW THIS!!! GO AWAY!!!>

