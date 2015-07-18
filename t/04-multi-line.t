#! /usr/bin/perl

use strict;
use warnings;
use Test::More;
use Log::Any '$log';
$SIG{__DIE__}= $SIG{__WARN__}= sub { diag @_; };

use_ok( 'Log::Any::Adapter', 'Daemontools', filter => 'none' ) || BAIL_OUT;

my $buf;

sub reset_stdout {
	close STDOUT;
	$buf= '';
	open STDOUT, '>', \$buf or die "Can't redirect stdout to a memory buffer: $!";
}

reset_stdout;
$log->notice("test2\ntest3\ntest4");
like( $buf, qr/notice: test2\nnotice: test3\nnotice: test4\n/ );

reset_stdout;
$log->notice("test2\ntest3\ntest4\n");
like( $buf, qr/notice: test2\nnotice: test3\nnotice: test4\n/ );

done_testing;
