use strict;
use warnings;
use utf8;
use JSON::PP;
use Time::Local;
binmode STDOUT, ':encoding(UTF-8)';

# !! The LIVE calendar is played from 2026-09-29 and was patched in place for
# !! v0.5.0 (4-letter starts, cut words). Re-running this rebuilds EVERY day,
# !! past ones included. To extend the calendar, append new days instead.
# !! After any rebuild or extension, run fix-traps.pl (removes theme-word traps
# !! from future days) and verify-calendar.pl.
# Builds daily-calendar.js: the themed daily, one entry per day from START.
# Each day = one theme + three climbs whose peaks rise (non-decreasing, last
# higher than first, at most one 7-letter climb), each climb holding a theme
# word (5+ letters, from themes.txt). Days are Trail / Ridge / Summit:
#   Trail  7·8·8 with easier climbs                         ~14 words (climbs start at 4 letters from v0.5.0)
#   Ridge  a 9-letter peak, or 7·8·8 with harder climbs     ~15-17
#   Summit a 10- or 11-letter peak (★ = 11)                 18-22
# mixed about 6:3:1 in a shuffled order that's the same for everyone:
# never more than 3 Trail days in a row, never two Summits back to back,
# ★ days spread out. Themes rotate evenly, never within a few days of
# themselves; holidays get their own theme. No climb repeats within a
# cycle; after the first cycle a climb may come back, but only with a
# theme it hasn't had before.
#
#   perl gen-calendar.pl            (START=YYYY-MM-DD DAYS=730 SEED=1 to change)
#
# Climbs: 8-letter peaks from climbs.js, others from daily-pool.js; any climb
# holding a climb-blocklist.txt word is skipped (climbs.js predates the list).

my $DIR   = 'D:/Claude Code/daily-climb';
my $START = $ENV{START} || '2026-09-29';
my $DAYS  = $ENV{DAYS}  || 730;
my $SEED  = $ENV{SEED}  || 1;
my $OUT   = "$DIR/daily-calendar.js";

