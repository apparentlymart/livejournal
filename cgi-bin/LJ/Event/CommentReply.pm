package LJ::Event::CommentReply;
use strict;
use base 'LJ::Event::JournalNewComment';

sub subscription_as_html {
    my ($class, $subscr) = @_;
    
    return LJ::Lang::ml('event.comment_reply');
}

sub available_for_user  { 1 }

sub is_subscription_visible_to { 1 }

sub is_tracking { 0 }

sub as_push {
    my $self = shift;
    my $u    = shift;
    my $lang = shift;
    my %opts = @_;

    my $edited  = $self->comment->is_edited;
    my $parent  = $self->comment->parent;
    my $entry   = $self->comment->entry;

    my $user = $self->comment->poster ? $self->comment->poster->display_username(1) : '(Anonymous user)';

    my $subject;
    if($subject = $entry->subject_text) {

        $subject = (substr $subject, 0, $opts{cut})."..."
            if $opts{cut} && length($subject) > $opts{cut};

    } else {
        $subject = LJ::Lang::get_text($lang, "widget.officialjournals.nosubject")
    }

    my $ml_key;
    if ($parent) {
        if ($edited) {
            $ml_key = LJ::u_equals($parent->poster, $u)
                    ? 'esn.push.commentreply.edit_reply_your_comment' : 'esn.push.commentreply.edit_reply_a_comment';
        } else {
            $ml_key = LJ::u_equals($parent->poster, $u)
                    ? 'esn.push.commentreply.replied_your_comment' : 'esn.push.commentreply.replied_a_comment';
        }
    } else {
        if ($edited) {
            $ml_key = LJ::u_equals($self->comment->entry->poster, $u)
                    ? 'esn.push.commentreply.edit_reply_your_post' : 'esn.push.commentreply.edit_reply_a_post';
        } else {
            $ml_key = LJ::u_equals($self->comment->entry->poster, $u)
                    ? 'esn.push.commentreply.replied_your_post' : 'esn.push.commentreply.replied_a_post';
        }
    }

    return LJ::Lang::get_text($lang, $ml_key, undef,
                              { user    => $user, 
                                subject => $subject, 
                                journal => $entry->journal->display_username(1) } );
}

sub as_push_payload {
    my ($self, $u, $lang) = @_;

    my $user    = $self->comment->poster ? $self->comment->poster->display_username(1) : '(Anonymous user)';
    my $edited  = $self->comment->is_edited;

    my $payload = { 't' => 27,
                    'e' => $edited ? 0 : 1,
                    'j' => $user,
                    'p' => $self->comment->entry->ditemid,
                    'c' => $self->comment->dtalkid,
                  };

    if ($self->comment->parent) {
        $payload->{'r'} =  $self->comment->parent->dtalkid;
    }

    return $payload;
}

sub as_sms {
    my ($self, $u, $opt) = @_;

    my $user = $self->comment->poster ? $self->comment->poster->display_username(1) : '(Anonymous user)';
    my $edited = $self->comment->is_edited;

    my $lang = $u->prop('browselang') || $LJ::DEFAULT_LANG;
    my $ml_key;
    if ($self->comment->parent) {
        if ($edited) {
            $ml_key = LJ::u_equals($self->comment->parent->poster, $u)
                    ? 'sms.commentreply.edit_reply_your_comment' : 'sms.commentreply.edit_reply_a_comment';
        } else {
            $ml_key = LJ::u_equals($self->comment->parent->poster, $u)
                    ? 'sms.commentreply.replied_your_comment' : 'sms.commentreply.replied_a_comment';
        }
    } else {
        if ($edited) {
            $ml_key = LJ::u_equals($self->comment->entry->poster, $u)
                    ? 'sms.commentreply.edit_reply_your_post' : 'sms.commentreply.edit_reply_a_post';
        } else {
            $ml_key = LJ::u_equals($self->comment->entry->poster, $u)
                    ? 'sms.commentreply.replied_your_post' : 'sms.commentreply.replied_a_post';
        }
    }
    my $msg = LJ::Lang::get_text($lang, $ml_key, undef, { user => $user } );
    my $mparms = $opt->{mobile_url_extra_params};
    my $tinyurl = $mparms?$self->comment->url( '&' . join('&', map {$_ . '=' . $mparms->{$_}} keys %$mparms))
        : $self->comment->url;
    $tinyurl = LJ::Client::BitLy->shorten($tinyurl);
    undef $tinyurl if $tinyurl =~ /^500/;

    return $msg . " " . $tinyurl; 
}

1;
