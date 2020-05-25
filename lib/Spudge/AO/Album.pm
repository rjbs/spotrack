use v5.20.0;
use warnings;
package Spudge::AO::Album;

use Moose;

use experimental qw(postderef signatures);

has name => (
  is => 'ro',
  required => 1,
);

has uri => (
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
    artists => [ map {; Spudge::AO::Artist->from_struct($_) } $struct->{artists}->@* ],
  });
}

no Moo;
1;
