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
      LJ::Directory::Constraint::UpdateTime->new(7));

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

__END__


# update last week, 14 to 17 years old:


# kde last week
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=kde&fr_user=&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100

# lists brad as friend:
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=&fr_user=brad&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100

# brad lists as friend:
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=&fr_user=&fro_user=brad&opt_format=pics&opt_sort=ut&opt_pagesize=100

