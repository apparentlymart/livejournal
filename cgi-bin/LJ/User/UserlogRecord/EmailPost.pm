package LJ::User::UserlogRecord::EmailPost;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'emailpost'}
sub group  {'entries'}

sub description {
    return LJ::Lang::ml('userlog.action.email.post');
}

1;
