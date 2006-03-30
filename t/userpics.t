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

sub run_tests {
    my ($up, $ext) = @_;

    # test comments
    {
        $up->set_comment('');
        ok(! $up->comment, "... has no comment set");
        my $cmt = "Comment on first userpic";
        ok($up->set_comment($cmt), "Set a comment.");
        is($up->comment, $cmt, "... it matches");
    }

    # duplicate testing
    {
        my $pre_id = $up->id;
        my $up2 = eval { LJ::Userpic->create($u, data => file_contents("good.$ext")); };
        ok($up2, "made another");
        is($pre_id, $up2->id, "duplicate userpic has same id");
        is($up, $up2, "physical instances are the same");
    }

    # md5 loading tests
    {
        my $md5 = Digest::MD5::md5_base64(${file_contents("good.$ext")});
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

    # set/get/clear keywords
    {
        my $keywords = 'keyword1, keyword2, keyword3';
        my @keywordsa = split(',', $keywords);

        $up->set_keywords($keywords);
        my $keywords_scalar = $up->keywords;
        is($keywords, $keywords_scalar, "... keywords match");
        my @keywords_array = $up->keywords;
        eq_array(\@keywordsa, \@keywords_array, "... keyword arrays match");

        $up->set_keywords(@keywordsa);
        @keywords_array = $up->keywords;
        eq_array(\@keywords_array, \@keywordsa, "... setting/retreiving array works");

        # clear keywords
        $up->set_keywords('');
        is($up->keywords('raw' => 1), '', "Emptied keywords");
    }

    # test defaults
    {
        $up->make_default;
        my $id = $up->id;
        is($id, $u->{defaultpicid}, "Set default pic");
        ok($up->is_default, "... accessor says yes");
    }

    # fullurl
    {
        my $fullurl = 'http://pics.livejournal.com/revmischa/pic/0088h66f';
        $up->set_fullurl($fullurl);
        is($up->fullurl, $fullurl, "Set fullurl");
    }

    return 1;
}

eval { delete_all_userpics($u) };
ok(!$@, "deleted all userpics, if any existed");

my $ext;
for(('jpg', 'png', 'gif')) {
    $ext = $_;

    $up = eval { LJ::Userpic->create($u, data => file_contents("good.$ext")); };
    ok($up, "made a userpic");
    die "ERROR: $@" unless $up;
    is($up->extension, $ext, "... it's a $ext");
    ok(! $up->inactive, "... not inactive");
    ok($up->state, "... have some state");
}

ok(run_tests($up, $ext), "Memcache. Now trying without.");

local $LJ::MemCache::GET_DISABLED = 1;
ok(run_tests($up, $ext), 'Without memcache');

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
