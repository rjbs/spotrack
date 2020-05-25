use v5.20.0;
use warnings;
package Spudge::AO::Page;

use Moose;

use experimental qw(postderef signatures);

has items => (
  handles  => { items => 'elements' },
  traits   => [ 'Array' ],
  required => 1,
);

has total => (
  is => 'ro',
  required => 1,
);

my %CLASS_FOR = (
  album   => 'Spudge::AO::Album',
  artist  => 'Spudge::AO::Artist',
  track   => 'Spudge::AO::Track',
);

sub from_struct ($class, $struct) {
  my $total = $struct->{total};
  my @items = map {
    my $class = $CLASS_FOR{$_->{type}};
    $class ? $class->from_struct($_) : $_;
  } $struct->{items}->@*;

  $class->new({
    total => $total,
    items => \@items,
  });
}

no Moose;
1;
