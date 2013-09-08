package Installer::Target;
# ABSTRACT: Currently running project

use Moo;
use Path::Tiny;
use IO::All;
use IPC::Open3 ();
use Installer::Software;
use JSON_File;
use File::chdir;
use CPAN::Perl::Releases qw[perl_tarballs];
use CPAN;

has output_code => (
  is => 'ro',
  lazy => 1,
  default => sub { sub {
    print @_, "\n";
  } },
);

has installer_code => (
  is => 'ro',
  required => 1,
);

has target_directory => (
  is => 'ro',
  required => 1,
);

has target => (
  is => 'ro',
  lazy => 1,
  default => sub { path($_[0]->target_directory)->absolute },
);
sub target_path { path(shift->target,@_) }

has installer_dir => (
  is => 'ro',
  lazy => 1,
  default => sub { path($_[0]->target,'installer')->absolute },
);

has software => (
  is => 'ro',
  lazy => 1,
  default => sub {{}},
);

has actions => (
  is => 'ro',
  lazy => 1,
  default => sub {[]},
);

has src_dir => (
  is => 'ro',
  lazy => 1,
  default => sub { path($_[0]->target,'src')->absolute },
);

has log_filename => (
  is => 'ro',
  lazy => 1,
  default => sub { path($_[0]->installer_dir,'build.'.(time).'.log')->absolute->stringify },
);

has log_io => (
  is => 'ro',
  lazy => 1,
  default => sub { io($_[0]->log_filename) },
);

has meta => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my ( $self ) = @_;
    tie(my %meta,'JSON_File',path($self->installer_dir,'meta.json')->stringify, pretty => 1);
    return \%meta;
  },
);

sub install_software {
  my ( $self, $software ) = @_;
  $self->software->{$software->alias} = $software;
  $software->installation;
  $self->meta->{software_packages_done} = [keys %{$self->software}];
  push @{$self->actions}, $software;
  $self->update_env;
  if (!defined $software->meta->{post_install} && $software->has_post_install) {
    $software->post_install->($software);
    $software->meta->{post_install} = 1;
  }
}

sub install_url {
  my ( $self, $url, %args ) = @_;
  $self->install_software(Installer::Software->new(
    target => $self,
    archive_url => $url,
    %args,
  ));
}

sub install_file {
  my ( $self, $file, %args ) = @_;
  $self->install_software(Installer::Software->new(
    target => $self,
    archive => path($file)->absolute->stringify,
    %args,
  ));
}

sub install_perl {
  my ( $self, $perl_version, %args ) = @_;
  my $hashref = perl_tarballs($perl_version);
  my $src = 'http://www.cpan.org/authors/id/'.$hashref->{'tar.gz'};
  $self->install_software(Installer::Software->new(
    target => $self,
    archive_url => $src,
    testable => 1,
    custom_configure => sub {
      my ( $self ) = @_;
      $self->run($self->unpack_path,'./Configure','-des','-Dprefix='.$self->target_directory);
    },
    post_install => sub {
      my ( $self ) = @_;
      $self->log_print("Installing App::cpanminus ...");
      my $cpanm_filename = path($self->target->installer_dir,'cpanm')->stringify;
      io($cpanm_filename)->print(io('http://cpanmin.us/')->get->content);
      chmod(0755,$cpanm_filename);
      $self->run(undef,$cpanm_filename,'-L',$self->target_path('perl5'),'App::cpanminus','local::lib');
    },
    export_sh => sub {
      my ( $self ) = @_;
      return 'eval $( perl -I'.$self->target_path('perl5','lib','perl5').' -Mlocal::lib='.$self->target_path('perl5').' )';
    },
    %args,
  ));
}

sub install_cpanm {
  my ( $self, @modules ) = @_;
  $self->run(undef,'cpanm',@modules);
}

sub install_pip {
  my ( $self, @modules ) = @_;
  for (@modules) {
    $self->run(undef,'pip','install',$_);    
  }
}

sub setup_env {
  my ( $self ) = @_;
  if (defined $self->meta->{PATH} && @{$self->meta->{PATH}}) {
    $ENV{PATH} = (join(':',@{$self->meta->{PATH}})).':'.$ENV{PATH};
  }
  if (defined $self->meta->{LD_LIBRARY_PATH} && @{$self->meta->{LD_LIBRARY_PATH}}) {
    $ENV{LD_LIBRARY_PATH} = (join(':',@{$self->meta->{LD_LIBRARY_PATH}})).(defined $ENV{LD_LIBRARY_PATH} ? ':'.$ENV{LD_LIBRARY_PATH} : '');
  }
}

