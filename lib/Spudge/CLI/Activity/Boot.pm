use v5.20.0;
package Spudge::CLI::Activity::Boot;

use Moo;
with 'CliM8::Activity';

use experimental qw(postderef signatures);
use utf8;

use CliM8::Util qw(
  matesay
  errsay
  okaysay
);

sub interact ($self) {
  my %initial_query;

  my $activity = $self->app->activity('main');

  CliM8::LoopControl::Swap->new({ activity => $activity })->throw;
}

no Moo;
1;
