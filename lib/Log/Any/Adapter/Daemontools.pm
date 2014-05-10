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
				my $self= shift;
				my $str= join(' ', map { !defined $_? '<undef>' : $_ } @_);
				$str =~ s/\n/\n$method: /g;
				print STDERR "$method: $str\n";
			}
			# Debug and trace logging
			: sub {
				return unless $level > $_[0]{filter};
				my $self= shift;
				my $str= join(' ', map { !defined $_? '<undef>' : !ref $_? $_ : $self->dumper->($_) } @_);
				$str =~ s/\n/\n$method: /g;
				print STDERR "$method: $str\n";
			};
		my $printfn=
			sub {
				return unless $level > $_[0]{filter};
				my ($self, $format, @args)= @_;
				my $str= sprintf $format, map { !defined $_? '<undef>' : !ref $_? $_ : $self->dumper->($_) } @args;
				$str =~ s/\n/\n$method: /g;
				print STDERR "$method: $str\n";
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

has filter => ( is => 'rw', default => sub { 0 }, coerce => \&_coerce_filter_level );
has dumper => ( is => 'rw', default => sub { \&_default_dumper } );

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