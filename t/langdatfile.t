#!/usr/bin/perl
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::LangDatFile;
use Test::More 'no_plan';

my $trans = LJ::LangDatFile->new("$ENV{LJHOME}/t/data/sampletrans.dat");
ok($trans, "Constructed a trans object");

is($trans->value("/loldongs.bml.btn.status"), "Change Status", "Parsed translation string");
like($trans->value("/lolsquatch.bml.banner"), qr/hyphytown/, "Parsed multiline translation string");
