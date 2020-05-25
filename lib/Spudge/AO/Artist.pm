use v5.20.0;
use warnings;
package Spudge::AO::Artist;

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

sub from_struct ($class, $struct) {
  $class->new({
    name    => $struct->{name},
    uri     => $struct->{uri},
  });
}

no Moose;
1;
