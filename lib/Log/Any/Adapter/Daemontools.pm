package Log::Any::Adapter::Daemontools;
use Moo 0.009009;
use warnings NONFATAL => 'all';
use Try::Tiny;
use Carp 'croak';
require Scalar::Util;
require Data::Dumper;

our $VERSION= '0.000001';

# ABSTRACT: Logging adapter suitable for use in a Daemontools-style logging chain

=head1 DESCRIPTION

This is a small simple module that writes logging messages to STDERR,
prefixing each line with an identifier like "error: ", "warning: ", etc.

For the Debug and Trace log levels, it additionally wraps the message
with an eval {}, and converts any non-scalar message parts into strings
using Data::Dumper or similar.  This allows debug messages to dump objects
without worry that the stringification would cause a fatal exception.

All other log levels are considered "important" such that you want the
exception if they fail, and arguments are converted to strings howver
they normally would if you tried printing them, on the assumption that
if you print an object in the course of normal logging then you probably
want the natural stringification for that type of object.

=cut

our %level_map;
BEGIN {
	%level_map= (
		trace    => -2,
		debug    => -1,
		info     =>  0,
		notice   =>  1,
		warning  =>  2,
		error    =>  3,
		critical =>  4,
		fatal    =>  4,
	);

	my $prev_level= 0;
	# We implement the stock methods, and also 'fatal' so that the
	# message written to the log starts with the proper level name.
	foreach my $method ( Log::Any->logging_methods(), 'fatal' ) {
		my $level= $prev_level= defined $level_map{$method}? $level_map{$method} : $prev_level;
		my $impl= ($level >= 0)
			# Standard logging
			? sub {
				return unless $level > $_[0]{filter};
				(shift)->write_msg($method, join(' ', map { !defined $_? '<undef>' : $_ } @_));
			}
			# Debug and trace logging
			: sub {
				return unless $level > $_[0]{filter};
				my $self= shift;
				eval { $self->write_msg($method, join(' ', map { !defined $_? '<undef>' : !ref $_? $_ : $self->dumper->($_) } @_)); };
			};
		my $printfn=
			sub {
				return unless $level > $_[0]{filter};
				my $self= shift;
				$self->write_msg($method, sprintf((shift), map { !defined $_? '<undef>' : !ref $_? $_ : $self->dumper->($_) } @_));
			};
		my $test= sub { $level > (shift)->{filter} };

		no strict 'refs';
		*{__PACKAGE__ . "::$method"}= $impl;
		*{__PACKAGE__ . "::${method}f"}= $printfn;
		*{__PACKAGE__ . "::is_$method"}= $test;
	}

	# Now create any alias that isn't handled
	my %aliases= Log::Any->log_level_aliases;
	for (keys %aliases) {
		next if __PACKAGE__->can($_);
		no strict 'refs';
		*{__PACKAGE__ . "::$_"}=    *{__PACKAGE__ . "::$aliases{$_}"};
		*{__PACKAGE__ . "::${_}f"}= *{__PACKAGE__ . "::$aliases{$_}f"};
		*{__PACKAGE__ . "::is_$_"}= *{__PACKAGE__ . "::is_$aliases{$_}"};
	}
}

=head1 ATTRIBUTES

=head2 filter

  use Log::Any::Adapter 'Daemontools', filter => 0;
  use Log::Any::Adapter 'Daemontools', filter => 'info';
  use Log::Any::Adapter "Daemontools', filter => 'debug';
  use Log::Any::Adapter "Daemontools', filter => "debug-$ENV{DEBUG}";

Messages equal to or less than the level of filter are suppressed.

filter may be an integer (0 is info, 1 is notice, -1 is debug, etc) or a level
name like 'info', 'debug', etc, or a level alias, the string 'none' or undef
which do not suppress anything, or a special notation of /debug-(\d+)/, where
a number will be subtracted from the debug level (this is useful for quickly
setting a log level from $ENV{DEBUG})

The default filter is 0, meaning 'info' and below are suppressed.

=head2 dumper

  use Log::Any::Adapter 'Daemontools', dumper => sub { ... };

Use a custom dumper function for converting perl data to strings.
The dumper is only used for the "*f()" formatting functions, and for log
levels 'debug' and 'trace'.  All normal logging will stringify the object
in the normal way.

=cut

has filter => ( is => 'rw', default => sub { 0 }, coerce => \&_coerce_filter_level );
has dumper => ( is => 'lazy', builder => sub { \&_default_dumper } );

=head1 METHODS

This logger has a method for all of the standard Log::Any methods (as of the
time this was written... I did not inherit from the Log::Any::Adapter::Core
base class)

=head2 write_msg

  $self->write_msg( $level_name, $message_string )

This is an internal method which all the other logging methods call.  You can
override it if you want to create a derived logger that handles line wrapping
differently, or write to a file handle other than STDERR.

=head2 _default_dumper

  _default_dumper( $value )

This is a function which dumps a value in a human readable format.  Currently
it uses Data::Dumper with a max depth of 4, but might change in the future.

This is the default value for the 'dumper' attribute.

=cut

sub write_msg {
	my ($self, $level_name, $str)= @_;
	$str =~ s/\n/\n$level_name: /g;
	print STDERR "$level_name: $str\n";
}

sub _default_dumper {
	my $val= shift;
	try {
		Data::Dumper->new([$val])->Indent(0)->Terse(1)->Useqq(1)->Quotekeys(0)->Maxdepth(4)->Sortkeys(1)->Dump;
	} catch {
		my $x= "$_";
		$x =~ s/\n//;
		substr($x, 50)= '...' if length $x >= 50;
		"<exception $x>";
	};
}

sub _coerce_filter_level {
	my $val= shift;
	return (!defined $val || $val eq 'none')? $level_map{trace}-1
		: Scalar::Util::looks_like_number($val)? $val
		: exists $level_map{$val}? $level_map{$val}
		: ($val =~ /^debug-(\d+)$/)? $level_map{debug} - $1
		: croak "unknown log level '$val'";
}

1;