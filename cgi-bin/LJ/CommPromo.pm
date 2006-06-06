#
# LiveJournal Community Promo
#

package LJ::CommPromo;

use strict;
use Carp qw ( croak );

sub render_for_comm {
    my ($class, $comm) = @_;

    croak "Non-community passed to LJ::CommPromo->render_for_community"
        unless $comm && $comm->is_comm;

    return $class->_render($comm);
}

# constructor given target community, loads a CommPromo object
# which can then be rendered
# Class method
sub grab_promo {
    my $class = shift;
    my $comm  = LJ::want_user(shift)
        or croak "Invalid community";

    # choose a community promo to show
    my $dbr = LJ::get_db_reader()
        or die "No db reader";

    my $jid;
    for (1..6) {
        # pick a random number between zero and 2^31 - 1
        my $rand = int(rand($LJ::MAX_32BIT_SIGNED));

        $jid = $dbr->selectrow_array
            ("SELECT journalid FROM comm_promo_list " .
             "WHERE r_start < ? AND r_end > ? AND journalid != ? LIMIT 1",
             undef, $rand, $rand, $comm->{userid});

        die $dbr->errstr if $dbr->err;
        last if $jid;
    }

    return undef unless $jid;

    return LJ::load_userid($jid);
}

sub _render {
    my ($class, $comm) = @_;

    return undef unless $comm;

    # find which community to link to
    my $target = $class->grab_promo($comm);
    return undef unless $target;

    # get the ljuser link
    my $commljuser = $target->ljuser_display;

    # link to journal
    my $journal_base = $target->journal_base;

    # get default userpic if any
    my $userpic = $target->userpic;
    my $userpic_html = '';
    if ($userpic) {
        my $userpic_url = $userpic->url;
        $userpic_html = qq { <a href="$journal_base"><img src="$userpic_url" /></a> };
    }

    my $blurb = "bluby blurb";

    my $html = qq {
        <div class="CommunityPromoBox">
            <div class="CommLink">$commljuser</div>
            <div class="Userpic">$userpic_html</div>
            <div class="Blurb">$blurb</div>
        </div>
    };

    return $html;
}

1;
