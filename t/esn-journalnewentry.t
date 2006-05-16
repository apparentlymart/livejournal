# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';

use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

# we want to test four major cases here, matching and not matching for
# two types of subscriptions, all of subscr etypeid = JournalNewEntry
#
#          jid   sarg1   sarg2   meaning
#    S1:     n       0       0   all new posts made by user 'n' (subject to security)
#    S2:     0       0       0   all new posts made by friends  (test security)
#

my %got_sms = ();   # userid -> received sms
local $LJ::_T_SMS_SEND = sub {
    my $sms = shift;
    my $rcpt = $sms->to_u or die "No destination user";
    $got_sms{$rcpt->{userid}} = $sms;
    return 1;
};

my $proc_events = sub {
    %got_sms = ();
    LJ::Event->process_fired_events;
};

my $got_notified = sub {
    my $u = shift;
    $proc_events->();
    return $got_sms{$u->{userid}};
};

# testing case S1 above:
memcache_stress(sub {
    test_esn_flow(sub {
        my ($u1, $u2, $ucomm) = @_;

        # subscribe $u1 to all posts by $u2
        my $subsc = $u1->subscribe(
                                   event   => "UserNewEntry",
                                   method  => "SMS",
                                   journal => $u2,
                                   );

        ok($subsc, "made S1 subscription");

        test_post($u1, $u2);

        ok($subsc->delete, "Deleted subscription");

        ###### S2:
        # subscribe $u1 to all comments on all friends journals
        # subscribe $u1 to all posts on $u2
        my $subsc = $u1->subscribe(
                                   event   => "JournalNewEntry",
                                   method  => "SMS",
                                   );

        ok($subsc, "made S2 subscription");

        test_post($u1, $u2);

        # remove $u2 from $u1's friends list, post in $u2 and make sure $u1 isn't notified
        LJ::remove_friend($u1, $u2); # make u1 friend u2
        $u2->t_post_fake_entry;
        my $sms = $got_notified->($u1);
        ok(! $sms, "u1 did not get notified because u2 is no longer his friend");

        ok($subsc->delete, "Deleted subscription");
    });
});

# post an entry in $u2, by $u2 and make sure $u1 gets notified
# post an entry in $u1, by $u2 and make sure $u1 doesn't get notified
# post a friends-only entry in $u2, by $u2 and make sure $u1 doesn't get notified
# post an entry in $ucomm, by $u2 and make sure $u1 gets notified
# post an entry in $u1, by $ucomm and make sure $u1 doesn't get notified
# post a friends-only entry in $ucomm, by $u2 and make sure $u1 doesn't get notified
sub test_post {
    my ($u1, $u2, $ucomm) = @_;
    my $sms;

    foreach my $usejournal (0..1) {
        my %opts = $usejournal ? ( usejournal => $ucomm->{user} ) : ();
        my $suffix = $usejournal ? " in comm" : "";

        # post an entry in $u2
        my $u2e1 = eval { $u2->t_post_fake_entry(%opts) };
        ok($u2e1, "made a post$suffix");
        is($@, "", "no errors");

        # make sure we got notification
        $sms = $got_notified->($u1);
        ok($sms, "got the SMS");
        is(eval { $sms->to }, 12345, "to right place");

        # S1 failing case:
        # post an entry on $u1, where nobody's subscribed
        my $u1e1 = eval { $u1->t_post_fake_entry(%opts) };
        ok($u1e1, "did a post$suffix");

        # make sure we did not get notification
        $sms = $got_notified->($u1);
        ok(! $sms, "got no SMS");

        # S1 failing case, posting to u2, due to security
        my $u2e2f = eval { $u2->t_post_fake_entry(security => "friends", %opts) };
        ok($u2e2f, "did a post$suffix");
        is($u2e2f->security, "usemask", "is actually friends only");

        # make sure we didn't get notification
        $sms = $got_notified->($u1);
        ok(! $sms, "got no SMS, due to security (u2 doesn't trust u1)");
    }
}


sub test_esn_flow {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();

    # need a community for $u1 and $u2 to play in
    my $ucomm = temp_user();
    LJ::update_user($ucomm, { journaltype => 'C' });

    $u1->set_sms_number(12345);
    $u2->set_sms_number(67890);
    LJ::add_friend($u1, $u2); # make u1 friend u2
    $cv->($u1, $u2, $ucomm);
}

1;

