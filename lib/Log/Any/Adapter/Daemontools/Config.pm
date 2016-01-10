package Log::Any::Adapter::Daemontools::Config;

# At top of file where lexical scope is the cleanest
sub _build_writer_eval_in_clean_scope {
	# Args: $self, $code, \$err
	local $@;
	my $output= $_[0]->output; # Needs to be in scope
	my $format= $_[0]->format; # of the eval
	my $coderef= eval $_[1];
	${ $_[2] }= $@ if defined $_[0]; # Save error because $@ is localized
	return $coderef;
}

use strict;
use warnings;
use Log::Any::Adapter::Util 'numeric_level', ':levels';
use Try::Tiny;
use Scalar::Util 'weaken', 'refaddr';

# Lazy-load carp, and also remove any Log::Any infrastructure from the trace
our @CARP_NOT= qw( Log::Any::Adapter::Base Log::Any::Adapter Log::Any::Proxy Log::Any );
sub _carp_exclude {
	my $i= 1;
	++$i while caller($i) =~ /^Log::Any/;
	return $i;
}
sub carp  { require Carp; local $Carp::CarpLevel= _carp_exclude; &Carp::carp; }
sub croak { require Carp; local $Carp::CarpLevel= _carp_exclude; &Carp::croak; }

=head1 ATTRIBUTES

=head2 log_level

  $config->log_level            # returns level name
  $config->log_level( 'info' ); # 'info'
  $config->log_level( 99 );     # 'trace' (clamped to max)
  $config->log_level( 3 );      # 'error'
  $config->log_level( '+= 1' ); # 'warning'
  $config->log_level( '-= 9' ); # 'emergency' (clamped to min)

Get or set the current log level.  Can be assigned with either a name
or a number, or "+= N" syntax.  (but use L<log_level_adjust> for that)
Returns the level name.

=head2 log_level_min

  # Our app should never have 'critical' squelched no matter how many '-q'
  # the user gives us
  $config->log_level_min('fatal');

Get or set the minimum allowed log level.
Log levels below the minimum are silently clamped.
Can be assigned either a name or number, or "+= N" syntax.
Returns the level name.

=head2 log_level_max

Get or set the maximum allowed log level.
Log levels above the maximum are silently clamped.
Can be assigned either a name or number, or "+= N" syntax.
Returns the level name.

=cut

my (%log_level_name, %log_level_num);
BEGIN {
	%log_level_num= (
		none => EMERGENCY-1,
		emergency => EMERGENCY,
		alert => ALERT,
		critical => CRITICAL,
		error => ERROR,
		warning => WARNING,
		notice => NOTICE,
		info => INFO,
		debug => DEBUG,
		trace => TRACE,
	);
	%log_level_name= reverse %log_level_num;
	
	# Add the aliases to the name-to-value mapping
	my %aliases= Log::Any::Adapter::Util::log_level_aliases();
	for (keys %aliases) {
		$log_level_num{$_}= $log_level_num{ $aliases{$_} };
	}
}

sub _parse_log_level {
	my ($spec, $base, $min, $max)= @_;
	my $lev= $spec =~ /^-?\d+$/?         $spec
		: $spec =~ /^([-+])= (-?\d+)$/?  $base + "${1}1" * $2
		: $log_level_num{$spec};
	defined $lev or croak "Invalid log level '$spec'";
	$min= EMERGENCY-1 unless defined $min;
	$lev= $min unless $lev >= $min;
	$max= TRACE unless defined $max;
	$lev= $max unless $lev <= $max;
	return $lev;
}

sub log_level {
	my $self= shift;
	if (@_) {
		croak "extra arguments" if @_ > 1;
		my $l= _parse_log_level($_[0], $self->{log_level_num}, $self->{log_level_min_num}, $self->{log_level_max_num});
		if ($l != $self->{log_level_num}) {
			$self->{log_level_num}= $l;
			$self->_reset_cached_adapters;
		}
	}
	$log_level_name{ $self->{log_level_num} };
}

