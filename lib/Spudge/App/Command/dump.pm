use 5.20.0;
use warnings;
package Spudge::App::Command::dump;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Spudge::Logger '$Logger';
use Term::ANSIColor;

sub abstract { 'fetch and dump an API object' }

sub usage_desc {
  'spudge dump %o { playlist } ID',
}

sub validate_args ($self, $opt, $args) {
  $self->usage_error("Invalid argument count") unless @$args == 2;

  $self->usage_error("Unhandled object type") unless $args->[0] eq 'playlist';
}

sub execute ($self, $opt, $args) {
  my $method = "_fetch_$args->[0]";

  die "Something very strange happened.\n" unless $self->can($method);

  $self->$method($opt, $args);
}

sub _fetch_playlist ($self, $opt, $args) {
  my $ua    = LWP::UserAgent->new(keep_alive => 1);
  my $token = Spudge->new->access_token;
  my $uri   = "https://api.spotify.com/v1/playlists/$args->[1]";
  my $res   = $ua->get($uri, 'Authorization' => "Bearer $token");

  unless ($res->is_success) {
    $Logger->log([
      "could not retrieve %s %s from Spotify: %s",
      $args->[0],
      $args->[1],
      $res->status_line
    ]);
    exit 1;
  }

  my $JSON = JSON::MaybeXS->new;

  my $playlist = $JSON->decode($res->decoded_content);
  print $JSON->canonical->pretty->encode($playlist);
}

1;
