use 5.20.0;
use warnings;
package Spudge::App::Command::next;
use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use LWP::UserAgent;
use Term::ANSIColor;

sub execute ($self, $opt, $args) {
  my $res = $self->app->spotify_post('/me/player/next');
  die $self->_error_from_res($res) . "\n" unless $res->is_success;

  my $now_res = $self->app->spotify_get('/me/player');
  die $self->_error_from_res($now_res) . "\n" unless $now_res->is_success;

  my $now = $self->app->decode_json($now_res->decoded_content);

  my $playlist;
  if ($now->{context} && $now->{context}{type} eq 'playlist') {
    my $id = $now->{context}{uri} =~ s/\Aspotify:playlist://r;
    my $res = $self->app->spotify_get("/playlists/$id");
    $playlist = $self->app->decode_json($res->decoded_content);
  }

  printf "Now playing %s by %s%s.\n",
    colored(['bold', 'white'], $now->{item}{name}),
    _and_list(map {; colored(['bold', 'white'], $_->{name}) } $now->{item}{artists}->@*),
    ($playlist ? (" on " . colored(['bold','white'], $playlist->{name})) : '');
}

sub _and_list (@list) {
  Carp::cluck("too few elements") unless @list;
  return "" unless @list;

  return $list[0] if @list == 1;
  return join q{ and }, @list if @list == 2;

  $list[-1] = "and $list[-1]";
  return join q{, }, @list;
}

sub _error_from_res ($self, $res) {
  $self->app->decode_json($res->decoded_content)->{error}{message};
}

1;
