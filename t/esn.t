
# -*-perl-*-

@LJ::EVENT_TYPES = ('LJ::Event::ForTest1', 'LJ::Event::ForTest2');

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Event;
use FindBin qw($Bin);

my $up;
my $u = LJ::load_user("system");
my ($evt, $evt2);

$evt = eval { LJ::Event::ForTest2->new($u, 5, 39, 8); };
like($@, qr/too many/, "too many args");
$evt = eval { LJ::Event::ForTest2->new($u, "foo"); };
like($@, qr/numeric/, "must be numeric");

{
    # event tests
    $evt = LJ::Event::ForTest1->new($u, 5, 39);
    ok($evt, "made event1");
    $evt2 = LJ::Event::ForTest2->new($u, 5, 39);
    ok($evt, "made event2");

    wipe_typeids();

    ok($evt->etypeid, "got typeid: " . $evt->etypeid);
    is($evt->etypeid, $evt->etypeid, "stayed the same");
    ok($evt->etypeid != $evt2->etypeid, "different typeids");

    is(LJ::Event->class($evt->etypeid),  ref $evt,  "LJ::Event->class");
    is(LJ::Event->class($evt2->etypeid), ref $evt2, "Got correct class");

    my @classes = $evt->all_classes;
    ok(@classes, "Got classes");
    ok(scalar (grep { $_ =~ /ForTest1/ } @classes), "found our class");
}

my $nm = LJ::NotificationMethod::ForTest->new($u);
ok($nm, "Made new email notificationmethod");

{
    # subscribe system to an event
    my $subscr = eval {
        $u->subscribe(
                      etypeid   => $evt2->etypeid,
                      ntypeid   => $nm->ntypeid,
                      arg1      => 69,
                      arg2      => 42,
                      journalid => $u->{userid},
                      );
    };

    ok($subscr, "Subscribed");

    # fire the event
    $evt->fire;
    $nm->notify($evt);
}


sub wipe_typeids {
    my $tm = LJ::Event->typemap or die;
    $tm->delete_class('LJ::Event::ForTest1');
    $tm->delete_class('LJ::Event::ForTest2');
}


package LJ::Event::ForTest1;
use base 'LJ::Event';

package LJ::Event::ForTest2;
use base 'LJ::Event';

package LJ::NotificationMethod::ForTest;
use base 'LJ::NotificationMethod';
sub notify {
    my $self = shift;
    die unless $self;

    my @events = @_;

    my $u = $self->{u};
    warn "Notifying $u->{user}: '" . $events[0]->as_string . "'\n";
}

sub new { return bless { u => $_[1] }, $_[0] }

sub is_common { 1 }

1;

