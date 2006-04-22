#!/usr/bin/perl
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Typemap;
use LJ::Test;

# Warning: this test will create bogus types in your typemap table!

my $table = 'portal_typemap';
my $classfield = 'class_name';
my $idfield = 'id';

sub run_tests {
    my $tm;

    {
        # create bogus typemaps
        eval { LJ::Typemap->new() };
        like($@, qr/No table/, "No table passed");
        eval { LJ::Typemap->new(table => 'bogus"', idfield => $idfield, classfield => $classfield) };
        like($@, qr/Invalid arguments/, "Invalid arguments");

        # create a typemap
        $tm = eval { LJ::Typemap->new(table => $table, idfield => $idfield, classfield => $classfield) };
        ok($tm, "Got typemap");
    }

    {
        # try to look up nonexistant typeid
        eval { $tm->typeid_to_class(9999) };
        like($@, qr/No class for id/, "Invalid class id");

        my $class = 'oogabooga';

        # insert a new class that shouldn't exist, should get a typeid
        my $id = $tm->class_to_typeid($class);
        ok(defined $id, "$class id is $id");

        # now look up the id and see if it matches the class
        my $gotclass = $tm->typeid_to_class($id);
        is($gotclass, $class, "Got class: $class for id $id");
    }
}

memcache_stress {
    run_tests();
}