# ---------------- random (seeded, same result every run) ----------------
my $rs = $SEED * 7919 + 17;
sub rnd { $rs = ($rs * 1103515245 + 12345) % 2147483648; $rs / 2147483648 }
sub shuffle { my @a = @_; for (my $i = $#a; $i > 0; $i--) { my $j = int(rnd() * ($i + 1)); @a[$i, $j] = @a[$j, $i]; } @a }

# ---------------- words ----------------
sub loadw {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!";
    my (%w, @o);
    while (my $l = <$fh>) { $l =~ s/\s+$//; next unless $l =~ /^[a-z]+$/; my $n = length $l; next if $n < 3 || $n > 15; push @o, $l unless $w{$l}++; }
    return (\%w, \@o);
}
sub keyf { join('', sort split //, $_[0]) }
sub forbidden { my ($s, $l) = @_; return 1 if $l eq $s.'s'; if ($s =~ /e$/) { return 1 if $l eq $s.'d' || $l eq $s.'r' || $l eq $s.'n'; } 0 }
my ($freq, $forder) = loadw("$DIR/freq.js");
my ($enable)        = loadw("$DIR/words.js");
my %rank; my $r = 0; $rank{$_} = ++$r for @$forder;
my %ebk; push @{ $ebk{ keyf($_) } }, $_ for keys %$enable;

my %blocked;
open(my $bf, '<', "$DIR/climb-blocklist.txt") or die;
while (<$bf>) { s/#.*//; s/\s+//g; $blocked{lc $_} = 1 if length; }

# ---------------- climbs ----------------
my (@climbs, $skipped);
for my $f ("climbs.js", "daily-pool.js") {
    open(my $fh, '<', "$DIR/$f") or die "$f: $!";
    my $js = do { local $/; <$fh> };
    while ($js =~ /\{c:\[([^\]]+)\],a:\[/g) {
        my @w = $1 =~ /"([a-z]+)"/g;
        my $n = length $w[-1];
        next if $f eq "climbs.js" && $n != 8;
        if (grep { $blocked{$_} } @w) { $skipped++; next; }
        push @climbs, { id => scalar @climbs, n => $n, w => \@w, top => $w[-1] };
    }
}

# ---------------- difficulty (difficulty.pl, scaled to any length) ----------------
sub dropOne { my ($w, $p) = @_; for my $i (0 .. length($w) - 1) { my $t = $w; substr($t, $i, 1) = ''; return 1 if $t eq $p; } 0 }
my @FEATS = ([hardestLog => 1.0], [bestRankLog => 1.0], [answersLog => -1.0], [insertSteps => -0.6], [easyEnd => -0.4], [onlyOne => 0.6], [rare => 0.3]);
for my $c (@climbs) {
    my @s = @{ $c->{w} }; my $R = @s;
    my %f = map { $_->[0] => 0 } @FEATS;
    for my $i (0 .. $R - 1) {
        my $prev = $i ? $s[$i - 1] : undef;
        my @ans = grep { !$prev || !forbidden($prev, $_) } @{ $ebk{ keyf($s[$i]) } || [] };
        my @common = grep { $rank{$_} } @ans;
        my $best = @common ? (sort { $rank{$a} <=> $rank{$b} } @common)[0] : $s[$i];
        my $bl = log($rank{$best} || 30000);
        $f{bestRankLog} += $bl / $R;
        $f{hardestLog} = $bl if $bl > $f{hardestLog};
        $f{answersLog} += log(1 + @common) / $R;
        $f{onlyOne} += 1 / ($R - 3) if @common <= 1 && $i >= 3;
        if ($i) {
            $f{insertSteps} += 1 / ($R - 1) if grep { dropOne($_, $prev) } @ans;
            $f{easyEnd}     += 1 / ($R - 1) if grep { /(ing|ed|es|er|s)$/ } @common;
        }
    }
    $f{rare} = () = $c->{top} =~ /[jqxzkvwyfb]/g;
    $c->{f} = \%f;
}
my (%mean, %sd);
for my $w (@FEATS) { my $k = $w->[0]; my @v = map { $_->{f}{$k} } @climbs; my $m = 0; $m += $_ / @v for @v;
    my $s = 0; $s += ($_ - $m) ** 2 / @v for @v; $mean{$k} = $m; $sd{$k} = sqrt($s) || 1; }
for my $c (@climbs) { my $t = 0; $t += $_->[1] * ($c->{f}{ $_->[0] } - $mean{ $_->[0] }) / $sd{ $_->[0] } for @FEATS; $c->{raw} = $t; }
# percentile within the same peak length: 0 = easiest of its size, 1 = hardest
my %byN; push @{ $byN{ $_->{n} } }, $_ for @climbs;
for my $n (keys %byN) { my @s = sort { $a->{raw} <=> $b->{raw} } @{ $byN{$n} }; $s[$_]{pct} = @s > 1 ? $_ / $#s : 0.5 for 0 .. $#s; }

# ---------------- themes ----------------
my (%THEME, @TORDER, %HOLIDAY);
{
    open(my $tf, '<:encoding(UTF-8)', "$DIR/themes.txt") or die;
    my $cur;
    while (my $l = <$tf>) {
        $l =~ s/\s+$//;
        next if $l =~ /^\s*(#|$)/;
        if ($l =~ /^\@holiday\s+(\S+)\s+(\S+)/) { $HOLIDAY{$1} = $2; next; }
        if ($l =~ /^==\s*(\w+)\s*\|\s*(.+?)\s*\|\s*(\S+)\s*\|\s*(.+?)\s*$/) {
            $cur = $1; push @TORDER, $cur;
            $THEME{$cur} = { name => $2, emoji => $3, word => $4, words => {} };
            next;
        }
        die "themes.txt: word line before any theme: $l" unless $cur;
        $l =~ s/^\+\d{4}-\d\d-\d\d\s+//;   # "+date" words count from that day (theme-words.js); still theme words here
        for my $w (split ' ', lc $l) { die "themes.txt: '$w' is under 5 letters ($cur)" if length $w < 5; $THEME{$cur}{words}{$w} = 1; }
    }
    for (values %HOLIDAY) { die "themes.txt: holiday theme '$_' doesn't exist" unless $THEME{$_}; }
}
# theme -> peak length -> [climb, theme words in it]
my %cand;
for my $t (@TORDER) {
    my $tw = $THEME{$t}{words};
    for my $c (@climbs) {
        my %seen; my @hit = grep { $tw->{$_} && !$seen{$_}++ } @{ $c->{w} };
        push @{ $cand{$t}{ $c->{n} } }, [$c, \@hit] if @hit;
    }
}

# ---------------- day patterns ----------------
my %PATS = (
    T    => [[7, 8, 8]],
    R    => [[7, 8, 9], [8, 8, 9], [7, 9, 9], [8, 9, 9]],
    Rh   => [[7, 8, 8]],                                    # Ridge by difficulty
    S    => [[8, 9, 10], [9, 9, 10], [7, 9, 10], [8, 8, 10], [9, 10, 10], [8, 10, 10], [7, 8, 10], [7, 10, 10]],
    STAR => [[8, 9, 11], [9, 10, 11], [8, 10, 11], [9, 9, 11], [7, 9, 11], [7, 8, 11], [8, 8, 11], [10, 10, 11]],
);
our $REUSE = 0;
my (%usedCycle, %pairUsed, %themeDays, %themeLast, @days);
my $cycle = 1;
my @cycleStart = (0);

# pick 3 climbs for theme $t with peaks $p; $mode steers difficulty
sub pick {
    my ($t, $p, $mode) = @_;
    my @slots;
    for my $n (@$p) {
        my @c = grep { ($REUSE || !$usedCycle{ $_->[0]{id} }) && !$pairUsed{"$_->[0]{id}|$t"} } @{ $cand{$t}{$n} || [] };
        return undef unless @c;
        if    ($mode eq 'easy') { @c = sort { $a->[0]{pct} <=> $b->[0]{pct} } @c; }
        elsif ($mode eq 'hard') { @c = sort { $b->[0]{pct} <=> $a->[0]{pct} } @c; }
        else                    { @c = shuffle(@c); }
        push @slots, [ @c[0 .. ($#c < 40 ? $#c : 39)] ];
    }
    # search the tallest peak first (scarcest), then the rest
    my @order = sort { $p->[$b] <=> $p->[$a] || $b <=> $a } 0 .. 2;
    my @chosen;
    my $ok = sub {
        my ($new, @have) = @_;
        return 0 if grep { $_->[0]{id} == $new->[0]{id} } @have;
        my %w = map { my $h = $_; map { $_ => 1 } @{ $h->[0]{w} } } @have;
        return 0 if grep { $w{$_} } @{ $new->[0]{w} };            # no word twice in a day
        return 1;
    };
    for my $x (@{ $slots[ $order[0] ] }) {
        for my $y (@{ $slots[ $order[1] ] }) { next unless $ok->($y, $x);
            for my $z (@{ $slots[ $order[2] ] }) { next unless $ok->($z, $x, $y);
                my @pick; $pick[ $order[0] ] = $x; $pick[ $order[1] ] = $y; $pick[ $order[2] ] = $z;
                my $avg = 0; $avg += $_->[0]{pct} / 3 for @pick;
                next if $mode eq 'easy' && $avg >= 0.65;
                next if $mode eq 'hard' && $avg < 0.65;
                return \@pick;
            } } }
    return undef;
}

sub dateOf { my ($i) = @_; my ($y, $m, $d) = split /-/, $START;
    my @t = gmtime(timegm(0, 0, 12, $d, $m - 1, $y) + $i * 86400);
    return sprintf "%04d-%02d-%02d", $t[5] + 1900, $t[4] + 1, $t[3]; }
sub holidayFor { my ($date) = @_; my ($y, $m, $d) = split /-/, $date;
    return $HOLIDAY{"$m-$d"} if $HOLIDAY{"$m-$d"};
    if ($HOLIDAY{thanksgiving} && $m == 11) {             # 4th Thursday
        my $wd = (gmtime(timegm(0, 0, 12, 1, 10, $y)))[6];
        my $first = 1 + (4 - $wd) % 7; return $HOLIDAY{thanksgiving} if $d == $first + 21; }
    return undef; }

# tier schedule state
# The first days ease players in: Trail first, no Summit in the first week,
# and the first ★ day lands about a month in.
my ($trailRun, $lastSummit, $lastStar, $starGap) = (0, -99, -8 - int(rnd() * 6), 36 + int(rnd() * 8));
my %tierCount = (T => 0, R => 0, S => 0);
my %TARGET = (T => 0.6, R => 0.3, S => 0.1);

DAY: for my $i (0 .. $DAYS - 1) {
    my $date = dateOf($i);
    # --- the tier this day wants ---
    my @want;
    if ($i - $lastStar >= $starGap && $i - $lastSummit >= 2) { @want = ('STAR'); }
    else {
        my $n = $i + 1;
        my %deficit = map { $_ => $TARGET{$_} * $n - $tierCount{$_} + rnd() * 0.9 } qw(T R S);
        $deficit{T} = -99 if $trailRun >= 3;
        $deficit{S} = -99 if $i - $lastSummit < 2 || $i < 7;
        $deficit{R} = -99 if $i == 0;
        @want = sort { $deficit{$b} <=> $deficit{$a} } grep { $deficit{$_} > -99 } qw(T R S);
    }
    # fall back through the other tiers if the wanted one can't be built today
    my %seenT; @want = grep { !$seenT{$_}++ } (@want, ($want[0] eq 'STAR' ? qw(S R T) : ()), qw(R T S));
    @want = grep { !($_ eq 'T' && $trailRun >= 3) && !(($_ eq 'S' || $_ eq 'STAR') && $i - $lastSummit < 2) } @want;

    # attempts, in order: the holiday's theme (if any); then for each tier
    # this day wants, themes not used in the last 6 days, then 3; then any
    # theme at all; least-used themes first. A holiday that can't be built
    # from fresh climbs may reuse one from earlier in the cycle.
    my $hol = holidayFor($date);
    my $fresh = sub { my $gap = shift; [ grep { !defined $themeLast{$_} || $i - $themeLast{$_} > $gap } @TORDER ] };
    my @attempts;
    push @attempts, map { [$_, [$hol], 0], [$_, [$hol], 1] } @want if $hol;
    for my $tier (@want) { push @attempts, [$tier, $fresh->(6), 0], [$tier, $fresh->(3), 0]; }
    push @attempts, map { [$_, $fresh->(0), 0] } @want;
    for my $a (@attempts) {
        my ($tier, $pool, $reuse) = @$a;
        local $REUSE = $reuse;
        my @themes = sort { ($themeDays{$a} || 0) <=> ($themeDays{$b} || 0) } shuffle(@$pool);
        for my $t (@themes) {
            my @tries = $tier eq 'T' ? (['T', 'easy']) : $tier eq 'R' ? (['R', 'any'], ['Rh', 'hard']) : ([$tier, 'any']);
            for my $try (@tries) {
                my ($pk, $mode) = @$try;
                for my $p (shuffle(@{ $PATS{$pk} })) {
                    my $got = pick($t, $p, $mode) or next;
                    my $k = $tier eq 'STAR' ? 'S' : $tier;
                    $usedCycle{ $_->[0]{id} } = 1 for @$got;
                    $pairUsed{"$_->[0]{id}|$t"} = 1 for @$got;
                    $themeDays{$t}++; $themeLast{$t} = $i; $tierCount{$k}++;
                    $trailRun = $k eq 'T' ? $trailRun + 1 : 0;
                    $lastSummit = $i if $k eq 'S';
                    if ($tier eq 'STAR') { $lastStar = $i; $starGap = 36 + int(rnd() * 8); }
                    push @days, { d => $date, t => $t, k => $k, star => ($tier eq 'STAR' ? 1 : 0), p => $p, cyc => $cycle,
                                  c => [ map { $_->[0] } @$got ], tw => [ map { $_->[1] } @$got ] };
                    next DAY;
                }
            }
        }
    }
    # nothing fits without repeating a climb: start the next cycle
    if ($i - $cycleStart[-1] < 30) { print "stopped at day $i: not enough climbs left even after a new cycle\n"; last; }
    $cycle++; push @cycleStart, $i; %usedCycle = ();
    redo DAY;
}

# ---------------- write ----------------
my $J = JSON::PP->new->canonical;
open(my $o, '>:encoding(UTF-8)', $OUT) or die "$OUT: $!";
print $o "// Themed daily calendar. Generated by gen-calendar.pl from themes.txt, climbs.js\n";
print $o "// and daily-pool.js - do not hand-edit. days[i] is the puzzle for start + i days.\n";
print $o "// k: T(rail) R(idge) S(ummit); s: 1 on 11-letter days; c: the three reference\n";
print $o "// ladders; w: the theme words in each climb (playing any of them finds it).\n";
print $o "window.DAILY_CALENDAR = {\n";
print $o "start: \"$START\",\n";
print $o "themes: {\n";
print $o join(",\n", map { my $T = $THEME{$_}; "$_: " . $J->encode({ name => $T->{name}, emoji => $T->{emoji}, word => $T->{word} }) } @TORDER), "\n},\n";
print $o "days: [\n";
for my $d (@days) {
    print $o $J->encode({ t => $d->{t}, k => $d->{k}, ($d->{star} ? (s => 1) : ()), c => [ map { $_->{w} } @{ $d->{c} } ], w => $d->{tw} }), ",\n";
}
print $o "]};\n";
close $o;

# data for the preview page (PREVIEW=path)
if ($ENV{PREVIEW}) {
    open(my $pv, '>:encoding(UTF-8)', $ENV{PREVIEW}) or die "$ENV{PREVIEW}: $!";
    my %inClimb; for my $c (@climbs) { $inClimb{$_} = 1 for @{ $c->{w} } }
    print $pv "const CAL = ", $J->encode({ start => $START, cycles => \@cycleStart,
        themes => { map { my $t = $_; my $T = $THEME{$t}; ($t => { name => $T->{name}, emoji => $T->{emoji}, word => $T->{word},
            words => [ sort grep { $inClimb{$_} } keys %{ $T->{words} } ],
            supply => { map { ($_ => scalar @{ $cand{$t}{$_} || [] }) } 7 .. 11 } }) } @TORDER },
        order => \@TORDER,
        days => [ map { my $d = $_; { d => $d->{d}, t => $d->{t}, k => $d->{k}, s => $d->{star}, cyc => $d->{cyc},
            c => [ map { $_->{w} } @{ $d->{c} } ], w => $d->{tw}, pct => [ map { sprintf("%.2f", $_->{pct}) + 0 } @{ $d->{c} } ] } } @days ] }), ";\n";
    close $pv;
}

# ---------------- report ----------------
my %cnt; $cnt{ $_->{k} }++ for @days; my $stars = grep { $_->{star} } @days;
printf "wrote %s: %d days from %s (%d skipped climbs with blocked words)\n", $OUT, scalar @days, $START, $skipped || 0;
printf "cycles start at day %s\n", join(", ", @cycleStart);
my $c1 = @cycleStart > 1 ? $cycleStart[1] : scalar @days;
my @one = @days[0 .. $c1 - 1]; my %c1; $c1{ $_->{k} }++ for @one;
printf "cycle 1: %d days · Trail %d · Ridge %d · Summit %d (★ %d)\n", $c1, $c1{T} || 0, $c1{R} || 0, $c1{S} || 0, scalar grep { $_->{star} } @one;
printf "all: Trail %d · Ridge %d · Summit %d (★ %d)\n", $cnt{T} || 0, $cnt{R} || 0, $cnt{S} || 0, $stars;
my ($run, $maxRun, $bb) = (0, 0, 0); my $prevS = 0;
for my $d (@days) { $run = $d->{k} eq 'T' ? $run + 1 : 0; $maxRun = $run if $run > $maxRun; $bb++ if $d->{k} eq 'S' && $prevS; $prevS = $d->{k} eq 'S'; }
printf "longest Trail run %d · back-to-back Summits %d\n", $maxRun, $bb;
my @sg; my $ls; for my $j (0 .. $#days) { next unless $days[$j]{star}; push @sg, $j - $ls if defined $ls; $ls = $j; }
printf "★ gaps: %s\n", join(" ", @sg);
my %pc; $pc{ join('-', @{ $_->{p} }) }++ for @days;
print "patterns: ", join(", ", map { "$_ $pc{$_}" } sort { $pc{$b} <=> $pc{$a} } keys %pc), "\n";
my %tc; $tc{ $_->{t} }++ for @one;
print "cycle 1 days per theme: ", join(", ", map { "$_ " . ($tc{$_} || 0) } sort { ($tc{$b} || 0) <=> ($tc{$a} || 0) } @TORDER), "\n";
my %used1; $used1{ $_->{n} }++ for map { @{ $_->{c} } } @one;
print "cycle 1 climbs used: ", join(", ", map { "$_-ltr " . ($used1{$_} || 0) . "/" . scalar @{ $byN{$_} } } sort { $a <=> $b } keys %byN), "\n";
my @hd = grep { holidayFor($_->{d}) } @days;
print "holidays: ", join(", ", map { "$_->{d} $_->{t}" . (holidayFor($_->{d}) eq $_->{t} ? "" : " (wanted " . holidayFor($_->{d}) . ")") } @hd), "\n";
