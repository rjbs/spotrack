use v5.20.0;
package Spudge::CLI::Activity::Main;

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

use Safe::Isa;
use Spudge::Util;
use URI;

has client => (
  is      => 'ro',
  lazy    => 1,
  default => sub { $_[0]->app->appcmd->app->spudge->client },
  handles => [ qw( api_get api_put encode_json decode_json ) ],
);

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
    my @devices = $self->client->devices;
    Spudge::Util->print_devices(\@devices);
  },
);

has _last_search     => (is => 'rw');
has _last_search_raw => (is => 'rw');

command 'search' => (
  aliases => [ '/' ],
  help    => {
    summary => 'search for anything',
    text    => <<'END',
Use double quotes to indicate words need to occur together, like "Roadhouse
Blues" to avoid matching "Blues at the Roadhouse".

Use "NOT" or a "-" prefix to exclude results.  "AND" and "+" also exist.

Key/value pairs, separated by a colon, can limit search by specific attributes.
For example, "album:rumours" or "artist:Mothersbaugh".

Valid attributes include:

    album   - the album name
    artist  - name of an artist on the result
    genre   - genre of music to search
    label   - name of the label releasing the music
    track   - name of a track being searched for
    year    - year or year range (X-Y) of the item
END
  },
  sub ($self, $cmd, $rest) {
    $self->_do_search($rest, [ qw( artist album track ) ]);
  },
);

for my $what (qw( art.ist alb.um tr.ack )) {
  my $dotless = $what =~ s/\.//gr;
  command $what => (
    help    => {
      summary => "search for ${dotless}s",
      text    => 'see "help search" for more on search options',
    },
    sub ($self, $cmd, $rest) {
      $self->_do_search($rest, [ $dotless ]);
    },
  );
}

sub _do_search ($self, $search, $types) {
  my $uri = URI->new("/search");
  $uri->query_form(
    q    => $search,
    type => join(q{,}, @$types),
  );

  my $res  = $self->api_get($uri);

  require Spudge::AO::SearchResult;
  require Spudge::AO::Page;
  require Spudge::AO::Album;
  require Spudge::AO::Artist;
  require Spudge::AO::Track;

  my $data = $self->client->decode_json($res->decoded_content);
  my $result = Spudge::AO::SearchResult->from_hashref({
    $data->%{ qw(albums artists tracks) },
  });

  $self->_last_search_raw($data);
  $self->_last_search($result);

  if (my @albums = $result->albums->items) {
    say colored('ping', "[Albums]");
    my $i = 0;
    for my $album (@albums) {
      printf "% 3s. %s\n", ('r' . ++$i), $album->name;
    }
    say q{};
  }

  if (my @artists = $result->artists->items) {
    say colored('ping', "[Artists]");
    my $i = 0;
    for my $artist (@artists) {
      printf "% 3s. %s\n", ('a' . ++$i), $artist->name;
    }

    say q{};
  }

  if (my @tracks = $result->tracks->items) {
    say colored('ping', "[Tracks]");
    my $i = 0;
    for my $track (@tracks) {
      printf "% 3s. %s\n", ('t' . ++$i), $track->name;
    }
  }
}

command 'json' => (
  help => {
    summary => 'pipe JSON of search results to pager',
  },
  sub ($self, $cmd, $rest) {
    cmderr "You don't have any search results!"  unless $self->_last_search_raw;
    my $json = JSON::MaybeXS->new->pretty->canonical->encode($self->_last_search_raw);
    open my $pager, "|-", "less", "-M";
    print $pager $json;
  },
);

command 'dump' => (
  help => {
    summary => 'pipe dumper of search results to pager',
  },
  sub ($self, $cmd, $rest) {
    cmderr "You don't have any search results!"  unless $self->_last_search;
    require Data::Dumper::Concise;
    my $dump = Data::Dumper::Concise::Dumper($self->_last_search);
    open my $pager, "|-", "less", "-M";
    print $pager $dump;
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

    my @items = $self->_last_search->$key->items;
    my $item  = $items[ $which - 1 ];

    cmderr "I don't think that was a valid selector." unless $item;

    my $to_play = $item->$_isa('Spudge::AO::Track')
      ? {
          context_uri => $item->album->uri,
          offset      => { position => $item->track_number - 1 },
        }
      : { context_uri => $item->uri };

    my $res = $self->api_put(
      "/me/player/play",
      'Content-Type'  => 'application/json',
      Content => $self->encode_json($to_play),
    );

    cmderr "I couldn't play that, I guess.  Sorry?" unless $res->is_success;

    say "Now playing " . $self->_summarize($item) . ".";
  }
);

command 'recent' => (
  help => {
    summary => 'show your recently played tracks',
  },
  sub ($self, $cmd, $rest) {
    my $res = $self->api_get(
      '/me/player/recently-played',
    );

    my $data = $self->decode_json($res->decoded_content);

    if ($data->{items}->@*) {
      say colored('ping', "[Tracks]");
      my $i = 0;
      for my $track (map {; $_->{track} } $data->{items}->@*) {
        printf "% 3s. %s\n", ('t' . ++$i), $track->{name};
      }
    }
  },
);

command 'top' => (
  help => {
    summary => 'show your top tracks',
  },
  sub ($self, $cmd, $rest) {
    my $res = $self->api_get(
      '/me/top/tracks?time_range=short_term',
    );

    my $data = $self->decode_json($res->decoded_content);

    if ($data->{items}->@*) {
      say colored('ping', "[Tracks]");
      my $i = 0;
      for my $track ($data->{items}->@*) {
        printf "% 3s. %s\n", ('t' . ++$i), $track->{name};
      }
    }
  },
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
