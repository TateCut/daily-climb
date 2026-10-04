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
# With BASE=<old calendar>, also: past days (before FROM) unchanged, and every
# day keeps its theme, tier and peak lengths.
#
#   perl verify-calendar.pl [calendar.js]      BASE=old.js FROM=2026-10-06 to compare

my $DIR = 'D:/Claude Code/daily-climb';
my $CAL = shift || "$DIR/daily-calendar.js";
sub words { my ($p, $min) = @_; open my $f, '<', $p or die "$p: $!"; my (%w, @o);
    while (<$f>) { s/\s+$//; next unless /^[a-z]+$/; next if length($_) < ($min || 3); push @o, $_ unless $w{$_}++; } (\%w, \@o) }
my ($every) = words("$DIR/freq.js");
my ($all)   = words("$DIR/words.js");
my %block; if (open my $b, '<', "$DIR/climb-blocklist.txt") { while (<$b>) { s/#.*//; s/\s+//g; $block{lc $_} = 1 if length } }
sub key { join '', sort split //, $_[0] }
my %ana; push @{ $ana{ key($_) } }, $_ for keys %$all;
sub cheap { my ($p, $w) = @_; $w eq "${p}s" || ($p =~ /e$/ && ($w eq "${p}d" || $w eq "${p}r" || $w eq "${p}n")) }
my %game; { open my $f, '<', "$DIR/theme-words.js" or die; while (<$f>) { $game{$1} = { map { $_ => 1 } split ' ', $2 } if /^(\w+): "([^"]*)"/ } }
my %list; { open my $f, '<:encoding(UTF-8)', "$DIR/themes.txt" or die; my $t;
    while (<$f>) { s/\s+$//; next if /^\s*(#|$)/ || /^\@/; if (/^==\s*(\w+)\s*\|/) { $t = $1; next } $list{$t}{$_} = 1 for grep { length >= 5 } split ' ', lc } }

sub load { my ($p) = @_; open my $f, '<:encoding(UTF-8)', $p or die "$p: $!"; my ($start, @d);
    while (<$f>) { $start = $1 if /^start: "([\d-]+)"/; push @d, decode_json($1) if /^(\{.*\}),\s*$/ } ($start, \@d) }
my ($start, $days) = load($CAL);
my ($y, $m, $dd) = split /-/, $start;
use Time::Local;
sub date { my @t = gmtime(timegm(0, 0, 12, $dd, $m - 1, $y) + $_[0] * 86400); sprintf "%04d-%02d-%02d", $t[5] + 1900, $t[4] + 1, $t[3] }

my @err; my $err = sub { push @err, date($_[0]) . " $_[1]" };
my %seen;   # ladder -> [day, theme]
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
            my @opn = grep { my $p = $_; $every->{$p} && grep { !cheap($p, $_) } @next } @here;
            $err->($i, "$tag: TRAP " . join('/', @blk) . " blocks " . join('/', @next)) if @blk && @opn;
        }
        # repeats
        my $lk = join ',', @c;
        for my $prev (@{ $seen{$lk} || [] }) {
            $err->($i, "$tag repeats with the same theme as " . date($prev->[0])) if $prev->[1] eq $d->{t};
            $err->($i, "$tag repeats within 60 days of " . date($prev->[0])) if $i - $prev->[0] < 60;
        }
        push @{ $seen{$lk} }, [$i, $d->{t}];
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
my $nTrap = grep { /TRAP/ } @err;
printf "%s: %d days, %d problems (%d traps)\n", $CAL, scalar @$days, scalar @err, $nTrap;
print "  $_\n" for $ENV{ALL} ? @err : @err[0 .. ($#err < 40 ? $#err : 39)];   # ALL=1 prints every problem
exit(@err ? 1 : 0);
