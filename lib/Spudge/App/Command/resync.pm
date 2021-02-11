use 5.20.0;
use warnings;
package Spudge::App::Command::resync;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Spudge::Logger '$Logger';
use Try::Tiny;

sub abstract { 'synchronize data' }

sub _spudge ($self) {
  return $self->{spudge} //= Spudge->new;
}

sub _json {
  state $JSON = JSON::MaybeXS->new;
  return $JSON;
}

sub _ua ($self) {
  $self->{ua} //= LWP::UserAgent->new(keep_alive => 1);
}

sub _save_complete_history ($self) {
  my $token = $self->_spudge->access_token;

  $self->_spudge->txn(sub {
    my $dbh = $_;

    my $positions = $dbh->selectall_arrayref(
      q{SELECT * from history_positions},
      { Slice => {} },
    );

    die "?! you can't track more than one history at present"
      if @$positions > 1;

    for my $cursor (@$positions) {
      my $human_id = $cursor->{human_id};
      my $after_ms = $cursor->{next_cursor_start_ms};

      my $uri = "https://api.spotify.com/v1/me/player/recently-played?limit=50&after=$after_ms";
      my $res = $self->_ua->get($uri, 'Authorization' => "Bearer $token");

      unless ($res->is_success) {
        warn "failed to get myself from Spotify: " . $res->status_line . "\n";
        return;
      }

      my $playlist = $self->_json->decode($res->decoded_content);

      unless ($playlist->{items}->@*) {
        $Logger->log("no new items to record");
        return;
      }

      my $sth = $dbh->prepare(
        q{
          INSERT INTO complete_play_history
          (human_id, played_at, track_id, artist, album, title, context_uri)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        }
      );

      for my $item ($playlist->{items}->@*) {
        my $track = $item->{track};
        my $title = $track->{name};
        my $by    = join q{; }, map {; $_->{name} } $track->{artists}->@*;
        say "$title by $by";

        $sth->execute(
          $human_id,
          $item->{played_at},
          $track->{id},
          $by,
          q{}, # We need to fetch the track separately to get album name.
          $title,
          $item->{context}{uri} // q{}, # Bogus. -- rjbs, 2021-02-11
        );
      }

      $dbh->do(
        q{
          INSERT INTO history_positions (human_id, next_cursor_start_ms)
          VALUES (?, ?)
          ON CONFLICT(human_id) DO UPDATE SET next_cursor_start_ms = ?
        },
        undef,
        $human_id, ($playlist->{cursors}{after}) x 2
      );
    }
  });
}

sub _sync_playlist {
  my ($self, $playlist) = @_;

  my $dbh   = $self->_spudge->dbi_connector->dbh;
  my $ident = "$playlist->{name}/$playlist->{type} ($playlist->{id})";
  my $token = $self->_spudge->access_token;

  my ($stored_snapshots) = $dbh->selectall_arrayref(
    "SELECT * FROM playlist_snapshots WHERE playlist_id = ?",
    { Slice => {} },
    $playlist->{id},
  );

  $Logger->log_debug([
    "there are %s snapshots for %s",
    (0 + @$stored_snapshots),
    $ident,
  ]);

  if (@$stored_snapshots && not $playlist->{is_mutable}) {
    # Immutable playlist already has a snapshot.  Let's skip it.
    $Logger->log_debug([ "skipping saved and immutable playlist" ]);
    return;
  }

  # First, we fetch the current state of the playlist.  If we already have its
  # current snapshot id on file, then there's nothing to do.  Otherwise, we'll
  # cache it to the database. -- rjbs, 2021-02-09
  my $uri = "https://api.spotify.com/v1/playlists/$playlist->{id}";
  my $res = $self->_ua->get($uri, 'Authorization' => "Bearer $token");

  unless ($res->is_success) {
    $Logger->log([
      "could not retrieve %s from Spotify: %s",
      $playlist->{id},
      $res->status_line
    ]);
    return;
  }

  my $snapshot    = $self->_json->decode($res->decoded_content);
  my $snapshot_id = $snapshot->{snapshot_id};

  $Logger->log_debug([ "spotify snapshot is %s", $snapshot_id ]);

  # If we got a snapshot, then we have no work to do! -- rjbs, 2021-02-09
  if (grep { $_->{playlist_snapshot_id} eq $snapshot_id } @$stored_snapshots) {
    $Logger->log_debug("snapshot already stored (by snapshot id)");
    return;
  }

  my $track_list_digest = Digest::MD5::md5_hex(
    join q{ }, map {; $_->{track} ? $_->{track}{id} : q{-} } $snapshot->{tracks}{items}->@*
  );

  # If we got a snapshot, then we have no work to do! -- rjbs, 2021-02-09
  if (grep { $_->{track_list_digest} eq $track_list_digest } @$stored_snapshots) {
    $Logger->log_debug("snapshot already stored (by track list digest)");
    return;
  }

  my @tracks;

  $Logger->log("saving snapshot $snapshot_id ($track_list_digest)");

  $self->_spudge->txn(sub {
    my $dbh = $_;

    $dbh->do(
      "INSERT INTO playlist_snapshots
        (playlist_snapshot_id, playlist_id, snapshot_time, track_list_digest)
      VALUES (?, ?, ?, ?)",
      undef,
      $snapshot_id,
      $playlist->{id},
      $snapshot->{tracks}{items}[0]{added_at},
      $track_list_digest,
    );

    my $row_id = $dbh->sqlite_last_insert_rowid;

    my $sth = $dbh->prepare(
      "INSERT INTO playlist_snapshot_tracks
        (snapshot_id, position, track_id, artist, title)
      VALUES (?, ?, ?, ?, ?)",
    );

    my $position = 1;

    for my $i (0 .. $snapshot->{tracks}{items}->$#*) {
      my $item  = $snapshot->{tracks}{items}[$i];
      my $track = $item->{track};

      unless ($track && $track->{id}) {
        $Logger->log("skipping bizarro non-track item at index $i");
        next;
      }

      next if $track->{is_local}; # Should never happen, right?

      my $artists = join q{; }, map {; $_->{name} } @{ $track->{artists} };

      my $row = {
        snapshot_id => $row_id,
        position    => $position++,
        track_id    => $track->{id},
        artist      => $artists,
        title       => $track->{name},
      };

      push @tracks, $row;

      $sth->execute($row->@{qw( snapshot_id position track_id artist title )});
    }
  });

  return { map {; $_->{track_id} => $_ } @tracks };
}

