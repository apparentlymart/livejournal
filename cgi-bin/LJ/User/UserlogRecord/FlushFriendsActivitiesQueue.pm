package LJ::User::UserlogRecord::FlushFriendsActivitiesQueue;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'flush_friends_activities_q'}
sub group  {'relations'}

sub description {
    LJ::Lang::ml('userlog.action.flush.friends.activities');
}

1;
