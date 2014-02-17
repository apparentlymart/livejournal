package LJ::User::UserlogRecord::PasswordChange;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'password_change'}
sub group  {'security'}

sub description {
    return LJ::Lang::ml('userlog.action.password.change');
}

1;
