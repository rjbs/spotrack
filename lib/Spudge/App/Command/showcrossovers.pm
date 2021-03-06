use 5.20.0;
use warnings;
package Spudge::App::Command::showcrossovers;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Term::ANSIColor;

sub abstract { 'show crossovers between playlists' }

sub command_names { qw(show-crossovers showcrossovers xovers) }

sub opt_spec {
  return (
    [ 'type|t=s', "what type of playlists to compare", { default => 'discover' } ],
    [ 'tag|T=s',  "what type of humans to compare" ],
  );
}

sub _get_tracks {
  my ($self, $dbh, $playlist_id) = @_;

  my ($snapshot_row_id) = $dbh->selectrow_array(
    "SELECT id
    FROM playlist_snapshots
    WHERE playlist_id = ?
    ORDER BY snapshot_time DESC
    LIMIT 1",
    { Slice => {} },
    $playlist_id,
  );

  return {} unless $snapshot_row_id;

  # we have a snapshot!
  my $tracks_ref = $dbh->selectall_hashref(
    "SELECT * FROM playlist_snapshot_tracks WHERE snapshot_id = ?",
    'track_id',
    { Slice => {} },
    $snapshot_row_id,
  );

  return $tracks_ref;
}

sub execute ($self, $opt, $args) {
  my $Spudge  = Spudge->new;
  my $dbh     = $Spudge->dbi_connector->dbh;

  my $type   = $opt->type;

  my @bind = $opt->tag ? $opt->tag : ();
  my $sql  = $opt->tag
           ? "AND human_id IN (SELECT human_id FROM human_tags WHERE tag = ?)"
           : q{};

  my $playlists = $dbh->selectall_arrayref(
    qq{
      SELECT playlists.id, type, human_id, humans.name AS name
      FROM playlists
      JOIN humans ON playlists.human_id = humans.id
      WHERE type = ?
        AND is_active = 1
        $sql
    },
    { Slice => {} },
    $type,
    @bind,
  );

  die sprintf "no playlists of type %s\n", $type unless @$playlists;

  my %tracks_for;
  for my $playlist (@$playlists) {
    $tracks_for{"$playlist->{name}/$playlist->{type}"} = $self->_get_tracks($dbh, $playlist->{id});
  }

  my %on;
  my %track_label;
  for my $plkey (keys %tracks_for) {
    my $pl = $tracks_for{$plkey};

    for my $t (values %$pl) {
      $track_label{ $t->{track_id } } //= "$t->{title} ($t->{artist})";
      push $on{$t->{track_id}}->@*, $plkey;
    }
  }

  my @duped = grep {; $on{$_}->@* > 1 } keys %on;

  for my $tid (sort { $track_label{$a} cmp $track_label{$b} } @duped) {
    print "$track_label{$tid}\n";
    print "  * $_\n" for sort $on{$tid}->@*;
  }
}

1;
