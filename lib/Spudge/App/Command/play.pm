use 5.20.0;
use warnings;
package Spudge::App::Command::play;
use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Term::ANSIColor;

sub abstract { 'find and play stuff' }

sub opt_spec {
  return (
    [ 'on-device|on|V=s', 'specify a device to play on' ],
  );
}

sub execute ($self, $opt, $args) {
  my $device = $self->app->find_device($opt->on_device) if $opt->on_device;

  my $result = $self->app->_stupid_search($args);

  die "didn't understand what to play\n" unless $result;

  my $res = $self->app->spotify_put(
    "/me/player/play"
      . ($device ? "?device_id=$device->{id}" : ''),
    'Content-Type'  => 'application/json',
    Content => $self->app->encode_json({
      $self->_thing_to_play_content($result)
    })
  );

  die $self->_error_from_res($res) . "\n" unless $res->is_success;

  say "Now playing " . $self->_summarize($result) . ".";
}

sub _thing_to_play_content ($self, $thing) {
  if ($thing->{type} eq 'track') {
    return (
      context_uri => $thing->{album}{uri},
      offset      => { position => $thing->{track_number} - 1 },
    )
  }

  return (context_uri => $thing->{uri});
}

sub _error_from_res ($self, $res) {
  $self->app->decode_json($res->decoded_content)->{error}{message};
}

sub _get_playlist ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:playlist://r;
  my $res = $self->app->spotify_get("/playlists/$id");
  $self->app->decode_json($res->decoded_content);
}

sub _get_album ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:album://r;
  my $res = $self->app->spotify_get("/albums/$id");
  $self->app->decode_json($res->decoded_content);
}

sub _get_track ($self, $uri) {
  my $id = $uri =~ s/\Aspotify:track://r;
  my $res = $self->app->spotify_get("/tracks/$id");
  $self->app->decode_json($res->decoded_content);
}

sub _and_list (@list) {
  Carp::cluck("too few elements") unless @list;
  return "" unless @list;

  return $list[0] if @list == 1;
  return join q{ and }, @list if @list == 2;

  $list[-1] = "and $list[-1]";
  return join q{, }, @list;
}

sub _summarize ($self, $thing) {
  return "a weird thing" unless $thing->{type};

  if ($thing->{type} eq 'track') {
    return sprintf "the track %s by %s %s on the album %s",
      colored(['bold', 'white'], $thing->{name}),
      ($thing->{artists}->@* > 1 ? "artists" : "artist"),
      _and_list(map {; colored(['bold', 'white'], $_->{name}) } $thing->{artists}->@*),
      colored(['bold','white'], $thing->{album}{name});
  }

  if ($thing->{type} eq 'album') {
    return sprintf "the album %s by %s",
      colored(['bold','white'], $thing->{name}),
      _and_list(map {; colored(['bold', 'white'], $_->{name}) } $thing->{artists}->@*);
  }

  if ($thing->{type} eq 'artist') {
    return sprintf "songs by %s",
      colored(['bold','white'], $thing->{name});
  }

  if ($thing->{type} eq 'playlist') {
    # We grep for defined because a track can be null if it has been deleted
    # from Spotify since being added to the playlist. -- rjbs, 2020-04-12
    my ($first) = grep {; defined } $thing->{tracks}{items}->@*;

    unless ($first) {
      return sprintf "the playlist %s",
        colored(['bold','white'], $thing->{name});
    }

    return sprintf "the playlist %s, starting with %s by %s",
      colored(['bold','white'], $thing->{name}),
      colored(['bold','white'], $first->{track}{name}),
      _and_list(map {; colored(['bold', 'white'], $_->{name}) } $first->{track}{artists}->@*);
  }

  return "a weird $thing->{type}";
}

1;
