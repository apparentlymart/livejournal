# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Userpic;
use FindBin qw($Bin);
use Digest::MD5;
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

# md5 loading tests
{
    my $md5 = Digest::MD5::md5_base64(${file_contents("good.jpg")});
    my $up3 = LJ::Userpic->new_from_md5($u, $md5);
    ok($up3, "Loaded from MD5");
    is($up3, $up, "... is the right one");
    my $bogus = eval { LJ::Userpic->new_from_md5($u, 'wrong size') };
    ok($@, "... got error with invalid md5 length");

    # make the md5 base64 bogus so it won't match anything
    chop $md5; $md5 .= "^";
    my $bogus2 = LJ::Userpic->new_from_md5($u, $md5);
    ok(!$bogus2, "... no instance found");
}

ok(0, "TODO: set_comment");
ok(0, "TODO: set_keywords and keywords accessor");
ok(0, "TODO: Mutable methods modify data structure ");
ok(0, "TODO: setting defaults");
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
