#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub EntryPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "EntryPage";
    $p->{'view'} = "entry";
    $p->{'days'} = [];

    return $p;
}

1;
