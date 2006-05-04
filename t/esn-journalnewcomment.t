# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';
require 'talklib.pl';

use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

# we want to test eight major cases here, matching and not matching for
# four types of subscriptions, all of subscr etypeid = JournalNewComment
#
#          jid   sarg1   sarg2   meaning
#    S1:     n       0       0   all new comments in journal 'n' (subject to security)
#    S2:     n ditemid       0   all new comments on post (n,ditemid)
#    S3:     n ditemid jtalkid   all new comments UNDER comment n/jtalkid (in ditemid)
#    S4:     0       0       0   all new comments from any journal you watch
#

my %got_sms = ();   # userid -> received sms
local $LJ::_T_SMS_SEND = sub {
    my $sms = shift;
    my $rcpt = $sms->to_u or die "No destination user";
    $got_sms{$rcpt->{userid}} = $sms;
};


# testing case S1 above:
test_esn_flow(sub {
    my ($u1, $u2) = @_;

    # subscribe $u1 to all posts on $u2
    my $subsc = $u1->subscribe(
                               event   => "JournalNewComment",
                               method  => "SMS",
                               journal => $u2,
                               );
    ok($subsc, "made S1 subscription");

    # post an entry in $u2
    my $entry = eval { $u2->t_post_fake_entry };
    ok($entry, "made a post");
    is($@, "", "no errors");
    my $jitemid = $entry->jitemid;

    # $u1 leave a comment on $u2
    my %err = ();
    my $jtalkid = LJ::Talk::Post::enter_comment($u2, {talkid => 0}, {itemid => $jitemid},
                                                   {u => $u1, state => 'A', subject => 'comment subject',
                                                    body => 'comment body',}, \%err);

    ok(!%err, "no error posting comment");
    ok($jtalkid, "got jtalkid");

    # make sure we got notification
    LJ::Event->process_fired_events;
    ok($got_sms{$u1->{userid}}, "got the SMS");
    is(eval { $got_sms{$u1->{userid}}->to }, 12345, "to right place");

    # S1 failing case:
    # post an entry on $u1, where nobody's subscribed
    $entry = eval { $u1->t_post_fake_entry };
    ok($entry, "did a post");
    $jitemid = $entry->jitemid;

    # post a comment on it
    $jtalkid = LJ::Talk::Post::enter_comment($u1, {talkid => 0}, {itemid => $jitemid},
                                             {u => $u1, state => 'A', subject => 'comment subject',
                                              body => 'comment body',}, \%err);

    ok(!%err, "no error posting comment");
    ok($jtalkid, "got jtalkid");

    # make sure we got notification
    delete $got_sms{$u1->{userid}};
    LJ::Event->process_fired_events;
    ok(! $got_sms{$u1->{userid}}, "got no SMS");

    # S1 failing case, posting to u2, due to security
    $entry = eval { $u2->t_post_fake_entry(security => "friends") };
    ok($entry, "did a post");
    $jitemid = $entry->jitemid;
    is($entry->security, "usemask", "is actually friends only");

    # post a comment on it
    $jtalkid = LJ::Talk::Post::enter_comment($u2, {talkid => 0}, {itemid => $jitemid},
                                             {u => $u2, state => 'A', subject => 'comment subject',
                                              body => 'comment body private',}, \%err);

    ok(!%err, "no error posting comment");
    ok($jtalkid, "got jtalkid");

    # make sure we got notification
    delete $got_sms{$u1->{userid}};
    LJ::Event->process_fired_events;
    ok(! $got_sms{$u1->{userid}}, "got no SMS, due to security (u2 doesn't trust u1)");


});

sub test_esn_flow {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();
    my $u3 = temp_user();
    $u1->set_sms_number(12345);
    $u2->set_sms_number(67890);
    LJ::add_friend($u1, $u2); # make u1 friend u2
    $cv->($u1, $u2, $u3);
}

1;

