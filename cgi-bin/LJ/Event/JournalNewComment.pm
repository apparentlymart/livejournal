package LJ::Event::JournalNewComment;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Comment LJ::HTML::Template);
use Carp qw(croak);
use LJ::Client::BitLy;
use base 'LJ::Event';

# we don't allow subscriptions to comments on friends' journals, so
# setting undef on this skips some nasty queries
sub zero_journalid_subs_means { undef }

sub new {
    my ($class, $comment) = @_;
    croak 'Not an LJ::Comment' unless blessed $comment && $comment->isa("LJ::Comment");
    return $class->SUPER::new($comment->journal, $comment->jtalkid);
}

sub is_common { 1 }

my @_ml_strings_en = (
    'esn.mail_comments.fromname.user',                      # "[[user]] - [[sitenameabbrev]] Comment",
    'esn.mail_comments.fromname.anonymous',                 # "[[sitenameshort]] Comment",
    'esn.mail_comments.subject.edit_reply_to_your_comment', # "Edited reply to your comment...",
    'esn.mail_comments.subject.reply_to_your_comment',      # "Reply to your comment...",
    'esn.mail_comments.subject.edit_reply_to_your_entry',   # "Edited reply to your entry...",
    'esn.mail_comments.subject.reply_to_your_entry',        # "Reply to your entry...",
    'esn.mail_comments.subject.edit_reply_to_an_entry',     # "Edited reply to an entry...",
    'esn.mail_comments.subject.reply_to_an_entry',          # "Reply to an entry...",
    'esn.mail_comments.subject.edit_reply_to_a_comment',    # "Edited reply to a comment...",
    'esn.mail_comments.subject.reply_to_a_comment',         # "Reply to a comment...",
    'esn.mail_comments.subject.comment_you_posted',         # "Comment you posted...",
    'esn.mail_comments.subject.comment_you_edited',         # "Comment you edited...",
    # as_im
    'esn.mail_comments.alert.user_edited_reply_to_your_comment',        #[[user]] edited a reply to your comment.
    'esn.mail_comments.alert.user_edited_reply_to_a_comment',           #[[user]] edited a reply to a comment.
    'esn.mail_comments.alert.user_reply_to_your_comment',               #[[user]] replied to your comment.
    'esn.mail_comments.alert.user_reply_to_a_comment',                  #[[user]] replied to a comment.
    'esn.mail_comments.alert.user_edited_reply_to_your_post',           #[[user]] edited a reply to your post.
    'esn.mail_comments.alert.user_edited_reply_to_a_post',              #[[user]] edited a reply to a post.
    'esn.mail_comments.alert.user_reply_to_your_post',                  #[[user]] replied to your post.
    'esn.mail_comments.alert.user_reply_to_a_post',                     #[[user]] replied to a post.
    'esn.mail_comments.alert.anonymous_edited_reply_to_your_comment',   #Anonymous user edited a reply to your comment.
    'esn.mail_comments.alert.anonymous_edited_reply_to_a_comment',      #Anonymous user edited a reply to a comment.
    'esn.mail_comments.alert.anonymous_reply_to_your_comment',          #Anonymous user replied to your comment.
    'esn.mail_comments.alert.anonymous_reply_to_a_comment',             #Anonymous user replied to a comment.
    'esn.mail_comments.alert.anonymous_edited_reply_to_your_post',      #Anonymous user edited a reply to your post.
    'esn.mail_comments.alert.anonymous_edited_reply_to_a_post',         #Anonymous user edited a reply to a post.
    'esn.mail_comments.alert.anonymous_reply_to_your_post',             #Anonymous user replied to your post.
    'esn.mail_comments.alert.anonymous_reply_to_a_post',                #Anonymous user replied to a post.
);

sub as_email_from_name {
    my ($self, $u) = @_;

    my $lang = $u->prop('browselang');

    my $vars = {
        user            => $self->comment->poster ? $self->comment->poster->display_username : '',
        sitenameabbrev  => $LJ::SITENAMEABBREV,
        sitenameshort   => $LJ::SITENAMESHORT,
    };

    my $key = 'esn.mail_comments.fromname.';
    if($self->comment->poster) {
        $key .= 'user';
    } else {
        $key .= 'anonymous';
    }

    return LJ::Lang::get_text($lang, $key, undef, $vars);
}

