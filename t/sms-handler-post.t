#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";

require "ljlib.pl";
require "ljprotocol.pl";
require "communitylib.pl";

use LJ::Entry;
use LJ::SMS;
use LJ::SMS::MessageHandler::Post;
use LJ::Test qw(memcache_stress temp_user temp_comm);

run_tests();

sub run_tests {

    # ->owns
    {
        # set up test accounts
        my $u = temp_user();
        my $user = $u->{user};

        # set up account settings
        $u->set_sms_number('+15555551212');

        foreach my $prefix (qw(post p)) {
            foreach my $sec
                ("",
                 ".public",
                 ".pu",
                 ".PuBliC",
                 ".pU",
                 ".friends",
                 ".fr",
                 ".fRieNDS",
                 ".FR",
                 ".private",
                 ".PR",
                 )
            {
                foreach my $subj
                    (map { $_ ? "$_ " : "" }
                     "",
                     "[TestSubject]",
                     "(TestSubject)")
                {
                    my $text = "$prefix$sec ${subj}foo";

                    my $msg = LJ::SMS::Message->new
                        (
                         owner => $u,
                         type  => 'incoming',
                         from  => $u,
                         to    => '12345',
                         body_text => $text
                         );

                    my $rv = LJ::SMS::MessageHandler::Post->owns($msg);
                    ok($rv, "owns: $text");

                    $rv = eval { LJ::SMS::MessageHandler->handle($msg) };
                    my $ok = $rv && ! $@ && $msg && $msg->is_success && ! $msg->error;
                    ok($ok, "handle: $text");
                    warn "rv: $rv, \$@: $@, msg: " . LJ::D($msg) unless $ok;


                    my $jitemid = $msg->meta("post_jitemid");
                    ok($jitemid, "post_jitemid set");
                    ok($msg->meta("handler_type") eq "Post", "handler_type prop set");

                    my $entry = eval { LJ::Entry->new($u, jitemid => $jitemid) };
                    ok($entry && ! $@, "entry in db");
                    ok($entry && $entry->event_text eq "foo", "event text matches");
                    ok($entry && $entry->prop("sms_msgid") eq $msg->id, "event sms_msgid prop matches");
                }
            }
        }
    }

}
