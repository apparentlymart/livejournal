#!/usr/bin/perl
#

package Apache::DebateSuicide;

use strict;
use Apache::Constants qw(:common);

use vars qw($gtop);
our %known_parent;
our $ppid;

# oh btw, this is totally linux-specific.  gtop didn't work, so so much for portability.
sub handler
{
    my $r = shift;
    return OK if $r->main;
    return OK unless $LJ::HAVE_GTOP && $LJ::SUICIDE;

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

    unless ($ppid) {
        my $self = pid_info($$);
        $ppid = $self->[3];
    }

    my $pids = child_info($ppid);
    my @pids = keys %$pids;

    $gtop ||= GTop->new;

    my %stats;
    my $sum_uniq = 0;
    foreach my $pid (@pids) {
        my $pm = $gtop->proc_mem($pid);
        $stats{$pid} = [ $pm->rss - $pm->share, $pm ];
        $sum_uniq += $stats{$pid}->[0];
    }

    @pids = (sort { $stats{$b}->[0] <=> $stats{$a}->[0] } @pids, 0, 0);

    my $my_pid = $$;
    if (grep { $my_pid == $_ } @pids[0,1]) {
        my $my_use_k = $stats{$$}[0] >> 10;
        $r->log_error("Suicide [$$]: system memory free = ${memfree}k; i'm big, using ${my_use_k}k") if $LJ::DEBUG{'suicide'};
        Apache::LiveJournal::db_logger($r) unless $r->pnotes('did_lj_logging');
        $r->child_terminate;
    }

    return OK;
}

sub pid_info {
    my $pid = shift;

    open (F, "/proc/$pid/stat") or next;
    $_ = <F>;
    close(F);
    my @f = split;
    return \@f;
}

sub child_info {
    my $ppid = shift;
    opendir(D, "/proc") or return undef;
    my @pids = grep { /^\d+$/ } readdir(D);
    closedir(D);

    my %ret;
    foreach my $p (@pids) {
        next if (defined $known_parent{$p} &&
                 $known_parent{$p} != $ppid);
        my $ary = pid_info($p);
        my $this_ppid = $ary->[3];
        $known_parent{$p} = $this_ppid;
        next unless $this_ppid == $ppid;
        $ret{$p} = $ary;
    }
    return \%ret;
}

1;
