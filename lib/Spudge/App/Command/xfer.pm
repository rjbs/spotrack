use 5.20.0;
use warnings;
package Spudge::App::Command::xfer;

use Spudge::App -command;

use utf8;

use experimental qw(postderef signatures);

use Term::ANSIColor;

sub abstract { 'switch playback from one device to another' }

sub opt_spec {
  return (
    [ 'to-device|to|V=s', 'specify a device to transfer to', { required => 1 } ],
  );
}

sub execute ($self, $opt, $args) {
  my $device = $self->app->find_device($opt->to_device) if $opt->to_device;

  my $res = $self->app->spotify_put(
    "/me/player",
    'Content-Type'  => 'application/json',
    Content => $self->app->encode_json({
      device_ids => [ $device->{id} ],
    })
  );

  die $self->_error_from_res($res) . "\n" unless $res->is_success;

  say "Playback transferred to $device->{name}."
}

1;