sub as_email_headers {
    my ($self, $u) = @_;

    my $this_msgid = $self->comment->email_messageid;
    my $top_msgid = $self->comment->entry->email_messageid;

    my $par_msgid;
    if ($self->comment->parent) { # a reply to a comment
        $par_msgid = $self->comment->parent->email_messageid;
    } else { # reply to an entry
        $par_msgid = $top_msgid;
        $top_msgid = "";  # so it's not duplicated
    }

    my $journalu = $self->comment->entry->journal;
    my $headers = {
        'Message-ID'   => $this_msgid,
        'In-Reply-To'  => $par_msgid,
        'References'   => "$top_msgid $par_msgid",
        'X-LJ-Journal' => $journalu->user,
    };

    return $headers;

}

sub as_email_subject {
    my ($self, $u) = @_;

    my $edited = $self->comment->is_edited;
    my $lang = $u->prop('browselang');

    my $filename = $self->template_file_for(section => 'subject', lang => $lang);
    if ($filename) {
        # Load template file into template processor
        my $t = LJ::HTML::Template->new(filename => $filename);
        $t->param(subject => $self->comment->subject_html);
        return $t->output;
    }

    my $key = 'esn.mail_comments.subject.';
    if ( my $comment_subject = $self->comment->subject_orig ) {
        return LJ::strip_html($comment_subject);
    } elsif (LJ::u_equals($self->comment->poster, $u)) {
        $key .= $edited ? 'comment_you_edited' : 'comment_you_posted';
    } elsif ($self->comment->parent) {
        if ($edited) {
            $key .= LJ::u_equals($self->comment->parent->poster, $u) ? 'edit_reply_to_your_comment' : 'edit_reply_to_a_comment';
        } else {
            $key .= LJ::u_equals($self->comment->parent->poster, $u) ? 'reply_to_your_comment' : 'reply_to_a_comment';
        }
    } else {
        if ($edited) {
            $key .= LJ::u_equals($self->comment->entry->poster, $u) ? 'edit_reply_to_your_entry' : 'edit_reply_to_an_entry';
        } else {
            $key .= LJ::u_equals($self->comment->entry->poster, $u) ? 'reply_to_your_entry' : 'reply_to_an_entry';
        }
    }

    my $ml_params = {};
    if ( my $entry_subject = $self->comment->entry->subject_raw ) {
        $key .= '.entry_subject';
        $ml_params->{'subject'} = LJ::strip_html($entry_subject);
    };

    return LJ::Lang::get_text( $lang, $key, undef, $ml_params );
}

sub as_email_string {
    my ($self, $u) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    LJ::set_remote($u);

    my $filename = $self->template_file_for(section => 'body_text', lang => $u->prop('browselang'));
    if ($filename) {
        # Load template file into template processor
        my $t = LJ::HTML::Template->new(filename => $filename);

        return $comment->format_template_text_mail($u, $t) if $t;
    }

    return $comment->format_text_mail($u);
}

sub as_email_html {
    my ($self, $u) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    LJ::set_remote($u);

    my $filename = $self->template_file_for(section => 'body_html', lang => $u->prop('browselang'));
    if ($filename) {
        # Load template file into template processor
        my $t = LJ::HTML::Template->new(filename => $filename);

        return $comment->format_template_html_mail($u, $t) if $t;
    }
 
    return $comment->format_html_mail($u);
}

sub as_string {
    my ($self, $u) = @_;
    my $comment = $self->comment;
    my $journal = $comment->entry->journal->user;

    return "There is a new anonymous comment in $journal at " . $comment->url
        unless $comment->poster;

    my $poster = $comment->poster->display_username;
    if ($self->comment->is_edited) {
        return "$poster has edited a comment in $journal at " . $comment->url;
    } else {
        return "$poster has posted a new comment in $journal at " . $comment->url;
    }
}

# 'esn.mail_comments.alert.user_edited_reply_to_your_comment',      #[[user]] edited a reply to your comment.
# 'esn.mail_comments.alert.user_edited_reply_to_a_comment',         #[[user]] edited a reply to a comment.
# 'esn.mail_comments.alert.user_reply_to_your_comment',             #[[user]] replied to your comment.
# 'esn.mail_comments.alert.user_reply_to_a_comment',                #[[user]] replied to a comment.
# 'esn.mail_comments.alert.user_edited_reply_to_your_post',         #[[user]] edited a reply to your post.
# 'esn.mail_comments.alert.user_edited_reply_to_a_post',            #[[user]] edited a reply to a post.
# 'esn.mail_comments.alert.user_reply_to_your_post',                #[[user]] replied to your post.
# 'esn.mail_comments.alert.user_reply_to_a_post',                   #[[user]] replied to a post.
# 'esn.mail_comments.alert.anonymous_edited_reply_to_your_comment', #Anonymous user edited a reply to your comment.
# 'esn.mail_comments.alert.anonymous_edited_reply_to_a_comment',    #Anonymous user edited a reply to a comment.
# 'esn.mail_comments.alert.anonymous_reply_to_your_comment',        #Anonymous user replied to your comment.
# 'esn.mail_comments.alert.anonymous_reply_to_a_comment',           #Anonymous user replied to a comment.
# 'esn.mail_comments.alert.anonymous_edited_reply_to_your_post',    #Anonymous user edited a reply to your post.
# 'esn.mail_comments.alert.anonymous_edited_reply_to_a_post',       #Anonymous user edited a reply to a post.
# 'esn.mail_comments.alert.anonymous_reply_to_your_post',           #Anonymous user replied to your post.
# 'esn.mail_comments.alert.anonymous_reply_to_a_post',              #Anonymous user replied to a post.

