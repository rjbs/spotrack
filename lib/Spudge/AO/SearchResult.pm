use v5.20.0;
use warnings;
package Spudge::AO::SearchResult;

use Moose;

use experimental qw(postderef signatures);

has albums => (
  is => 'ro',
  predicate => 'has_albums',
);

has artists => (
  is => 'ro',
  predicate => 'has_artists',
);

has playlists => (
  is => 'ro',
  predicate => 'has_playlists',
);

has tracks => (
  is => 'ro',
  predicate => 'has_tracks',
);

sub from_hashref ($class, $hashref) {
  $class->new({
    map {;
      (($hashref->{$_} && $hashref->{$_}{items}->@* > 0)
        ? ($_ => Spudge::AO::Page->from_struct($hashref->{$_}))
        : ())
    } qw( albums artists playlists tracks )
  });
}

no Moose;
1;
