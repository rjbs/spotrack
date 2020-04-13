use 5.20.0;
use warnings;
package Spudge::App::Command::get;
use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

sub execute ($self, $opt, $args) {
  my $result = $self->app->spotify_get($args->[0]);

  my $data = $self->app->decode_json($result->decoded_content);
  print $self->app->pretty_json($data);
}

1;
