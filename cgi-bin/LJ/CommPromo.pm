#
# LiveJournal Community Promo
#

package LJ::CommPromo;

use strict;
use Carp qw ( croak );

sub render_for_comm {
    my ($class, $comm) = @_;

    return $class->_render($comm);
}

# constructor given target community, loads a CommPromo object
# which can then be rendered
# Class method
sub grab_promo {
    my $class = shift;
    my $comm  = LJ::want_user(shift);

    # choose a community promo to show
    my $dbr = LJ::get_db_reader()
        or die "No db reader";

    my $jid;
    for (1..6) {
        # pick a random number between zero and 2^31 - 1
        my $rand = int(rand($LJ::MAX_32BIT_SIGNED));

        my $sql = "SELECT journalid FROM comm_promo_list WHERE r_start < ? AND r_end > ?";
        my @args = ($rand, $rand);

        if ($comm) {
            $sql .= " AND journalid != ? ";
            push @args, $comm->{userid};
        }

        $sql .= " LIMIT 1";

        $jid = $dbr->selectrow_array($sql, undef, @args);

        die $dbr->errstr if $dbr->err;
        last if $jid;
    }

    return undef unless $jid;

    return LJ::load_userid($jid);
}

sub _render {
    my ($class, $comm) = @_;

    # find which community to link to
    my $target = $class->grab_promo($comm);
    return undef unless $target;

    return $class->render_promo_of_community($target);
}

sub render_promo_of_community {
    my ($class, $comm, $style) = @_;

    return undef unless $comm;

    $style ||= 'Vertical';

    # get the ljuser link
    my $commljuser = $comm->ljuser_display;

    # link to journal
    my $journal_base = $comm->journal_base;

    # get default userpic if any
    my $userpic = $comm->userpic;
    my $userpic_html = '';
    if ($userpic) {
        my $userpic_url = $userpic->url;
        $userpic_html = qq { <a href="$journal_base"><img src="$userpic_url" /></a> };
    }

    my $blurb = $comm->prop('comm_promo_blurb') || '';

    my $join_link = "$LJ::SITEROOT/community/join.bml?comm=$comm->{user}";
    my $watch_link = "$LJ::SITEROOT/friends/add.bml?user=$comm->{user}";
    my $read_link = $comm->journal_base;

    LJ::need_res("stc/lj_base.css");

    # if horizontal, userpic needs to come before everything
    my $box_class;
    my $comm_display;

    if (lc $style eq 'horizontal') {
        $box_class = 'Horizontal';
        $comm_display = qq {
            <div class="Userpic">$userpic_html</div>
            <div class="Title">LJ Community Promo</div>
            <div class="CommLink">$commljuser</div>
        };
    } else {
        $box_class = 'Vertical';
        $comm_display = qq {
            <div class="Title">LJ Community Promo</div>
            <div class="CommLink">$commljuser</div>
            <div class="Userpic">$userpic_html</div>
        };
    }


    my $html = qq {
        <div class="CommunityPromoBox">
            <div class="$box_class">
                $comm_display
                <div class="Blurb">$blurb</div>
                <div class="Links"><a href="$join_link">Join</a> | <a href="$watch_link">Watch</a> |
                    <a href="$read_link">Read</a></div>

                <div class='ljclear'>&nbsp;</div>
            </div>
        </div>
    };

    return $html;
}

1;
