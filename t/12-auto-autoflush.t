#! /usr/bin/perl

use strict;
use warnings;
use Test::More;

my $out= _run(q/ use Log::Any q{$log}; use Log::Any::Adapter q{Daemontools}; $log->info(q{stdout}); print STDERR qq{stderr\n} /);
is( $out, "stdout\nstderr\n", 'default stdout gets autoflush' );

$out= _run(q/ use IO::File; use Log::Any q{$log}; use Log::Any::Adapter q{Daemontools}, -init => { output => \*STDOUT }; $log->info(q{stdout}); print STDERR qq{stderr\n} /);
is( $out, "stdout\nstderr\n", 'default stdout gets autoflush when IO::File loaded' );

$out= _run(q/ use IO::File; use Log::Any q{$log}; use Log::Any::Adapter q{Daemontools}, -init => { output => IO::File->new_from_fd(1,q{w}) }; $log->info(q{stdout}); print STDERR qq{stderr\n} /);
is( $out, "stdout\nstderr\n", 'autoflush IO::File' );

$out= _run(q/ use Log::Any q{$log}; use Log::Any::Adapter q{Daemontools}, -init => { output => sub { print @_ } }; $log->info(q{stdout}); print STDERR qq{stderr\n} /);
is( $out, "stderr\nstdout\n", 'coderef can\'t be autoflushed' );

sub _run {
	# Temporarily redirect stderr rather than relying on the shell to do it,
	# for Win32 compatibility.
	my $script= shift;
	my $out= `$^X -e '$script' 2>&1`;
	diag "command exited ".($? >> 8).": $^X -e '$script'\n"
		if $?;
	return $out;
}

done_testing;
