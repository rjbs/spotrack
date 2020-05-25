use v5.20.0;
use warnings;
package Spudge::AO::Track;

use Moose;

use experimental qw(postderef signatures);

has [ qw( name uri track_number ) ] => (
  is => 'ro',
  required => 1,
);

has album   => (
  is => 'ro',
  required => 1,
);

has artists => (
  handles  => { artists => 'elements' },
  traits   => [ 'Array' ],
  required => 1,
);

sub from_struct ($class, $struct) {
  $class->new({
    name    => $struct->{name},
    uri     => $struct->{uri},
    album   => Spudge::AO::Album->from_struct($struct->{album}),
    artists => [ map {; Spudge::AO::Artist->from_struct($_) } $struct->{artists}->@* ],
    track_number => $struct->{track_number},
  });
}

no Moose;
1;
