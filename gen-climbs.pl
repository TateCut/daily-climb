use strict;
use warnings;

my $DIR = 'D:/Claude Code/portfolio/games/3-2-1';
my $OUT = "$DIR/climbs.js";

sub load {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!";
    my %w;
    while (my $l = <$fh>) {
        $l =~ s/\s+$//;
        next unless $l =~ /^[a-z]+$/;
        my $n = length $l;
        next if $n < 3 || $n > 8;
        $w{$l} = 1;
    }
    close $fh;
    return \%w;
}
sub keyf { join('', sort split //, $_[0]) }

# forbidden step short S -> long L :  L is S plus a grammatical single-letter ending
sub forbidden {
    my ($s, $l) = @_;
    return 1 if $l eq $s . 's';
    if ($s =~ /e$/) { return 1 if $l eq $s.'d' || $l eq $s.'r' || $l eq $s.'n'; }
    return 0;
}

my $freq   = load("$DIR/freq.js");     # dictionary that defines "everyday word"
my $enable = load("$DIR/words.js");    # only used to prefer readable predecessors

my %wbk;
push @{ $wbk{ keyf($_) } }, $_ for keys %$freq;

# predecessors(L) : real freq words one letter shorter whose multiset is L's minus one char
my %preds;
for my $L (keys %$freq) {
    next if length($L) == 3;
    my $key = keyf($L);
    my (%seen, %got);
    my @ch = split //, $key;
    for my $i (0 .. $#ch) {
        next if $seen{ $ch[$i] }++;
        my $sub = $key; substr($sub, $i, 1) = '';
        $got{$_} = 1 for @{ $wbk{$sub} || [] };
    }
    $preds{$L} = [ keys %got ];
}

# reachability up from length 3, no forbidden steps
my (%ok, %pred);
my @byLen;
push @{ $byLen[ length $_ ] }, $_ for keys %$freq;
$ok{$_} = 1 for @{ $byLen[3] };
for my $k (4 .. 8) {
    for my $L (@{ $byLen[$k] }) {
        for my $S (@{ $preds{$L} }) {
            next unless $ok{$S};
            next if forbidden($S, $L);
            $ok{$L} = 1;
            push @{ $pred{$L} }, $S;
        }
    }
}

# frequency rank for readability tie-breaks (earlier line in freq.js == more common)
my %rank; my $r = 0;
open(my $ff, '<', "$DIR/freq.js") or die;
while (<$ff>) { s/\s+$//; next unless /^[a-z]+$/; $rank{$_} //= $r++; }
close $ff;

# pick the most-common predecessor, then shortest chain feel
my $best_pred = sub {
    my @c = grep { defined } @_;
    @c = sort { ($rank{$a} // 1e9) <=> ($rank{$b} // 1e9) or $a cmp $b } @c;
    return $c[0];
};

# one chain per qualifying 8-letter word, build order 3..8
my @rows;
for my $w8 (sort @{ $byLen[8] }) {
    next unless $ok{$w8};
    my @chain = ($w8);
    my $cur = $w8;
    while (length($cur) > 3) {
        my $s = $best_pred->(@{ $pred{$cur} });
        die "no pred for $cur (target $w8)" unless defined $s;
        push @chain, $s;
        $cur = $s;
    }
    @chain = reverse @chain;                 # now 3 -> 8

    # sanity: 6 distinct words, each +1 letter, no forbidden step, all freq words
    die "len $w8" unless @chain == 6;
    for my $i (0 .. 4) {
        die "step $w8 [$i]" unless length($chain[$i]) + 1 == length($chain[$i+1]);
        die "notword $chain[$i]" unless $freq->{ $chain[$i] };
        die "forbidden $chain[$i]->$chain[$i+1]" if forbidden($chain[$i], $chain[$i+1]);
        # multiset subset check
        my %h; $h{$_}++ for split //, $chain[$i+1];
        $h{$_}-- for split //, $chain[$i];
        my @extra = grep { $h{$_} != 0 } keys %h;
        die "diff $chain[$i]->$chain[$i+1]" unless @extra == 1 && $h{$extra[0]} == 1;
    }
    die "notword $chain[5]" unless $freq->{ $chain[5] };

    my @adds;
    for my $i (0 .. 4) {
        my %h; $h{$_}++ for split //, $chain[$i+1];
        $h{$_}-- for split //, $chain[$i];
        my ($a) = grep { $h{$_} > 0 } keys %h;
        push @adds, $a;
    }
    push @rows, [ \@chain, \@adds ];
}

open(my $o, '>', $OUT) or die "$OUT: $!";
print $o "// 3->8 letter CLIMB puzzles for 3-2-1.  Generated - do not hand-edit.\n";
print $o "// Each: c = the reference ladder (6 everyday words, 3..8 letters, +1 letter per rung,\n";
print $o "//       no rung is the rung below it plus a grammatical ending -s/-d/-r/-n).\n";
print $o "//       a = the 5 letters added, a[0] going 3->4 ... a[4] going 7->8.\n";
print $o "// The player may answer any valid word at each rung, not just c[i].\n";
printf $o "window.THREE21_CLIMBS = [\n";
for my $row (@rows) {
    my ($c, $a) = @$row;
    printf $o "{c:[%s],a:[%s]},\n",
        join(',', map { "\"$_\"" } @$c),
        join(',', map { "\"$_\"" } @$a);
}
print $o "];\n";
close $o;

printf "wrote %s  (%d puzzles)\n", $OUT, scalar(@rows);
# a few for eyeballing
print "  ", join(' -> ', map { uc } @{ $rows[$_][0] }), "\n" for (0, 1, 2, int(@rows/2), $#rows-1, $#rows);
