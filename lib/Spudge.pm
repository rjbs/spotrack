package Spudge;
use v5.20.0;
use warnings;

use DBIx::Connector;
use File::HomeDir;
use JSON::MaybeXS ();
use OAuth::Lite2;
use OAuth::Lite2::Client::WebServer;
use Path::Tiny ();

sub root_dir {
  state $root;

  return $root if $root;

  $root = $ENV{SPOTRACK_CONFIG_DIR}
        ? Path::Tiny::path($ENV{SPOTRACK_CONFIG_DIR})
        : Path::Tiny::path( File::HomeDir->my_home )->child(".spotrack");

  die "config root $root does not exist\n"     unless -e $root;
  die "config root $root is not a directory\n" unless -d $root;

  return $root;
}

sub get_access_token {
  my $root = $_[0]->root_dir;

  state $JSON = JSON::MaybeXS->new;

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
  my $token = $token_obj->access_token;
}

sub db_path {
  my ($class) = @_;

  my $db_path = $class->root_dir->child("spotrack.sqlite");
}

sub _mk_connector {
  my ($class) = @_;

  my $db_path = $class->root_dir->child("spotrack.sqlite");

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
  my ($class) = @_;

  my $db_path = $class->root_dir->child("spotrack.sqlite");

  die "database already exists: $db_path\n" if -e $db_path;

  $class->_mk_connector->dbh;
}

sub dbi_connector {
  my ($class) = @_;

  state $connector;
  return $connector if $connector;

  my $db_path = $class->root_dir->child("spotrack.sqlite");
  die "no $db_path\n" unless -e $db_path;

  $connector = $class->_mk_connector;
}

sub txn {
  $_[0]->dbi_connector->txn(ping => $_[1]);
}

1;
