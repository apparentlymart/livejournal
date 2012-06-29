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
    my $qid         = $msg->qid;
    my $inbox       = "$LJ::SITEROOT/inbox/?view=usermsg_recvd&selected=" . $msgid . "#all_Row_$qid";
    $inbox = "<a href=\"$inbox\">" . LJ::Lang::get_text($lang, 'esn.your_inbox') . "</a>" if $is_html;

    my $vars = {
        user            => $is_html ? ($u->ljuser_display) : ($u->user),
        subject         => $msg->subject,
        sender          => $is_html ? ($other_u->ljuser_display) : ($other_u->user),
        postername      => $other_u->user,
        sitenameshort   => $LJ::SITENAMESHORT,
        inbox           => $inbox,
        siteroot        => $LJ::SITEROOT,
    };

    my $reply_lnk = "$LJ::SITEROOT/inbox/compose.bml?mode=reply&msgid=$msgid";

    my $ml_var = 'esn.email.pm_without_body';
    if ( $u->get_cap('full_pm_esn') ) {
        # paid users receive full texts of messages
        $ml_var = 'esn.email.pm';
        $vars->{'body'} = $msg->body;
    }

    my $body = LJ::Lang::get_text($lang, $ml_var, undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.reply_message'   => [ 1, $reply_lnk ],
            'esn.view_profile'    => [ 2, $other_u->profile_url ],
            'esn.read_journal'    => [ 3, $other_u->journal_base ],
            'esn.add_friend'      => [ $u->is_friend($other_u) ? 0 : 4,
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
    my %opts = @_;

    my $msg = $self->load_message;
    my $msgid = $msg->msgid;
    my $u = LJ::want_user($msg->journalid);

    my $ret = "<div class='actions'>";
    $ret .= " <a href='$LJ::SITEROOT/inbox/compose.bml?mode=reply&msgid=$msgid'>".LJ::Lang::ml('esn.html_actions.reply')."</a>";

    if (LJ::is_enabled('spam_inbox') && $opts{'state'} && $opts{'state'} eq 'S') {
        $ret .= " | <a href='#' class='mark-notspam'>".LJ::Lang::ml('esn.html_actions.unspam')."</a>";
    } else {
        $ret .= " | <a href='$LJ::SITEROOT/friends/add.bml?user=". $msg->other_u->user ."'>".LJ::Lang::ml('esn.html_actions.add_as_friend')."</a>"
            unless $u->is_friend($msg->other_u);
        $ret .= " | <a href='$LJ::SITEROOT/inbox/markspam.bml?msgid=". $msg->msgid ."' class='mark-spam'>".LJ::Lang::ml('esn.html_actions.spam')."</a>";
    }
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;

    my $subject = $self->load_message->subject;
    my $other_u = $self->load_message->other_u;
    my $msgid   = $self->load_message->msgid;
    my $qid     = $self->load_message->qid;

    my $inbox = "$LJ::SITEROOT/inbox/?view=usermsg_recvd&selected=" . $msgid . "#all_Row_$qid";
    my $ret = sprintf("You've received a new message \"%s\" from %s. %s",
                   $subject, $other_u->{user},
                   $inbox);
    return $ret;
}

sub as_sms {
    my ($self, $u) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    
    my $subject = '';

    # make subject if if not empty
    $subject = $self->load_message->subject
        if $self->load_message->subject_raw;

    my $other_u = $self->load_message->other_u;
    my $body    = $self->load_message->body;

    # %usename% sent you a message on LiveJournal: %Message_Subject%
    # %Message_Body%
    # ------
    # To respond, send your reply to the number this message was sent from. LiveJournal will automatically forward it to %usename%. 
    #
    my $text = LJ::Lang::get_text($lang, 'notification.sms.usermessagerecvd', undef, {
        subject => $subject,
        body    => $body,
        user    => $other_u->user,
    });    

    return $text;
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

sub as_push {
    my $self = shift;
    my $u = shift;
    my $lang = shift;
    my %opts = @_;
   
    if (exists $opts{'message'}) {
        my $msg = $self->load_message;
        return $msg->body; 
    }

    return LJ::Lang::get_text($lang, "esn.push.notification.usermessagerecvd", 1, {
        user => $self->load_message->other_u->{user},
    })
}

sub as_push_payload {
    my $self = shift;
    my $lang = shift; 
    my $os = shift;

    return { 'm' => int($self->arg1),
             't' => 9,};
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
    my ($u, $state) = @_;

    my $msg = $self->load_message;

    my $body = $msg->body;
    $body = LJ::html_newlines($body);

    return $body . $self->as_html_actions( 'state' => $state );
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
    $ret .= $pic ? $pic->url : "$LJ::STATPREFIX/horizon/nouserpic.png?v=2621";
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

    my $poster = $msg->other_u;
    if($poster->is_identity){
        my $i = $poster->identity;
        $res->{'poster_identity_type'}    = $i->pretty_type;
        $res->{'poster_identity_value'}   = $i->value;
        $res->{'poster_identity_url'}     = $i->url($poster);
        $res->{'poster_identity_display'} = $msg->other_u->display_name;
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
