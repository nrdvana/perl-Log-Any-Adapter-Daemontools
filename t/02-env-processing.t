#! /usr/bin/perl

use strict;
use warnings;
use Test::More;
use Log::Any::Adapter::Util ':levels';
use Log::Any '$log';
$SIG{__DIE__}= $SIG{__WARN__}= sub { diag @_; };

use_ok( 'Log::Any::Adapter', 'Daemontools' ) || BAIL_OUT;

my $laad= 'Log::Any::Adapter::Daemontools';

subtest debug_var => sub {
	my @tests= (
		[ 0 => INFO ],
		[ 1 => DEBUG ],
		[ 2 => TRACE ],
		[ 'info' => INFO ],
		[ -1 => NOTICE ],
		[ 'error' => ERROR ],
		[ 'fatal' => CRITICAL ],
	);
	for (@tests) {
		my ($env_val, $level)= @$_;
		$ENV{__TEST}= $env_val;
		$laad->process_env( debug => '__TEST' );
		is( $laad->global_log_level, $level, "DEBUG=$env_val  -> $level" );
	}
};

subtest level_var => sub {
	my @tests= (
		[ -1 => -1 ],
		[ 0 => 0 ],
		[ 1 => 1 ],
		[ 'debug' => DEBUG ],
	);
	for (@tests) {
		my ($env_val, $level)= @$_;
		$ENV{__TEST}= $env_val;
		$laad->process_env( log_level => '__TEST' );
		is( $laad->global_log_level, $level, "LOG_LEVEL=$env_val  -> $level" );
	}
};

done_testing;
