package Spudge;
use Moose;

use v5.20.0;
use experimental qw(signatures);

use DBIx::Connector;
use File::HomeDir;
use JSON::MaybeXS ();
use OAuth::Lite2;
use OAuth::Lite2::Client::WebServer;
use Path::Tiny ();

use Spudge::Client;

state $JSON = JSON::MaybeXS->new;

has root_dir => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $root = $ENV{SPOTRACK_CONFIG_DIR}
             ? Path::Tiny::path($ENV{SPOTRACK_CONFIG_DIR})
             : Path::Tiny::path( File::HomeDir->my_home )->child(".spotrack");

    die "config root $root does not exist\n"     unless -e $root;
    die "config root $root is not a directory\n" unless -d $root;

    return $root;
  },
);

has client => (
  is => 'ro',
  lazy => 1,
  default => sub ($self, @) {
    my $root = $self->root_dir;

    my $config = $JSON->decode( $root->child("oauth.json")->slurp );

    return Spudge::Client->new({
      client_id     => $config->{id},
      client_secret => $config->{secret},
      refresh_token => $config->{refresh},
    });
  },
);

sub db_path {
  my ($self) = @_;

  my $db_path = $self->root_dir->child("spotrack.sqlite");
}

sub _mk_connector {
  my ($self) = @_;

  my $db_path = $self->root_dir->child("spotrack.sqlite");

  return DBIx::Connector->new(
    "dbi:SQLite:dbname=$db_path",
    undef,
    undef,
    {
      sqlite_unicode => 1,
      RaiseError => 1,
    }
  );
}

sub create_db_and_return_handle {
  my ($self) = @_;

  my $db_path = $self->root_dir->child("spotrack.sqlite");

  die "database already exists: $db_path\n" if -e $db_path;

  $self->_mk_connector->dbh;
}

has dbi_connector => (
  is => 'ro',
  lazy => 1,
  default => sub ($self, @) {
    my $db_path = $self->root_dir->child("spotrack.sqlite");
    die "no $db_path\n" unless -e $db_path;

    return $self->_mk_connector;
  }
);

sub txn {
  $_[0]->dbi_connector->txn(ping => $_[1]);
}

1;
