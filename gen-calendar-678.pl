use strict;
use warnings;
use JSON::PP;
use Time::Local;
binmode STDOUT, ':encoding(UTF-8)';

# Builds the Daily Climb calendar in the 6-7-8 format: from FROM on, every day is one theme and three climbs that
# peak at 6, 7 and 8 letters, with at least K "forks in the trail" across the day (steps whose letters spell a
# common theme word and a top-10,000 everyday word). Days before FROM are kept exactly as they are and count as
# history for every rule below.
#
#   FROM=2026-10-10 perl gen-calendar-678.pl                     dry run: prints what it would build
#   FROM=2026-10-10 WRITE=1 perl gen-calendar-678.pl             rewrites daily-calendar.js
#   CAL=path OUT=path                                            read one calendar, write another (default: both daily-calendar.js)
#   K=3                                                          forks per day (default 3)
#
# Every climb: 4 letters up, +1 letter a step, everyday words (4-6 letters in the top 12,000), nothing from
# climb-blocklist.txt, no cheap step (+s, or +d/r/n after -e), no lockout, no dead end, no trap, and a 5+ letter
# theme word on the ladder. Across days (same letters count as the same step, so COAST and TACOS match):
#   - no step's letters twice in a day
#   - the same first two steps 30+ days apart, the same first three 60+ days apart
#   - the same peak 60+ days apart, and never twice on one theme
#   - a theme word back on its theme 30+ days apart
# Themes: each day takes the theme unused the longest that can still make a valid day (never two days running);
# a theme with nothing left drops out. The calendar ends where no theme can make a day.

my $DIR  = 'D:/Claude Code/daily-climb';
my $FROM = $ENV{FROM} or die "set FROM=YYYY-MM-DD (the first 6-7-8 day)\n";
my $CAL  = $ENV{CAL} || "$DIR/daily-calendar.js";
my $OUT  = $ENV{OUT} || $CAL;
my $K    = $ENV{K} // 3;
my $SHORTMAX = 12000; my $CHOICERANK = 10000; my $ROUTES = 40; my $MAXK = 3;
my @PEAKS = (6, 7, 8);

