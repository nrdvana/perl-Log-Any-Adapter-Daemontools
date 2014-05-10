#! /usr/bin/perl

use strict;
use warnings;
use Test::More;
use Log::Any '$log';
$SIG{__DIE__}= $SIG{__WARN__}= sub { diag @_; };

use_ok( 'Log::Any::Adapter', 'Daemontools' ) || BAIL_OUT;

my $buf;

sub reset_stderr {
	close STDERR;
	$buf= '';
	open STDERR, '>', \$buf or die "Can't redirect STDERR to a memory buffer: $!";
}

reset_stderr;
$log->warnf("%s", "test1");
like( $buf, qr/^warning: test1\n$/ );

reset_stderr;
$log->errorf("%d %s", 5, [ 1, 2, 3 ]);
like( $buf, qr/^error: 5 \[1,2,3\]\n$/ );

reset_stderr;
$log->warningf("%s%s", "test3\n", "test4");
like( $buf, qr/^warning: test3\nwarning: test4\n$/ );

done_testing;
