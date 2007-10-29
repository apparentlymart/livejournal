#!/usr/bin/perl
#

use strict;

use vars qw(%cap_local);

# Local caps are placed here.
# Use format in cap2db.pl; substituting 'caps_general' with 'caps_local'

$caps_local{'paid'} = {
    type => 'boolean',
    desc => 'User has paid for their account type.',
};
$caps_local{'fastserver'} = {
    type => 'boolean',
    desc => 'User has access to the faster (paid) servers.',
};

