use 5.20.0;
use warnings;
package Spudge::App::Command::initdb;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Term::ANSIColor;

sub abstract { 'initialize a fresh database' }

sub command_names { qw(init-db initdb) }

sub execute ($self, $opt, $args) {
  my $Spudge = Spudge->new;
  my $dbh = $Spudge->create_db_and_return_handle;

  my @statements = (
    q{
      CREATE TABLE humans (
        id integer PRIMARY KEY,
        name text NOT NULL,
        is_active BOOLEAN NOT NULL DEFAULT 1
      );
    },
    q{
      CREATE TABLE human_tags (
        human_id integer PRIMARY KEY,
        tag text NOT NULL,
        UNIQUE(human_id, tag)
      );
    },
    q{
      CREATE TABLE playlists (
        id text PRIMARY KEY,
        human_id integer NOT NULL REFERENCES humans (id),
        type text NOT NULL,
        generator text NOT NULL,
        is_mutable integer NOT NULL,
        UNIQUE(human_id, type)
      );
    },
    q{
      CREATE TABLE playlist_snapshots (
        id integer PRIMARY KEY,
        playlist_snapshot_id text NOT NULL UNIQUE,
        playlist_id text NOT NULL REFERENCES playlists (id),
        snapshot_time text NOT NULL,
        track_list_digest text, /* should be not null */
      );
    },
    q{
      CREATE TABLE playlist_snapshot_tracks (
        snapshot_id integer NOT NULL REFERENCES playlist_snapshots (id),
        position integer NOT NULL,
        track_id text NOT NULL,
        artist text NOT NULL,
        title text NOT NULL,
        UNIQUE(snapshot_id, position)
      );
    },
    q{
      CREATE TABLE complete_play_history (
        history_id PRIMARY KEY,
        human_id integer NOT NULL REFERENCES humans (id),
        played_at text NOT NULL,
        track_id text NOT NULL,
        artist text NOT NULL,
        album text NOT NULL,
        title text NOT NULL,
        context_uri text NOT NULL
      );
    },
    q{
      CREATE TABLE history_positions (
        human_id integer NOT NULL REFERENCES humans (id),
        next_cursor_start_ms integer NOT NULL,
        UNIQUE(human_id)
      );
    },
    q{
      CREATE TABLE top_tracks_snapshots (
        id integer PRIMARY KEY,
        human_id integer NOT NULL REFERENCES humans (id),
        yyyymm text NOT NULL,
        time_range text NOT NULL,
        generated_at text NOT NULL,
        UNIQUE(human_id, yyyymm, time_range)
      );
    },
    q{
      CREATE TABLE top_tracks_snapshot_tracks (
        snapshot_id integer NOT NULL REFERENCES top_tracks_snapshots (id),
        position integer NOT NULL,
        track_id text NOT NULL,
        artist text NOT NULL,
        title text NOT NULL,
        run_count integer NOT NULL,
        previous_position integer,
        UNIQUE(snapshot_id, position)
      );
    },
    q{
      CREATE TABLE tracks (
        track_id text PRIMARY KEY,
        title text NOT NULL,
        artist text NOT NULL,
        album text NOT NULL
      );
    },
  );

  $dbh->do($_) for @statements;
}

1;
