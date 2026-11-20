#!/usr/bin/perl
# Runs upstream's libpq URI test table (src/interfaces/libpq/t/001_uri.pl) against the built
# libpq_uri_regress, without the TAP/IPC::Run harness the image lacks. The @tests list is taken
# verbatim from the upstream file, so new upstream cases are picked up automatically.
# Usage: uri_regress.pl <001_uri.pl> <libpq_uri_regress>; prints "PASS n FAIL m".
use strict;
use warnings;
use IPC::Open3;
use Symbol 'gensym';

my ($tap, $prog) = @ARGV;
open(my $fh, '<', $tap) or die "open $tap: $!";
my $src = do { local $/; <$fh> };
close($fh);
$src =~ /^(my \@tests = \(.*?\]\s*\);)/ms or die "no \@tests table in $tap";
my @tests;
{
	my $code = $1;
	$code =~ s/^my //;
	eval "$code; 1" or die "eval: $@";
}
die "empty test table" unless @tests;

my ($pass, $fail) = (0, 0);
foreach my $t (@tests)
{
	my ($uri, $exp_out, $exp_err, %env) = @$t;
	local %ENV = (%ENV, %env);
	my $err = gensym;
	my $pid = open3(my $in, my $out, $err, $prog, $uri);
	close($in);
	my $got_out = do { local $/; <$out> } // '';
	my $got_err = do { local $/; <$err> } // '';
	waitpid($pid, 0);
	my $ok_exit = ($? == 0);
	chomp($got_out);
	chomp($got_err);
	if ($got_out eq $exp_out && $got_err eq $exp_err && $ok_exit == ($exp_err eq ''))
	{
		$pass++;
	}
	else
	{
		$fail++;
		print STDERR "FAIL: $uri\n  want out=[$exp_out] err=[$exp_err]\n  got  out=[$got_out] err=[$got_err] exit=$?\n";
	}
}
print "PASS $pass FAIL $fail\n";
