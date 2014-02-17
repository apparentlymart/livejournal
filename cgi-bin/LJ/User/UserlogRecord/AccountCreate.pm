package LJ::User::UserlogRecord::AccountCreate;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'account_create'}
sub group  {'account'}

sub description {
    return LJ::Lang::ml('userlog.action.account.create');
}

1;