sub as_alert {
    my $self = shift;
    my $u = shift;

    # TODO: [[post]] [[reply]] etc
    my $comment = $self->comment;
    my $user = $comment->poster ? $comment->poster->ljuser_display() : '(Anonymous user)';
    my $edited = $comment->is_edited;

    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.mail_comments.alert.' .
            ($comment->poster ? 'user' : 'anonymous') . '_' .
            ($edited ? 'edited_' : '') . 'reply_' .
            (LJ::u_equals($comment->entry->poster, $u) ? 'to_your' : 'to_a') . '_' .
            ($comment->parent ? 'comment' : 'post'), undef,
                {
                    user        => $user,
                    openlink    => '<a href="' . $comment->url . '">',
                    closelink   => '</a>',
                });
}

sub as_sms {
    my ($self, $u, $opt) = @_;

    my $user = $self->comment->poster ? $self->comment->poster->display_username(1) : '(Anonymous user)';
    my $edited = $self->comment->is_edited;

    my $parent = $self->comment->parent;
    my $entry = $self->comment->entry;
    my $lang = $u->prop('browselang') || $LJ::DEFAULT_LANG;

    my ($ml_key, $ml_params);
    if ($self->event_journal->journaltype eq 'C') {
        if ($parent) {
            if ($edited) {
                $ml_key = LJ::u_equals($parent->poster, $u) ? 
                    'sms.communityentryreply.edit_reply_your_comment' : 'sms.communityentryreply.edit_reply_a_comment';
            } else {
                $ml_key = LJ::u_equals($parent->poster, $u) ? 
                    'sms.communityentryreply.replied_your_comment' : 'sms.communityentryreply.replied_a_comment';
            }
        } else {
            if ($edited) {
                $ml_key = LJ::u_equals($entry->poster, $u) ? 
                    'sms.communityentryreply.edit_reply_your_post' : 'sms.communityentryreply.edit_reply_a_post';
            } else {
                $ml_key = LJ::u_equals($entry->poster, $u) ? 
                    'sms.communityentryreply.replied_your_post' : 'sms.communityentryreply.replied_a_post';
            }
        }
        $ml_params = { user => $user, community => $self->event_journal->user };
    } else {
        if ($parent) {
            if ($edited) {
                $ml_key = LJ::u_equals($parent->poster, $u)
                        ? 'sms.journalnewcomment.edit_reply_your_comment' : 'sms.journalnewcomment.edit_reply_a_comment';
            } else {
                $ml_key = LJ::u_equals($parent->poster, $u)
                        ? 'sms.journalnewcomment.replied_your_comment' : 'sms.journalnewcomment.replied_a_comment';
            }
        } else {
            if ($edited) {
                $ml_key = LJ::u_equals($entry->poster, $u)
                        ? 'sms.journalnewcomment.edit_reply_your_post' : 'sms.journalnewcomment.edit_reply_a_post';
            } else {
                $ml_key = LJ::u_equals($entry->poster, $u)
                        ? 'sms.journalnewcomment.replied_your_post' : 'sms.journalnewcomment.replied_a_post';
            }
        }
        $ml_params = { user => $user };
    }

    my $msg = LJ::Lang::get_text($lang, $ml_key, undef, $ml_params);
    #/read/user/%username%/%post_ID%/comments/%comment_ID%#comments
    my $tinyurl = "http://m.livejournal.com/read/user/".$self->event_journal->user."/".$entry->ditemid."/comments/".$self->comment->dtalkid;
    my $mparms = $opt->{mobile_url_extra_params};
    $tinyurl .= '?' . join('&', map {$_ . '=' . $mparms->{$_}} keys %$mparms) if $mparms;
    $tinyurl .= "#comments";
    $tinyurl = LJ::Client::BitLy->shorten($tinyurl);
    undef $tinyurl if $tinyurl =~ /^500/;
    return $msg . " " . $tinyurl; 
}

