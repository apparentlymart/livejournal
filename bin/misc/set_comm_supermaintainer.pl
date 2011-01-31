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

my $to_journal = LJ::load_user("lj_elections");

if (($to_journal && $to_journal->is_expunged) || !$to_journal) {
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

my $help = <<"HELP";
    This script set the supermaintainer role for all or selected communities. 
    If no supermaintainer can be set, then poll is created for the community.

    Usage:
        $0 comm1 comm2 comm3

    Options: 
        --verbose       Show progress
        --all           Process all communities
        --help          Show this text and exit
HELP

my ($need_help, $verbose, $all);
GetOptions(
    "help"          => \$need_help, 
    "verbose"       => \$verbose,
    "all"           => \$all,
) or die $help;
if ($need_help || (!@ARGV && !$all)) {
    print $help;
    exit(1);
}

my $dbr = LJ::get_dbh("slow") or die "Can't get slow DB connection";
$dbr->{RaiseError} = 1;
$dbr->{ShowErrorStatement} = 1;

my $where = @ARGV ? " AND user IN('".join("','",@ARGV)."') " : '';
$verbose = 1 if @ARGV;
my $communities = $dbr->selectall_arrayref ("SELECT userid, user FROM user WHERE journaltype = 'C'$where", { Slice => {} });

sub _log {
    print @_ if $verbose;
}

my $i = 0;
foreach my $c (@$communities) {
    _log '-' x 30, "\n";

    _log "Start work with community '" . $c->{'user'} . "'\n";
    my $comm = LJ::load_userid ($c->{userid});
    next unless $comm;

    _log "Search and set supermaintainer for community: " . $c->{'user'}."\n";

    ## skip if community has supermaintainer already
    my $s_maints = LJ::load_rel_user($c->{userid}, 'S');
    my $s_maint_u = @$s_maints ? LJ::load_userid($s_maints) : undef;
    if ($s_maint_u) {
        _log "Community has supermaintainer already: " . $s_maint_u->user . "\n";
        next;
    }

    if ($comm->prop ('election_poll_id')) {
        my $jitemid = $comm->prop ('election_poll_id');
        ## Poll was created
        if ($jitemid) {
            my $poll = LJ::Poll->new ($jitemid);
            if ($poll->is_closed) {
                _log "Poll is closed and supermaintainer did not set.\n";
            } else {
                _log "Poll is open.\n";
                next;
            }
        }
    }

    my $maintainers = LJ::load_rel_user($c->{userid}, 'A');
    ## Check for all maintainers are alive
    my $users = LJ::load_userids(@$maintainers);
    my @alive_mainteiners;
    foreach my $u (values %$users) {
        if ($u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90)) {
            push @alive_mainteiners, $u;
        }
    }
    unless (@alive_mainteiners) {
        _log "Community does not have active maintainers\n";
        next;
    }

    if (scalar @alive_mainteiners == 1) {
        ## Check for alone maintainer is normal user and if ok set to supermaintainer
        my $user = $alive_mainteiners[0];
        _log "Set user ".$user->user." as supermaintainer for ".$comm->user."\n";
        LJ::set_rel($c->{userid}, $user->{userid}, 'S');
    } else {
        ## Search for maintainer via userlog
        _log "Search in userlog for creator or first alive maintainer\n";
        my $u = _check_maintainers ($comm);
        if ($u) {
            _log "Set user ".$u->user." as supermaintainer for ".$comm->user."\n";
            LJ::set_rel($c->{userid}, $u->{userid}, 'S');
        } else {
            _log "Create poll for supermaintainer election\n";
            my $poll_id = _create_poll ($c->{userid});
            $comm->set_prop ('election_poll_id' => $poll_id)
                or die "Can't set prop 'election_poll_id'";
        }
    } 

    $i++;
    if ($i > 1000) {
        print "Sleeping...\n";
        sleep 1;
        $i = 0;
    }
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
        return $u if $u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90);
    }

    $sth->execute($comm->{userid}, 'maintainer_add');
    while (my $row = $sth->fetchrow_hashref) {
        my $u_id = $row->{'actiontarget'};
        my $u = LJ::load_userid ($u_id);
        return $u if $u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90);
    }

    ## Can't find active maintainer
    return undef;
}

