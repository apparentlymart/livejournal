package LJ::HostedComments;
use strict;
use URI;

# given a URL of a news article off-site, returns the local $u object
# for the journal that's mirroring the content (or excerts) of each
# article for holding comments.
sub journal_of_url {
    my ($class, $url) = @_;

    my $uo   = URI->new($url);
    my $host = $uo->host or return undef;

    my $user = $LJ::HOSTED_COMMENTS_JOURNAL_OF_HOST{lc $host} or return undef;
    return LJ::load_user($user);
}

sub entry_of_url {
    my ($class, $url) = @_;
    my $u = $class->journal_of_url($url) or return undef;

    # TODO: clean URL, removing &lj.foo params
    my $clean_url = $url;

    my $prop = LJ::get_prop("log", "syn_link") or die "no syn_link prop";

    my $jitemid = LJ::MemCache::get_or_set("jit_of_url:$url", sub {
        $u->selectrow_array("SELECT jitemid FROM logprop2 ".
                            "WHERE journalid=? AND propid=? AND value=?",
                            undef, $u->id, $prop->{id}, $clean_url);
    });
    return undef unless $jitemid;
    return LJ::Entry->new($u, jitemid => $jitemid);
}


1;
