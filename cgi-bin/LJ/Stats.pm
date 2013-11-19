# This is a module for returning stats info
# Functions in statslib.pl should get moved here

use strict;

package LJ::Stats;

use LJ::Faq;
use LJ::Lang;

sub get_popular_interests {
    my $memkey = 'pop_interests';
    my $ints;

    # Try to fetch from memcache
    my $mem = LJ::MemCache::get($memkey);
    if ($mem) {
        $ints = $mem;
        return $ints;
    }

    # Fetch from database
    my $dbr = LJ::get_db_reader();
    $ints
        = $dbr->selectall_arrayref(
        "SELECT statkey, statval FROM stats WHERE " . "statcat=? ORDER BY statval DESC, statkey ASC",
        undef, 'pop_interests' );
    return undef if $dbr->err;

    # update memcache
    my $rv = LJ::MemCache::set( $memkey, \@$ints, 3600 );

    return $ints;
}

sub get_popular_faq {
    my ($user, $user_url) = @_;

    my $dbr = LJ::get_db_reader();
    my $rows
        = $dbr->selectall_arrayref( "SELECT statkey FROM stats WHERE statcat='pop_faq' ORDER BY statval DESC LIMIT 10",
        { Slice => {} } );

    my $faq;

    foreach my $r (@$rows) {
        my $f = LJ::Faq->load( $r->{statkey}, 'lang' => LJ::Lang::current_language() );
        $f->render_in_place( { user => $user, url => $user_url } );
        my $q    = $f->question_html;
        my $link = $f->page_url;
        push @$faq, { link => $link, question => $q };
    }

    return $faq;
}

1;
