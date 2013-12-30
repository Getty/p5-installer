package Installer::Software;
# ABSTRACT: A software installation

use Moo;
use IO::All;
use IO::All::LWP;
use JSON_File;
use Path::Class;
use File::chdir;
use Archive::Extract;
use namespace::clean;

has target => (
  is => 'ro',
  required => 1,
);
sub log_print { shift->target->log_print(@_) }
sub run { shift->target->run(@_) }
sub target_directory { shift->target->target->stringify }
sub target_path { shift->target->target_path(@_) }
sub target_file { shift->target->target_file(@_) }

has archive_url => (
  is => 'ro',
  predicate => 1,
);

has archive => (
  is => 'ro',
  predicate => 1,
);

has export => (
  is => 'ro',
  predicate => 1,
);

has unset => (
  is => 'ro',
  predicate => 1,
);

for (qw( custom_configure custom_test post_install export_sh )) {
  has $_ => (
    is => 'ro',
    predicate => 1,
  );
}

for (qw( with enable disable without patch )) {
  has $_ => (
    is => 'ro',
    predicate => 1,
  );
}

has alias => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my ( $self ) = @_;
    if ($self->has_archive_url) {
      return (split('-',(split('/',io($self->archive_url)->uri->path))[-1]))[0];
    } elsif ($self->has_archive) {
      return (split('-',(split('/',$self->archive))[-1]))[0];
    }
    die "Can't produce an alias for this sofware";
  },
);

has meta => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my ( $self ) = @_;
    tie(my %meta,'JSON_File',file($self->target->installer_dir,$_[0]->alias.'.json')->stringify,, pretty => 1 );
    return \%meta;
  },
);

has testable => (
  is => 'ro',
  lazy => 1,
  default => sub { $_[0]->has_custom_test ? 1 : 0 },
);

sub installation {
  my ( $self ) = @_;
  $self->fetch;
  $self->unpack;
  $self->configure;
  $self->compile;
  $self->test if $self->testable;
  $self->install;
}

sub fetch {
  my ( $self ) = @_;
  return if defined $self->meta->{fetch};
  if ($self->has_archive_url) {
    my $sio = io($self->archive_url);
    my $filename = (split('/',$sio->uri->path))[-1];
    $self->log_print("Downloading ".$self->archive_url." as ".$filename." ...");
    my $full_filename = file($self->target->src_dir,$filename)->stringify;
    io($full_filename)->print(io($self->archive_url)->get->content);
    $self->meta->{fetch} = $full_filename;
  } elsif ($self->has_archive) {
    $self->meta->{fetch} = file($self->archive)->absolute->stringify;
  }
  die "Unable to get an archive for unpacking for this software" unless defined $self->meta->{fetch};
}
sub fetch_path { file(shift->meta->{fetch}) }

sub unpack {
  my ( $self ) = @_;
  return if defined $self->meta->{unpack};
  $self->log_print("Extracting ".$self->fetch_path." ...");
  my $archive = Archive::Extract->new( archive => $self->fetch_path );
  local $CWD = $self->target->src_dir;
  $archive->extract;
  for (@{$archive->files}) {
    $self->target->log($_);
  }
  my $src_path = dir($archive->extract_path)->absolute->stringify;
  $self->log_print("Extracted to ".$src_path." ...");
  if ($self->has_patch) {
    my @patches = ref $self->patch eq 'ARRAY'
      ? @{$self->patch}
      : $self->patch;
    for (@patches) {
      $self->target->patch_via_url($self->target->src_dir,$_,'-p0');
    }
  }
  $self->meta->{unpack} = $src_path;
}
sub unpack_path { dir(shift->meta->{unpack},@_) }
sub unpack_file { file(shift->meta->{unpack},@_) }

sub run_configure {
  my ( $self, @configure_args ) = @_;
  if ($self->has_with) {
    for my $key (keys %{$self->with}) {
      my $value = $self->with->{$key};
      if (defined $value && $value ne "") {
        push @configure_args, '--with-'.$key.'='.$value;
      } else {
        push @configure_args, '--with-'.$key;
      }
    }
  }
  for my $func (qw( enable disable without )) {
    my $has_func = 'has_'.$func;
    if ($self->$has_func) {
      for my $value (@{$self->$func}) {
        push @configure_args, '--'.$func.'-'.$value;
      }
    }
  }
  $self->run($self->unpack_path,'./configure','--prefix='.$self->target_directory,@configure_args);
}

sub configure {
  my ( $self ) = @_;
  return if defined $self->meta->{configure};
  $self->log_print("Configuring ".$self->unpack_path." ...");
  if ($self->has_custom_configure) {
    $self->custom_configure->($self);
  } else {
    if (-f $self->unpack_file('autogen.sh')) {
      $self->run($self->unpack_path,'./autogen.sh');
    }
    if (-f $self->unpack_file('configure')) {
      $self->run_configure;
    } elsif (-f $self->unpack_path('setup.py')) {
      # no configure
    } elsif ($self->unpack_file('Makefile.PL')) {
      $self->run($self->unpack_path,'perl','Makefile.PL');
    }
  }
  $self->meta->{configure} = 1;
}

sub compile {
  my ( $self ) = @_;
  return if defined $self->meta->{compile};
  $self->log_print("Compiling ".$self->unpack_path." ...");
  if (-f $self->unpack_file('setup.py') and !-f $self->unpack_file('configure')) {
    $self->run($self->unpack_path,'python','setup.py','build');
  } elsif (-f $self->unpack_file('Makefile')) {
    $self->run($self->unpack_path,'make');
  }
  $self->meta->{compile} = 1;
}

sub test {
  my ( $self ) = @_;
  return if defined $self->meta->{test};
  $self->log_print("Testing ".$self->unpack_path." ...");
  if ($self->has_custom_test) {
    $self->custom_test->($self);
  } else {
    if (-f $self->unpack_file('Makefile')) {
      $self->run($self->unpack_path,'make','test');
    }
  }
  $self->meta->{test} = 1;
}

sub install {
  my ( $self ) = @_;
  return if defined $self->meta->{install};
  $self->log_print("Installing ".$self->unpack_path." ...");
  if (-f $self->unpack_file('setup.py') and !-f $self->unpack_file('configure')) {
    $self->run($self->unpack_path,'python','setup.py','install');
  } elsif (-f $self->unpack_file('Makefile')) {
    $self->run($self->unpack_path,'make','install');
  }
  $self->meta->{install} = 1;
}

1;

=head1 DESCRIPTION

You should use this through the command L<installto>.

B<TOTALLY BETA, PLEASE TEST :D>

=head1 SUPPORT

IRC

  Join #cindustries on irc.quakenet.org. Highlight Getty for fast reaction :).

Repository

  http://github.com/Getty/p5-installer
  Pull request and additional contributors are welcome
 
Issue Tracker

  http://github.com/Getty/p5-installer/issues

=cut
