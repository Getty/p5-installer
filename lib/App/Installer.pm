package App::Installer;
# ABSTRACT: Application class for Installer

use Moo;
use Path::Class;
use IO::All;
use namespace::clean;

has target => (
  is => 'ro',
  required => 1,
);

has file => (
  is => 'ro',
  lazy => 1,
  default => sub { '.installer' },
);

has installer_code => (
  is => 'ro',
  predicate => 1,
);

has 'url' => (
  is => 'ro',
  predicate => 1,
);

has file_path => (
  is => 'ro',
  lazy => 1,
  default => sub { file($_[0]->file)->absolute->stringify },
);

sub install_to_target {
  my ( $self ) = @_;
  my $target = $self->target;
  $target = dir($target)->absolute->stringify;
  my $installer_code;
  if ($self->has_installer_code) {
    $installer_code = $self->installer_code;
  } elsif ($self->has_url) {
    $installer_code = io($self->url)->get->content;
  } else {
    $installer_code = io($self->file_path)->all;
  }
  my $target_class = 'App::Installer::Sandbox'.$$;

  my ( $err );
  {
    local $@;
    eval <<EVAL;
package $target_class;
no strict;
no warnings;
use Installer;

install_to '$target' => sub {
  $installer_code;
};

EVAL
    $err = $@;
  }

  if ($err) { die "$err" };

}

1;

=encoding utf8

=head1 DESCRIPTION

See L<installer> and for more information
