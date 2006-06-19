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

sub title {
    return 'New Comment on Journal';
}

sub content {
    my $self = shift;
    my $comment = $self->comment or return "(Invalid comment)";

    LJ::need_res('js/commentmanage.js');

    my $comment_subject = $comment->subject_text;
    my $comment_body = $comment->body_html;
    my $buttons = $comment->manage_buttons;
    my $dtalkid = $comment->dtalkid;

    my $ret = qq {
        <div id="ljcmt$dtalkid" class="JournalNewComment">
            <div class="Subject">$comment_subject</div>
            <div class="ManageButtons">$buttons</div>
            <div class="Body">$comment_body</div>
        </div>
    };

    my $cmt_info = $comment->info;
    my $cmt_info_js = LJ::js_dumper($cmt_info) || '{}';

    my $posterusername = $self->comment->poster ? $self->comment->poster->{user} : "";

    $ret .= qq {
        <script language="JavaScript">
            LJ_cmtinfo = $cmt_info_js;
            LJ_cmtinfo["$dtalkid"] = "$posterusername";
        </script>
    };

    return $ret;
}

sub as_html {
    my $self = shift;

    my $comment = $self->comment;
    my $journal = $self->u;

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($comment->poster);
    my $url = $comment->url;

    my $entry = $comment->entry or return "(Invalid entry)";

    my $in_text = '<a href="' . $entry->url . '">an entry</a>';

    my $subject = $comment->subject_text ? ' "' . $comment->subject_text . '"' : '';

    return "New <a href=\"$url\">comment</a>$subject in $in_text on $ju by $pu.";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journal = $subscr->journal;

    if (!$journal) {
        return "All comments in any journals on my friends page";
    }

    my $user = LJ::ljuser($journal);

    if ($arg1 == 0 && $arg2 == 0) {
        return "All comments in $user, on any post.";
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
        or return "Comments on a deleted post in $user";

    my $entrydesc = $entry->subject_text;
    $entrydesc = $entrydesc ? "\"$entrydesc\"" : "a post";

    my $entryurl  = $entry->url;
    my $in_journal = $journal_is_owner ? " on my journal" : "in $user";
    return "All comments on <a href='$entryurl'>$entrydesc</a> $in_journal" if $arg2 == 0;

    my $threadurl = $comment->url;

    my $posteru = $comment->poster;
    my $posteruser = $posteru ? LJ::ljuser($posteru) : "(Anonymous)";

    $posteruser = $journal_is_owner ? 'me' : $posteruser;

    my $thread_desc = $comment->subject_text ? '"' . $comment->subject_text . '"' : "the thread";

    return "New comments under <a href='$threadurl'>$thread_desc</a> by $posteruser in <a href='$entryurl'>$entrydesc</a> $in_journal";
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
    return 0 unless $entry->visible_to($watcher);

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

1;
