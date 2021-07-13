use 5.20.0;
use warnings;
package Spudge::App::Command::addhuman;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

sub abstract { 'register a human we might reference' }

sub command_names { qw(add-human addhuman) }

sub opt_spec {
  return (
    [ 'human|h=s',  "who's the human we're adding?",  { required => 1 } ],
    [ 'tag|T=s@',   "tags for the user",                                ],
  );
}

sub execute ($self, $opt, $args) {
  my $Spudge = Spudge->new;
  my $dbh = $Spudge->dbi_connector->dbh;

  $dbh->do(
    q{INSERT INTO humans (name) VALUES (?)},
    undef,
    $opt->human,
  ) || die "can't insert human: " . $dbh->errstr;

  my $human_id = $dbh->sqlite_last_insert_rowid;

  for my $tag (($opt->tag // [])->@*) {
    $dbh->do(
      q{INSERT INTO human_tags (human_id, tag) VALUES (?, ?)},
      undef,
      $human_id,
      $tag,
    ) || warn "can't insert tag $tag: " . $dbh->errstr;
  }

  print "You created a new human.  Congratulations!\n";
}

1;
