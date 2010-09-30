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

sub as_sms {
    my ($self, $u) = @_;

    my $user = $self->comment->poster ? $self->comment->poster->display_username : '(Anonymous user)';
    my $edited = $self->comment->is_edited;

    my $msg;

    my $lang = $self->comment->poster ? $self->comment->poster->prop('browselang') : $LJ::DEFAULT_LANG;
    if ($self->comment->parent) {
        if ($edited) {
            $msg = LJ::u_equals($self->comment->parent->poster, $u)
                    ? LJ::Lang::get_text($lang, 'sms.commentreply.edit_reply_your_comment', undef, { user => $user } )
                    : LJ::Lang::get_text($lang, 'sms.commentreply.edit_reply_a_comment', undef, { user => $user } );
        } else {
            $msg = LJ::u_equals($self->comment->parent->poster, $u)
                    ? LJ::Lang::get_text($lang, 'sms.commentreply.replied_your_comment', undef, { user => $user } )
                    : LJ::Lang::get_text($lang, 'sms.commentreply.replied_a_comment', undef, { user => $user } );
        }
    } else {
        if ($edited) {
            $msg = LJ::u_equals($self->comment->entry->poster, $u)
                    ? LJ::Lang::get_text($lang, 'sms.commentreply.edit_reply_your_post', undef, { user => $user } )
                    : LJ::Lang::get_text($lang, 'sms.commentreply.edit_reply_a_post', undef, { user => $user } );
        } else {
            $msg = LJ::u_equals($self->comment->entry->poster, $u)
                    ? LJ::Lang::get_text($lang, 'sms.commentreply.replied_your_post', undef, { user => $user } )
                    : LJ::Lang::get_text($lang, 'sms.commentreply.replied_a_post', undef, { user => $user } );
        }
    }

    my $tinyurl = LJ::API::BitLy->shorten($self->comment->url);
    return undef if $tinyurl =~ /^500/;
    return $msg . " " . $tinyurl; 
}

1;
