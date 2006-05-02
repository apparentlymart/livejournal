# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';

use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

test_esn_flow(sub {
    my ($u1, $u2) = @_;
    $u1->set_sms_number(12345);
    my $subsc = $u1->subscribe(
                                event   => "JournalNewEntry",
                                method  => "SMS",
                                journal => $u2,
                                );
    ok($subsc, "got subscription");

    my $got_sms = 0;
    local $LJ::_T_SMS_SEND = sub {
        my $sms = shift;
        $got_sms = $sms;
    };

    my $res = $u2->post_fake_entry;
    is($res->{'success'},      "OK", "did success");
    is($res->{'errmsg'} || "", "", "no errors");
    ok($res->{'url'}, "got a URL");

    LJ::Event->process_fired_events;

    ok($got_sms, "got the SMS");
    is($got_sms->to, 12345, "to right place");

});

sub test_esn_flow {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();
    $cv->($u1, $u2);
}

# create another user and make them friends
#my $u2 = temp_user();
#LJ::add_friend($u2, $u);


1;

