# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::ExternalSite::Vox;

my $vox = LJ::ExternalSite::Vox->new;
ok($vox);


1;

