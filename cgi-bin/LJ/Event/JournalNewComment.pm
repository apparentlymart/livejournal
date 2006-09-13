package LJ::Event::JournalNewComment;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Comment);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $comment) = @_;
    croak 'Not an LJ::Comment' unless blessed $comment && $comment->isa("LJ::Comment");
    return $class->SUPER::new($comment->journal, $comment->jtalkid);
}

sub is_common { 1 }

sub as_email_from_name {
    my ($self, $u) = @_;

    if($self->comment->poster) {
        return sprintf "%s - $LJ::SITENAMEABBREV Comment", $self->comment->poster->display_username;
    } else {
        return "$LJ::SITENAMESHORT Comment";
    }
}

sub as_email_headers {
    my ($self, $u) = @_;

    my $anum = $self->comment->entry->anum;
    my $dtalkid = $self->comment->dtalkid;
    my $ditemid = $self->comment->entry->ditemid;
    my $journalu = $self->comment->entry->journal;

    my $this_msgid = generate_messageid("comment", $journalu, $dtalkid);
    my $top_msgid = generate_messageid("entry", $journalu, $ditemid);

    my $par_msgid;
    if ($self->comment->parent) { # a reply to a comment
        $par_msgid = generate_messageid("comment", $journalu, $self->comment->parent->{talkid} * 256 + $anum);
    } else { # reply to an entry
        $par_msgid = $top_msgid;
        $top_msgid = "";  # so it's not duplicated
    }

    my $headers = {
        'Message-ID'   => $this_msgid,
        'In-Reply-To'  => $par_msgid,
        'References'   => "$top_msgid $par_msgid",
        'X-LJ-Journal' => $journalu->user,
    };

    return $headers;

}


sub generate_messageid {
    my ($type, $journalu, $did) = @_;
    # $type = {"entry" | "comment"}
    # $journalu = $u of journal
    # $did = display id of comment/entry

    my $jid = $journalu->{userid};
    return "<$type-$jid-$did\@$LJ::DOMAIN>";
}



sub as_email_subject {
    my ($self, $u) = @_;

    if($self->comment->subject_text) {
        return $self->comment->subject_text;
    } elsif ($self->comment->parent) {
        return LJ::u_equals($self->comment->parent->poster, $u) ? 'Reply to your comment...' : 'Reply to a comment...';
    } else {
        return LJ::u_equals($self->comment->entry->poster, $u) ? 'Reply to your entry...' : 'Reply to an entry...';
    }
}

sub as_email_string {
    my ($self, $u) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    return $comment->format_text_mail($u);
}

sub as_email_html {
    my ($self, $u) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    return $comment->format_html_mail($u);
}

sub content {
    my ($self, $target) = @_;

    my $comment = $self->comment or return "(Invalid comment)";

    return "(Comment on a deleted entry)" unless $comment->entry->valid;
    return "(You do not have permission to view this comment)" unless $comment->visible_to($target);
    return "(Deleted comment)" if $comment->is_deleted;

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

    return $ret;
}

sub as_html {
    my ($self, $target) = @_;

    my $comment = $self->comment;
    my $journal = $self->u;

    my $entry = $comment->entry or return "(Invalid entry)";

    return "(Deleted comment)" if $comment->is_deleted || ! $comment->entry->valid;
    return "(Not authorized)" unless $comment->visible_to($target);

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($comment->poster);
    my $url = $comment->url;

    my $in_text = '<a href="' . $entry->url . '">an entry</a>';
    my $subject = $comment->subject_text ? ' "' . $comment->subject_text . '"' : '';

    my $poster = $comment->poster ? "by $pu" : '';
    my $ret = "New <a href=\"$url\">comment</a> $subject $poster on $in_text in $ju.";

    return $ret;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journal = $subscr->journal;

    if (!$journal) {
        return "Someone comments in any journal on my friends page";
    }

    my $user = LJ::u_equals($journal, $subscr->owner) ? 'my journal' : LJ::ljuser($journal);

    if ($arg1 == 0 && $arg2 == 0) {
        return "Someone comments in $user, on any entry.";
    }

    # load ditemid from jtalkid if no ditemid
    my $comment;
    if ($arg2) {
        $comment = LJ::Comment->new($journal, jtalkid => $arg2);
        return "(Invalid comment)" unless $comment && $comment->valid;
        $arg1 = $comment->entry->ditemid unless $arg1;
    }

    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);

    my $entry = LJ::Entry->new($journal, ditemid => $arg1)
        or return "Someone comments on a deleted entry in $user";

    my $entrydesc = $entry->subject_text;
    $entrydesc = $entrydesc ? "\"$entrydesc\"" : "an entry";

    my $entryurl  = $entry->url;
    my $in_journal = $journal_is_owner ? " on my journal" : "in $user";
    return "Someone comments on <a href='$entryurl'>$entrydesc</a> $in_journal" if $arg2 == 0;

    my $threadurl = $comment->url;

    my $posteru = $comment->poster;
    my $posteruser = $posteru ? LJ::ljuser($posteru) : "(Anonymous)";

    $posteruser = $journal_is_owner ? 'me' : $posteruser;

    my $thread_desc = $comment->subject_text ? '"' . $comment->subject_text . '"' : "the thread";

    return "Someone comments under <a href='$threadurl'>$thread_desc</a> by $posteruser in <a href='$entryurl'>$entrydesc</a> $in_journal";
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->{userid};

    # if subscription is for a specific journal (not a wildcard like 0
    # for all friends) then it must match the event's journal exactly.
    return 0 if $sjid && $sjid != $ejid;

    my ($earg1, $earg2) = ($self->arg1, $self->arg2);
    my ($sarg1, $sarg2) = ($subscr->arg1, $subscr->arg2);

    my $comment = $self->comment;
    my $entry   = $comment->entry;
    my $watcher = $subscr->owner;
    return 0 unless $comment->visible_to($watcher);

    # not a match if this user posted the comment and they don't
    # want to be notified of their own posts
    if (LJ::u_equals($comment->poster, $watcher)) {
        return unless $watcher->get_cap('getselfemail') && $watcher->prop('opt_getselfemail');
    }

    # not a match if this user posted the entry and they don't want comments,
    # unless they posted it. (don't need to check again for the cap, since we did above.)
    if (LJ::u_equals($entry->poster, $watcher) && !$watcher->prop('opt_getselfemail')) {
        return if $entry->prop('opt_noemail');
    }

    # watching a specific journal
    if ($sarg1 == 0 && $sarg2 == 0) {
        # TODO: friend group filtering in case of $sjid == 0 when
        # a subprop is filtering on a friend group
        return 1;
    }

    my $wanted_ditemid = $sarg1;
    return 0 unless $entry->ditemid == $wanted_ditemid;

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

# when was this comment left?
sub eventtime_unix {
    my $self = shift;
    my $cmt = $self->comment;
    return $cmt ? $cmt->unixtime : $self->SUPER::eventtime_unix;
}

sub comment {
    my $self = shift;
    return LJ::Comment->new($self->event_journal, jtalkid => $self->jtalkid);
}

sub available_for_user  {
    my ($class, $u, $subscr) = @_;

    # not allowed to track replies to comments
    return 0 if ! $u->get_cap('track_thread') &&
        $subscr->arg2;

    return 1;
}

1;