sub log_level_min {
	my $self= shift;
	if (@_) {
		croak "extra arguments" if @_ > 1;
		$self->{log_level_min_num}= _parse_log_level($_[0], $self->{log_level_min_num}, EMERGENCY-1, $self->{log_level_max_num});
		if ($self->{log_level_min_num} > $self->{log_level_num}) {
			$self->{log_level_num}= $self->{log_level_min_num};
			$self->_reset_cached_adapters;
		}
	}
	$log_level_name{ $self->{log_level_min_num} };
}

sub log_level_max {
	my $self= shift;
	if (@_) {
		croak "extra arguments" if @_ > 1;
		$self->{log_level_max_num}= _parse_log_level($_[0], $self->{log_level_max_num}, $self->{log_level_min_num}, TRACE);
		if ($self->{log_level_max_num} < $self->{log_level_num}) {
			$self->{log_level_num}= $self->{log_level_max_num};
			$self->_reset_cached_adapters;
		}
	}
	$log_level_name{ $self->{log_level_max_num} };
}

=head2 output

This is the handle (or coderef) log messages are written to.  If it is a
handle (either a GLOB ref or class which can ->print) we call ->print on it.
If it is a coderef, we pass the same arguments that would be given to print.

If a message from Log::Any contains newlines, they are broken into separate
strings (but still ending with newline) so be ready to receive multiple
arguments.

(But if you set L<writer> to a custom coderef, this attribute is ignored
 completely)

The default is \*STDERR.

=cut

sub output {
	my $self= shift;
	if (@_) {
		croak "extra arguments" if @_ > 1;
		defined $_[0] && (ref $_[0] eq 'GLOB' || ref $_[0] eq 'CODE' || ref($_[0])->can('print'))
			or croak "Argument must be file handle or coderef";
		$self->{output}= $_[0];
		delete $self->{_writer_cache};
		$self->_reset_cached_adapters unless $self->{writer};
	}
	return defined $self->{output}? $self->{output} : \*STDOUT;
}

=head2 format

This attrbute determines how messages are formatted into text lines.  It is a
*string* of perl code (or a coderef) which executes within the following context:

  $output->print( map { eval $format } split /\n/, $message );

(But if you set L<writer> to a custom coderef, this attribute is ignored
 completely)

The following variables become available if seen in your string of code:

=over

=item $_

The line of message text

=item $category

The name of the Log::Any category the message came from

=item $level

The name of the log level

=item $level_prefix

The default behavior of "$level: " for all levels except info which is ''.

=item $file

The full filename from caller()

=item $file_brief

The filename from caller() minus the library path (best guess, no guarantees)

=item $line

The line number from caller()

=item $package

The package name from caller()

=back

The default is C<'"$level_prefix$_\n"'>

=cut

sub format {
	my $self= shift;
	if (@_) {
		@_ == 1 && defined $_[0] && (!ref $_[0] or ref $_[0] eq 'CODE')
			or croak "Expected string or coderef";
		if (!ref $_[0]) {
			# Test their supplied code right away, so the error happens in a
			# place where its easy to fix
			my $x= $self->_build_writer_eval_in_clean_scope(
				"sub { "
				.' my ($category, $level, $level_prefix, $file, $file_brief, $line, $package);'
				." $_[0]; "
				."}",
				\my $err
			);
			defined $x && ref $x eq 'CODE'
				or croak "Invalid format (make sure you wrote *code* that returns a string): $err";
		}
		$self->{format}= $_[0];
		delete $self->{_writer_cache};
		$self->_reset_cached_adapters unless $self->{writer};
	}
	defined $self->{format}? $self->{format} : '"$level_prefix$_\n"';
}

=head2 writer

If specified, this coderef overrides the routine that would have been built
from L<output> and L<format>.

Its arguments are:

  sub { my ($adapter, $level, $message)= @_; ... };

where $level is the level name, and adapter is an instance of
Log::Any::Adapter::Daemontools.  (and the adapter attributes you are probably
most interested in are 'category' and 'config').

=cut

sub writer {
	my $self= shift;
	if (@_) {
		@_ == 1 && (!defined $_[0] || ref $_[0] eq 'CODE')
			or croak "Expected coderef or undef";
		$self->{writer}= $_[0];
		$self->_reset_cached_adapters;
	}
}