sub update_env {
  my ( $self ) = @_;
  my %seen = defined $self->meta->{seen_dirs}
    ? %{$self->meta->{seen_dirs}}
    : ();
  if (!$seen{'bin'} && $self->target_path('bin')->exists) {
    my @bindirs = defined $self->meta->{PATH}
      ? @{$self->meta->{PATH}}
      : ();
    my $bindir = $self->target_path('bin')->absolute->stringify;
    push @bindirs, $bindir;
    $self->meta->{PATH} = \@bindirs;
    $ENV{PATH} = $bindir.':'.$ENV{PATH};
    $seen{'bin'} = 1;
  }
  if (!$seen{'lib'} && $self->target_path('lib')->exists) {
    my @libdirs = defined $self->meta->{LD_LIBRARY_PATH}
      ? @{$self->meta->{LD_LIBRARY_PATH}}
      : ();
    my $libdir = $self->target_path('lib')->absolute->stringify;
    push @libdirs, $libdir;
    $self->meta->{LD_LIBRARY_PATH} = \@libdirs;
    $ENV{LD_LIBRARY_PATH} = $libdir.(defined $ENV{LD_LIBRARY_PATH} ? ':'.$ENV{LD_LIBRARY_PATH} : '');
    $seen{'lib'} = 1;
  }
  $self->meta->{seen_dirs} = \%seen;
}

sub custom_run {
  my ( $self, @args ) = @_;
  $self->run($self->target,@args);
  push @{$self->actions}, {
    run => \@args,
  };
}

sub run {
  my ( $self, $dir, @args ) = @_;
  $dir = $self->target_path unless $dir;
  local $CWD = "$dir";
  $self->log_print("Executing in $dir: ".join(" ",@args));
  $|=1;
  my $run_log = "";
  my $pid = IPC::Open3::open3(my ( $in, $out ), undef, join(" ",@args));
  while(defined(my $line = <$out>)){
    $run_log .= $line;
    chomp($line);
    $self->log($line);
  }
  waitpid($pid, 0);
  my $status = $? >> 8;
  if ($status) {
    print $run_log;
    print "\n";
    print "     Command: ".join(" ",@args)."\n";
    print "in Directory: ".$dir."\n";
    print "exited with status $status\n\n";
    print "\n";
    die "Error on run ".$self->log_filename;
  }
}

sub log {
  my ( $self, @line ) = @_;
  $self->log_io->append(join(" ",@line),"\n");
}

sub log_print {
  my ( $self, @line ) = @_;
  $self->log("#" x 80);
  $self->log("##");
  $self->log("## ",@line);
  my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
  $self->log("## ",sprintf("%.2d.%.2d.%.4d %.2d:%.2d:%.2d",$mday,$mon,$year+1900,$hour,$min,$sec));
  $self->log("##");
  $self->log("#" x 80);
  $self->output_code->(@line);
}

sub write_export {
  my ( $self ) = @_;
  my $export_filename = path($self->target,'export.sh')->stringify;
  $self->log_print("Generating ".$export_filename." ...");
  my $export_sh = "#!/bin/sh\n#\n# Installer auto generated export.sh\n#\n".("#" x 60)."\n\n";
  if (defined $self->meta->{PATH} && @{$self->meta->{PATH}}) {
    $export_sh .= 'export PATH="'.join(':',@{$self->meta->{PATH}}).':$PATH"'."\n";
  }
  if (defined $self->meta->{LD_LIBRARY_PATH} && @{$self->meta->{LD_LIBRARY_PATH}}) {
    $export_sh .= 'export LD_LIBRARY_PATH="'.join(':',@{$self->meta->{LD_LIBRARY_PATH}}).':$LD_LIBRARY_PATH"'."\n";
  }
  $export_sh .= "\n";
  for (@{$self->meta->{software_packages_done}}) {
    my $software = $self->software->{$_};
    if ($software->has_export_sh) {
      my @lines = $software->export_sh->($software);
      $export_sh .= "# export.sh addition by ".$software->alias."\n";
      $export_sh .= join("\n",@lines)."\n\n";
    }
  }
  $export_sh .= ("#" x 60)."\n";
  io($export_filename)->print($export_sh);
  chmod(0755,$export_filename);
}

our $current;
sub installation {
  my ( $self ) = @_;
  die "Target directory is a file" if $self->target->is_file;
  $current = $self;
  $self->target->mkpath unless $self->target->exists;
  $self->installer_dir->mkpath unless $self->installer_dir->exists;
  $self->src_dir->mkpath unless $self->src_dir->exists;
  $self->log_io->print(("#" x 80)."\nStarting new log ".(time)."\n".("#" x 80)."\n\n");
  $self->meta->{last_run} = time;
  $self->meta->{preinstall_ENV} = \%ENV;
  $self->setup_env;
  $self->installer_code->($self);
  $self->write_export;
  $self->log_print("Done");
  %ENV = %{$self->meta->{preinstall_ENV}};
  delete $self->meta->{preinstall_ENV};
  $current = undef;
}

1;