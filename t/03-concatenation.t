#! /usr/bin/perl

use strict;
use warnings;
use Test::More;
use Log::Any '$log';
$SIG{__DIE__}= $SIG{__WARN__}= sub { diag @_; };

use_ok( 'Log::Any::Adapter', 'Daemontools', filter => -1 ) || BAIL_OUT;

my $buf;

sub reset_stdout {
	close STDOUT;
	$buf= '';
	open STDOUT, '>', \$buf or die "Can't redirect stdout to a memory buffer: $!";
}

reset_stdout;
$log->notice("foo","bar");

# Log::Any 1.00 or later will auto-concatenate with space; older log-any
# will not and this adapter will do so without spaces
like( $buf, qr/notice: foo ?bar\n/ );

done_testing;
