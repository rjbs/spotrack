use 5.20.0;
use warnings;
package Spudge::App::Command::trackplaylist;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Term::ANSIColor;

sub abstract { 'register a playlist to be tracked' }

sub command_names { qw(track-playlist track trackplaylist) }

sub opt_spec {
  return (
    [ 'human|h=s',  "who's the human who owns this list?",  { required => 1 } ],
    [ 'type|t=s',   "what type of playlists to add",        { required => 1 } ],
    [ 'id|i=s',     "the id of the playlist",               { required => 1 } ],
    [ 'immutable',  "the playlist will never change",                         ],
  );
}

sub execute ($self, $opt, $args) {
  my $Spudge = Spudge->new;
  my $dbh = $Spudge->dbi_connector->dbh;

  my ($human) = $dbh->selectrow_hashref(
    q{SELECT id FROM humans WHERE name = ?},
    undef,
    $opt->human,
  );

  die "Could find any record of the specified human\n" unless $human;
  die "You're trying to add a playlist for an inactive human\n" unless $human->{is_active};

  my $rows = $dbh->selectall_arrayref(
    "SELECT *
    FROM playlists
    WHERE (type = ? AND human_id = ?)
       OR (id = ?)",
    { Slice => {} },
    $opt->type,
    $opt->human,
    $opt->id,
  );

  die "Conflict! " . Dumper($rows) if @$rows;

  $dbh->do(
    "INSERT INTO playlists (id, human_id, type, generator, is_mutable)
    VALUES (?, ?, ?, ?)",
    undef,
    $opt->id,
    $human->{id},
    $opt->type,
    q{-},
    ($opt->is_immutable ? 0 : 1),
  );

  print "You are now tracking this person's playlist.  Weird.\n";
}

1;
