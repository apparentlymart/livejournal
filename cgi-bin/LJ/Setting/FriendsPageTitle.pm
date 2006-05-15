package LJ::Setting::FriendsPageTitle;
use base 'LJ::Setting::TextSetting';
use strict;
use warnings;

sub tags { qw(friends page title) }

sub prop_name { "friendspagetitle" }
sub text_size { 40 }
sub question { "Friends Page Title &nbsp;" }

1;