sub content {
    my ($self, $target) = @_;

    my $comment = $self->comment;

    return undef unless $comment && $comment->valid;
    return undef unless $comment->entry && $comment->entry->valid;
    return undef unless $comment->visible_to($target);
    return undef if $comment->is_deleted;

    LJ::need_res('js/commentmanage.js');

    my $comment_body = $comment->body_html;
    my $buttons = $comment->manage_buttons;
    my $dtalkid = $comment->dtalkid;

    $comment_body =~ s/\n/<br \/>/g;

    my $ret = qq {
        <div id="ljcmt$dtalkid" class="JournalNewComment">
            <div class="ManageButtons">$buttons</div>
            <div class="Body">$comment_body</div>
        </div>
    };

    my $cmt_info = $comment->info;
    my $cmt_info_js = LJ::js_dumper($cmt_info) || '{}';

    my $posterusername = $self->comment->poster ? $self->comment->poster->{user} : "";

    $ret .= qq {
        <script language="JavaScript">
        };

    while (my ($k, $v) = each %$cmt_info) {
        $k = LJ::ejs($k);
        $v = LJ::ejs($v);
        $ret .= "LJ_cmtinfo['$k'] = '$v';\n";
    }

    my $dtid_cmt_info = {u => $posterusername, rc => []};

    $ret .= "LJ_cmtinfo['$dtalkid'] = " . LJ::js_dumper($dtid_cmt_info) . "\n";

    $ret .= qq {
        </script>
        };
    $ret .= $self->as_html_actions;

    return $ret;
}

sub as_html {
    my ($self, $target) = @_;

    my $comment = $self->comment;
    my $journal = $self->u;

    return sprintf("(Deleted comment in %s)", $journal->ljuser_display)
        unless $comment && $comment->valid && !$comment->is_deleted;

    my $entry = $comment->entry;
    return sprintf("(Comment on a deleted entry in %s)", $journal->ljuser_display)
        unless $entry && $entry->valid;

    return "(You are not authorized to view this comment)" unless $comment->visible_to($target);

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($comment->poster);
    my $url = $comment->url;

    my $in_text = '<a href="' . $entry->url . '">an entry</a>';
    my $subject = $comment->subject_text ? ' "' . $comment->subject_text . '"' : '';

    my $poster = $comment->poster ? "by $pu" : '';
    if ($comment->is_edited) {
        return "Edited <a href=\"$url\">comment</a> $subject $poster on $in_text in $ju.";
    } else {
        return "New <a href=\"$url\">comment</a> $subject $poster on $in_text in $ju.";
    }
}

sub as_html_actions {
    my ($self) = @_;

    my $comment = $self->comment;
    my $url = $comment->url;
    my $reply_url = $comment->reply_url;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='$reply_url'>Reply</a>";
    $ret .= " <a href='$url'>Link</a>";
    $ret .= "</div>";

    return $ret;
}

