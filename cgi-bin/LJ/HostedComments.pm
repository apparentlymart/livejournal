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


1;
