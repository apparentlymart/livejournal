package LJ::Portal::Box::Notifications; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "Notifications";
our $_box_description = "Notifications Inbox";
our $_box_name = "Notifications Inbox";
our $_prop_keys = {
    'maxnotices' => 2,
    'daysold'    => 1,
};
our $_config_props = {
    'maxnotices'  => {
        'type'    => 'integer',
        'desc'    => 'Maximum number of notices to display',
        'default' => 5,
        'min'     => 1,
        'max'     => 50,
    },
    'daysold'  => {
        'type'    => 'integer',
        'desc'    => 'How many days to save notifications',
        'default' => 50,
        'min'     => 1,
        'max'     => 365,
    },
};

sub handle_request {
    my ($self, $GET, $POST) = @_;

    # process any deletions
    if ($GET->{'delete_note'} || $POST->{'delete_note'}) {
        my $q = $self->queue or return undef;
        my $qid = int($GET->{'del_note_qid'} || $POST->{'del_note_qid'});
        $q->delete_from_queue($qid) if $qid;
    }

    return undef;
}

sub queue {
    my $self = shift;
    return LJ::NotificationInbox->new($self->{u});
}

sub generate_content {
    my $self = shift;

    my $pboxid = $self->pboxid;
    my $u = $self->{u};

    my $content = '';
    my $maxnotices = $self->get_prop('maxnotices');
    my $daysold    = $self->get_prop('daysold');

    my $q = $self->queue;
    return "Could not retreive inbox." unless $q;

    my $notices = $q->notifications($daysold);

    $content .= qq {
        <table style="width: 100%;">
            <tr class="PortalTableHeader"><td>Date</td><td>Notification</td><td>Delete</td></tr>
        };

    my $noticecount = 0;

    while ( my ($qid, $evt) = each %$notices ) {
        my $desc = $evt->as_html;
        my $delrequest = "portalboxaction=$pboxid&delete_note=1&del_note_qid=$qid";

        my $delicon = "<img src=\"$LJ::IMGPREFIX/portal/btn_del.gif\" align=\"center\" />";

        my $rowmod = $noticecount % 2 + 1;
        $content .= qq {
            <tr class="PortalRow$rowmod">
                <td>(no date yet)</td>
                <td>$desc</td>
                <td align="center"><a href="/portal/index.bml?$delrequest" onclick="return evalXrequest('$delrequest', null);">$delicon</a></td>
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

# caching options
sub cache_global { 0; } # cache per-user
sub cache_time { 5 * 60; } # check etag every 5 minutes
sub etag {
    my $self = shift;

    my $daysold = $self->get_prop('daysold');
    my $maxnotices = $self->get_prop('maxnotices');

    my $q = $self->queue or return undef;

    my $notifications = $q->notifications;
    return "$daysold-" . join('-', keys %$notifications); # qids
}

1;
