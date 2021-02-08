package Spudge;
use v5.20.0;
use warnings;

use Path::Tiny ();

sub root_dir {
  state $root;

  return $root if $root;

  $root = $ENV{SPOTRACK_CONFIG_DIR}
        ? Path::Tiny::path($ENV{SPOTRACK_CONFIG_DIR})
        : Path::Tiny::path( File::HomeDir->my_home )->child(".spotrack");

  die "config root $root does not exist\n"     unless -e $root;
  die "config root $root is not a directory\n" unless -d $root;

  return $root;
}

1;
