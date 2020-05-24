use 5.20.0;
use warnings;
package Spudge::Util;

use utf8;

use experimental qw(postderef signatures);

use Term::ANSIColor;

my %TYPE_EMOJI = (
  Computer    => "\N{PERSONAL COMPUTER}",
  Smartphone  => "\N{MOBILE PHONE}",
  Tablet      => "\N{CLIPBOARD}",
  unknown     => "\N{BLACK QUESTION MARK ORNAMENT}",
);

sub print_devices ($self, $devices) {
  unless (@$devices) {
    print "Sorry, you've got no devices available!  Try opening Spotify.";
  }

  for my $device (sort { fc $a->{name} cmp fc $b->{name} } @$devices) {
    printf "%s %s %s %s\n",
      colored(['bold', 'green'], ($device->{is_active} ? '⮕' : ' ')),
      ($TYPE_EMOJI{ $device->{type} } // $TYPE_EMOJI{unknown}),
      ( colored(['bold', 'black'], '[')
      . colored(['bold', 'green'], substr($device->{id}, 0, 6))
      . colored(['bold', 'black'], ']')
      ),
      colored(['bold', 'white'], $device->{name});
  }
}

1;
