#!/usr/bin/perl
# Generates window.THREE21_DAILY_TRIPLES for climbs.js — a one-time partition of
# all climb seeds into groups of 3 that share NO word at any rung (3..8 letters)
# with each other, so a single day's Daily Climb never repeats a word across its
# 3 rounds. Re-run this only if climbs.js's seed list changes (seeds added/
# removed/reordered) — otherwise the shipped array is the source of truth.
#
# Within each triple, round order is [round1, round2, round3]. The construction
# below guarantees zero shared words at ANY stage, so the "if 2 seeds share the
# 3-letter word, put them in round 1 & 3" rule never actually needs to fire —
# it's kept as a defensive fallback in case this script is ever re-run against
# a seed set where a perfectly clean partition isn't achievable.
use strict;
use warnings;

my $root = "D:/Claude Code/portfolio/games/3-2-1";

open(my $cfh, "<:raw", "$root/climbs.js") or die $!;
local $/;
my $raw = <$cfh>;
close $cfh;

my @seeds;
while ($raw =~ /\{c:\[([^\]]+)\],a:\[([^\]]+)\]\}/g) {
    my @c = ($1 =~ /"([^"]*)"/g);
    push @seeds, \@c;
}
my $n = scalar(@seeds);
print STDERR "loaded $n seeds\n";

# ---- conflict graph: i conflicts with j if they share a word at any rung ----
my @conflicts = map { {} } (0 .. $n - 1);
for (my $i = 0; $i < $n; $i++) {
    for (my $j = $i + 1; $j < $n; $j++) {
        for my $k (0 .. 5) {
            if ($seeds[$i][$k] eq $seeds[$j][$k]) {
                $conflicts[$i]{$j} = 1;
                $conflicts[$j]{$i} = 1;
                last;
            }
        }
    }
}

# ---- shuffle the pool so triples aren't just consecutive seed ids ----
srand(0xC11D5); # fixed seed, purely so re-runs are reproducible
my @pool = (0 .. $n - 1);
for (my $i = $#pool; $i > 0; $i--) {
    my $j = int(rand($i + 1));
    @pool[$i, $j] = @pool[$j, $i];
}

sub compatible { my ($a, $b) = @_; return !exists $conflicts[$a]{$b}; }

my @triples;
my @forced_conflicts;
while (@pool >= 3) {
    my $anchor = shift @pool;

    # find any B compatible with anchor
    my $bi = -1;
    for my $k (0 .. $#pool) {
        if (compatible($anchor, $pool[$k])) { $bi = $k; last; }
    }
    if ($bi == -1) {
        # anchor is incompatible with EVERYONE left — shouldn't happen given the
        # data, but if it does, just pair it with whoever's next and flag it.
        push @forced_conflicts, $anchor;
        push @pool, $anchor;
        my $b = shift @pool;
        my $c = shift @pool;
        push @triples, [$anchor, $b, $c];
        next;
    }
    my $b = splice(@pool, $bi, 1);

    # find any C compatible with BOTH anchor and b
    my $ci = -1;
    for my $k (0 .. $#pool) {
        if (compatible($anchor, $pool[$k]) && compatible($b, $pool[$k])) { $ci = $k; last; }
    }
    if ($ci == -1) {
        # no clean 3rd — fall back to whichever remaining seed conflicts with the
        # FEWEST of {anchor,b}, then order per the round-1/round-3 rule below.
        my $best = 0; my $bestScore = 999;
        for my $k (0 .. $#pool) {
            my $score = (exists $conflicts[$anchor]{$pool[$k]} ? 1 : 0) + (exists $conflicts[$b]{$pool[$k]} ? 1 : 0);
            if ($score < $bestScore) { $bestScore = $score; $best = $k; }
        }
        my $c = splice(@pool, $best, 1);
        push @forced_conflicts, $anchor;
        push @triples, [$anchor, $b, $c];
        next;
    }
    my $c = splice(@pool, $ci, 1);
    push @triples, [$anchor, $b, $c];
}
print STDERR "leftover seed(s) unused this cycle: " . join(",", @pool) . " (count=" . scalar(@pool) . ")\n";
print STDERR "triples built: " . scalar(@triples) . "\n";
print STDERR "triples with a forced (unavoidable) conflict: " . scalar(@forced_conflicts) . "\n";

# ---- verify + apply the round-1/round-3 fallback rule where needed ----
my $verified_clean = 0;
my $reordered = 0;
for my $t (@triples) {
    my ($x, $y, $z) = @$t;
    my $xy = exists $conflicts[$x]{$y};
    my $yz = exists $conflicts[$y]{$z};
    my $xz = exists $conflicts[$x]{$z};
    my $conflictCount = ($xy?1:0) + ($yz?1:0) + ($xz?1:0);
    if ($conflictCount == 0) { $verified_clean++; next; }
    # exactly one conflicting pair expected (the "all 3 share" case is assumed
    # impossible per the construction above, which never groups a seed with two
    # others it both conflict with unless truly forced). Put the conflicting
    # pair at round1/round3, the clean seed at round2.
    if ($xy && !$yz && !$xz) { @$t = ($x, $z, $y); $reordered++; }       # x-y conflict -> spread to 1&3, z buffers
    elsif ($yz && !$xy && !$xz) { @$t = ($y, $x, $z); $reordered++; }    # y-z conflict -> spread to 1&3, x buffers
    elsif ($xz && !$xy && !$yz) { $reordered++; }                        # x-z conflict -> already at 1&3, nothing to do
    else { print STDERR "WARNING: triple (" . join(",", @$t) . ") has $conflictCount conflicting pairs — all-3-share case, no reordering can fully fix this\n"; }
}
print STDERR "clean triples (zero shared words at any stage): $verified_clean / " . scalar(@triples) . "\n";
print STDERR "triples reordered to keep a forced pair at round1/round3: $reordered\n";

print "window.THREE21_DAILY_TRIPLES = [\n";
for my $t (@triples) {
    print "[" . join(",", @$t) . "],\n";
}
print "];\n";
