use v5.20.0;
use warnings;

package Spudge::CLI;

use Moo;

use experimental qw(postderef signatures);

with 'Yakker::App';

use JSON::MaybeXS;

use Yakker::Util qw(okaysay errsay);

sub name { 'spudge' }

sub activity_class ($self, $name) {
  state %ACTIVITY = (
    boot  => 'Spudge::CLI::Activity::Boot',
    main  => 'Spudge::CLI::Activity::Main',
  );

  return $ACTIVITY{$name};
}

has appcmd => (
  is => 'ro',
  requires => 1,
);

require Spudge::CLI::Activity::Boot;
require Spudge::CLI::Activity::Main;

1;
