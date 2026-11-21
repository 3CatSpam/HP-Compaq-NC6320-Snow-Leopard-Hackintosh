#!/usr/bin/perl
# Usage: applypatch.pl <patchfile> <input> <output>
# Applies a byte-level patch (offset oldhex newhex per line) to <input> and writes <output>.
# Refuses to run if <input> is not exactly the file the patch was made for.
use strict; use warnings; use Digest::SHA qw(sha256_hex);
my ($pf, $in, $out) = @ARGV;
die "usage: applypatch.pl patch input output\n" unless defined $out;
open(my $p, '<', $pf) or die "cannot read $pf: $!\n";
my ($src, $res, @runs);
while (<$p>) {
  chomp;
  if (/^# source-sha256 (\w+)/) { $src = $1; next }
  if (/^# result-sha256 (\w+)/) { $res = $1; next }
  next if /^#/ || /^\s*$/;
  my ($off, $old, $new) = split ' ';
  push @runs, [$off, pack('H*', $old), pack('H*', $new)];
}
close $p;
open(my $i, '<:raw', $in) or die "cannot read $in: $!\n";
local $/; my $d = <$i>; close $i;
die "ERROR: $in is not the expected original file (sha256 mismatch). Not patching.\n"
  unless sha256_hex($d) eq $src;
for my $r (@runs) {
  my ($off, $old, $new) = @$r;
  die "ERROR: unexpected bytes at offset $off\n" unless substr($d, $off, length $old) eq $old;
  substr($d, $off, length $new) = $new;
}
die "ERROR: result checksum mismatch\n" unless sha256_hex($d) eq $res;
open(my $o, '>:raw', $out) or die "cannot write $out: $!\n";
print $o $d; close $o;
print "patched OK: $out\n";