=head1 METHODS

=head2 new

Constructor; accepts any of the attributes as arguments, as a hash or hashref.

=cut

# Yes, I should use Moo, but in the spirit of Log::Any having no non-core deps,
# I decided to do the same.
sub new {
	my $class= shift;
	my $self= bless {
		log_level_num => INFO,
		log_level_min_num => EMERGENCY-1,
		log_level_max_num => TRACE,
	}, $class;
	
	# Convert hashref to plain key/value list
	unshift @_, %{ shift @_ }
		if @_ == 1 && ref $_[0] eq 'HASH';
	
	# Iterate key/value pairs and call the accessor method for each
	while (@_) {
		my ($k, $v)= (shift, shift);
		$self->$k($v);
	}
	$self;
}

=head2 init

  $config->init( argv => 1, level => 'warn', format => '"$level: $_ ($category)"' )

Different from a constructor, this method takes a hashref of short aliases
and notations and calls various methods that might have effects outside of
this object.
The primary purpose is to provide convenient initialization of the global
logging configuration.  The following are provided:

=over

=item env

  env => $name_or_args

Convenient passthrough to L<process_env> method.

If env is a hashref, it is passed directly.  If it is a scalar, it is
interpreted as a pre-defined "profile" of arguments.

Profiles:

=over

=item 1

  { debug => 'DEBUG' }

=back

=item argv

  argv => $name_or_args

Convenient passthrough to L<process_argv>.

If argv is a hashref, it is passed directly.  If it is a scalar, it is
interpreted as a pre-defined "profile" of arguments.

Profiles:

=over

=item 1

=item "gnu"

  {
    bundle  => 1,
    verbose => qr/^(--verbose|-v)$/,
    quiet   => qr/^(--quiet|-q)$/,
    stop    => '--'
  }

=back

=item signals

  signals => [ $v, $q ],
  signals => { verbose => $v, quiet => $q },

Convenient passthrough to L<install_signal_handlers>.

If handle_signals is an arrayref of length 2, they are used as the verbose and
quiet parameters, respectively.  If it is a hashref, it is passed directly.

=item level

Sets L<log_level>

=item min

Sets L<log_level_min>

=item max

Sets L<log_level_max>

=item format

Sets L<format>

=item out

Sets L<output>

=item writer

Sets L<writer>

=cut

our (%env_profile, %argv_profile);
BEGIN {
	$env_profile{1}= { debug => 'DEBUG' };
	$argv_profile{1}= {
		bundle  => 1,
		verbose => qr/^(--verbose|-v)$/,
		quiet   => qr/^(--quiet|-q)$/,
		stop    => '--'
	};
}

my %_init_args= map { $_ => 1 } qw(
	level log_level min level_min log_level_min max level_max log_level_max
	env argv signals format output writer
);
sub init {
	my $self= shift;
	my $cfg= (@_ == 1 and ref $_[0] eq 'HASH')? $_[0] : { @_ };
	# Warn on unknown arguments
	my @unknown= grep { !$_init_args{$_} } keys %$cfg;
	carp "Invalid arguments: ".join(', ', @unknown) if @unknown;
	
	defined $cfg->{$_} and $self->log_level($cfg->{$_})
		for qw: level log_level :;
	
	defined $cfg->{$_} and $self->log_level_min($cfg->{$_})
		for qw: min level_min log_level_min :;
	
	defined $cfg->{$_} and $self->log_level_max($cfg->{$_})
		for qw: max level_max log_level_max :;

	# Optional ENV processing
	if ($cfg->{env}) {
		$self->process_env( %{
			ref $cfg->{env} eq 'HASH'? $cfg->{env}
			: $env_profile{$cfg->{env}}
				|| croak "Unknown \"env\" value $cfg->{env}"
		} );
	}
	
	# Optional ARGV parsing
	if ($cfg->{argv}) {
		$self->process_argv( %{
			ref $cfg->{argv} eq 'HASH'? $cfg->{argv}
			: $argv_profile{$cfg->{argv}}
				|| croak "Unknown \"argv\" value $cfg->{argv}"
		} );
	}
	
	# Optional installation of signal handlers
	if ($cfg->{signals}) {
		my $r= ref($cfg->{signals}) || '';
		$self->install_signal_handlers( %{
			$r eq 'HASH'? $cfg->{signals}
			: $r eq 'ARRAY'? { verbose => $cfg->{signals}[0], quiet => $cfg->{signals}[1] }
			: croak "Unknown \"signals\" value $cfg->{signals}"
		} );
	}
		
	$self->format($cfg->{format})
		if defined $cfg->{format};
	
	$self->output($cfg->{output})
		if defined $cfg->{output};
	
	$self->writer($cfg->{writer})
		if defined $cfg->{writer};
	
	$self;
}

