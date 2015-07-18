package Log::Any::Adapter::Daemontools;
use strict;
use warnings;
use parent 'Log::Any::Adapter::Filtered';
use Carp 'croak';
require Scalar::Util;
require Data::Dumper;

our $VERSION= '0.003000';

# ABSTRACT: Logging adapter suitable for use in a Daemontools-style logging chain

=head1 DESCRIPTION

In the daemontools way of thinking, a daemon writes all its logging output
to STDOUT, which is a pipe to a logger process.  When writing all log info
to a pipe, you lose the log level information.  An elegantly simple way to
preserve this information is to prefix each line with "error:" or etc.

This is a small simple module that writes logging messages to STDOUT,
prefixing each line with an identifier like "error: ", "warning: ", etc.

For the Debug and Trace log levels, it additionally wraps the message
with an eval {}, and converts any non-scalar message parts into strings
using Data::Dumper or similar.  This allows debug messages to dump objects
without worry that the stringification would cause a fatal exception.

All other log levels are considered "important" such that you want the
exception if they fail, and arguments are converted to strings however
they normally would if you tried printing them, on the assumption that
if you print an object in the course of normal logging then you probably
want the natural stringification for that type of object.

=head1 ATTRIBUTES

=head2 filter

  use Log::Any::Adapter 'Daemontools', filter => 0;
  use Log::Any::Adapter 'Daemontools', filter => 'info';
  use Log::Any::Adapter 'Daemontools', filter => 'debug';
  use Log::Any::Adapter 'Daemontools', filter => "debug-$ENV{DEBUG}";

Messages equal to or less than the level of filter are suppressed.

The default filter is 0, meaning 'info' and below are suppressed.

filter may be:

=over 5

=item *

an integer (1 is notice, 0 is info, -1 is debug, etc)

=item *

a level name like 'info', 'debug', etc, or a level alias as documented
in Log::Any.

=item *

undef, or the string 'none', which do not suppress anything

=item *

a special notation matching /debug-(\d+)/, where a number will be
subtracted from the debug level

This is useful for quickly setting a log level from $ENV{DEBUG} using
the following code:

  use Log::Any::Adapter 'Daemontools', filter => "debug-".($ENV{DEBUG}||0);
  
so that DEBUG=1 causes debug to be shown, but not trace, and DEBUG=2
causes both debug and trace to show.

=back

=head2 dumper

  use Log::Any::Adapter 'Daemontools', dumper => sub { my $val=shift; ... };

Use a custom dumper function for converting perl data to strings.
The dumper is only used for the "*f()" formatting functions, and for log
levels 'debug' and 'trace'.  All normal logging will stringify the object
in the normal way.

=head2 category

Returns the name of the category of this logging object.

=head1 METHODS

This logger has a method for all of the standard logging methods.

=head2 new

  use Log::Any::Adapter 'Daemontools', filter => 'notice', dumper => sub { ... };
  
  Log::Any::Adapter->set('Daemontools', filter => 'notice', dumper => sub { ... });

Construct a new instance of the logger, in a variety of ways.  Accepted
paramters are currently 'filter' and 'dumper'.

=head2 write_msg

  $self->write_msg( $level_name, $message_string )

This is an internal method which all the other logging methods call.  You can
override it if you want to create a derived logger that handles line wrapping
differently, or write to a file handle other than STDOUT.

=cut

sub write_msg {
	my ($self, $level_name, $str)= @_;
	chomp $str;
	$str =~ s/^/$level_name: /mg unless $level_name eq 'info';
	print STDOUT $str, "\n";
}

=head1 LOGGING METHODS

This module has all the standard logging methods from L<Log::Any/LOG LEVELS>.

For regular logging functions (i.e. C<warn>, C<info>) the arguments are
stringified and concatenated.  Errors during stringify or printing are not
caught.

For printf-like logging functions (i.e. C<warnf>, C<infof>) reference
arguments are passed to C<$self-E<gt>dumper> before passing them to
sprintf.  Errors are not caught here either.

For any log level below C<info>, errors ARE caught with an C<eval> and printed
as a warning.
This is to prevent sloppy debugging code from ever crashing a production system.
Also, references are passed to C<$self-E<gt>dumper> even for the regular methods.

=head1 SEE ALSO

=head2 Process Supervision Tools

=over 15

=item Daemontools

The pioneer of the design:

L<http://cr.yp.to/daemontools.html>

=item Runit

A popular re-implementation of the same idea:

L<http://smarden.org/runit>

Also available as a busybox applet:

L<http://busybox.org>

=item Perp

A variation that uses a single process to supervise many jobs:

L<http://b0llix.net/perp/>

=item s6

Extreme minimalist supervisor with high level of attention to detail.

L<http://skarnet.org/software/s6/>

Also see discussion and comparison of tools at L<http://skarnet.org/software/s6/why.html>

=item Daemonproxy

Scriptable supervision tool that lets you easily build your own supervisor.

L<http://www.nrdvana.net/daemonproxy/>

=back

=head2 Useful Loggers

=over 15

=item Tinylog

Basic log-to-file with rotation built-in.

L<http://b0llix.net/perp/site.cgi?page=tinylog.8>

=item Sissylog

Log to syslog, using prefixes to determine log level

L<http://b0llix.net/perp/site.cgi?page=sissylog.8>

=item s6-log

Filter log messages into files by pattern, with many useful features.

L<http://skarnet.org/software/s6/s6-log.html>

=back

=cut

1;