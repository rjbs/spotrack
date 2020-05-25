use v5.20.0;
use warnings;
package Spudge::AO::SearchResult;

use Moose;

use experimental qw(postderef signatures);

has albums => (
  is => 'ro',
  required  => 1,
);

has artists => (
  is => 'ro',
  required  => 1,
);

has playlists => (
  is => 'ro',
  required  => 1,
);

has tracks => (
  is => 'ro',
  required  => 1,
);

sub from_struct ($class, $struct) {
  $class->new({
    albums    => Spudge::AO::Page->from_struct($struct->{albums}),
    artists   => Spudge::AO::Page->from_struct($struct->{artists}),
    playlists => Spudge::AO::Page->from_struct($struct->{playlists}),
    tracks    => Spudge::AO::Page->from_struct($struct->{tracks}),
  });
}

no Moose;
1;