# ML-keys and contents of all items used in this subroutine:
# 01 event.journal_new_comment.friend=Someone comments in any journal on my friends page
# 02 event.journal_new_comment.my_journal=Someone comments in my journal, on any entry
# 03 event.journal_new_comment.user_journal=Someone comments in [[user]], on any entry
# 04 event.journal_new_comment.user_journal.deleted=Someone comments on a deleted entry in [[user]]
# 05 event.journal_new_comment.my_journal.deleted=Someone comments on a deleted entry in my journal
# 06 event.journal_new_comment.user_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 07 event.journal_new_comment.user_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> in [[user]]
# 08 event.journal_new_comment.my_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> my journal
# 09 event.journal_new_comment.my_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> my journal
# 10 event.journal_new_comment.my_journal.titled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 11 event.journal_new_comment.my_journal.titled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 12 event.journal_new_comment.my_journal.titled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 13 event.journal_new_comment.my_journal.titled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 14 event.journal_new_comment.my_journal.titled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 15 event.journal_new_comment.my_journal.titled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 16 event.journal_new_comment.my_journal.untitled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> on my journal
# 17 event.journal_new_comment.my_journal.untitled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> on my journal
# 18 event.journal_new_comment.my_journal.untitled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>en entry</a> on my journal
# 19 event.journal_new_comment.my_journal.untitled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>en entry</a> on my journal
# 20 event.journal_new_comment.my_journal.untitled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> on my journal
# 21 event.journal_new_comment.my_journal.untitled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> on my journal
# 22 event.journal_new_comment.user_journal.titled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 23 event.journal_new_comment.user_journal.titled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 24 event.journal_new_comment.user_journal.titled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 25 event.journal_new_comment.user_journal.titled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 26 event.journal_new_comment.user_journal.titled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 27 event.journal_new_comment.user_journal.titled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 28 event.journal_new_comment.user_journal.untitled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 29 event.journal_new_comment.user_journal.untitled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 30 event.journal_new_comment.user_journal.untitled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 31 event.journal_new_comment.user_journal.untitled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 32 event.journal_new_comment.user_journal.untitled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 33 event.journal_new_comment.user_journal.untitled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> in [[user]]
# -- now, let's begin.
sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journal = $subscr->journal;

    my $key = 'event.journal_new_comment';

    if (!$journal) {
### 01 event.journal_new_comment.friend=Someone comments in any journal on my friends page
        return LJ::Lang::ml($key . '.friend');
    }

    my ($user, $journal_is_owner);
    if (LJ::u_equals($journal, $subscr->owner)) {
        $user = 'my journal';
        $key .= '.my_journal';
        my $journal_is_owner = 1;
    } else {
        $user = LJ::ljuser($journal);
        $key .= '.user_journal';
        my $journal_is_owner = 0;
    }

    if ($arg1 == 0 && $arg2 == 0) {
### 02 event.journal_new_comment.my_journal=Someone comments in my journal, on any entry
### 03 event.journal_new_comment.user_journal=Someone comments in [[user]], on any entry
        return LJ::Lang::ml($key, { user => $user });
    }

    # load ditemid from jtalkid if no ditemid
    my $comment;
    if ($arg2) {
        $comment = LJ::Comment->new($journal, jtalkid => $arg2);
        return "(Invalid comment)" unless $comment && $comment->valid;
        $arg1 = eval { $comment->entry->ditemid } unless $arg1;
        return "(Invalid entry [$arg1:$arg2])" if $@;
    }

    my $entry = LJ::Entry->new($journal, ditemid => $arg1);
### 04 event.journal_new_comment.user_journal.deleted=Someone comments on a deleted entry in [[user]]
### 05 event.journal_new_comment.my_journal.deleted=Someone comments on a deleted entry in my journal
    return LJ::Lang::ml($key . '.deleted', { user => $user }) unless $entry && $entry->valid;

    my $entrydesc = $entry->subject_text;
    if ($entrydesc) {
        $entrydesc = "\"$entrydesc\"";
        $key .= '.titled_entry';
    } else {
        $entrydesc = "an entry";
        $key .= '.untitled_entry';
    }

    my $entryurl  = $entry->url;
### 06 event.journal_new_comment.user_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
### 07 event.journal_new_comment.user_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> in [[user]]
### 08 event.journal_new_comment.my_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> my journal
### 09 event.journal_new_comment.my_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> my journal
    return LJ::Lang::ml($key,
        {
            user        => $user,
            entryurl    => $entryurl,
            entrydesc   => $entrydesc,
        }) if $arg2 == 0;

    my $posteru = $comment->poster;
    my $posteruser;

    my $threadurl = $comment->url;
    my $thread_desc = $comment->subject_text;
    if ($thread_desc) {
        $thread_desc = "\"$thread_desc\"";
        $key .= '.titled_thread';
    } else {
        $thread_desc = "the thread";
        $key .= '.untitled_thread';
    }

    if ($posteru) {
        if ($journal_is_owner) {
            $posteruser = LJ::ljuser($posteru);
            $key .= '.me';
        } else {
            $posteruser = LJ::ljuser($posteru);
            $key .= '.user';
        }
    } else {
        $posteruser = "(Anonymous)";
        $key .= '.anonymous';
    }
    
    if ($comment->state eq 'B') {
        $key .= '.spam';
    }

### 10 ... 33
    return LJ::Lang::ml($key,
    {
        user            => $user,
        threadurl       => $threadurl,
        thread_desc     => $thread_desc,
        posteruser      => $posteruser,
        entryurl        => $entryurl,
        entrydesc       => $entrydesc,
    });
}

