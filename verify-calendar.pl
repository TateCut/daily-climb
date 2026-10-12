use strict;
use warnings;
use JSON::PP;

# Independent check of a daily calendar (doesn't share code with fix-traps.pl or
# gen-calendar.pl). Every day must pass:
#   ladder rules  - 4 letters up, +1 letter a rung, every rung an everyday word,
#                   no rung = the one below + s (or + d/r/n after an -e), no blocklisted word
#   no lockout    - whatever valid word a player picks, the next rung stays solvable
#   no word twice in a day; every climb holds a theme word on one of its rungs
#   no traps      - no step where one word blocks the next step's theme word(s)
#                   while another everyday word on that step would keep them open
#   no repeats    - a climb never comes back with a theme it has had, nor within 60 days
# Same letters count as the same step everywhere (COAST and TACOS match), so a climb that only swaps
# a word for its anagram is still a repeat. From the 6-7-8 start (read from the calendar's header, or
# FORMAT=YYYY-MM-DD), also:
#   shape         - three climbs from 4 letters, peaking at 6, 7 and 8
#   forks         - 3+ steps a day whose letters spell a common theme word and a top-10,000 everyday word
#   spacing       - no step's letters twice in a day; the same first two steps 30+ days apart; the same
#                   peak 60+ days apart and never twice on a theme
# With BASE=<old calendar>, also: past days (before FROM) unchanged, and every
# day keeps its theme, tier and peak lengths.
#
#   perl verify-calendar.pl [calendar.js]      BASE=old.js FROM=2026-10-06 to compare

