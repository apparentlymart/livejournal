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

    my ($ditemid, $itemid, $anum);
    unless ($uri =~ /(\d+)\.html/) {
        $opts->{'handler_return'} = 404;
        return;
    }
    $ditemid = $1;
    $anum = $ditemid % 256;
    $itemid = $ditemid >> 8;

    my $entry = LJ::Talk::get_journal_item($u, $itemid);
    unless ($entry && $entry->{'anum'} == $anum) {
        $opts->{'handler_return'} = 404;
        return;
    }
    
    my $permalink = LJ::journal_base($u) . "/$ditemid.html";

    my $s2entry = Entry($u, {
        'subject' => $entry->{'subject'},
        'text' => $entry->{'event'},
        'dateparts' => $entry->{'alldatepart'},
        'security' => $entry->{'security'},
        'props' => $entry->{'logprops'},
        'itemid' => $ditemid,
        'journal' => undef, # FIXME UserLite
        'poster' => undef, # FIXME UserLite
        'new_day' => 0,
        'end_day' => 0,
        'userpic' => undef, # FIXME
        'permalink_url' => $permalink,
    });
    $p->{'entry'} = $s2entry;

    return $p;
}

1;
