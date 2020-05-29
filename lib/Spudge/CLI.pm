use v5.20.0;
use warnings;

package Spudge::CLI;

use Moo;

use experimental qw(postderef signatures);

with 'CliM8::App';

use JSON::MaybeXS;

use CliM8::Util qw(okaysay errsay);

sub name { 'spudge' }

my %ACTIVITY = (
  boot  => 'Spudge::CLI::Activity::Boot',
  main  => 'Spudge::CLI::Activity::Main',
);

has appcmd => (
  is => 'ro',
  requires => 1,
);

require Spudge::CLI::Activity::Boot;
require Spudge::CLI::Activity::Main;

sub activity ($self, $name, $arg = {}) {
  die "unknown activity $name" unless my $class = $ACTIVITY{ $name };

  return $class->new({
    %$arg,
    app => $self,
  });
}

1;
