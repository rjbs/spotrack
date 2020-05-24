package Spudge::CLI::Activity::Main;
use v5.20.0;
use Moo;

with 'CliM8::Activity',
     'CliM8::Role::Readline';

use experimental qw(postderef signatures);
use utf8;

use CliM8::Util qw(
  cmderr
  cmdmissing
  cmdnext
  cmdlast

  matesay
  errsay
  okaysay

  colored
  colored_prompt
  prefixes
  prefix_re
);

use CliM8::Commando -setup => {
  help_sections => [
    { key => '',          title => 'The Basics' },
  ]
};

use CliM8::Commando::Completionist -all;

use Spudge::Util;
use URI;

sub get_input ($self, $prompt) {
  my $input = $self->readline->readline($prompt);

  return undef unless defined $input;

  $input = decode('utf-8', $input, Encode::FB_CROAK);

  $input =~ s/\A\s+//g;
  $input =~ s/\s+\z//g;

  return $input;
}

sub interact ($self) {
  say q{};

  my $prompt = colored_prompt(['ansi46'], 'spudge > ');

  my $input = $self->get_input($prompt);

  cmdlast unless defined $input;
  cmdnext unless length $input;

  my ($cmd, $rest) = split /\s+/, $input, 2;
  if (my $command = $self->commando->command_for($cmd)) {
    my $code = $command->{code};
    $self->$code($cmd, $rest);
    cmdnext;
  }

  cmderr("I don't know what you wanted to do!");

  return $self;
}

command 'q.uit' => (
  aliases => [ 'exit' ],
  help    => {
    summary => 'enough already, just quit',
  },
  sub { CliM8::LoopControl::Empty->new->throw },
);

command 'dev.ices' => (
  help    => {
    summary => 'list your available playback devices',
  },
  sub ($self, $cmd, $rest) {
		my @devices = $self->app->appcmd->app->devices;
    Spudge::Util->print_devices(\@devices);
	},
);

has _last_search => (
  is => 'rw',
);

command 'search' => (
  help    => {
    summary => 'list your available playback devices',
  },
  sub ($self, $cmd, $rest) {
    my $uri = URI->new("/search");
    $uri->query_form(
      q    => $rest,
      type => 'artist,album,track',
    );

    my $res  = $self->app->appcmd->app->spotify_get($uri);
    my $data = $self->app->appcmd->app->decode_json($res->decoded_content);

    $self->_last_search($data);

    say JSON::MaybeXS->new->pretty->canonical->encode($data);

    if ($data->{albums}{items}->@*) {
      say colored('ping', "[Albums]");
      my $i = 0;
      for my $album ($data->{albums}{items}->@*) {
        printf "% 3s. %s\n", ('r' . ++$i), $album->{name};
      }
      say q{};
    }

    if ($data->{artists}{items}->@*) {
      say colored('ping', "[Artists]");
      my $i = 0;
      for my $artist ($data->{artists}{items}->@*) {
        printf "% 3s. %s\n", ('a' . ++$i), $artist->{name};
      }

      say q{};
    }

    if ($data->{tracks}{items}->@*) {
      say colored('ping', "[Tracks]");
      my $i = 0;
      for my $track ($data->{tracks}{items}->@*) {
        printf "% 3s. %s\n", ('t' . ++$i), $track->{name};
      }
    }
	},
);

command 'play' => (
  help    => {
    summary => 'play something',
  },
  sub ($self, $cmd, $rest) {
    my ($type, $which) = $rest =~ /\A([art])([0-9]+)\z/;

    cmderr "You don't have any search results!"  unless $self->_last_search;
    cmderr "I don't know what you want to hear." unless $type;

    my $key = $type eq 'a' ? 'artists'
            : $type eq 'r' ? 'albums'
            : $type eq 't' ? 'tracks'
            : cmderr("I don't understand that selector.");

    my $item = $self->_last_search->{$key}{items}[ $which - 1 ];

    cmderr "I don't think that was a valid selector." unless $item;

    my $to_play = $item->{type} eq 'track'
      ? {
          context_uri => $item->{album}{uri},
          offset      => { position => $item->{track_number} - 1 },
        }
      : { context_uri => $item->{uri} };

    my $res = $self->app->appcmd->app->spotify_put(
      "/me/player/play",
      'Content-Type'  => 'application/json',
      Content => $self->app->appcmd->app->encode_json($to_play),
    );

    cmderr "I couldn't play that, I guess.  Sorry?" unless $res->is_success;

    say "Now playing " . $self->_summarize($item) . ".";
  }
);

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


no Moo;
1;