sub matches_filter {
    my ($self, $subscr) = @_;

    return 1 if
        LJ::Event->class($subscr->etypeid) ne __PACKAGE__ ||
        !$subscr->id;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->{userid};

    # if subscription is for a specific journal (not a wildcard like 0
    # for all friends) then it must match the event's journal exactly.
    return 0 if $sjid && $sjid != $ejid;

    my ($earg1, $earg2) = ($self->arg1, $self->arg2);
    my ($sarg1, $sarg2) = ($subscr->arg1, $subscr->arg2);

    my $comment = $self->comment;
    my $parent_comment = $comment->parent;
    my $parent_comment_author = $parent_comment ?
        $parent_comment->poster : undef;

    my $entry   = $comment->entry;

    my $watcher = $subscr->owner;

    return 0 unless 
        $comment->visible_to($watcher) ||
        LJ::u_equals($parent_comment_author, $watcher);

    # not a match if this user posted the comment and they don't
    # want to be notified of their own posts
    # moreover, getselfemail only applies to email, so if it's not an email
    # notification, it's not a match either
    if (LJ::u_equals($comment->poster, $watcher)) {
        return 0
            unless $watcher->get_cap('getselfemail')
                && $watcher->prop('opt_getselfemail')
                && $subscr->ntypeid == LJ::NotificationMethod::Email->ntypeid;
    }

    # watching a specific journal
    if ($sarg1 == 0 && $sarg2 == 0) {
        # if this is a community, maintainer gets notified no matter
        # what entry settings are
        return 1 unless LJ::u_equals($entry->journal, $entry->poster);

        # if this is their own journal and they selected not to be notified
        # of comments to this specific entry, well, don't notify them
        return 0 if $entry->prop('opt_noemail');

        return 1;
    }

    my $wanted_ditemid = $sarg1;
    # a (journal, dtalkid) pair identifies a comment uniquely, as does
    # a (journal, ditemid, dtalkid pair). So ditemid is optional. If we have
    # it, though, it needs to be correct.
    return 0 if $wanted_ditemid && $entry->ditemid != $wanted_ditemid;

    # watching a post
    return 1 if $sarg2 == 0;

    # watching a thread
    my $wanted_jtalkid = $sarg2;
    while ($comment) {
        return 1 if $comment->jtalkid == $wanted_jtalkid;
        $comment = $comment->parent;
    }
    return 0;
}

sub jtalkid {
    my $self = shift;
    return $self->arg1;
}

# when was this comment posted or edited?
sub eventtime_unix {
    my $self = shift;
    my $cmt = $self->comment;

    my $time = $cmt->is_edited ? $cmt->edit_time : $cmt->unixtime;
    return $cmt ? $time : $self->SUPER::eventtime_unix;
}

sub comment {
    my $self = shift;
    return LJ::Comment->new($self->event_journal, jtalkid => $self->jtalkid);
}

sub available_for_user  {
    my ($self, $u) = @_;

    my $journal = $self->event_journal;
    my ($arg1, $arg2) = ($self->arg1, $self->arg2);
    
    # user can always track all comments to their own journal
    if (LJ::u_equals($journal, $u) && !$arg1 && !$arg2) {
        return 1;
    }

    # user can always track comments to a specific entry
    if ($arg1) {
        return 1;
    }

    # user can track comments left to a thread if and only if they have a paid
    # account
    if ($arg2) {
        return $u->get_cap('track_thread') ? 1 : 0;
    }

    # user can track all comments to their community journal, provided
    # that the community is paid
    if ($u && $u->can_manage($journal)) {
        return $journal->get_cap('maintainer_track_comments') ? 1 : 0;
    }

    return 0;
}

sub is_subscription_visible_to { 1 }

sub get_disabled_pic {
    my ($self, $u) = @_;

    my $journal = $self->event_journal;

    return LJ::run_hook('esn_community_comments_track_upgrade', $u, $journal) || ''
        unless ref $self ne 'LJ::Event::JournalNewComment' ||
            $self->arg1 || $self->arg2 || LJ::u_equals($u, $journal);

    return $self->SUPER::get_disabled_pic($u);
}

# return detailed data for XMLRPC::getinbox
sub raw_info {
    my ($self, $target, $flags) = @_;
    my $extended = ($flags and $flags->{extended}) ? 1 : 0; # add comments body
    
    my $res = $self->SUPER::raw_info;

    my $comment = $self->comment;
    my $journal = $self->u;

    $res->{journal} = $journal->user;

    return { %$res, action => 'deleted' }
        unless $comment && $comment->valid && !$comment->is_deleted;

    my $entry = $comment->entry;
    return { %$res, action => 'comment_deleted' }
        unless $entry && $entry->valid;

    return { %$res, visibility => 'no' } unless $comment->visible_to($target);

    $res->{entry}   = $entry->url;
    $res->{comment} = $comment->url;
    $res->{poster}  = $comment->poster->user if $comment->poster;
    $res->{subject} = $comment->subject_text;

    if ($extended){
        $res->{extended}->{subject_raw} = $comment->subject_raw;
        $res->{extended}->{body}        = $comment->body_raw;
        $res->{extended}->{dtalkid}     = $comment->dtalkid;
    }

    if ($comment->is_edited) {
        return { %$res, action => 'edited' };
    } else {
        return { %$res, action => 'new' };
    }
}

sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = int delete $args{'limit'};    # optional
    my $original_limit = int $limit;

    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my $comment = $self->comment;
    my $parent_comment = $comment->parent;
    my $entry = $comment->entry;

    my $comment_author = $comment->poster;
    my $parent_comment_author = $parent_comment ?
        $parent_comment->poster :
        undef;
    my $entry_author = $entry->poster;
    if (!$entry_author) {
        warn "No entry author for entry " . $entry->url;
        return;
    }
    
    my $entry_journal = $entry->journal;

    my @subs;

    if ($comment_author && $comment->state eq 'B' && $entry_journal->is_personal && $entry_journal->in_class('paid')) {
        
        ## Get 
        my @ids = $comment_author->friend_uids;
        my %is_friend = map { $_ => 1 } @ids; # uid -> 1

        require LJ::M::ProfilePage;
        my $pm = LJ::M::ProfilePage->new($comment_author);
        require LJ::M::FriendsOf;
        my $fro_m = LJ::M::FriendsOf->new($comment_author,
                                          sloppy => 1, # approximate if no summary info
                                          mutuals_separate => 0,
                                          # TODO: lame that we have to pass this in, but currently
                                          # it's not cached on the $u singleton
                                          friends => \%is_friend,
                                          hide_test_cb => sub {
                                              return $pm->should_hide_friendof($_[0]);
                                          },
                                         );
        my $friend_ofs_count = $fro_m->friend_ofs;
        
        return if $friend_ofs_count <= $LJ::SPAM_MAX_FRIEND_OFS &&
                    (time() - $comment_author->timecreate) / 86400 <= $LJ::SPAM_MAX_DAYS_CREATED;

        my $spam = 0;
        LJ::run_hook('spam_in_friends_journals', \$spam, $entry_journal, $comment_author);
        return if $spam;
    }

    my $acquire_sub_slot = sub {
        my ($how_much) = @_;
        $how_much ||= 1;

        return $how_much unless $original_limit;

        $how_much = $limit if $limit < $how_much;

        $limit -= $how_much;
        return $how_much;
    };

    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my $email_ntypeid = LJ::NotificationMethod::Email->ntypeid;

    # own comments are deliberately sent to email only
    if (
        $comment_author &&
        (!$cid || $comment_author->clusterid == $cid) &&
        $comment_author->prop('opt_getselfemail') &&
        $comment_author->get_cap('getselfemail') &&
        $acquire_sub_slot->()
    ) {
        push @subs, LJ::Subscription->new_from_row({
            'etypeid' => LJ::Event::JournalNewComment->etypeid,
            'userid'  => $comment_author->id,
            'ntypeid' => $email_ntypeid,
        });
    }

    # send a notification to the author of the "parent" comment, if they
    # want to get it
    if (
        $parent_comment && $parent_comment_author &&
        (!$cid || $parent_comment_author->clusterid == $cid) &&

        # if they are responding to themselves and wish to get that, we've
        # already handled it above
        !LJ::u_equals($comment_author, $parent_comment_author) &&

        # if parent_comment_author is also the author of the container entry,
        # we should respect their choice to not get this comment, as set
        # in the entry properties
        (!LJ::u_equals($parent_comment_author, $entry_author) ||
        !$entry->prop('opt_noemail'))
    ) {
        my @subs2 = LJ::Subscription->find($parent_comment_author,
            'event' => 'CommentReply',
            'require_active' => 1,
        );

        push @subs2, LJ::Subscription->new_from_row({
            'etypeid' => LJ::Event::CommentReply->etypeid,
            'userid'  => $parent_comment_author->id,
            'ntypeid' => $email_ntypeid,
        }) if $parent_comment_author->{'opt_gettalkemail'} eq 'Y';

        my $count = scalar(@subs2);
        if ($count && ($count = $acquire_sub_slot->($count))) {
            $#subs2 = $count - 1;
            push @subs, @subs2;
        }
    }

    # send a notification to the author of the entry, if they
    # want to get it
    if (
        # if they are responding to themselves and wish to get that, we've
        # already handled it above
        !LJ::u_equals($comment_author, $entry_author) &&
        (!$cid || $entry_author->clusterid == $cid) &&

        !$entry->prop('opt_noemail')
    ) {

        if (!LJ::u_equals($entry_author, $entry_journal)) {
            # community journal
            my @subs2 = LJ::Subscription->find($entry_author,
                'event' => 'CommunityEntryReply',
                'require_active' => 1,
            );

            my $count = scalar(@subs2);
            if ($count && ($count = $acquire_sub_slot->($count))) {
                $#subs2 = $count - 1;
                push @subs, @subs2;
            }
        }

        push @subs, LJ::Subscription->new_from_row({
            'etypeid' => LJ::Event::JournalNewComment->etypeid,
            'userid'  => $entry_author->id,
            'ntypeid' => $email_ntypeid,
        }) if
            $entry_author->{'opt_gettalkemail'} eq 'Y' && $acquire_sub_slot->();
    }

    return @subs unless ($limit || !$original_limit);

    # handle tracks as usual
    push @subs, $self->SUPER::subscriptions(
        cluster => $cid,
        limit   => $limit
    );

    return @subs;
}