sub key { join '', sort split //, $_[0] }
sub cheap { my ($s, $l) = @_; return 1 if $l eq "${s}s"; $s =~ /e$/ && ($l eq "${s}d" || $l eq "${s}r" || $l eq "${s}n") }
sub loadw { my $p = shift; open my $fh, '<', $p or die "$p: $!"; my (%w, @o); while (my $l = <$fh>) { $l =~ s/\s+$//; next unless $l =~ /^[a-z]+$/; my $n = length $l; next if $n < 3 || $n > 15; push @o, $l unless $w{$l}++ } (\%w, \@o) }
my (undef, $forder) = loadw("$DIR/freq.js"); my ($game) = loadw("$DIR/words.js");
my %rank; my $r = 0; $rank{$_} = ++$r for @$forder;
my %block; { open my $bf, '<', "$DIR/climb-blocklist.txt" or die; while (<$bf>) { s/#.*//; s/\s+//g; $block{ lc $_ } = 1 if length } }
sub common { my $w = shift; $rank{$w} && (length($w) > 6 || $rank{$w} <= $SHORTMAX) }
my %cm = map { $_ => 1 } grep { my $L = length $_; $game->{$_} && !$block{$_} && $L >= 4 && $L <= 8 && common($_) } keys %rank;
my (%G, %C, @by); push @{ $G{ key($_) } }, $_ for keys %$game; push @{ $C{ key($_) } }, $_ for keys %cm; push @{ $by[ length $_ ] }, $_ for keys %cm;

# a step is safe if every word you could type leaves a word to play next (no lockout), and every everyday word
# leaves an everyday word (no dead end)
my %safeC;
sub safe { my ($ka, $kb) = @_; my $k = "$ka>$kb"; return $safeC{$k} if exists $safeC{$k};
    for my $p (@{ $G{$ka} || [] }) { return $safeC{$k} = 0 unless grep { !cheap($p, $_) } @{ $G{$kb} || [] } }
    for my $p (@{ $C{$ka} || [] }) { return $safeC{$k} = 0 unless grep { !cheap($p, $_) } @{ $C{$kb} || [] } }
    $safeC{$k} = 1 }
my %pred;
for my $k (5 .. 8) { for my $x (@{ $by[$k] || [] }) { my $kx = key($x); my @ch = split //, $kx; my %s;
    for my $i (0 .. $#ch) { next if $s{ $ch[$i] }++; my $sub = $kx; substr($sub, $i, 1) = '';
        for my $p (@{ $C{$sub} || [] }) { push @{ $pred{$x} }, $p unless cheap($p, $x) || !safe($sub, $kx) } } } }

# the game's theme words (theme-words.js)
my (%TW, @order);
{ open my $fh, '<', "$DIR/theme-words.js" or die; while (<$fh>) { last if /THEME_WORDS_FROM/; if (/^(\w+): "([^"]*)"/) { push @order, $1; $TW{$1} = { map { $_ => 1 } split ' ', $2 } } } }

# ---- every theme's climbs: per peak word, its trap-free themed routes (several openers) and their forks ----
my %climbs;   # theme -> length -> [ { peak, routes => [ [ladder, forks], ... ] } ]
for my $th (@order) {
    my $ts = $TW{$th}; my (%fork, %trapC);
    my $fk = sub { my $kx = key($_[0]); return $fork{$kx} if exists $fork{$kx};
        my @c = grep { !$block{$_} } @{ $G{$kx} || [] };
        $fork{$kx} = ((grep { $ts->{$_} && common($_) } @c) && (grep { !$ts->{$_} && $rank{$_} && $rank{$_} <= $CHOICERANK } @c)) ? 1 : 0 };
    # a trap: some word you can type on a step blocks every theme word on the next, while an everyday word wouldn't
    my $trap = sub { my ($ka, $kb) = (key($_[0]), key($_[1])); my $k = "$ka>$kb"; return $trapC{$k} if exists $trapC{$k};
        my @next = grep { $ts->{$_} } @{ $G{$kb} || [] }; return $trapC{$k} = 0 unless @next;
        my @here = @{ $G{$ka} || [] };
        my $blk = grep { my $p = $_; !grep { !cheap($p, $_) } @next } @here;
        my $opn = grep { my $p = $_; common($p) && grep { !cheap($p, $_) } @next } @here;
        $trapC{$k} = ($blk && $opn) ? 1 : 0 };
    # forks on a ladder, counting only words you could actually play there (no cheap step from some playable word
    # on the step before): POTTERS can't be a fork's theme word when POTTER is the only word on the step before
    my $forksOf = sub { my ($lad) = @_; my ($c, @reach) = (0);
        for my $s (0 .. $#$lad) { my @all = @{ $G{ key($lad->[$s]) } || [] };
            my @play = $s ? grep { my $w = $_; grep { !cheap($_, $w) } @reach } @all : @all;
            my @ok = grep { !$block{$_} } @play;
            $c++ if (grep { $ts->{$_} && common($_) } @ok) && (grep { !$ts->{$_} && $rank{$_} && $rank{$_} <= $CHOICERANK } @ok);
            @reach = @play }
        $c };
    my %ok; $ok{$_} = 1 for @{ $by[4] || [] };
    for my $k (5 .. 8) { for my $x (@{ $by[$k] || [] }) { $ok{$x} = 1 if grep { $ok{$_} && !$trap->($_, $x) } @{ $pred{$x} || [] } } }
    for my $L (@PEAKS) { for my $x (sort @{ $by[$L] || [] }) { next unless $ok{$x};
        my @rt; my $n = 0;
        my $dfs; $dfs = sub { my ($w, $suf) = @_; return if $n >= 400;
            if (length $w == 4) { $n++; my @lad = ($w, @$suf); return unless grep { length $_ >= 5 && $ts->{$_} } @lad;
                push @rt, [\@lad, $forksOf->(\@lad)]; return }
            for my $p (sort { $rank{$a} <=> $rank{$b} } @{ $pred{$w} || [] }) { next unless $ok{$p} && !$trap->($p, $w); $dfs->($p, [$w, @$suf]) } };
        $dfs->($x, []);
        next unless @rt;
        my (%seen2, @keep, @rest);   # the richest routes, spread over different openers
        for my $one (sort { $b->[1] <=> $a->[1] } @rt) { my $o = "$one->[0][0],$one->[0][1]"; if ($seen2{$o}++) { push @rest, $one } else { push @keep, $one } }
        push @keep, @rest; splice @keep, $ROUTES if @keep > $ROUTES;
        push @{ $climbs{$th}{$L} }, { peak => $x, routes => \@keep };
    } }
}

# ---- the calendar so far ----
local $/; open my $cf, '<:encoding(UTF-8)', $CAL or die "$CAL: $!"; my $src = <$cf>; close $cf; $/ = "\n";
my ($pre) = $src =~ /\A(.*?^days: \[\n)/ms or die "no 'days: [' line in $CAL\n";
my ($start) = $src =~ /^start: "(\d{4}-\d\d-\d\d)"/m or die "no start date in $CAL\n";
my @lines = $src =~ /^(\{"c".*\}),\s*$/mg;
sub dnum { my ($y, $m, $d) = split /-/, $_[0]; int(timegm(0, 0, 12, $d, $m - 1, $y) / 86400) }
sub dateOf { my @t = gmtime((dnum($start) + $_[0]) * 86400 + 43200); sprintf "%04d-%02d-%02d", $t[5] + 1900, $t[4] + 1, $t[3] }
my $NPAST = dnum($FROM) - dnum($start);
die "FROM is before the calendar starts\n" if $NPAST < 0;
die "FROM is past the end of the calendar\n" if $NPAST > @lines;
my @past = map { JSON::PP->new->decode($_) } @lines[0 .. $NPAST - 1];

# ---- build day by day ----
my (%used, %lastPk, %lastTW, %last2, %last3, %lastT, @cal);
my %rk; @rk{@order} = 0 .. $#order;
for my $p (0 .. $#past) { my $pd = $past[$p]; my $rel = $p - $NPAST; $lastT{ $pd->{t} } = $rel;
    for my $j (0 .. $#{ $pd->{c} }) { my $l = $pd->{c}[$j];
        $last2{ join(",", map { key($_) } @$l[0, 1]) } = $rel; $last3{ join(",", map { key($_) } @$l[0 .. 2]) } = $rel;
        $lastPk{ key($l->[-1]) } = $rel; $used{ "$pd->{t}|" . key($l->[-1]) } = 1;
        $lastTW{"$pd->{t}|$_"} = $rel for (@{ $pd->{w}[$j] || [] }), grep { $TW{ $pd->{t} }{$_} } @$l } }
my $left = sub { my $th = shift; my $m = 1e9; for my $L (@PEAKS) { my $c = grep { !$used{"$th|" . key($_->{peak})} } @{ $climbs{$th}{$L} || [] }; $m = $c if $c < $m } $m };
my @combos;
for my $a (0 .. $MAXK) { for my $b (0 .. $MAXK) { for my $c (0 .. $MAXK) { push @combos, [$a, $b, $c] if $a + $b + $c >= $K } } }
@combos = sort { ($a->[0] + $a->[1] + $a->[2]) <=> ($b->[0] + $b->[1] + $b->[2]) } @combos;
my $day = 0;
DAY: while (1) {
    for my $th (sort { ($lastT{$a} // -1e9) <=> ($lastT{$b} // -1e9) || $rk{$a} <=> $rk{$b} } @order) {
        next if $left->($th) == 0 || (defined $lastT{$th} && $lastT{$th} == $day - 1);
        my @opt;   # per peak length: usable routes today, by fork count
        for my $i (0 .. $#PEAKS) { my %g;
            for my $c (@{ $climbs{$th}{ $PEAKS[$i] } || [] }) { my $pk = key($c->{peak});
                next if $used{"$th|$pk"} || (defined $lastPk{$pk} && $day - $lastPk{$pk} < 60);
                my %seenv; for my $one (@{ $c->{routes} }) { my $l = $one->[0];
                    my $s2 = join(",", map { key($_) } @$l[0, 1]); my $s3 = "$s2," . key($l->[2]);
                    next if defined $last2{$s2} && $day - $last2{$s2} < 30;
                    next if defined $last3{$s3} && $day - $last3{$s3} < 60;
                    next if grep { $TW{$th}{$_} && defined $lastTW{"$th|$_"} && $day - $lastTW{"$th|$_"} < 30 } @$l;
                    my $v = $one->[1] > $MAXK ? $MAXK : $one->[1]; next if $seenv{$v}++;
                    push @{ $g{$v} }, [$c, $l] } }
            $opt[$i] = \%g }
        for my $cb (@combos) {
            my ($A, $B, $Cc) = map { $opt[$_]{ $cb->[$_] } || [] } 0 .. 2; next unless @$A && @$B && @$Cc;
            my $tries = 0;
            for my $x (@$A) { for my $y (@$B) {
                my %w = map { key($_) => 1 } @{ $x->[1] }; next if grep { $w{ key($_) } } @{ $y->[1] }; $w{ key($_) } = 1 for @{ $y->[1] };
                for my $z (@$Cc) { last if ++$tries > 3000; next if grep { $w{ key($_) } } @{ $z->[1] };
                    for my $pick ($x, $y, $z) { my $l = $pick->[1]; my $pk = key($pick->[0]{peak});
                        $used{"$th|$pk"} = 1; $lastPk{$pk} = $day; $lastTW{"$th|$_"} = $day for grep { $TW{$th}{$_} } @$l;
                        $last2{ join(",", map { key($_) } @$l[0, 1]) } = $day; $last3{ join(",", map { key($_) } @$l[0 .. 2]) } = $day }
                    $lastT{$th} = $day; push @cal, [$th, [ map { $_->[1] } $x, $y, $z ]]; $day++; next DAY } } }
        }
    }
    last;
}

# ---- write ----
my $J = JSON::PP->new->canonical;
my @new = map { my ($th, $lads) = @$_;
    my @w = map { my $l = $_; my @t = grep { $TW{$th}{$_} } @$l; [ (grep { length($_) >= 5 } @t), (grep { length($_) < 5 } @t) ] } @$lads;
    $J->encode({ c => $lads, k => 'T', t => $th, w => \@w }) } @cal;
printf "kept %d days (%s to %s); built %d 6-7-8 days with %d+ forks each (%s to %s)\n", $NPAST, dateOf(0), dateOf($NPAST - 1),
    scalar @new, $K, dateOf($NPAST), dateOf($NPAST + $#new);
my @gone = grep { $left->($_) == 0 } @order;
print "themes with nothing left by the end: ", (join(', ', @gone) || 'none'), "\n";
if ($ENV{WRITE}) {
    my $head = "// Themed daily calendar - do not hand-edit. days[i] is the puzzle for start + i days.\n" .
        "// c: the three reference ladders; w: the theme words on each ladder; t: the theme; k/s: the old day type\n" .
        "// (Trail/Ridge/Summit, 11-letter star), kept on old days only. Days from $FROM on are the 6-7-8 format, built by\n" .
        "// gen-calendar-678.pl (see its header for the rules); earlier days came from gen-calendar.pl + fix-traps.pl.\n" .
        "// Check with verify-calendar.pl after any change.\n";
    (my $body = $pre) =~ s/\A(?:\/\/[^\n]*\n)+//;
    open my $o, '>:encoding(UTF-8)', $OUT or die "$OUT: $!";
    print $o $head, $body, (map { "$_,\n" } @lines[0 .. $NPAST - 1], @new), "]};\n";
    close $o;
    print "wrote $OUT\n";
}
