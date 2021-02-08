use v5.20.0;
use warnings;
package Spudge::App;
# ABSTRACT: a Spotify control tool

use App::Cmd::Setup -app;

use experimental qw(signatures);

use Path::Tiny;
use Spudge;

sub decode_json ($self, $json) {
  require JSON::MaybeXS;
  state $JSON = JSON::MaybeXS->new->utf8;
  $JSON->decode($json);
}

sub encode_json ($self, $data) {
  require JSON::MaybeXS;
  state $JSON = JSON::MaybeXS->new->utf8;
  $JSON->encode($data);
}

sub pretty_json ($self, $data) {
  require JSON::MaybeXS;
  state $JSON = JSON::MaybeXS->new->pretty->canonical;
  $JSON->encode($data);
}

sub storage_dir ($self) {
  return $self->{storage_dir} //= Spudge->root_dir;
}

sub sqlite_dbh ($self) {
  Spudge->dbi_connector->dbh; # XXX replace me -- rjbs, 2021-02-08
}

sub bearer_token ($self) {
  return $self->{bearer_token} //= do {
    require OAuth::Lite2::Client::WebServer;

    my $config = $self->decode_json(
      $self->storage_dir->child("oauth.json")->slurp
    );

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
}

sub devices ($self) {
  my $res = $self->spotify_get('/me/player/devices');

  unless ($res->is_success) {
    warn "failed to get myself from Spotify: " . $res->status_line . "\n";
  }

  my @devices = $self->decode_json($res->decoded_content)->{devices}->@*;
}

sub find_device ($self, $str) {
  my (@devices) = grep {; index($_->{id}, $str) == 0 || fc $_->{name} eq fc $str }
                  $self->devices;

  die "No candidate device found!\n" unless @devices;
  die "Sorry, more than one device matched!\n" if @devices > 1;

  return $devices[0];
}

sub spotify_ua ($self) {
  return $self->{spotify_ua} //= do {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    $ua->default_header('Authorization' => "Bearer " . $self->bearer_token);
    $ua;
  };
}

my $BASE = "https://api.spotify.com/v1";

for my $method (qw(get put post delete)) {
  my $name = "spotify_$method";
  my $code = sub ($self, $uri, @rest) {
    $uri = "$BASE$uri" unless $uri =~ /\Ahttps:/;
    $self->spotify_ua->$method($uri, @rest);
  };

  no strict 'refs';
  *$name = $code;
}

sub _stupid_search ($self, $args) {
  if (@$args == 1 && $args->[0] =~ /\Aspotify:playlist:/) {
    return $self->_get_playlist($args->[0]);
  }

  if (@$args == 1 && $args->[0] =~ /\Aspotify:album:/) {
    return $self->_get_album($args->[0]);
  }

  if (@$args == 1 && $args->[0] =~ /\Aspotify:track:/) {
    return $self->_get_track($args->[0]);
  }

  if ($args->[0] eq 'pl') {
    my $who   = $args->[1];
    my $which = $args->[2];

    my $row = $self->sqlite_dbh->selectrow_hashref(
      q{SELECT * FROM playlists WHERE human = ? AND type = ?},
      undef,
      $who,
      $which,
    );

    return $self->_get_playlist("spotify:playlist:$row->{id}");
  }

  if ($args->[0] =~ s{\A/}{}) {
    my $noun  = shift @$args;
    my $nouns = $noun . q{s};
    my $token = $self->bearer_token;

    my $uri = URI->new("/search");
    $uri->query_form(
      q    => "@$args",
      type => $noun || 'artist,album,track',
    );

    my $res = $self->spotify_get($uri);

    my $data = $self->decode_json($res->decoded_content);
    my $item = $data->{$nouns}{items}[0] // $data->{tracks}{items}[0];

    return $item;
  }

  return;
}

sub _get_playlist ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:playlist://r;
  my $res = $self->spotify_get("/playlists/$id");
  $self->decode_json($res->decoded_content);
}

sub _get_album ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:album://r;
  my $res = $self->spotify_get("/albums/$id");
  $self->decode_json($res->decoded_content);
}

sub _get_track ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:track://r;
  my $res = $self->spotify_get("/tracks/$id");
  $self->decode_json($res->decoded_content);
}

1;
