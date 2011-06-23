use strict;
package LJ::S2;

use LJ::UserApps;

sub TagsPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts);
    $p->{'_type'} = "TagsPage";
    $p->{'view'} = "tags";
    $p->{'tags'} = [];
    $p->{'head_content'}->set_object_type( $p->{'_type'} );
    $p->{'view_my_games'} = $remote && $remote->equals($u) && !LJ::SUP->is_remote_sup() && LJ::UserApps->user_games_count($remote); 

    my $user = $u->{'user'};
    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }

    # get tags for the page to display
    my @taglist;
    my $tags = LJ::Tags::get_usertags($u, { remote => $remote });
    foreach my $kwid (keys %{$tags}) {
        # only show tags for display
        next unless $tags->{$kwid}->{display};
        push @taglist, LJ::S2::TagDetail($u, $kwid => $tags->{$kwid});
    }
    @taglist = sort { $a->{name} cmp $b->{name} } @taglist;
    $p->{'_visible_tag_list'} = $p->{'tags'} = \@taglist;

    return $p;
}

1;
