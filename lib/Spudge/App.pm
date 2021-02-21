use v5.20.0;
use warnings;
package Spudge::App;
# ABSTRACT: a Spotify control tool

use App::Cmd::Setup -app;

use experimental qw(signatures);

use Path::Tiny;
use Spudge;

sub spudge ($self) {
  $self->{spudge} //= Spudge->new;
}

sub pretty_json ($self, $data) {
  require JSON::MaybeXS;
  state $JSON = JSON::MaybeXS->new->pretty->canonical;
  $JSON->encode($data);
}

sub storage_dir ($self) {
  $self->spudge->root_dir;
}

sub sqlite_dbh ($self) {
  $self->spudge->dbi_connector->dbh; # XXX replace me -- rjbs, 2021-02-08
}

1;