sub _save_tracked_playlists ($self) {
  my $token   = $self->_spudge->access_token;
  my $dbh     = $self->_spudge->dbi_connector->dbh;

  my $playlists = $dbh->selectall_arrayref(
    "SELECT playlists.id, is_mutable, type, human_id, humans.name AS name
    FROM playlists
    JOIN humans ON humans.id = playlists.human_id
    WHERE is_active = 1
    ORDER BY name, type",
    { Slice => {} },
  );

  unless (@$playlists) {
    $Logger->log("no playlists to sync");
    return;
  }

  for my $playlist (@$playlists) {
    local $Logger = $Logger->proxy({
      proxy_prefix => "[$playlist->{name}/$playlist->{type}] ",
    });

    $self->_sync_playlist($playlist);
  }

  $Logger->log("Saved copies of everyone's playlists.  This is not creepy.");
}

sub _get_snapshot ($self, $human_id, $time_range, $yyyymm) {
  return $self->_spudge->dbi_connector->dbh->selectrow_hashref(
    q{
      SELECT *
      FROM top_tracks_snapshots
      WHERE human_id = ? AND time_range = ? AND yyyymm = ?
    },
    undef,
    $human_id,
    $time_range,
    $yyyymm,
  );
}

sub _save_top_tracks ($self) {
  my $token  = $self->_spudge->access_token;

  my $owner = $ENV{USER} // die "who are you?";

  my ($human_id) = $self->_spudge->dbi_connector->dbh->selectrow_array(
    q{SELECT id FROM humans WHERE name = ?},
    undef,
    $owner,
  );

  die "no user for supposed owner of this install" unless $human_id;

  my $now    = DateTime->now(time_zone => 'UTC');
  my $yyyymm = $now->format_cldr('YYYYMM');
  my $generated_at = $now->iso8601 . 'Z';

  RANGE: for my $time_range (qw( long_term medium_term short_term )) {
    try {
      $self->_spudge->txn(sub {
        my $dbh = $_;

        if ($self->_get_snapshot($human_id, $time_range, $yyyymm)) {
          $Logger->log("Already have top tracks for $yyyymm/$time_range");
          return;
        }

        my $prev_snapshot_id = $dbh->selectrow_hashref(
          q{SELECT *
          FROM top_tracks_snapshots
          WHERE human_id = ?
          ORDER BY yyyymm DESC
          LIMIT 1},
          undef,
          $human_id,
        );

        my %last_track_data;
        if ($prev_snapshot_id) {
          my $last_snapshot_tracks = $dbh->selectrow_hashref(
            q{SELECT * FROM top_tracks_snapshot_tracks WHERE snapshot_id = ?},
            undef,
            $prev_snapshot_id,
          );

          %last_track_data = %{ $last_snapshot_tracks // {} };
        }

        my $uri = "https://api.spotify.com/v1/me/top/tracks?limit=40&time_range=$time_range";
        my $res = $self->_ua->get($uri, 'Authorization' => "Bearer $token");

        unless ($res->is_success) {
          warn "failed to get top tracks from Spotify: " . $res->status_line . "\n";
          return;
        }

        my $playlist = $self->_json->decode($res->decoded_content);

        unless ($playlist->{items}->@*) {
          $Logger->log("no new items to record");
          return;
        }

        $dbh->do(
          q{
            INSERT INTO top_tracks_snapshots
            (human_id, yyyymm, time_range, generated_at)
            VALUES (?, ?, ?, ?)
          },
          undef,
          $human_id,
          $yyyymm,
          $time_range,
          $generated_at,
        );

        my $snapshot_id = $dbh->sqlite_last_insert_rowid;

        my $sth = $dbh->prepare(
          q{
            INSERT INTO top_tracks_snapshot_tracks
            (snapshot_id, position, track_id, artist, title, run_count, previous_position)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          },
        );

        for my $i (keys $playlist->{items}->@*) {
          my $track = $playlist->{items}->[$i];
          my $title = $track->{name};
          my $by    = join q{; }, map {; $_->{name} } $track->{artists}->@*;
          say "$title by $by";

          my $last_time = $last_track_data{ $track->{id} } // { run_count => 0 };

          $sth->execute(
            $snapshot_id,
            $i+1,
            $track->{id},
            $by,
            $title,
            $last_time->{run_count} + 1,
            $last_time->{position},
          );
        }
      });
    } catch {
      die $_;
    }
  }

}

sub execute ($self, $opt, $args) {
  require DateTime;
  require Digest::MD5;

  $self->_save_complete_history;
  $self->_save_tracked_playlists;
  $self->_save_top_tracks;
}

1;
