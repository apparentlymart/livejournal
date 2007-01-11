# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Directory::Search;

my @args;

my $is = sub {
    my ($name, $str, @good_cons) = @_;
    my %args = map { LJ::durl($_) } split(/[=&]/, $str);
    my @cons = sort { ref($a) cmp ref($b) } LJ::Directory::Constraint->constraints_from_formargs(\%args);
    is_deeply(\@cons, \@good_cons, $name);
};

$is->("US/Oregon",
      "loc_cn=US&loc_st=OR&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR'));

$is->("OR (without US)",
      "loc_cn=&loc_st=OR&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR'));

$is->("Oregon (without US)",
      "loc_cn=&loc_st=Oregon&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR'));

$is->("Russia",
      "loc_cn=RU&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'RU'));

$is->("Age Range + last week",
      "loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=14&age_max=27&int_like=&fr_user=&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100",
      LJ::Directory::Constraint::Age->new(from => 14, to => 27),
      LJ::Directory::Constraint::UpdateTime->new(days => 7));

$is->("Interest",
      "int_like=lindenz&opt_sort=ut",
      LJ::Directory::Constraint::Interest->new(int => 'lindenz'));

$is->("Has friend",
      "fr_user=system&opt_sort=ut",
      LJ::Directory::Constraint::HasFriend->new(user => 'system'));

$is->("Is friend of",
      "fro_user=system&opt_sort=ut",
      LJ::Directory::Constraint::FriendOf->new(user => 'system'));

$is->("Is a community",
      "journaltype=C&opt_sort=ut",
      LJ::Directory::Constraint::JournalType->new(journaltype => 'C'));

# serializing tests
{
    my ($con, $back, $str);
    $con = LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR');
    is($con->serialize, "Location:country=US&state=OR", "serializes");
    $con = LJ::Directory::Constraint::Location->new(country => 'US', state => '');
    $str = $con->serialize;
    is($str, "Location:country=US", "serializes");
    $back = LJ::Directory::Constraint->deserialize($str);
    ok($back, "went back");
    is(ref $back, ref $con, "same type");
}

# init the search system
my $inittime = time();
{
    my $users = 100;
    LJ::UserSearch::reset_usermeta(($users + 1) * 4);
    for (0..$users) {
        my $buf = pack("NN", $inittime - $users + $_, 0);
        LJ::UserSearch::add_usermeta($buf, 8);
    }
}

# doing actual searches
{
    my ($search, $res);
    local @LJ::GEARMAN_SERVERS = ();  # don't dispatch set requests.  all in-process.

    $search = LJ::Directory::Search->new;
    ok($search, "made a search");

    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5"));
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "2,3,4,5,6,2,2,2,2,2,2,2"));

    $res = $search->search_no_dispatch;
    ok($res, "got a result");

    is($res->pages, 1, "just one page");
    is_deeply([$res->userids], [5,4,3,2], "got the right results back");

    # test paging
    $search = LJ::Directory::Search->new(page_size => 2, page => 2);
    is($search->page, 2, "requested page 2");
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9,10"));
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9,10,11,12,14,15,888888888"));
    $res = $search->search_no_dispatch;
    is($res->pages, 5, "five pages");
    is_deeply([$res->userids], [8,7], "got the right results back");

    # test paging, not even page size
    $search = LJ::Directory::Search->new(page_size => 2, page => 3);
    is($search->page, 3, "requested page 3");
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9"));
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9,10,11,12,14,15,888888888"));
    $res = $search->search_no_dispatch;
    is($res->pages, 5, "five pages");
    is_deeply([$res->userids], [5,4], "got the right results back");

    # test update times
    $search = LJ::Directory::Search->new;
    $search->add_constraint(LJ::Directory::Constraint::UpdateTime->new(since => ($inittime - 5)));
    $res = $search->search_no_dispatch;
    is_deeply([$res->userids], [10,9,8,7,6,5,4], "got recent posters");

}


__END__


# update last week, 14 to 17 years old:


# kde last week
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=kde&fr_user=&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100

# lists brad as friend:
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=&fr_user=brad&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100

# brad lists as friend:
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=&fr_user=&fro_user=brad&opt_format=pics&opt_sort=ut&opt_pagesize=100

