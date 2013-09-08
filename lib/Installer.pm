package Installer;
# ABSTRACT: What does it do? It installs stuff....

use strict;
use warnings;
use Installer::Target;

our @functions = qw(

  run
  url
  file
  perl
  cpanm
  pip

);

sub import {
  my $pkg = caller;
  {
    no strict 'refs';
    *{"$pkg\::install_to"} = sub {
      my ( $target_directory, $installer_code ) = @_;
      my $installer_target = Installer::Target->new(
        target_directory => $target_directory,
        installer_code => $installer_code,
      );
      $installer_target->installation;
    };
  }
  for my $command (@functions) {
    my $function = 'install_'.$command;
    no strict 'refs';
    *{"$pkg\::$command"} = sub {
      die "Not inside installation" unless defined $Installer::Target::current;
      $Installer::Target::current->$function(@_);
    };
  }
}

1;

=encoding utf8

=head1 SYNOPSIS

  use Installer;

  install_to $ENV{HOME}.'/myenv' => sub {
    perl "5.18.1";
    url "http://ftp.postgresql.org/pub/source/v9.2.4/postgresql-9.2.4.tar.gz", with => {
      pgport => 15432,
    };
    url "http://download.osgeo.org/gdal/1.10.1/gdal-1.10.1.tar.gz";
    url "http://download.osgeo.org/geos/geos-3.4.2.tar.bz2";
    url "http://download.osgeo.org/postgis/source/postgis-2.1.0.tar.gz", custom_test => sub {
      $_[0]->run($_[0]->unpack_path,'make','check');
    };
    cpanm "DBD::Pg";
  };

Or in class usage (not suggested):

  use Installer::Target;

  my $target = Installer::Target->new(
    target_directory => $ENV{HOME}.'/myenv',
  );

  $target->prepare_installation;
  $target->install_perl("5.18.1");
  $target->install_file("postgresql-9.2.4.tar.gz", with => {
    pgport => 15432,
  });
  $target->install_cpanm("DBD::Pg","Plack");
  # will run in the target directory
  $target->install_run("command","--with-args");
  $target->finish_installation;

=head1 DESCRIPTION

See L<installer> for more information.

B<TOTALLY BETA, PLEASE TEST :D>

