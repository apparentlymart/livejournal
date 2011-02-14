#!/usr/bin/perl

use strict;
use warnings;
no warnings 'once';
use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";
require "ljdb.pl";
require "ljlang.pl";
require 'ljprotocol.pl';
use Getopt::Long;
use LJ::DBUtil;
use Data::Dumper;
use IO::Handle;

STDOUT->autoflush(1);
STDERR->autoflush(1);



my $help = <<"HELP";
    This script set the supermaintainer role for all or selected communities. 
    If no supermaintainer can be set, then poll is created for the community.

    Usage:
        $0 comm1 comm2 comm3

    Options: 
        --verbose       Show progress
        --all           Process all communities
        --cluster-id    Cluster ID
        --do-nothing    Do nothing. Only logging.
        --help          Show this text and exit
HELP

my ($need_help, $verbose, $no_job, $cluster_id, $all);
GetOptions(
    "help"          => \$need_help, 
    "verbose"       => \$verbose,
    "do-nothing"    => \$no_job,
    "cluster-id=i"  => \$cluster_id,
    "all"           => \$all,
) or die $help;
if ($need_help || (!@ARGV && !$all)) {
    print $help;
    exit(1);
}

my $to_journal = LJ::load_user("lj_elections");
if (!$to_journal) {
    warn "Try to create journal 'lj_elections'\n";
    $to_journal = LJ::User->create_personal (
        ofage => 1,
        status => 'A',
        user => 'lj_elections',
        bdate => '1989-04-15',
        email => 'cc@livejournalinc.com',
        password => LJ::rand_chars(10),
    );
    warn "Created user 'lj_elections'\n" if $to_journal;
}

die "No user 'lj_elections' on this server" unless $to_journal;

my $poster = LJ::load_user("system") 
    or die "No user 'system' on this server";


my $dbr = LJ::get_dbh("slow") or die "Can't get slow DB connection";
$dbr->{RaiseError} = 1;
$dbr->{ShowErrorStatement} = 1;

my $where = @ARGV ? " AND user IN('".join("','",@ARGV)."') " : '';
my $where_cluster = $cluster_id ? " AND clusterid = $cluster_id " : " AND clusterid != 0 ";
$verbose = 1 if @ARGV;

sub _log {
    print @_ if $verbose;
}

$cluster_id
    ? _log "Using cluster $cluster_id\n"
    : _log "Using all clusters\n";

