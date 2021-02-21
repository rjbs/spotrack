package Spudge::Client;
# ABSTRACT: a Spotify web client, I guess?

use v5.20.0;
use Moose;
use experimental qw(signatures);

use LWP::UserAgent;
use OAuth::Lite2::Client::WebServer;

has [ qw( client_id client_secret refresh_token ) ] => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

has access_token => (
  is    => 'ro',
  lazy  => 1,
  init_arg  => undef,
  default   => sub ($self, @) {
    my $id      = $self->client_id;
    my $secret  = $self->client_secret;
    my $refresh = $self->refresh_token;

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

has _json_codec => (
  is    => 'ro',
  lazy  => 1,
  default => sub {
    require JSON::MaybeXS;
    return JSON::MaybeXS->new->utf8;
  },
  handles => {
    encode_json => 'encode',
    decode_json => 'decode',
  },
);

has _lwp => (
  is    => 'ro',
  lazy  => 1,
  default => sub {
    my ($self) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->default_header('Authorization' => "Bearer " . $self->access_token);
    $ua;
  },
);

has base_uri => (
  is  => 'ro',
  default => "https://api.spotify.com/v1",
);

for my $method (qw(get put post delete)) {
  my $name = "api_$method";
  my $code = sub ($self, $uri, @rest) {
    my $base = $self->base_uri;
    $uri = "$base$uri" unless $uri =~ /\A\Q$base/;
    $self->_lwp->$method($uri, @rest);
  };

  no strict 'refs';
  *$name = $code;
}

sub devices ($self) {
  my $res = $self->api_get('/me/player/devices');

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

  if ($args->[0] =~ s{\A/}{}) {
    my $noun  = shift @$args;
    my $nouns = $noun . q{s};

    my $uri = URI->new("/search");
    $uri->query_form(
      q    => "@$args",
      type => $noun || 'artist,album,track',
    );

    my $res = $self->api_get($uri);

    my $data = $self->decode_json($res->decoded_content);
    my $item = $data->{$nouns}{items}[0] // $data->{tracks}{items}[0];

    return $item;
  }

  return;
}

sub _get_playlist ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:playlist://r;
  my $res = $self->api_get("/playlists/$id");
  $self->decode_json($res->decoded_content);
}

sub _get_album ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:album://r;
  my $res = $self->api_get("/albums/$id");
  $self->decode_json($res->decoded_content);
}

sub _get_track ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:track://r;
  my $res = $self->api_get("/tracks/$id");
  $self->decode_json($res->decoded_content);
}

1;
