# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Userpic;
use FindBin qw($Bin);
chdir "$Bin/data/userpics" or die "Failed to chdir to t/data/userpics";

my $up;
my $u = LJ::load_user("system");
ok($u, "Have system user");
die unless $u;

eval { delete_all_userpics($u) };
ok(!$@, "deleted all userpics, if any existed");

$up = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
ok($up, "made a userpic");
is($up->extension, "jpg", "it's a jpeg");

# duplicate testing
{
    my $pre_id = $up->id;
    my $up2 = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
    ok($up2, "made another");
    is($pre_id, $up2->id, "duplicate userpic has same id");
    is($up, $up2, "physical instances are the same");
}

ok(0, "TODO: test things on different backends (mogile, local, db, etc)");
ok(0, "TODO: test w/ , w/o memcached enabled");




sub file_contents {
    my $file = shift;
    open (my $fh, $file) or die $!;
    my $ct = do { local $/; <$fh> };
    return \$ct;
}

sub delete_all_userpics {
    my $u = shift;
    my @userpics = LJ::Userpic->load_user_userpics($u);
    foreach my $up (@userpics) {
        $up->delete;
    }
}