=head2 log_level_num

The current log level, returned as a number.  This is *NOT* a writeable attribute, just
a shortcut for numeric_level( $self->log_level )

=head2 log_level_min_num

The current minimum, returned as a number.  This is *NOT* a writeable attribute, just
a shortcut for numeric_level( $self->log_level_min ).

=head2 log_level_max_num

The current maximum, returned as a number.  This is *NOT* a writeable attribute, just
a shortcut for numeric_level( $self->log_level_max ).

=cut

# We lied.  This is the actual attribute in the implementation
sub log_level_num     { shift->{log_level_num} }
sub log_level_min_num { shift->{log_level_min_num} }
sub log_level_max_num { shift->{log_level_max_num} }

=head2 log_level_adjust

  $config->log_level_adjust(-2);

Add or subtract a number from the current log level.  The value is clamped to
the current minimum and maximum.  (positive increases logging verbosity, and
negative decreases it)

=cut

sub log_level_adjust {
	my ($self, $offset)= @_;
	defined $offset && ($offset =~ /^-?\d+$/) && @_ == 2
		or die "Expected offset integer";
	$self->log_level( $self->log_level_num + $offset );
}

=head2 process_env

  $config->process_env( debug => $ENV_VAR_NAME );
  # and/or
  $config->process_env( log_level => $ENV_VAR_NAME );

Request that this package check for the named variable(s), and if set,
interpret it either as a debug level or a log level, and then set L<log_level>.

A log_level environment variable is applied directly to the L<log_level> attribute.

A "debug level" environment variable refers to the typical Unix practice of a
variable named DEBUG where 0 is disabled, 1 is enabled, and larger numbers
increase the verbosity.
This results in the following mapping: 2=trace, 1=debug, 0=info, -1=notice and
so on.  Larger numbers are clamped to 'trace'.

=cut

my %_process_env_args= ( debug => 1, log_level => 1 );
sub process_env {
	my ($self, %spec)= @_;
	# Warn on unknown arguments
	my @unknown= grep { !$_process_env_args{$_} } keys %spec;
	carp "Invalid arguments: ".join(', ', @unknown) if @unknown;
	
	if (defined $spec{log_level} && defined $ENV{$spec{log_level}}) {
		$self->log_level($ENV{$spec{log_level}});
	}
	if (defined $spec{debug} && defined $ENV{$spec{debug}}) {
		$self->log_level( $self->debug_level_to_log_level($ENV{$spec{debug}}) );
	}
}

sub debug_level_to_log_level {
	my ($class, $level)= @_;
	$level+= 6 if $level =~ /^-?\d+$/;
	$level;
}

=head2 process_argv

  $self->process_argv( bundle => ..., verbose => ..., quiet => ..., stop => ..., remove => ... )

Scans (and optionally modifies) @ARGV using method L<parse_log_level_opts>,
with the supplied options, and updates the log level accordingly.

=cut

my %_process_argv_args= ( bundle => 1, verbose => 1, quiet => 1, stop => 1, array => 1, remove => 1 );
sub process_argv {
	my $self= shift;
	my $ofs= $self->parse_log_level_opts(array => \@ARGV, @_);
	$self->log_level_adjust($ofs)
		if $ofs;
	1;
}

