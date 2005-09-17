package LJ::Portal::Box::Announcements; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "Announcements";
our $_box_description = "News and announcements from the $LJ::SITENAME Staff";
our $_box_name = "$LJ::SITENAME Announcements";
our $_prop_keys = {
    'shownews' => 2,
    'deletednotices' => 5,
    'maxnotices' => 1,
    'showpaid' => 4,
    'showmaintenance' => 3,
};
our $_config_props = {
    'shownews' => {
        'type'      => 'checkbox',
        'desc'      => 'Display latest posts from news',
        'default'   => 1,
    },
    'showmaintenance' => {
        'type'      => 'checkbox',
        'desc'      => 'Display latest posts from lj_maintenance',
        'default'   => 1,
    },
    'showpaid' => {
        'type'      => 'checkbox',
        'desc'      => 'Display latest posts from paidaccounts',
        'default'   => undef,
        'disabled'   => \&isdisabled,
    },
    'deletednotices' => {
        'type'     => 'hidden',
        'default'  => '',
    },
    'maxnotices'  => {
        'type'    => 'integer',
        'desc'    => 'Maximum number of notices to display',
        'default' => 5,
        'min'     => 1,
        'max'     => 50,
    },
};

sub isdisabled {
    my $self = shift;
    return !$self->ispaidacct;
}

sub ispaidacct {
    my $self = shift;
    my $u = $self->{'u'};
    return LJ::get_cap($u, 'paid') || 0;
}

sub initialize {
    my $self = shift;

    # showpaid needs to be initialized to correct default value
    if (!defined $self->get_prop('showpaid')) {

        # add paidmembers by default if paid account
        if ($self->ispaidacct) {
            $self->set_prop('showpaid', '1');
        } else {
            $self->set_prop('showpaid', '0');
        }
    }
}

sub handle_request {
    my ($self, $GET, $POST) = @_;

    my @deleted = $self->get_prop('deletednotices') ? split ':', $self->get_prop('deletednotices') : ();

    # process any deletions
    if ($GET->{'delete_announcement'} || $POST->{'delete_announcement'}) {
        my $uid = ($GET->{'del_ann_uid'} || $POST->{'del_ann_uid'}) + 0;
        my $itemid = ($GET->{'del_ann_itemid'} || $POST->{'del_ann_itemid'}) + 0;
        if ($uid && $itemid) {
            push @deleted, "$uid-$itemid";
            $self->set_prop('deletednotices', join(':', @deleted));
        }
    }
    return undef;
}

sub generate_content {
    my $self = shift;

    my $pboxid = $self->pboxid;

    my $content = '';
    my $shownews = $self->get_prop('shownews');
    my $showmaint = $self->get_prop('showmaintenance');
    my $showpaid = $self->get_prop('showpaid');
    my $maxnotices = $self->get_prop('maxnotices');
    my $noticecount = 0;

    my @toget;

    push @toget, 'news' if ($shownews);
    push @toget, 'paidmembers' if ($showpaid);
    push @toget, 'lj_maintenance' if ($showmaint);

    $content .= qq {
        <table style="width: 100%;">
            <tr class="PortalTableHeader"><td>Date</td><td>From</td><td>Subject</td><td>Delete</td></tr>
        };

    my $entries = {};

    foreach my $user (@toget) {
        # retreive news
        my $u = LJ::load_user($user);
        return "Error: could not find user $user.\n" unless $u;

        my $err;
        my @itemids;
        my @posts;

        push @posts, LJ::get_recent_items( {
            'err' => \$err,
            'userid' => $u->{'userid'},
            'remote' => $self->{'u'},
            'clusterid' => $u->{'clusterid'},
            'itemshow' => 3,
            'itemids' => \@itemids,
            'dateformat' => 'S2',
            'order' => ($u->{'journaltype'} eq "C" || $u->{'journaltype'} eq "Y")
                ? "logtime" : "",
        });

        my $items = LJ::get_logtext2($u, @itemids);

        for (my $i = 0; $i < scalar @itemids; $i++) {
            my $itemid = $itemids[$i];
            my $date = $posts[$i]->{'alldatepart'};
            my $userid = $u->{'userid'};
            $date =~ s/\s//g;
            $entries->{"$date$itemid$userid"} = [$posts[$i], $u, $items->{$itemid}];
        }

        return "Error loading $user: $err\n" if $err;

    }

    foreach my $date (reverse (sort keys %$entries)) {
        my $post = $entries->{$date};

        my $u = $post->[1];
        my $itemid = $post->[0]->{'itemid'};
        my $text = $post->[2];

        # if the user deleted this, don't show it
        my @deleted = split ':', $self->get_prop('deletednotices');
        my $user_deleted = 0;
        foreach my $delann (@deleted) {
            my ($deluid, $delitemid) = split '-', $delann;
            if ($deluid == $u->{'userid'} && $delitemid == $itemid) {
                $user_deleted = 1;
                last;
            }
        }
        next if $user_deleted;

        my $subject = $text->[0];
        my $poster = LJ::ljuser($u);
        LJ::CleanHTML::clean_subject(\$subject) if ($subject);
        $subject ||= "(no subject)";

        my $delrequest = "portalboxaction=$pboxid&delete_announcement=1&del_ann_uid=$u->{userid}&del_ann_itemid=$itemid";

        my @date = split ' ', $post->[0]->{'alldatepart'};

        my $entrylink = LJ::item_link($u, $itemid, $post->[0]->{'anum'});

        my $rowmod = $noticecount % 2 + 1;
        $content .= qq {
            <tr class="AnnouncementRow$rowmod">
                <td>$date[0]-$date[1]-$date[2]</td>
                <td>$poster</td>
                <td><a href="$entrylink">$subject</a></td>
                <td><a href="/portal/index.bml?$delrequest" onclick="return evalXrequest('$delrequest', null);">[X]</a></td>
            </tr>
            };

        $noticecount++;
        last if $noticecount >= $maxnotices;
    }

    $content .= '</table>';

    return $content;
}


#######################################

sub can_refresh { 1; }
sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }

1;
