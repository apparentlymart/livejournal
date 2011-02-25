package LJ::Event::UserMessageSent;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';
use LJ::Message;
use LJ::NotificationMethod::Inbox;

sub new {
    my ($class, $u, $msgid, $other_u) = @_;
    foreach ($u, $other_u) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $msgid, $other_u->{userid});
}

# TODO Should this return 1?
sub is_common { 1 }

sub load_message {
    my ($self) = @_;

    my $msg = LJ::Message->load({msgid => $self->arg1, journalid => $self->u->{userid}, otherid => $self->arg2});
    return $msg;
}

sub as_html {
    my $self = shift;

    my $msg = $self->load_message;
    my $sender_u = LJ::want_user($msg->journalid);
    my $pichtml = display_pic($msg, $sender_u);
    my $subject = $msg->subject;
    my $other_u = $msg->other_u;

    my $ret;
    $ret .= "<div class='pkg'><div style='width: 60px; float: left;'>";
    $ret .= $pichtml . "</div><div>";
    $ret .= $subject;
    $ret .= "<br />sent to " . $other_u->ljuser_display . "</div>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my ($self, $u) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    my $other_u = $self->load_message->other_u;

# message sent to [[user]].
    return LJ::Lang::get_text($lang, 'notification.sms.usermessagesent', undef, {
        user    => $other_u->{user},
    });    
}

sub subscription_as_html {''}

sub content {
    my $self = shift;

    my $msg = $self->load_message;

    my $body = $msg->body;
    $body = LJ::html_newlines($body);

    return $body;
}

# override parent class subscriptions method to always return
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

    return @subs;
}

# Have notifications for this event show up as read
sub mark_read {
    my $self = shift;
    return 1;
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
    my $sender_u = LJ::want_user($msg->journalid);

    my $pic;
    if ($msg->userpic) {
        $pic = LJ::Userpic->new_from_keyword($sender_u, $msg->userpic);
    } else {
        $pic = $sender_u->userpic;
    }

    $res->{to} = $msg->other_u->user;
    $res->{to_id} = $msg->other_u->{userid};
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

sub is_subscription_visible_to  { 0 }

sub is_tracking { 0 }

1;