my $DIR = 'D:/Claude Code/daily-climb';
my $CAL = shift || "$DIR/daily-calendar.js";
sub words { my ($p, $min) = @_; open my $f, '<', $p or die "$p: $!"; my (%w, @o);
    while (<$f>) { s/\s+$//; next unless /^[a-z]+$/; next if length($_) < ($min || 3); push @o, $_ unless $w{$_}++; } (\%w, \@o) }
my ($every, $everyOrder) = words("$DIR/freq.js");
my %rank; { my $r = 0; $rank{$_} = ++$r for @$everyOrder }   # 3+ letter words, most common first
# "common": everyday, and for 4-6 letter words one of the top 12,000 (SHORTMAX)
sub common { my ($w) = @_; $rank{$w} && (length($w) > 6 || $rank{$w} <= ($ENV{SHORTMAX} || 12000)) }
my ($all)   = words("$DIR/words.js");
my %block; if (open my $b, '<', "$DIR/climb-blocklist.txt") { while (<$b>) { s/#.*//; s/\s+//g; $block{lc $_} = 1 if length } }
sub key { join '', sort split //, $_[0] }
my %ana; push @{ $ana{ key($_) } }, $_ for keys %$all;
sub cheap { my ($p, $w) = @_; $w eq "${p}s" || ($p =~ /e$/ && ($w eq "${p}d" || $w eq "${p}r" || $w eq "${p}n")) }
my %game; { open my $f, '<', "$DIR/theme-words.js" or die; while (<$f>) { $game{$1} = { map { $_ => 1 } split ' ', $2 } if /^(\w+): "([^"]*)"/ } }
my %list; { open my $f, '<:encoding(UTF-8)', "$DIR/themes.txt" or die; my $t;
    while (<$f>) { s/\s+$//; next if /^\s*(#|$)/ || /^\@/; if (/^==\s*(\w+)\s*\|/) { $t = $1; next } $list{$t}{$_} = 1 for grep { length >= 5 } split ' ', lc } }

my $FORMAT = $ENV{FORMAT};
sub load { my ($p) = @_; open my $f, '<:encoding(UTF-8)', $p or die "$p: $!"; my ($start, @d);
    while (<$f>) { $start = $1 if /^start: "([\d-]+)"/; $FORMAT //= $1 if /Days from (\d{4}-\d\d-\d\d) on are the 6-7-8 format/;
        push @d, JSON::PP->new->decode($1) if /^(\{.*\}),\s*$/ } ($start, \@d) }
my ($start, $days) = load($CAL);
$FORMAT //= '9999-12-31';
my $RULES = $ENV{RULES} || '2026-10-11'; $RULES = $FORMAT if $FORMAT lt $RULES;
my (%start2, %lastPeak, %peakTheme);   # first 2 steps' letters -> last day; peak letters -> last day; theme|peak letters
my ($y, $m, $dd) = split /-/, $start;
use Time::Local;
sub date { my @t = gmtime(timegm(0, 0, 12, $dd, $m - 1, $y) + $_[0] * 86400); sprintf "%04d-%02d-%02d", $t[5] + 1900, $t[4] + 1, $t[3] }

my @err; my $err = sub { push @err, date($_[0]) . " $_[1]" };
my %seen;   # ladder -> [day, theme]
my (%lastTW, %start3);   # theme|word -> last day it was a theme word; first 3 rungs -> days
for my $i (0 .. $#$days) {
    my $d = $days->[$i]; my %dayw;
    for my $j (0 .. 2) {
        my @c = @{ $d->{c}[$j] }; my $tag = "climb " . ($j + 1) . " (" . join(' ', @c) . ")";
        $err->($i, "$tag doesn't start at 4 letters") unless length $c[0] == 4;
        for my $k (0 .. $#c) {
            my $w = $c[$k];
            $err->($i, "$tag: $w isn't an everyday word") unless $every->{$w};
            $err->($i, "$tag: $w is blocklisted") if $block{$w};
            $err->($i, "$tag: $w appears twice today") if $dayw{$w}++;
            next unless $k;
            my %h; $h{$_}++ for split //, $w; $h{$_}-- for split //, $c[$k - 1];
            my @x = grep { $h{$_} } keys %h;
            $err->($i, "$tag: $c[$k-1] -> $w isn't +1 letter") unless @x == 1 && $h{ $x[0] } == 1;
            $err->($i, "$tag: $c[$k-1] -> $w is a cheap step") if cheap($c[$k - 1], $w);
        }
        # lockout
        my %reach = map { $_ => 1 } @{ $ana{ key($c[0]) } || [] };
        for my $k (1 .. $#c) { my @w = @{ $ana{ key($c[$k]) } || [] }; my %n;
            for my $p (keys %reach) { my @ok = grep { !cheap($p, $_) } @w; unless (@ok) { $err->($i, "$tag: lockout after $p"); last } $n{$_} = 1 for @ok }
            %reach = %n; }
        # theme word on a rung
        my @tw = @{ $d->{w}[$j] || [] };
        $err->($i, "$tag has no theme word") unless @tw;
        for my $t (@tw) { my %r = map { $_ => 1 } @c; $err->($i, "$tag: theme word $t isn't a rung") unless $r{$t}; }
        # traps
        my %th = (%{ $game{ $d->{t} } || {} }, map { $_ => 1 } @tw);
        for my $k (0 .. $#c - 1) {
            my @next = grep { $th{$_} } @{ $ana{ key($c[$k + 1]) } || [] }; next unless @next;
            my @here = @{ $ana{ key($c[$k]) } || [] };
            my @blk = grep { my $p = $_; !grep { !cheap($p, $_) } @next } @here;
            my @opn = grep { my $p = $_; common($p) && grep { !cheap($p, $_) } @next } @here;   # an obscure word isn't a real choice
            $err->($i, "$tag: TRAP " . join('/', @blk) . " blocks " . join('/', @next)) if @blk && @opn;
        }
        # repeats (by letters)
        my $lk = join ',', map { key($_) } @c;
        for my $prev (@{ $seen{$lk} || [] }) {
            $err->($i, "$tag repeats with the same theme as " . date($prev->[0])) if $prev->[1] eq $d->{t};
            $err->($i, "$tag repeats within 60 days of " . date($prev->[0])) if $i - $prev->[0] < 60;
        }
        push @{ $seen{$lk} }, [$i, $d->{t}];
        # near repeats (from RULES, default 2026-10-11): the same theme word again within 30 days, or a climb
        # starting with the same first 3 words as one within 60 days (a different last word isn't a new climb)
        my $new = date($i) ge $FORMAT;
        if (date($i) ge $RULES) {
            for my $w (@c) { $err->($i, "$tag: RARE-STEP $w isn't a common word (short steps must be top 12,000)") unless common($w) }
            for my $t (@tw) { my $p = $lastTW{"$d->{t}|$t"};
                $err->($i, "$tag: SAME-WORD theme word $t again after " . ($i - $p) . " days") if defined $p && $p != $i && $i - $p < 30; }
            if (@c >= 3) { my $pk = join ' ', map { key($_) } @c[0 .. 2];
                for my $p (@{ $start3{$pk} || [] }) { $err->($i, "$tag: SAME-START as " . date($p) . " (" . ($i - $p) . " days)") if $p != $i && $i - $p < 60 } }
        }
        if ($new) {
            $err->($i, "$tag: SHAPE should peak at " . (6 + $j) . " letters") unless length $c[-1] == 6 + $j && @c == 3 + $j;
            my $s2 = join ' ', map { key($_) } @c[0, 1]; my $p2 = $start2{$s2};
            $err->($i, "$tag: SAME-START2 first two steps as " . date($p2) . " (" . ($i - $p2) . " days)") if defined $p2 && $i - $p2 < 30;
            my $pk = key($c[-1]); my $pp = $lastPeak{$pk};
            $err->($i, "$tag: SAME-PEAK as " . date($pp) . " (" . ($i - $pp) . " days)") if defined $pp && $i - $pp < 60;
            $err->($i, "$tag: SAME-PEAK again on this theme") if $peakTheme{"$d->{t}|$pk"};
        }
        $lastTW{"$d->{t}|$_"} = $i for @tw;
        push @{ $start3{ join ' ', map { key($_) } @c[0 .. 2] } }, $i if @c >= 3;
        $start2{ join ' ', map { key($_) } @c[0, 1] } = $i; $lastPeak{ key($c[-1]) } = $i; $peakTheme{ "$d->{t}|" . key($c[-1]) } = 1;
    }
    # forks: steps whose letters spell a common theme word AND a top-10,000 word that isn't one
    # (from RULES at least one a day; from the 6-7-8 start, 3 or more; and no step's letters twice in a day)
    if (date($i) ge $RULES) {
        my ($forks, %keys) = (0);
        for my $j (0 .. $#{ $d->{c} }) {
            my %th = (%{ $game{ $d->{t} } || {} }, map { $_ => 1 } @{ $d->{w}[$j] || [] });
            my @reach;   # only words you could actually play count (no cheap step from a playable word on the step before)
            for my $r (@{ $d->{c}[$j] }) { my @all = @{ $ana{ key($r) } || [] };
                my @play = @reach ? grep { my $w = $_; grep { !cheap($_, $w) } @reach } @all : @all;
                my @a = grep { !$block{$_} } @play;
                $err->($i, "SAME-LETTERS $r: these letters are a step twice today") if date($i) ge $FORMAT && $keys{ key($r) }++;
                $forks++ if (grep { $th{$_} && common($_) } @a) && (grep { !$th{$_} && $rank{$_} && $rank{$_} <= 10000 } @a);
                @reach = @play }
        }
        my $need = date($i) ge $FORMAT ? 3 : 1;
        $err->($i, "NO-CHOICE: only $forks fork(s) in the trail, needs $need") if $forks < $need;
    }
}
if ($ENV{BASE}) {
    my (undef, $old) = load($ENV{BASE}); my $from = $ENV{FROM} || '2026-10-06';
    for my $i (0 .. $#$old) {
        my ($a, $b) = ($old->[$i], $days->[$i]);
        if (date($i) lt $from) { my $cj = JSON::PP->new->canonical; push @err, date($i) . " changed but is before $from" if $cj->encode($a) ne $cj->encode($b); next }
        push @err, date($i) . " theme/tier changed" if $a->{t} ne $b->{t} || $a->{k} ne $b->{k};
        push @err, date($i) . " peak lengths changed" if join(',', map { length $_->[-1] } @{ $a->{c} }) ne join(',', map { length $_->[-1] } @{ $b->{c} });
    }
    push @err, "day count changed" if @$old != @$days;
}
my $nTrap = grep { /TRAP/ } @err; my $nSW = grep { /SAME-WORD/ } @err; my $nSS = grep { /SAME-START/ } @err;
my $nRS = grep { /RARE-STEP/ } @err; my $nNC = grep { /NO-CHOICE/ } @err;
my $n678 = grep { /SHAPE|SAME-START2|SAME-PEAK|SAME-LETTERS/ } @err;
printf "%s: %d days, %d problems (%d traps, %d theme words back within 30 days, %d same starts within 60 days, %d rare short steps, %d days short on forks, %d 6-7-8 shape/spacing)\n",
    $CAL, scalar @$days, scalar @err, $nTrap, $nSW, $nSS, $nRS, $nNC, $n678;
print "  6-7-8 format from $FORMAT\n" if $FORMAT ne '9999-12-31';
print "  $_\n" for $ENV{ALL} ? @err : @err[0 .. ($#err < 40 ? $#err : 39)];   # ALL=1 prints every problem
exit(@err ? 1 : 0);
