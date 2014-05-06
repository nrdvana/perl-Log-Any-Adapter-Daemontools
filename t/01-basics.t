#! /usr/bin/perl

use strict;
use warnings;
use Test::More;
use Log::Any '$log';

use_ok( 'Log::Any::Adapter', 'Daemontools' ) || BAIL_OUT;

my $buf= '';
close STDERR;
open STDERR, '>', \$buf or die "Can't redirect STDERR to a memory buffer: $!";
$SIG{__DIE__}= $SIG{__WARN__}= sub { diag @_; };

$log->warn("test1");
like( $buf, qr/warning: test1\n/ );

$log->error("test2");
like( $buf, qr/error: test2\n/ );

$log->debug("test3");
unlike( $buf, qr/debug: test3\n/ );

Log::Any::Adapter->set('Daemontools', filter => undef);
$log->debug("test4");
like( $buf, qr/debug: test4\n/ );

done_testing;
