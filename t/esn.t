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

$evt = LJ::Event::ForTest1->new($u, 5, 39);
ok($evt, "made event1");
$evt2 = LJ::Event::ForTest2->new($u, 5, 39);
ok($evt, "made event2");

wipe_typeids();

ok($evt->etypeid, "got typeid: " . $evt->etypeid);
is($evt->etypeid, $evt->etypeid, "stayed the same");
ok($evt2->etypeid);
ok($evt->etypeid != $evt2->etypeid);

is(LJ::Event->class($evt->etypeid),  ref $evt,  "LJ::Event->class");
is(LJ::Event->class($evt2->etypeid), ref $evt2);

my @classes = $evt->all_classes;
ok(@classes);
ok(scalar (grep { $_ =~ /ForTest1/ } @classes), "found our class");

$evt2->fire;


sub wipe_typeids {
    my $dbh = LJ::get_db_writer();
    $dbh->do("DELETE FROM eventtypelist WHERE class LIKE 'LJ::Event::ForTest1'");
    my $max = $dbh->selectrow_array("SELECT MAX(eventtypeid) FROM eventtypelist") + 1;
    $dbh->do("ALTER TABLE eventtypelist AUTO_INCREMENT=$max");
}


package LJ::Event::ForTest1;
use base 'LJ::Event';

package LJ::Event::ForTest2;
use base 'LJ::Event';

sub is_common { 1 }

1;

