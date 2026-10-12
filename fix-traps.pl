use strict;
use warnings;
use utf8;
use JSON::PP;
use Time::Local;
binmode STDOUT, ':encoding(UTF-8)';

# Removes "theme-word traps" from the FUTURE days of daily-calendar.js, leaving
# past days (and any day that may already be in play) exactly as they are.
#
# A trap: on some step of a climb, one word you can legally play (an anagram of
# that rung, when another word also fits) makes the theme word(s) on the next step unplayable, because each
# of them is just that word + s (or + d/r/n after an -e): STABLE blocks STABLED,
# PLEASE blocks PLEASED, RACE blocks RACER. Nobody can see the next letter, so
# whether you lose a theme point comes down to luck.
#
# Each trapped climb is swapped for a trap-free one with the same theme and peak
# length, the nearest difficulty, no word shared with the day's other climbs,
# and never a climb this theme has used before or one used within 60 days.
# The day's theme, tier and peaks stay the same.
#
#   perl fix-traps.pl                  dry run: writes the report only
#   WRITE=1 perl fix-traps.pl          also rewrites daily-calendar.js
#   FROM=2026-10-06                    first day that may change (default)
#   DEADENDS=1                         also fix dead ends (below); REPORT=name.json for its report
#   BLOCKED=1                          also swap climbs using a word added to climb-blocklist.txt since
#   STRONG=theme=w1,w2,...             swap that theme's climbs whose theme words aren't among w1.. (rework a weak theme)
#
# A dead end: an everyday word you can play on some step (STAR) after which every everyday
# word on the next step is blocked (STARS is just STAR + s), leaving only unusual ones (TSARS,
# TRASS). Never impossible, but it feels it. With DEADENDS=1 those climbs are swapped too, and
# no replacement may have a trap or a dead end.
#
# Shares the climb loading, difficulty and theme code with gen-calendar.pl.

my $DIR   = 'D:/Claude Code/daily-climb';
my $START = "2026-09-29";

my $SEED  = $ENV{SEED}  || 1;


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
# "common": an everyday word, and for the short steps (4-6 letters) one of the top SHORTMAX (12,000) -
# the bottom of the list is full of words few people know (LAIRD, TOSH), fine high on a climb, not low down
my $SHORTMAX = $ENV{SHORTMAX} || 12000;
sub common { my ($w) = @_; $rank{$w} && (length($w) > 6 || $rank{$w} <= $SHORTMAX) }
sub rareSteps { grep { !common($_) } @{ $_[0] } }
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
        for my $w (split ' ', lc $l) { next if length $w < 5;   # 4-letter theme words score in the game but don't pick climbs
$THEME{$cur}{words}{$w} = 1; }
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

# ---------------- the game's theme-word lists (what actually scores) ----------------
my %GAMEWORDS;
{
    open(my $fh, '<', "$DIR/theme-words.js") or die;
    while (<$fh>) { $GAMEWORDS{$1} = { map { $_ => 1 } split ' ', $2 } if /^(\w+): "([^"]*)"/; }
}

