#!/usr/bin/perl
#

package Apache::SendStats;

BEGIN {
    $LJ::HAVE_INLINE = eval "use Inline (C => 'DATA', DIRECTORY => \"\$ENV{'LJHOME'}/var\"); 1";
}
use strict;
use IO::Socket::INET;
use Apache::Constants qw(:common);

Inline->init() if $LJ::HAVE_INLINE;

sub handler
{
    my $r = shift;
    return OK if $r->main;
    return OK unless $LJ::HAVE_INLINE;

    my $cleanup = ($r && $r->current_callback() eq "PerlCleanupHandler");

    my $free = free_servers();
    $r->log_error("cleanup=$cleanup, free servers: $free");

    $free += $cleanup;
    if ($LJ::FREECHILDREN_BCAST && 
        $LJ::FREECHILDREN_BCAST =~ /^(\S+):(\d+)$/) {
        my $bcast = $1;
        my $port = $2;
        my $sock = IO::Socket::INET->new(Proto => 'udp');
        $r->log_error("SendStats: couldn't create socket") unless $sock;
        if ($sock) {
            $sock->sockopt(SO_BROADCAST, 1);
            my $ipaddr = inet_aton($bcast);
            my $portaddr = sockaddr_in($port, $ipaddr);
            my $res = $sock->send("free_servers=$free\n", 0, $portaddr);
            $r->log_error("SendStats: couldn't broadcast") 
                unless $res;
        }
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


int free_servers() {
    int i, count;
    short_score *ss;
    parent_score *ps;

    ss = (short_score *)ap_scoreboard_image;
    ps = (parent_score *) ((unsigned char *)ap_scoreboard_image + sizeof(short_score)*hard_limit);

    count = 0;
    for (i=0; i<hard_limit; i++)
        if(ss[i].status == 2)  /* READY */
            count++;
    return count;
}


    
