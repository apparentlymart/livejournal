#!/usr/bin/perl
#

package Apache::SendStats;

BEGIN {
    $LJ::HAVE_INLINE = eval q{
        use Inline (C => 'DATA',
                    DIRECTORY => $ENV{LJ_INLINE_DIR} ||"$ENV{'LJHOME'}/Inline",
                    );
        1;
    };
}
use strict;
use IO::Socket::INET;
use Apache::Constants qw(:common);

if ($LJ::HAVE_INLINE && $LJ::FREECHILDREN_BCAST) {
    eval {
        Inline->init();
    };
    if ($@ && ! $LJ::JUST_COMPILING) {
        print STDERR "Warning: You seem to have Inline.pm, but you haven't run \$LJHOME/bin/lj-inline.pl.  " .
            "Continuing without it, but stats won't broadcast.\n";
        $LJ::HAVE_INLINE = 0;
    }
}

use vars qw(%udp_sock);

sub handler
{
    my $r = shift;
    return OK if $r->main;
    return OK unless $LJ::HAVE_INLINE && $LJ::FREECHILDREN_BCAST;

    my $callback = $r->current_callback() if $r;
    my $cleanup = $callback eq "PerlCleanupHandler";
    my $childinit = $callback eq "PerlChildInitHandler";

    if ($LJ::TRACK_URL_ACTIVE)
    {
	my $key = "url_active:$LJ::SERVER_NAME:$$";
	if ($cleanup) {
	    LJ::MemCache::delete($key);
	} else {
	    LJ::MemCache::set($key, $r->uri . "(" . $r->method . "/" . scalar($r->args) . ")");
	  }
    }

    my ($active, $free) = count_servers();

    $free += $cleanup;
    $free += $childinit;
    $active -= $cleanup if $active;

    my $list = ref $LJ::FREECHILDREN_BCAST ?
        $LJ::FREECHILDREN_BCAST : [ $LJ::FREECHILDREN_BCAST ];

    foreach my $host (@$list) {
        next unless $host =~ /^(\S+):(\d+)$/;
        my $bcast = $1;
        my $port = $2;
        my $sock = $udp_sock{$host};
        unless ($sock) {
            $udp_sock{$host} = $sock = IO::Socket::INET->new(Proto => 'udp');
            if ($sock) {
                $sock->sockopt(SO_BROADCAST, 1)
                    if $LJ::SENDSTATS_BCAST;
            } else {
                $r->log_error("SendStats: couldn't create socket: $host");
                next;
            } 
        }

        my $ipaddr = inet_aton($bcast);
        my $portaddr = sockaddr_in($port, $ipaddr);
        my $message = "bcast_ver=1\nfree=$free\nactive=$active\n";
        my $res = $sock->send($message, 0, $portaddr);
        $r->log_error("SendStats: couldn't broadcast") 
            unless $res;
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


void count_servers() {
    int i, count_free, count_active;
    short_score *ss;
    parent_score *ps;
    Inline_Stack_Vars;

    ss = (short_score *)ap_scoreboard_image;
    ps = (parent_score *) ((unsigned char *)ap_scoreboard_image + sizeof(short_score)*hard_limit);

    count_free = 0; count_active = 0;
    for (i=0; i<hard_limit; i++) {
        if(ss[i].status == 2)  /* READY */
            count_free++;
        if(ss[i].status > 2)   /* busy doing something */
            count_active++;
    }
    Inline_Stack_Reset;
    Inline_Stack_Push(newSViv(count_active));
    Inline_Stack_Push(newSViv(count_free));
    Inline_Stack_Done;
  
    return;
}


    
