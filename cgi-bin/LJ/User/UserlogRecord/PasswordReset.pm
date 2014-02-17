package LJ::User::UserlogRecord::PasswordReset;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'password_reset'}
sub group  {'security'}

sub description {
    return LJ::Lang::ml('userlog.action.password.reset');
}

1;
