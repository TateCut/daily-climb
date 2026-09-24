#!/usr/bin/perl
# Verify every seed in climbs.js still has a fully valid intended ladder under
# the CURRENT runtime rules. Re-run this after any change to climbs.js, the
# bundled dictionary, or the word-acceptance/inflection rules in index.html.
#   1. every c[i] is in the bundled ENABLE word list (words.js) - so it's
#      accepted instantly, with no Datamuse round-trip at all (an online-check
#      tightening in verifyWord/NAME_DEF only ever touches words NOT in that
#      list, so this proves such a change can't have broken the intended path);
#   2. c[i+1]'s letters are exactly c[i]'s letters plus the recorded a[i]
#      (climbs.js's own data is internally consistent);
#   3. no rung is the rung below it plus a grammatical ending (-s/-d/-r/-n on
#      an -e word) - the actual "no cheap steps" rule enforced in submit().
#   4. no lockouts: the "no cheap steps" rule is checked against the word the
#      player ACTUALLY played, not the reference ladder. So for every word a
#      player could reach on each rung (any dictionary anagram that isn't a
#      cheap step off something they could have played before), the next
#      rung must still offer at least one word that isn't just that word plus
#      an ending. Otherwise a valid earlier choice (e.g. DESIGN instead of
#      SIGNED) leaves DESIGNS as the only word and the climb can't continue.
use strict;
use warnings;

my $root = "D:/Claude Code/portfolio/games/3-2-1";

# ---- load the bundled dictionary (WORD_SET equivalent: len >= 3) ----
open(my $wfh, "<:raw", "$root/words.js") or die "words.js: $!";
local $/;
my $words_raw = <$wfh>;
close $wfh;
$words_raw =~ /`\n(.*)\n`/s or die "couldn't find the backtick word block";
my %word_set;
for my $w (split /\n/, $1) {
    $word_set{$w} = 1 if length($w) >= 3;
}
print "loaded " . scalar(keys %word_set) . " dictionary words\n";
my %anagrams;
push @{ $anagrams{ join("", sort split //, $_) } }, $_ for keys %word_set;

# ---- load climbs.js ----
open(my $cfh, "<:raw", "$root/climbs.js") or die "climbs.js: $!";
my $climbs_raw = <$cfh>;
close $cfh;

my @seeds;
while ($climbs_raw =~ /\{c:\[([^\]]+)\],a:\[([^\]]+)\]\}/g) {
    my ($c_part, $a_part) = ($1, $2);
    my @c = ($c_part =~ /"([^"]*)"/g);
    my @a = ($a_part =~ /"([^"]*)"/g);
    push @seeds, { c => \@c, a => \@a };
}
print "loaded " . scalar(@seeds) . " seeds\n\n";

sub sorted_letters { return join("", sort split //, lc(shift)); }

sub is_inflection_of {
    my ($word, $prev) = @_;
    return 0 unless defined($prev) && defined($word);
    return 1 if $word eq $prev . "s";
    if ($prev =~ /e$/) {
        return 1 if $word eq $prev . "d";
        return 1 if $word eq $prev . "r";
        return 1 if $word eq $prev . "n";
    }
    return 0;
}

my @bad;
my $seed_i = 0;
for my $seed (@seeds) {
    $seed_i++;
    my @c = @{ $seed->{c} };
    my @a = @{ $seed->{a} };
    my @problems;

    if (@c != 6) { push @problems, "c has " . scalar(@c) . " entries, expected 6"; }
    if (@a != 5) { push @problems, "a has " . scalar(@a) . " entries, expected 5"; }

    for my $i (0 .. $#c) {
        my $expect_len = 3 + $i;
        if (length($c[$i]) != $expect_len) {
            push @problems, "c[$i]='$c[$i]' has length " . length($c[$i]) . ", expected $expect_len";
        }
        unless (exists $word_set{lc($c[$i])}) {
            push @problems, "c[$i]='$c[$i]' is NOT in the bundled dictionary (would need an online check to accept)";
        }
    }

    for my $i (0 .. 4) {
        next unless defined $c[$i] && defined $c[$i+1] && defined $a[$i];
        my $expect = sorted_letters($c[$i] . $a[$i]);
        my $got    = sorted_letters($c[$i+1]);
        if ($expect ne $got) {
            push @problems, "letters mismatch at rung $i->" . ($i+1) . ": '$c[$i]'+'$a[$i]' sorts to [$expect], but c[" . ($i+1) . "]='$c[$i+1]' sorts to [$got]";
        }
        if (is_inflection_of($c[$i+1], $c[$i])) {
            push @problems, "c[" . ($i+1) . "]='$c[$i+1]' is a grammatical inflection of c[$i]='$c[$i]' - violates the no-cheap-steps rule";
        }
    }

    my %reachable = map { $_ => 1 } @{ $anagrams{ sorted_letters($c[0]) } || [] };
    for my $i (1 .. $#c) {
        my @words = @{ $anagrams{ sorted_letters($c[$i]) } || [] };
        my %next;
        for my $prev (sort keys %reachable) {
            my @ok = grep { !is_inflection_of($_, $prev) } @words;
            if (!@ok) {
                push @problems, "LOCKOUT at rung $i: a player who played '$prev' can only make '" . join("/", @words) . "', which is '$prev' plus an ending";
            }
            $next{$_} = 1 for @ok;
        }
        %reachable = %next;
    }

    if (@problems) {
        push @bad, { index => $seed_i, chain => join(" -> ", @c), problems => \@problems };
    }
}

print "=== RESULTS ===\n";
print "seeds checked: " . scalar(@seeds) . "\n";
print "seeds with a problem: " . scalar(@bad) . "\n\n";
for my $b (@bad) {
    print "SEED #$b->{index}: $b->{chain}\n";
    print "  - $_\n" for @{ $b->{problems} };
    print "\n";
}
print "All seeds are fully doable under the current ruleset.\n" unless @bad;
