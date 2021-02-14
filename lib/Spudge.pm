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

has access_token => (
  is => 'ro',
  lazy => 1,
  clearer => 'clear_access_token',
  default => sub ($self, @) {
    my $root = $self->root_dir;

    my $config = $JSON->decode( $root->child("oauth.json")->slurp );

    my $id      = $config->{id};
    my $secret  = $config->{secret};
    my $refresh = $config->{refresh};

    my $client = OAuth::Lite2::Client::WebServer->new(
      id               => $id,
      secret           => $secret,
      authorize_uri    => q{https://accounts.spotify.com/authorize},
      access_token_uri => q{https://accounts.spotify.com/api/token},
    );

    my $token_obj = $client->refresh_access_token(refresh_token => $refresh);

    unless ($token_obj) {
      Carp::confess("Couldn't refresh access token: " . $client->errstr);
    }

    return $token_obj->access_token;
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
