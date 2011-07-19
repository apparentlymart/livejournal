package LJ::Event::UserMessageRecvd;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';
use LJ::Message;

sub new {
    my ($class, $u, $msgid, $other_u) = @_;
    foreach ($u, $other_u) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $msgid, $other_u->{userid});
}

sub is_common { 1 }

sub as_email_subject {
    my ($self, $u) = @_;

    my $other_u = $self->load_message->other_u;
    my $lang    = $u->prop('browselang');

    return LJ::Lang::get_text($lang, 'esn.email.pm.subject', undef,
        {
            sender => $self->load_message->other_u->display_username,
        });
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $lang        = $u->prop('browselang');
    my $msg         = $self->load_message;
    my $other_u     = $msg->other_u;
    my $sender      = $other_u->user;
    my $msgid       = $msg->msgid;
    my $inbox       = "$LJ::SITEROOT/inbox/?view=usermsg_recvd&selected=" . $msgid;
    $inbox = "<a href=\"$inbox\">" . LJ::Lang::get_text($lang, 'esn.your_inbox') . "</a>" if $is_html;

    my $vars = {
        user            => $is_html ? ($u->ljuser_display) : ($u->user),
        subject         => $msg->subject,
        body            => $msg->body,
        sender          => $is_html ? ($other_u->ljuser_display) : ($other_u->user),
        postername      => $other_u->user,
        sitenameshort   => $LJ::SITENAMESHORT,
        inbox           => $inbox,
    };

    my $body = LJ::Lang::get_text($lang, 'esn.email.pm_without_body', undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.view_profile'    => [ 1, $other_u->profile_url ],
            'esn.read_journal'    => [ 2, $other_u->journal_base ],
            'esn.add_friend'      => [ $u->is_friend($other_u) ? 0 : 3,
                                            "$LJ::SITEROOT/friends/add.bml?user=$sender" ],
        }
    );

    if ($is_html) {
        $body =~ s/\n/\n<br\/>/g unless $body =~ m!<br!i;
    }

    return $body;
}

sub as_email_string {
    my ($self, $u) = @_;
    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return _as_email($self, $u, 1);
}

sub load_message {
    my ($self) = @_;

    my $msg = LJ::Message->load({msgid => $self->arg1,
                                 journalid => $self->u->{userid},
                                 otherid => $self->arg2});
    return $msg;
}

sub as_html {
    my $self = shift;

    my $msg = $self->load_message;
    my $other_u = $msg->other_u;
    my $pichtml = display_pic($msg, $other_u);
    my $subject = $msg->subject;

    my $ret;
    $ret .= "<div class='pkg'><div style='width: 60px; float: left;'>";
    $ret .= $pichtml . "</div><div>";
    $ret .= $subject;
    $ret .= "<br />from " . $other_u->ljuser_display . "</div>";
    $ret .= "</div>";

    return $ret;
}

sub as_html_actions {
    my $self = shift;

    my $msg = $self->load_message;
    my $msgid = $msg->msgid;
    my $u = LJ::want_user($msg->journalid);

    my $ret = "<div class='actions'>";
    $ret .= " <a href='$LJ::SITEROOT/inbox/compose.bml?mode=reply&msgid=$msgid'>Reply</a>";
    $ret .= " | <a href='$LJ::SITEROOT/friends/add.bml?user=". $msg->other_u->user ."'>Add as friend</a>"
        unless $u->is_friend($msg->other_u);
    $ret .= " | <a href='$LJ::SITEROOT/inbox/markspam.bml?msgid=". $msgid ."'>Mark as Spam</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;

    my $subject = $self->load_message->subject;
    my $other_u = $self->load_message->other_u;
    my $msgid = $self->load_message->msgid;
    my $inbox = "$LJ::SITEROOT/inbox/?view=usermsg_recvd&selected=" . $msgid;
    my $ret = sprintf("You've received a new message \"%s\" from %s. %s",
                   $subject, $other_u->{user},
                   $inbox);
    return $ret;
}

