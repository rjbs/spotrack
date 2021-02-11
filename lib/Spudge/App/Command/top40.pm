use 5.20.0;
use warnings;
package Spudge::App::Command::top40;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Term::ANSIColor;

sub abstract { 'show the top 40 chart' }

sub opt_spec {
  return (
    [ 'for=s',    "whose top tracks are you getting? defaults to \$USER",
                  { default => $ENV{USER} } ],
    [ 'when=s',   "which month's snapshot to get (in yyyymm format)" ],
    [ 'range=s',  "what range to get: long, medium, short; default: medium",
                  { default => 'medium' } ],
  );
}

sub execute ($self, $opt, $args) {
  require Lingua::EN::Inflect;
  require Term::ANSIColor;

  my $Spudge  = Spudge->new;
  my $token   = $Spudge->access_token;

  my ($human_id) = $Spudge->dbi_connector->dbh->selectrow_array(
    q{SELECT id FROM humans WHERE name = ?},
    undef,
    $opt->for,
  );

  die "don't know user " . $opt->for . "\n" unless $human_id;

  my $snapshot_row;
  my $dbh = $Spudge->dbi_connector->dbh;

  if ($opt->when) {
    $snapshot_row = $dbh->selectrow_hashref(
      q{
        SELECT *
        FROM top_tracks_snapshots
        WHERE human_id = ? AND time_range = ? AND yyyymm = ?
      },
      undef,
      $human_id,
      $opt->range,
      $opt->when,
    );
  } else {
    $snapshot_row = $dbh->selectrow_hashref(
      q{
        SELECT *
        FROM top_tracks_snapshots
        WHERE human_id = ? AND time_range = ?
        ORDER BY yyyymm DESC
      },
      undef,
      $human_id,
      $opt->range . "_term",
    );
  }

  die "Couldn't find a snapshot!\n" unless $snapshot_row;

  my $tracks = $dbh->selectall_arrayref(
    q{
      SELECT *
      FROM top_tracks_snapshot_tracks
      WHERE snapshot_id = ?
      ORDER BY position
    },
    { Slice => {} },
    $snapshot_row->{id},
  );

  my $up    = Term::ANSIColor::colored([ 'ansi46'  ], q{↑});
  my $down  = Term::ANSIColor::colored([ 'ansi160' ], q{↓});
  my $same  = Term::ANSIColor::colored([ 'ansi102' ], q{→});
  my $new   = Term::ANSIColor::colored([ 'ansi226' ], q{⭑});

  RANGE: for my $track (@$tracks) {
    my $movement = ! defined $track->{last_position}            ? $new
                 : $track->{last_position} > $track->{position} ? $up
                 : $track->{last_position} < $track->{position} ? $down
                 :                                                $same;

    my ($artist, @rest) = split /; /, $track->{artist};

    printf "%s %2i. %s by %s%s\n",
      $movement,
      $track->{position},
      Term::ANSIColor::colored(['ansi229'], $track->{title}),
      Term::ANSIColor::colored(['ansi189'], @rest ? "$artist (&c.)" : $artist),
      ($track->{run_count} > 1
        ? (Lingua::EN::Inflect::ORD($track->{run_count}) . " week on the chart")
        : q{});
  }
}

1;
