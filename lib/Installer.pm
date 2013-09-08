package Installer;
# ABSTRACT: What does it do? It installs stuff....

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
  cpanm

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

sub cpanm {
  die "Not inside installation" unless defined $Installer::Target::current;
  $Installer::Target::current->install_cpanm(@_);
}

1;

=encoding utf8

=head1 SYNOPSIS

  use strict;
  use warnings;
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

=head1 DESCRIPTION

See L<installer> for more information

B<TOTALLY ALPHA, YOU NEVER SAW THIS!!! GO AWAY!!!>