my $communities = $dbr->selectcol_arrayref ("
                        SELECT userid 
                        FROM user 
                        WHERE 
                            statusvis <> 'X' 
                            $where_cluster
                            AND journaltype = 'C' 
                            $where
                    ");

die "Can't fetch communities list\n" unless $communities;

my $i = 0;
foreach my $c_id (@$communities) {
    LJ::start_request();
    $i++;

    _log '-' x 30, "\n";

    my $comm = LJ::load_userid ($c_id);
    unless ($comm) {
        _log "Error while loading community (Id: $c_id)\n";
        next;
    }
    next if $comm->{user} eq 'cheaptrip';

    _log "Start work with community '$comm->{'user'}'\n";

    ## skip if community has supermaintainer already
    my $s_maints = LJ::load_rel_user($c_id, 'S');
    my $s_maint_u = @$s_maints ? LJ::load_userid($s_maints) : undef;
    if ($s_maint_u) {
        _log "Community has supermaintainer already: " . $s_maint_u->user . "\n";
        next;
    }

    if (my $pollid = $comm->prop ('election_poll_id')) {
        ## Poll was created
        if ($pollid) {
            my $poll = LJ::Poll->new ($pollid);
            unless ($poll->journalid) { ## Try to load poll from DB
                _log "Can't load election poll for community " . $comm->{'user'} . "\n";
                next;
            }
            if ($poll->is_closed) {
                _log "Poll is closed and supermaintainer did not set.\n";
            } else {
                _log "Poll is open.\n";
                next;
            }
        }
    }

    my $maintainers = LJ::load_rel_user($c_id, 'A');
    _log "List of maintainers (uids): " . join(", ", @$maintainers) . "\n";
    ## Check for all maintainers are alive
    my $users = LJ::load_userids(@$maintainers);
    my @alive_maintainers;
    while (my ($uid, $u) = each %$users) {
        unless ($u) {
            _log "\t\tCan't load maintainer ($uid)\n";
            next;
        }
        my $username = $u->{user};
        unless ($u->is_visible) {
            _log "\t\tuser ($username/$uid) is not visible\n";
            next;
        }
        unless ($u->can_manage($comm)) {
            _log "\t\tuser ($username/$uid) can not manage community\n";
            next;
        }
        unless ($u->check_activity(90)) {
            _log "\t\tuser ($username/$uid) is not active at last 90 days\n";
            next;
        }
        _log "\tAdd maintainer $username to election list\n";
        push @alive_maintainers, $u;
    }

    unless (@alive_maintainers) {
        _log "Community does not have active maintainers\n";
        next;
    }

    _log "Found " . (scalar @alive_maintainers) . " maintainers\n";

    my $system = LJ::load_user('system');
    if (scalar @alive_maintainers == 1) {
        ## Check for alone maintainer is normal user and if ok set to supermaintainer
        my $user = $alive_maintainers[0];
        _log "Set user ".$user->user." as supermaintainer for ".$comm->user."\n";
        unless ($no_job) {
            $comm->log_event('set_owner', { actiontarget => $user->{userid}, remote => $system });
            LJ::statushistory_add($comm, $system, 'set_owner', "LJ script set owner as ".$user->{user});
            LJ::set_rel($c_id, $user->{userid}, 'S')
                or die "Can't set 'owner' status for community " . $comm->{'user'} . "\n";
            _send_email_to_sm ($comm, $user->{userid});
        }
    } else {
        ## Search for maintainer via userlog
        _log "Search in userlog for creator or first alive maintainer\n";
        my $u = _check_maintainers ($comm);
        if ($u) {
            _log "Set user ".$u->user." as supermaintainer for ".$comm->user."\n";
            unless ($no_job) {
                $comm->log_event('set_owner', { actiontarget => $u->{userid}, remote => $system });
                LJ::set_rel($c_id, $u->{userid}, 'S')
                    or die "Can't set 'owner' status for community " . $comm->{'user'} . "\n";
                _send_email_to_sm ($comm, $u->{userid});
                LJ::statushistory_add($comm, $system, 'set_owner', "LJ script set owner as ".$u->{user});
            }
        } else {
            _log "Create poll for supermaintainer election\n";
            my $log = '';
            my $poll_id = LJ::create_supermaintainer_election_poll (
                    comm_id     => $c_id, 
                    maint_list  => \@alive_maintainers, 
                    log         => \$log,
                    no_job      => $no_job,
                    to_journal  => $to_journal,
            );
            _log $log;
            unless ($no_job) {
                $comm->set_prop ('election_poll_id' => $poll_id)
                    or die "Can't set prop 'election_poll_id'";
            }
        }
    } 
}

_log '-' x 30, "\n";
_log "Total count of processed communities: " . $i . "\n";

sub _send_email_to_sm {
    my $comm = shift;
    my $maint_id = shift;

    my $subject = LJ::Lang::ml('poll.election.not.need.subject');
    my $u = LJ::load_userid ($maint_id);
    next unless $u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90);
    _log "\tSend email to maintainer ".$u->user."\n";
    LJ::send_mail({ 'to'        => $u->email_raw,
                    'from'      => $LJ::ACCOUNTS_EMAIL,
                    'fromname'  => $LJ::SITENAMESHORT,
                    'wrap'      => 1,
                    'charset'   => $u->mailencoding || 'utf-8',
                    'subject'   => $subject,
                    'html'      => (LJ::Lang::ml('poll.election.not.need.html', {
                                            username        => LJ::ljuser($u),
                                            communityname   => LJ::ljuser($comm),
                                            faqlink         => '#',
                                            shortsite       => $LJ::SITENAMESHORT,
                                            authas          => $comm->{user},
                                            siteroot        => $LJ::SITEROOT,
                                        })
                                    ),
                    'body'      => (LJ::Lang::ml('poll.election.not.need.html.plain', {
                                            username        => LJ::ljuser($u),
                                            communityname   => LJ::ljuser($comm),
                                            faqlink         => '#',
                                            shortsite       => $LJ::SITENAMESHORT,
                                            authas          => $comm->{user},
                                            siteroot        => $LJ::SITEROOT,
                                        })
                                    ),
                });
}

sub _check_maintainers {
    my $comm = shift;

    my $dbcr = LJ::get_cluster_reader($comm)
        or die "Unable to get user cluster reader.";
    $dbcr->{RaiseError} = 1;

    my $sth = $dbcr->prepare("SELECT action, actiontarget, remoteid FROM userlog WHERE userid = ? AND action = ? ORDER BY logtime ASC");
    $sth->execute($comm->{userid}, 'account_create');

    my $row = $sth->fetchrow_hashref;
    if ($row) {
        my $u_id = $row->{'remoteid'};
        my $u = LJ::load_userid ($u_id);
        if (!$u) {
            $u_id = "[undefined]" unless defined $u_id;
            _log "\t\tCan't load maintainer ($u_id)\n";
            _log Dumper($row);
        } elsif (!$u->is_visible) {
            _log "\t\tuser ($u->{user}) is not visible\n";
        } elsif (!$u->can_manage($comm)) {
            _log "\t\tuser ($u->{user}) can not manage community\n";
        } elsif (!$u->check_activity(90)) {
            _log "\t\tuser ($u->{user}) is not active at last 90 days\n";
        } else {
            _log "\tuser ($u->{user}) is the person who created the community\n";
            return $u;
        }
    }

    _log "No 'account_create' record. Start the election.\n";
    return undef;

}