=head2 parse_log_level_opts

  $level_offset= $class->parse_log_level_opts(
    array   => $arrayref, # required
    verbose => $strings_or_regexes,
    quiet   => $strings_or_regexes,
    stop    => $strings_or_regexes,
    bundle  => $bool, # defaults to false
    remove  => $bool, # defaults to false
  );

Scans the elements of 'array' looking for patterns listed in 'verbose', 'quiet', or 'stop'.
Each match of a pattern in 'quiet' subtracts one from the return value, and
each match of a pattern in 'verbose' adds one.  Stops iterating the array if
any pattern in 'stop' matches.

If 'bundle' is true, then this routine will also split apart "bundled options",
so for example

  --foo -wbmvrcd --bar

is processed as if it were

  --foo -w -b -m -v -r -c -d --bar

If 'remove' is true, then this routine will alter the array to remove matching
elements for 'quiet' and 'verbose' patterns.  It can also remove the bundled
arguments if bundling is enabled:

  @array= ( '--foo', '-qvvqlkj', '--verbose' );
  my $n= parse_log_level_opts(
    array => \@array,
    quiet => [ '-q', '--quiet' ],
    verbose => [ '-v', '--verbose' ],
    bundle => 1,
    remove => 1
  );
  # $n = -1
  # @array = ( '--foo', '-lkj' );

=cut

sub _make_regex_list {
	return () unless defined $_[0];
	return qr/^\Q$_[0]\E$/ unless ref $_[0];
	return map { _make_regex_list($_) } @{ $_[0] } if ref $_[0] eq 'ARRAY';
	return $_[0] if ref $_[0] eq 'Regexp';
	croak "Not a regular expression, string, or array: $_[0]"
}
sub _combine_regex {
	my @list= _make_regex_list(@_);
	return @list == 0? qr/\0^/  # a regex that doesn't match anything
		: @list == 1? $list[0]
		: qr/@{[ join '|', @list ]}/;
}
sub parse_log_level_opts {
	my ($class, %spec)= @_;
	# Warn on unknown arguments
	my @unknown= grep { !$_process_argv_args{$_} } keys %spec;
	carp "Invalid arguments: ".join(', ', @unknown) if @unknown;
	
	defined $spec{array} or croak "Parameter 'array' is required";
	my $stop=    _combine_regex( $spec{stop} );
	my $verbose= _combine_regex( $spec{verbose} );
	my $quiet=   _combine_regex( $spec{quiet} );
	my $level_ofs= 0;
	
	my $parse;
	$parse= sub {
		my $array= $_[0];
		for (my $i= 0; $i < @$array; $i++) {
			last if $array->[$i] =~ $stop;
			if ($array->[$i] =~ /^-[^-=][^-=]+$/ and $spec{bundle}) {
				# Un-bundle the arguments
				my @un_bundled= map { "-$_" } split //, substr($array->[$i], 1);
				my $len= @un_bundled;
				# Then filter them as usual
				$parse->(\@un_bundled);
				# Then re-bundle them, if altered
				if ($spec{remove} && $len != @un_bundled) {
					if (@un_bundled) {
						$array->[$i]= '-' . join('', map { substr($_,1) } @un_bundled);
					} else {
						splice( @$array, $i--, 1 );
					}
				}
			}
			elsif ($array->[$i] =~ $verbose) {
				$level_ofs++;
				splice( @$array, $i--, 1 ) if $spec{remove};
			}
			elsif ($array->[$i] =~ $quiet) {
				$level_ofs--;
				splice( @$array, $i--, 1 ) if $spec{remove};
			}
		}
	};

	$parse->( $spec{array} );
	return $level_ofs;
}

=head2 install_signal_handlers

  $config->handle_signals( verbose => $signal_name, quiet => $signal_name );

Install signal handlers (probably USR1, USR2) which increase or decrease
the log level.

Basically:

  $SIG{ $verbose_name }= sub { $config->log_level_adjust(1); }
    if $verbose_name;
  
  $SIG{ $quiet_name   }= sub { $config->log_level_adjust(-1); }
    if $quiet_name;

=cut