sub is_tracking {
    my ($self, $ownerid) = @_;

    return 1 if $self->arg1 || $self->arg2;
    return 1 unless $self->event_journal->id == $ownerid;

    return 0;
}


sub as_push {
    my $self = shift;
    my $u    = shift;
    my %opts = @_;

    my $parent = $self->comment->parent;
    my $entry = $self->comment->entry;

    my $subject;
    if($subject = $entry->subject_text) {

        $subject = (substr $subject, 0, $opts{cut})."..."
            if $opts{cut} && length($subject) > $opts{cut};

    } else {
        $subject = LJ::Lang::get_text($u->prop('browselang'), "widget.officialjournals.nosubject")
    }

    # tracking event
    unless($u->equals($self->event_journal)) {

        if($self->event_journal->journaltype eq 'C') {

            if($self->comment->parent) {
                return LJ::Lang::get_text($u->prop('browselang'), "esn.push.notification.eventtrackcommetstreadinentrytitle", 1, {
                    user    => $self->comment->poster->user,
                    subject => $subject, 
                    poster  => $self->comment->parent->poster->user,
                    journal => $self->event_journal->user,
                });

            } else {
                return LJ::Lang::get_text($u->prop('browselang'), "esn.push.notification.eventtrackcommetsonentrytitle", 1, {
                    user    => $self->comment->poster->user,
                    subject => $subject,
                    journal => $self->event_journal->user,
                });
            }
        } else {
                return LJ::Lang::get_text($u->prop('browselang'), "esn.push.notification.eventtrackcommetsonentrytitle", 1, {
                user    => $self->comment->poster->user,
                subject => $subject,
                journal => $self->event_journal->user,
            });
        }

    } else {

        if($parent && LJ::u_equals($parent->poster, $u)) {
            return LJ::Lang::get_text($u->prop('browselang'), "esn.push.notification.commentreply", 1, {
                user    => $self->comment->poster->user,
                journal => $self->event_journal->user,
            });

        } elsif($self->event_journal->journaltype eq 'C') {
            return LJ::Lang::get_text($u->prop('browselang'), "esn.push.notification.communityentryreply", 1, {
                user        => $self->comment->poster->user,
                community   => $self->event_journal->user,
            })

        } else {
            return LJ::Lang::get_text($u->prop('browselang'), "esn.push.notification.journalnewcomment", 1, {
                user => $self->comment->poster->user,
            })
        }
    }
}   
    
sub as_push_payload {
    my $self = shift;
    my $u = shift;

    my $entry = $self->comment->entry;
    my $parent = $self->comment->parent;

    my $payload = { 'p' => $entry->ditemid,
                    'c' => $self->comment->dtalkid,
                  };


    unless($u->equals($self->event_journal)) {

        if($self->event_journal->journaltype eq 'C') {
            if($parent) {
                $payload->{'t'} = 26;
                $payload->{'j'} = $self->event_journal->user;
                $payload->{'r'} = $self->comment->parent->dtalkid;
                return $payload;
            }
        } else {
            $payload->{'t'} = 25;
            $payload->{'j'} = $self->event_journal->user;
            return $payload;
        }

    } else {
        $payload->{'j'} = $self->event_journal->user;

        if($parent && LJ::u_equals($parent->poster, $u)) {
            $payload->{'t'} = 5;
            return $payload;
        } elsif($self->event_journal->journaltype eq 'C') {
            $payload->{'t'} = 4;
            return $payload;
        } else {
            $payload->{'t'} = 3;
            return $payload;
        }
    }
}  

1;
