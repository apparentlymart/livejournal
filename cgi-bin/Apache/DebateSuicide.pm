#!/usr/bin/perl
#

package Apache::DebateSuicide;

BEGIN {
    $LJ::HAVE_INLINE = eval "use Inline (C => 'DATA', DIRECTORY => \"\$ENV{'LJHOME'}/Inline\"); 1";
}
use strict;
use Apache::Constants qw(:common);

if ($LJ::HAVE_INLINE && ($LJ::SUICIDE_LOAD || $LJ::SUICIDE)) {
    eval {
        Inline->init();
    };
    if ($@ && ! $LJ::JUST_COMPILING) {
        print STDERR "Warning: You seem to have Inline.pm, but you haven't run \$LJHOME/bin/lj-inline.pl.  " .
            "Continuing without it, but stats won't broadcast.\n";
        $LJ::HAVE_INLINE = 0;
    }
}

use vars qw($gtop);

# oh btw, this is totally linux-specific.  gtop didn't work, so so much for portability.
sub handler
{
    my $r = shift;
    return OK if $r->main;
    return OK unless $LJ::HAVE_INLINE && $LJ::HAVE_GTOP && $LJ::SUICIDE;

    my $meminfo;
    return OK unless open (MI, "/proc/meminfo");
    $meminfo = join('', <MI>);
    close MI;

    my %meminfo;
    while ($meminfo =~ m/(\w+):\s*(\d+)\skB/g) {
        $meminfo{$1} = $2;
    }

    my $memfree = $meminfo{'MemFree'} + $meminfo{'Cached'};
    return OK unless $memfree;

    my $goodfree = $LJ::SUICIDE_UNDER{$LJ::SERVER_NAME} || $LJ::SUICIDE_UNDER || 150_000;
    return OK if $memfree > $goodfree;

    my @pids = (getppid(), get_sibling_pids());
    $gtop ||= GTop->new;

    my %stats;
    my $sum_uniq = 0;
    foreach my $pid (@pids) {
        my $pm = $gtop->proc_mem($pid);
        $stats{$pid} = [ $pm->rss - $pm->share, $pm ];
        $sum_uniq += $stats{$pid}->[0];
    }

    @pids = sort { $stats{$a}->[0] <=> $stats{$b}->[0] } @pids;

    if (grep { $$ == $_ } @pids[-2..-1]) {
        my $my_use_k = $stats{$$}[0] >> 10;
        $r->log_error("Suicide [$$]: system memory free = ${memfree}k; i'm big, using ${my_use_k}k") if $LJ::DEBUG{'suicide'};
        Apache::LiveJournal::db_logger($r) unless $r->pnotes('did_lj_logging');
        CORE::exit();
    }

    return OK;
}

1;

__DATA__
__C__

extern unsigned char *ap_scoreboard_image;

/* 
 * the following structure is for Linux on i32 ONLY! It makes certan
 * choices where apache's scoreboard.h has #ifdef's. See scoreboard.h
 * for real declarations, here we only name a few things we actually need.
 */

/* total length of struct should be 164 bytes */
typedef struct {
    int foo1;
    short foo2;
    unsigned char status;
    int foo3[39];
} short_score;

/* length should be 16 bytes */
typedef struct {
    int pid;
    int foo[3];
} parent_score;

static int hard_limit = 512; /* array size on debian */

/* 
 * Scoreboard is laid out like this: array of short_score structs,
 * then array of parent_score structs, then one int, the generation
 * number. Both arrays are of size HARD_SERVERS_LIMIT, 256 by default
 * on Unixes.
 */


void get_sibling_pids () {
    int i;
    short_score *ss;
    parent_score *ps;
    Inline_Stack_Vars;

    ss = (short_score *)ap_scoreboard_image;
    ps = (parent_score *) ((unsigned char *)ap_scoreboard_image + sizeof(short_score)*hard_limit);

    Inline_Stack_Reset;
    for (i=0; i<hard_limit; i++) {
        /* ready or busy */
        if(ss[i].status >= 2) {
            Inline_Stack_Push(newSViv(ps[i].pid));
        }
    }
    Inline_Stack_Done;
    return;
}
