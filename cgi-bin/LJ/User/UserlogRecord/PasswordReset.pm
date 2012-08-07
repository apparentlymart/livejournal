package LJ::User::UserlogRecord::PasswordReset;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action      {'password_reset'}
sub description {'User reset password via lost password email'}

1;