# ---------------- the current calendar ----------------
my $CALF = "$DIR/daily-calendar.js";
open(my $cf, '<:encoding(UTF-8)', $CALF) or die;
my @lines = <$cf>; close $cf;
my $J = JSON::PP->new->canonical;
my (@days, @dayLine);
for my $n (0 .. $#lines) { next unless $lines[$n] =~ /^(\{.*\}),\s*$/; push @days, $J->decode($1); push @dayLine, $n; }
sub dateOf { my ($i) = @_; my ($y, $m, $d) = split /-/, $START;
    my @t = gmtime(timegm(0, 0, 12, $d, $m - 1, $y) + $i * 86400); sprintf "%04d-%02d-%02d", $t[5] + 1900, $t[4] + 1, $t[3]; }
my $FROM = $ENV{FROM} || '2026-10-06';
my $from = 0; $from++ while $from < @days && dateOf($from) lt $FROM;

# ---------------- traps ----------------
# [step, blocker, [blocked theme words]] for every trap in a ladder
sub traps {
    my ($ladder, $theme) = @_;
    my @out;
    for my $k (0 .. $#$ladder - 1) {
        my @next = grep { $theme->{$_} } @{ $ebk{ keyf($ladder->[$k + 1]) } || [] };
        next unless @next;
        my @here = @{ $ebk{ keyf($ladder->[$k]) } || [$ladder->[$k]] };
        my @block = grep { my $p = $_; !grep { !forbidden($p, $_) } @next } @here;
        # Only a trap if there was a choice: another word on this step keeps the theme word open.
        # (If the blocker is the only word that fits, everyone plays it and nobody is out-guessed.)
        my @open = grep { my $p = $_; grep { !forbidden($p, $_) } @next } @here;
        @open = grep { common($_) } @open unless $ENV{ANYOPEN};   # an obscure word (MACER for CREAM) isn't a real choice
        next unless @block && @open;
        push @out, [$k + 1, $_, \@next] for @block;
    }
    return @out;
}
# [step, everyday word, [what's left on the next step]] for every dead end in a ladder
sub deadends {
    my ($ladder) = @_;
    my @out;
    for my $k (0 .. $#$ladder - 1) {
        my @here = grep { $rank{$_} } @{ $ebk{ keyf($ladder->[$k]) } || [] };
        my @next = @{ $ebk{ keyf($ladder->[$k + 1]) } || [] };
        for my $p (@here) {
            my @ok = grep { !forbidden($p, $_) } @next;
            push @out, [$k + 1, $p, \@ok] unless grep { common($_) } @ok;
        }
    }
    return @out;
}
# every word a player could type on each rung: [word, everyday?, theme word?] (for the report's path explorer)
sub stepsOf { my ($lad, $ts) = @_; [ map { [ map { [$_, $rank{$_} ? 1 : 0, $ts->{$_} ? 1 : 0] } sort @{ $ebk{ keyf($_) } || [$_] } ] } @$lad ] }
sub themeSetFor { my ($t, $w) = @_; my %s = %{ $GAMEWORDS{$t} || {} }; $s{$_} = 1 for @$w; \%s }

# ---------------- new climbs (option A) ----------------
# When no existing climb fits, build fresh ones the way gen-daily-pool.pl does
# (everyday words from 4 letters up, +1 letter a rung, no forbidden step, no
# blocklisted word, no lockout) but through one of the theme's words and along
# other routes than the pool's single "most common" one. Daily-only: they're
# written into the calendar, not into climbs.js or daily-pool.js.
my (%okE, %predE, %succE, @byLenE);
{
    my %ev = map { $_ => 1 } grep { !$blocked{$_} && common($_) } keys %$freq;
    push @{ $byLenE[ length $_ ] }, $_ for keys %ev;
    my %fk; push @{ $fk{ keyf($_) } }, $_ for keys %ev;
    $okE{$_} = 1 for @{ $byLenE[4] || [] };
    for my $k (5 .. 11) {
        for my $L (@{ $byLenE[$k] || [] }) {
            my $key = keyf($L); my %seenc; my @ch = split //, $key;
            for my $x (0 .. $#ch) { next if $seenc{ $ch[$x] }++; my $sub = $key; substr($sub, $x, 1) = '';
                for my $S (@{ $fk{$sub} || [] }) { next unless $okE{$S} && !forbidden($S, $L); $okE{$L} = 1; push @{ $predE{$L} }, $S; push @{ $succE{$S} }, $L; } }
        }
    }
}
sub byRank { sort { ($rank{$a} || 1e9) <=> ($rank{$b} || 1e9) || $a cmp $b } @_ }
sub downChains { my ($w) = @_; return ([$w]) if length $w == 4;
    map { my $p = $_; map { [@$_, $w] } downChains($p) } grep { defined } (byRank(@{ $predE{$w} || [] }))[0 .. ($ENV{DOWNK} || 3) - 1] }
sub upChains { my ($w, $n) = @_; return ([$w]) if length $w == $n;
    map { my $s = $_; map { [$w, @$_] } upChains($s, $n) } grep { defined } (byRank(@{ $succE{$w} || [] }))[0 .. ($ENV{UPK} || 4) - 1] }
sub lockout {
    my @c = @_;
    my %reach = map { $_ => 1 } @{ $ebk{ keyf($c[0]) } || [] };
    for my $i (1 .. $#c) {
        my @words = @{ $ebk{ keyf($c[$i]) } || [] }; my %next;
        for my $p (keys %reach) { my @okw = grep { !forbidden($p, $_) } @words; return 1 unless @okw; $next{$_} = 1 for @okw; }
        %reach = %next;
    }
    0;
}
# the calendar's difficulty score for any ladder, as a percentile among climbs of its length
sub pctOf {
    my @s = @_; my $R = @s; my %f = map { $_->[0] => 0 } @FEATS;
    for my $i (0 .. $R - 1) {
        my $prev = $i ? $s[$i - 1] : undef;
        my @ans = grep { !$prev || !forbidden($prev, $_) } @{ $ebk{ keyf($s[$i]) } || [] };
        my @common = grep { $rank{$_} } @ans;
        my $best = @common ? (sort { $rank{$a} <=> $rank{$b} } @common)[0] : $s[$i];
        my $bl = log($rank{$best} || 30000);
        $f{bestRankLog} += $bl / $R; $f{hardestLog} = $bl if $bl > $f{hardestLog};
        $f{answersLog} += log(1 + @common) / $R;
        $f{onlyOne} += 1 / ($R - 3) if @common <= 1 && $i >= 3;
        if ($i) { $f{insertSteps} += 1 / ($R - 1) if grep { dropOne($_, $prev) } @ans;
                  $f{easyEnd} += 1 / ($R - 1) if grep { /(ing|ed|es|er|s)$/ } @common; }
    }
    $f{rare} = () = $s[-1] =~ /[jqxzkvwyfb]/g;
    my $raw = 0; $raw += $_->[1] * ($f{ $_->[0] } - $mean{ $_->[0] }) / $sd{ $_->[0] } for @FEATS;
    my @pool = @{ $byN{ length $s[-1] } || [] }; return 0.5 unless @pool;
    my $below = grep { $_->{raw} < $raw } @pool; return $below / @pool;
}
my %newCache;
sub newClimbs {
    my ($t, $n) = @_;
    return @{ $newCache{"$t|$n"} } if $newCache{"$t|$n"};
    my (%seen, @out);
    for my $w (sort grep { length $_ <= $n && length $_ >= 5 && $okE{$_} } keys %{ $THEME{$t}{words} }) {
        my @down = downChains($w); my @up = upChains($w, $n); my $made = 0;
        for my $dn (@down) { for my $u (@up) {
            my @lad = (@$dn, @$u[1 .. $#$u]);
            next unless @lad == $n - 3;
            my $key = join(',', @lad); next if $seen{$key}++;
            next if lockout(@lad);
            my %sh; my @hits = grep { $THEME{$t}{words}{$_} && !$sh{$_}++ } @lad;
            push @out, [ { w => \@lad, n => $n, pct => pctOf(@lad), gen => 1 }, \@hits ];
            last if ++$made >= ($ENV{MADE} || 40);
        } last if $made >= ($ENV{MADE} || 40); }
    }
    $newCache{"$t|$n"} = \@out;
    return @out;
}

# ---------------- swap ----------------
my %byKey = map { join(',', @{ $_->{w} }) => $_ } @climbs;
my %usedAt;   # ladder -> day indices using it
for my $i (0 .. $#days) { push @{ $usedAt{ join(',', @$_) } }, $i for @{ $days[$i]{c} }; }
my %taken;
my (@report, $swapped, $stuck);
my ($strongT, %strong) = ('');
if (($ENV{STRONG} || '') =~ /^(\w+)=(.+)$/) { $strongT = $1; %strong = map { $_ => 1 } split /,/, $2; }
# A real choice at a theme word: some step's letters spell a theme word AND a common non-theme word
# (top CHOICERANK everyday words, not blocklisted), so spotting the theme word is what earns the point.
my $CHOICERANK = $ENV{CHOICERANK} || 10000;
my $UNTIL = $ENV{UNTIL} || '9999-12-31';
my %NOCHOICE = map { $_ => 1 } split /,/, ($ENV{CHOICEEXCLUDE} || '');   # theme words that don't count as the choice (too weak for the theme)
sub hasChoice {
    my ($ladder, $ts) = @_;
    for my $w (@$ladder) {
        my @c = grep { !$blocked{$_} } @{ $ebk{ keyf($w) } || [] };
        # the theme word in the choice must be a common word too (a step word could be); its rival a top-10,000 word
        return 1 if (grep { $ts->{$_} && !$NOCHOICE{$_} && common($_) } @c) && (grep { !$ts->{$_} && $rank{$_} && $rank{$_} <= $CHOICERANK } @c);
    }
    0;
}
sub dayHasChoice { my ($d) = @_; grep { hasChoice($d->{c}[$_], themeSetFor($d->{t}, $d->{w}[$_])) } 0 .. 2 }
# RULES=YYYY-MM-DD: from that day on, also no near repeats: a theme word back on its theme within
# 30 days, or a climb starting with the same first 3 words as one within 60 days.
my $RULESFROM = $ENV{RULES} || '';
sub near {
    my ($i, $lad, $hits, $t) = @_;
    return () unless $RULESFROM && dateOf($i) ge $RULESFROM;
    # starts compare by letters: COAST and TACOS are the same step
    my @p; my $s3 = join(' ', map { keyf($_) } @$lad[0 .. 2]); my %h = map { $_ => 1 } @$hits;
    for my $q (($i > 59 ? $i - 59 : 0) .. $i - 1) {
        my $e = $days[$q];
        for my $x (0 .. 2) { push @p, "same start as " . dateOf($q) if join(' ', map { keyf($_) } @{ $e->{c}[$x] }[0 .. 2]) eq $s3 }
        if ($ENV{NEAR2} && $i - $q < $ENV{NEAR2}) { my $s2 = join(' ', map { keyf($_) } @$lad[0 .. 1]); for my $x (0 .. 2) { push @p, "same first two steps as " . dateOf($q) if join(' ', map { keyf($_) } @{ $e->{c}[$x] }[0 .. 1]) eq $s2 } }   # NEAR2=14: the first 2 steps' letters not again within 14 days
        next unless $i - $q < 30 && $e->{t} eq $t;
        for my $w (map { @$_ } @{ $e->{w} }) { push @p, "theme word $w again (" . dateOf($q) . ")" if $h{$w} }
    }
    @p;
}
# every replacement that would be fine as climb $j of day $i (pool climbs and newly built ones)
sub fitting {
    my ($i, $j, $needChoice) = @_;
    my $d = $days[$i]; my $lad = $d->{c}[$j];
    my %dayWords = map { my $x = $_; $x == $j ? () : map { $_ => 1 } @{ $d->{c}[$x] } } 0 .. 2;
    my $ok = sub {
        my ($c, $hits) = @{ $_[0] }; my $key = join(',', @{ $c->{w} });
        # a climb may come back, but never with a theme it has had, nor within 60 days of another use
        @$hits && !(grep { $days[$_]{t} eq $d->{t} || abs($_ - $i) < ($ENV{REUSEDAYS} || 60) } @{ $usedAt{$key} || [] })
          && !$taken{$key} && !(grep { $dayWords{$_} } @{ $c->{w} })
          && !(grep { $blocked{$_} } @{ $c->{w} })
          && !traps($c->{w}, themeSetFor($d->{t}, $hits))
          && !(($ENV{DEADENDS} || $RULESFROM) && deadends($c->{w}))
          && !($d->{t} eq $strongT && !grep { $strong{$_} } @$hits)
          && !near($i, $c->{w}, $hits, $d->{t})
          && !($RULESFROM && rareSteps($c->{w}))
          && (!$needChoice || hasChoice($c->{w}, themeSetFor($d->{t}, $hits)))
    };
    my @pool = grep { $ok->($_) } @{ $cand{ $d->{t} }{ length $lad->[-1] } || [] };
    return @pool if @pool && !$RULESFROM && !$needChoice;
    return (@pool, $ENV{NOGEN} ? () : grep { $ok->($_) } newClimbs($d->{t}, length $lad->[-1]));
}
sub swapIn {
    my ($i, $j, $best, $rec, $oldPct) = @_;
    my $d = $days[$i];
    $taken{ join(',', @{ $best->[0]{w} }) } = 1;
    push @{ $usedAt{ join(',', @{ $best->[0]{w} }) } }, $i;
    $d->{c}[$j] = $best->[0]{w}; $d->{w}[$j] = $best->[1];
    @$rec{qw(new newW oldPct newPct)} = ($best->[0]{w}, $best->[1], sprintf("%.2f", $oldPct) + 0, sprintf("%.2f", $best->[0]{pct}) + 0);
    $rec->{built} = 1 if $best->[0]{gen};
    $rec->{newSteps} = stepsOf($best->[0]{w}, themeSetFor($d->{t}, $best->[1]));
    $swapped++;
}
sub pctNow { my ($lad) = @_; my $o = $byKey{ join(',', @$lad) }; $o ? $o->{pct} : pctOf(@$lad) }
my $byDiff = sub { my ($p) = @_; sort { abs($a->[0]{pct} - $p) <=> abs($b->[0]{pct} - $p) } @_[1 .. $#_] };
for my $i ($from .. $#days) {
    my $d = $days[$i];
    for my $j (0 .. 2) {
        my $lad = $d->{c}[$j];
        my @tr = traps($lad, themeSetFor($d->{t}, $d->{w}[$j]));
        my @de = ($ENV{DEADENDS} || $RULESFROM) ? deadends($lad) : ();
        my @bl = ($ENV{BLOCKED} || $RULESFROM) ? grep { $blocked{$_} } @$lad : ();
        my $weak = $d->{t} eq $strongT && !grep { $strong{$_} } @{ $d->{w}[$j] || [] };
        my @nr = near($i, $lad, $d->{w}[$j], $d->{t});
        my @rs = $RULESFROM && dateOf($i) ge $RULESFROM ? rareSteps($lad) : ();
        next unless @tr || @de || @bl || $weak || @nr || @rs;
        my $oldPct = pctNow($lad);
        my @c = fitting($i, $j, 0);
        my $rec = { day => dateOf($i), theme => $THEME{ $d->{t} }{name}, tier => $d->{k}, climb => $j + 1,
                    old => $lad, oldW => $d->{w}[$j], oldSteps => stepsOf($lad, themeSetFor($d->{t}, $d->{w}[$j])), traps => [ map { { step => $_->[0], word => $_->[1], blocks => $_->[2] } } @tr ],
                    dead => [ map { { step => $_->[0], word => $_->[1], left => $_->[2] } } @de ], blocked => \@bl, weak => $weak ? 1 : 0, near => \@nr };
        if (@c) { swapIn($i, $j, ($byDiff->($oldPct, @c))[0], $rec, $oldPct) }
        else {
            $rec->{stuck} = 1; $stuck++;
            # fallback check: the theme words this climb keeps if the blocked ones stop scoring that day
            my $ts = themeSetFor($d->{t}, $d->{w}[$j]); my %blk = map { map { $_ => 1 } @{ $_->[2] } } @tr; my %seen;
            $rec->{left} = [ grep { $ts->{$_} && !$blk{$_} && !$seen{$_}++ } map { @{ $ebk{ keyf($_) } || [$_] } } @$lad ];
        }
        push @report, $rec;
    }
    # CHOICE=1: a day with no choice step (through UNTIL) gets one climb swapped for the nearest-difficulty one that has it
    if ($ENV{CHOICE} && dateOf($i) le $UNTIL && !dayHasChoice($d)) {
        my @opts;
        for my $j (0 .. 2) {
            my $oldPct = pctNow($d->{c}[$j]);
            my @c = $byDiff->($oldPct, fitting($i, $j, 1)) or next;
            if ($ENV{CHOICELIST}) { printf "OPTION %s climb %d (old %.2f): %s | theme %s | pct %.2f\n", dateOf($i), $j + 1, $oldPct,
                join(' ', @{ $_->[0]{w} }), join('/', @{ $_->[1] }), $_->[0]{pct} for @c[0 .. ($#c < 3 ? $#c : 3)]; }
            push @opts, [$j, $c[0], abs($c[0][0]{pct} - $oldPct), $oldPct];
        }
        my $rec = { day => dateOf($i), theme => $THEME{ $d->{t} }{name}, tier => $d->{k}, reason => 'choice' };
        if (my ($o) = sort { $a->[2] <=> $b->[2] } @opts) {
            my ($j, $best, undef, $oldPct) = @$o;
            @$rec{qw(climb old oldW oldSteps)} = ($j + 1, $d->{c}[$j], $d->{w}[$j], stepsOf($d->{c}[$j], themeSetFor($d->{t}, $d->{w}[$j])));
            swapIn($i, $j, $best, $rec, $oldPct);
        } else { $rec->{stuck} = 1; $stuck++; }
        push @report, $rec;
    }
}

# ---------------- out ----------------
my %daysHit = map { $_->{day} => 1 } @report;
open(my $rp, '>:encoding(UTF-8)', "$DIR/../daily-climb-beta-tools/" . ($ENV{REPORT} || "traps-report.json")) or die;
print $rp JSON::PP->new->canonical->pretty->encode({ from => $FROM, daysChecked => @days - $from, daysAffected => scalar keys %daysHit,
    climbsSwapped => $swapped || 0, climbsStuck => $stuck || 0, swaps => \@report });
close $rp;
printf "checked %d days from %s: %d days affected, %d climbs swapped, %d with no trap-free replacement\n",
    @days - $from, $FROM, scalar keys %daysHit, $swapped || 0, $stuck || 0;
if ($ENV{WRITE}) {
    $lines[ $dayLine[$_] ] = $J->encode($days[$_]) . ",\n" for $from .. $#days;
    open(my $o, '>:encoding(UTF-8)', $CALF) or die; print $o @lines; close $o;
    print "rewrote $CALF\n";
}