sub _edit_post {
    my %opts = @_;

    my $u = $opts{to};
    my $comm = $opts{comm};
    my $entry = $opts{entry};
    my $poll = $opts{poll};

    my $security = delete $opts{security} || 'private';
    my $proto_sec = $security;
    if ($security eq "friends") {
        $proto_sec = "usemask";
    }

    my $subject = delete $opts{subject} || LJ::Lang::ml('poll.election.post_subject');
    my $body    = delete $opts{body}    || LJ::Lang::ml('poll.election.post_body', { comm => $comm->user });

    my %req = (
               mode     => 'editevent',
               ver      => $LJ::PROTOCOL_VER,
               user     => $u->{user},
               password => '',
               event    => $body . "<br/>" . "<lj-poll-".$poll->pollid.">",
               subject  => $subject,
               tz       => 'guess',
               security => $proto_sec,
               itemid   => $entry->jitemid,
               );

    $req{allowmask} = 1 if $security eq 'friends';

    my %res;
    my $flags = { noauth => 1, nomod => 1 };

    LJ::do_request(\%req, \%res, $flags);

    die "Error posting: $res{errmsg}" unless $res{'success'} eq "OK";
    my $jitemid = $res{itemid} or die "No itemid";

    return LJ::Entry->new($u, jitemid => $jitemid);
}

sub _create_post {
    my %opts = @_;

    my $u = $opts{to};
    my $comm = $opts{comm};

    my $security = delete $opts{security} || 'private';
    my $proto_sec = $security;
    if ($security eq "friends") {
        $proto_sec = "usemask";
    }

    my $subject = delete $opts{subject} || LJ::Lang::ml('poll.election.post_subject');
    my $body    = delete $opts{body}    || LJ::Lang::ml('poll.election.post_body', { comm => $comm->user });

    my %req = (
               mode => 'postevent',
               ver => $LJ::PROTOCOL_VER,
               user => $u->{user},
               password => '',
               event => $body,
               subject => $subject,
               tz => 'guess',
               security => $proto_sec,
               );

    $req{allowmask} = 1 if $security eq 'friends';

    my %res;
    my $flags = { noauth => 1, nomod => 1 };

    LJ::do_request(\%req, \%res, $flags);

    die "Error posting: $res{errmsg}" unless $res{'success'} eq "OK";
    my $jitemid = $res{itemid} or die "No itemid";

    return LJ::Entry->new($u, jitemid => $jitemid);
}

sub _create_poll {
    my $comm_id = shift;

    my $comm = LJ::load_userid($comm_id);
    my $entry = _create_post (to => $to_journal, comm => $comm);

    die "Entry for Poll does not created\n" unless $entry;

    my @items = ();
    my $maintainers = LJ::load_rel_user($comm_id, 'A');
    foreach my $u_id (@$maintainers) {
        my $u = LJ::load_userid($u_id);
        next unless $u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90);
        _log "\tAdd ".$u->user." as item to poll\n";
        push @items, {
            item    => "<lj user='".$u->user."'>",
        };
    }

    my @q = (
        {
            qtext   => LJ::Lang::ml('poll.election.subject'),
            type    => 'radio',
            items   => \@items,
        }
    );

    my $poll = LJ::Poll->create (entry => $entry, whovote => 'all', whoview => 'all', questions => \@q)
        or die "Poll was not created";

    $poll->set_prop ('createdate' => $entry->eventtime_mysql)
        or die "Can't set prop 'createdate'";

    $poll->set_prop ('supermaintainer' => $comm->userid)
        or die "Can't set prop 'supermaintainer'";

    _edit_post (to => $to_journal, comm => $comm, entry => $entry, poll => $poll) 
        or die "Can't edit post";

    ## All are ok. Emailing to all maintainers about election.
    my $subject = LJ::Lang::ml('poll.election.email.subject');
    _log "Sending emails to all maintainers for community " . $comm->user . "\n";
    foreach my $maint_id (@$maintainers) {
        my $u = LJ::load_userid ($maint_id);
        next unless $u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90);
        _log "\tSend email to maintainer ".$u->user."\n";
        LJ::send_mail({ 'to'        => $u->email_raw,
                        'from'      => $LJ::ACCOUNTS_EMAIL,
                        'fromname'  => $LJ::SITENAMESHORT,
                        'wrap'      => 1,
                        'charset'   => $u->mailencoding || 'utf-8',
                        'subject'   => $subject,
                        'html'      => (LJ::Lang::ml('poll.election.start.email', {
                                                username        => LJ::ljuser($u),
                                                communityname   => LJ::ljuser($comm),
                                                faqlink         => '#',
                                                shortsite       => $LJ::SITENAMESHORT,
                                                authas          => $comm->{user},
                                                siteroot        => $LJ::SITEROOT,
                                            })
                                        ),
                    });
        ## We need a pause to change sender-id in mail headers
        sleep 1;
    }

    return $poll->pollid;
}


