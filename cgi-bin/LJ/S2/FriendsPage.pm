#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub FriendsPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "FriendsPage";
    $p->{'view'} = "friends";
    $p->{'entries'} = [];

    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $dbcr;
    if ($u->{'clusterid'}) {
        $dbcr = LJ::get_cluster_reader($u);
    }

    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) .
            "/calendar" . $opts->{'pathextra'};
        return 1;
    }

    LJ::load_user_props($dbs, $remote, "opt_nctalklinks");

    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    if ($LJ::UNICODE) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\">\n";
    }

    my %FORM = ();
    LJ::decode_url_string($opts->{'args'}, \%FORM);


    return $p;
}

1;
