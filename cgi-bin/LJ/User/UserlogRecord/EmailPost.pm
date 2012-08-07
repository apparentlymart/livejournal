package LJ::User::UserlogRecord::EmailPost;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action      {'emailpost'}
sub description {'User posted via email gateway'}

1;
