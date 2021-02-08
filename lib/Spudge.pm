package Spudge;
use v5.20.0;
use warnings;

use File::HomeDir;
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

  state $JSON = JSON->new;

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

1;
