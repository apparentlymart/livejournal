# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Event;
use FindBin qw($Bin);

my $up;
my $u = LJ::load_user("system");
my $evt;

$evt = LJ::Event::ForTest1->new($u, 5, 39);
ok($evt, "made event1");
$evt = LJ::Event::ForTest2->new($u, 5, 39);
ok($evt, "made event2");

$evt = eval { LJ::Event::ForTest2->new($u, 5, 39, 8); };
like($@, qr/too many/, "too many args");
$evt = eval { LJ::Event::ForTest2->new($u, "foo"); };
like($@, qr/numeric/, "must be numeric");


package LJ::Event::ForTest1;
use base 'LJ::Event';

package LJ::Event::ForTest2;
use base 'LJ::Event';

1;

