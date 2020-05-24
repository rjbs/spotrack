use 5.20.0;
use warnings;
package Spudge::App::Command::cli;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use CliM8::HTTP;
use CliM8::Util qw( activityloop matesay );
use Term::ANSIColor;

sub abstract { "a CLI for Spotify" }

sub opt_spec {
  return (
    [ 'offline',    "offline, totally fake, does not work mode" ],
  );
}

sub execute ($self, $opt, $args) {
  require Spudge::CLI;
  require Term::ReadLine;
  require Term::ReadLine::Gnu;

  my $cli = Spudge::CLI->new({ appcmd => $self });

  activityloop($cli->activity(boot => { opts => $opt }));

  say q{};
  matesay("Onya, buddy, you're all done!  Catch you later!");
}

1;
