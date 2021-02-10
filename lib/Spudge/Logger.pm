use v5.20;
use warnings;
package Spudge::Logger;

use parent 'Log::Dispatchouli::Global';

use Log::Dispatchouli 2.019; # ->enable_std{err,out}

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

# sub default_logger_class { 'Spudge::Logger::_Logger' }

sub default_logger_args {
  return {
    ident     => "spudge",
    to_stdout => 1, # $_[0]->default_logger_class->env_value('STDERR') ? 1 : 0,
    log_pid   => 0,
  }
}

1;