my %_handle_signal_args= ( verbose => 1, quiet => 1 );
sub install_signal_handlers {
	my ($self, %spec)= @_;
	# Warn on unknown arguments
	my @unknown= grep { !$_handle_signal_args{$_} } keys %spec;
	carp "Invalid arguments: ".join(', ', @unknown) if @unknown;
	
	$SIG{ $spec{verbose} }= sub { $self->log_level_adjust(1); }
		if $spec{verbose};
  
	$SIG{ $spec{quiet}   }= sub { $self->log_level_adjust(-1); }
		if $spec{quiet};
}

=head2 compiled_writer

This returns the L<writer> attribute if it is defined, or the compiled
result of L<output> and L<format> otherwise.

=cut

sub compiled_writer {
	my $self= shift;
	$self->{writer} || ($self->{_writer_cache} ||= $self->_build_writer_cache)
}

# This method combines the output and format settings into a writer.
sub _build_writer_cache {
	my $self= shift;
	my $code= "sub {  \n" . $self->_build_writer_code . "\n}";
	my $err;
	my $writer= $self->_build_writer_eval_in_clean_scope( $code, \$err )
		or croak "Compilation of log writer failed: $err\nSource code is: $code";
	return $writer;
}

# separate from _build_writer_cache so that test cases (and maybe subclasses)
# can inspect the generated code.
sub _build_writer_code {
	my $self= shift;
	my $format= $self->format;
	my $code= '  my ($adapter, $level, $message)= @_;'."\n"
			. '  $message =~ s/\n+$//;'."\n";
	
	if ($format =~ /\$\{?category(\W|$)/) {
		$code .= '  my $category= $adapter->category;'."\n";
	}
	if ($format =~ /\$\{?(package|file|line|file_brief)(\W|$)/) {
		$code .= '  my ($package,$file,$line);'."\n"
				.'  { my $i= 0; do { ($package, $file, $line)= caller(++$i) } while $package =~ /^Log::Any/; };'."\n";
		
		$code .= '  my $file_brief= $file;'."\n"
				.'  $file_brief =~ s|.*[\\/]lib[\\/]||;'."\n"
			if $format =~ /\$\{?file_brief(\W|$)/;
	}
	if ($format =~ /\$\{?level_prefix(\W|$)/) {
		$code .= '  my $level_prefix= ($level eq "info")? "" : "$level: ";'."\n";
	}
	my $output= $self->output;
	if (ref $output eq 'GLOB') {
		$code .= '  print $output (';
	} elsif (ref($output)->can('print')) {
		$code .= '  $output->print(';
	} elsif (ref $output eq 'CODE') {
		$code .= '  $output->(';
	} else {
		croak "Unhandled type of output: $output";
	}
	
	if (ref $format eq 'CODE') {
		# Closure over '$format', rather than deparsing the coderef
		$code .= ' map {; $format->($_) } split /\n/, $message)';
	} else {
		$code .= ' map {; '.$format.' } split /\n/, $message)'; 
	}

	return $code;
}

# "Cached Adapters" would more properly be a field of the config object, but then
# it shows a giant mess if/when you Dump() the object, so I'm using this trick
# to keep the list attached to the package instead of the object.
# Object destructor cleans up the list.
our %_cached_adapters;

# Holds a list of weak references to Adapter instances which have cached values from this config
sub _cached_adapters {
	# Use refaddr in case someone subclasses and gets creative with re-blessing objects
	$_cached_adapters{refaddr $_[0]} ||= [];
}
sub DESTROY {
	delete $_cached_adapters{refaddr $_[0]};
}

# Called by an adapter after it caches things from this config to ask that it
# be notified about any changes.
sub _register_cached_adapter {
	my ($self, $adapter)= @_;
	my $cache= $self->_cached_adapters;
	push @$cache, $adapter;
	weaken( $cache->[-1] );
}

# Inform all the Adapters who have cached our settings that the cache is invalid.
sub _reset_cached_adapters {
	my $self= shift;
	my $cache= $self->_cached_adapters;
	$_->_uncache_config for grep { defined } @$cache;
	@$cache= ();
}

1;
