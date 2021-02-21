use v5.20.0;
use warnings;
package Spudge::AO::SearchResult;

use Moose;

use experimental qw(postderef signatures);

has albums => (
  is => 'ro',
  required => 1,
);

has artists => (
  is => 'ro',
  required => 1,
);

has playlists => (
  is => 'ro',
  required => 1,
);

has tracks => (
  is => 'ro',
  required => 1,
);

sub from_hashref ($class, $hashref) {
  $class->new({
    map {;
      (($hashref->{$_} && $hashref->{$_}{items}->@* > 0)
        ? ($_ => Spudge::AO::Page->from_struct($hashref->{$_}))
        : ($_ => Spudge::AO::Page->from_struct({ items => [], total => 0 })))
    } qw( albums artists playlists tracks )
  });
}

no Moose;
1;