sub as_sms {
    my ($self, $u) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    my $subject = $self->load_message->subject;
    my $other_u = $self->load_message->other_u;

# You've received a new message "[[subject]]" from [[user]]
    return LJ::Lang::get_text($lang, 'notification.sms.usermessagerecvd', undef, {
        subject => $subject,
        user    => $other_u->user,
    });    
}

sub as_alert {
    my $self = shift;
    my $u = shift;

    my $lang    = $u->prop('browselang');
    my $message = $self->load_message;
    my $subject = $message->subject;
    my $other_u = $message->other_u;
    my $msgid   = $message->msgid;

    return LJ::Lang::get_text($lang, 'event.user_message_recvd.alert', undef, {
            subject => $subject,
            selected => $msgid,
            user    => $other_u->ljuser_display(),
        });
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    my $journal = $subscr->journal or croak "No user";

    # "Someone sends $user a message"
    # "Someone sends me a message"
    return LJ::u_equals($journal, $subscr->owner) ?
        LJ::Lang::ml('event.user_message_recvd.me') :
        LJ::Lang::ml('event.user_message_recvd.user', { user => $journal->ljuser_display } );
}

sub content {
    my $self = shift;

    my $msg = $self->load_message;

    my $body = $msg->body;
    $body = LJ::html_newlines($body);

    return $body . $self->as_html_actions;
}

# override parent class sbuscriptions method to always return
# a subscription object for the user
sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = delete $args{'limit'};    # optional
    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my @subs;
    my $u = $self->u;
    return unless ( $cid == $u->clusterid );

    my $row = { userid  => $self->u->{userid},
                ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
              };

    push @subs, LJ::Subscription->new_from_row($row);

    push @subs, eval { $self->SUPER::subscriptions(cluster => $cid,
                                                   limit   => $limit) };

    return @subs;
}

sub display_pic {
    my ($msg, $u) = @_;

    my $pic;
    if ($msg->userpic) {
        $pic = LJ::Userpic->new_from_keyword($u, $msg->userpic);
    } else {
        $pic = $u->userpic;
    }

    my $ret;
    $ret .= '<img src="';
    $ret .= $pic ? $pic->url : "$LJ::STATPREFIX/horizon/nouserpic.png";
    $ret .= '" width="50" align="top" />';

    return $ret;
}

# return detailed data for XMLRPC::getinbox
sub raw_info {
    my ($self, $target) = @_;

    my $res = $self->SUPER::raw_info;

    my $msg = $self->load_message;

    my $pic;
    if ($msg->userpic) {
        $pic = LJ::Userpic->new_from_keyword($msg->other_u, $msg->userpic);
    } else {
        $pic = $msg->other_u->userpic;
    }

    $res->{from} = $msg->other_u->user;
    $res->{from_id} = $msg->other_u->{userid};
    $res->{picture} = $pic->url if $pic;
    $res->{picture_id} = $pic->picid if $pic;
    $res->{subject} = $msg->subject;
    $res->{body} = $msg->body;
    $res->{msgid} = $msg->msgid;
    $res->{msg_type} = $msg->type;
    $res->{timesent} = $msg->timesent;
    $res->{parent} = $msg->parent_msgid if $msg->parent_msgid;

    return $res;
}

sub available_for_user  {
    my ($self, $u) = @_;

    return $self->userid != $u->id ? 0 : 1;
}

sub is_subscription_visible_to  {
    my ($self, $u) = @_;

    return $self->userid != $u->id ? 0 : 1;
}

sub is_tracking { 0 }

sub is_subscription_ntype_disabled_for {
    my ($self, $ntypeid, $u) = @_;

    return 1 if $ntypeid == LJ::NotificationMethod::Inbox->ntypeid;
    return $self->SUPER::is_subscription_ntype_disabled_for($ntypeid, $u);
}

sub get_subscription_ntype_force {
    my ($self, $ntypeid, $u) = @_;

    return 1 if $ntypeid == LJ::NotificationMethod::Inbox->ntypeid;
    return $self->SUPER::get_subscription_ntype_force($ntypeid, $u);
}

1;
