package LJ::User::UserlogRecord::FlushFriendsActivitiesQueue;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action      {'flush_friends_activities_q'}
sub description {'Flushed the queue of friends activities'}

1;
