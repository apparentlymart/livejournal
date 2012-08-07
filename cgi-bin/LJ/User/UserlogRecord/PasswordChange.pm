package LJ::User::UserlogRecord::PasswordChange;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action      {'password_change'}
sub description {'User changed password'}

1;
