#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub EntryPage
{
    my ($u, $remote, $opts) = @_;

    my $ctx = $opts->{'ctx'};
    my $r = $opts->{'r'};
    my $uri = $r->uri;

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "EntryPage";
    $p->{'view'} = "entry";
    $p->{'comment_pages'} = undef;
    $p->{'comments'} = [];

    my ($itemid, $anum);
    unless ($uri =~ /(\d+)\.html/) {
        $r->log_error("Bogus URL: $uri");
        $opts->{'handler_return'} = 404;
        return;
    }
    $itemid = $1;
    $anum = $itemid % 256;
    $itemid = $itemid >> 8;

    my $entry = LJ::Talk::get_journal_item($u, $itemid);
    unless ($entry && $entry->{'anum'} == $anum) {
        $r->log_error("real anum = $anum, entry = $entry, its anum = $entry->{'anum'}");
        $opts->{'handler_return'} = 404;
        return;
    }

    my $s2entry = {
        '_type' => "Entry",
        'subject' => $entry->{'subject'},
        'text' => $entry->{'event'},
    };
    $p->{'entry'} = $s2entry;

    return $p;
}

1;
