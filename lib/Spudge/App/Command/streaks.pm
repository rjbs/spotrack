use 5.20.0;
use warnings;
package Spudge::App::Command::streaks;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use List::Util qw(uniq);
use Term::ANSIColor;

sub abstract { 'show track replay streaks' }

sub opt_spec {
  return (
    [ 'human|h=s',        "look for streaks in whose history"  ],
    [ 'date-prefix|d=s',  "limit to play times with this prefix (YYYY-MM etc)" ],
  );
}

sub execute ($self, $opt, $args) {
  my $Spudge  = Spudge->new;
  my $dbh     = $Spudge->dbi_connector->dbh;

  my ($human) = $dbh->selectrow_hashref(
    q{SELECT id, is_active FROM humans WHERE name = ?},
    undef,
    $opt->human,
  );

  die "Could find any record of the specified human\n" unless $human;

  my $prefix = $opt->date_prefix // '';

  my $track_sth = $dbh->prepare(
    q{
      SELECT *
      FROM complete_play_history
      WHERE human_id = ? AND substr(played_at, 1, ?) = ?
      ORDER BY played_at
    },
  );

  $track_sth->execute(
    $human->{id},
    length($prefix),
    $prefix,
  );

  my $max_streak_length = 0;
  my @streaks;

  while (my $row = $track_sth->fetchrow_hashref) {
    if (@streaks && $streaks[-1]{track_id} eq $row->{track_id}) {
      $streaks[-1]{count}++;
      $streaks[-1]{end} = $row->{played_at};
    } else {
      push @streaks, {
        count => 1,
        $row->%{ qw( track_id artist title album ) },
        start => $row->{played_at},
        end   => $row->{played_at},
      };
    }
  }

  my @lengths = grep {; $_ > 1 }
                sort { $b <=> $a }
                uniq map {; $_->{count} } @streaks;

  for my $length (grep {; defined } @lengths[ 0 .. 4 ]) {
    say "Streaks with a run length of $length:";
    for my $streak (grep {; $_->{count} == $length } @streaks) {
      say "  * $streak->{title} by $streak->{artist}";
    }
  }
}

1;
