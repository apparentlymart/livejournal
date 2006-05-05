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

sub as_html {
    my $self = shift;

    my $journal = $self->u;    # what journal did this comment happen in?
    my $arg1    = $self->arg1; # jtalkid

    my $comment = LJ::Comment->new($journal, jtalkid => $arg1);
    return "(Invalid comment)" unless $comment && $comment->valid;

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($comment->poster);
    my $url = $comment->url;

    return "New <a href=\"$url\">comment</a> in $ju by $pu.";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journalid = $subscr->journalid;

    if (!$journalid) {
        return "All comments in any journals on my friends page";
    }

    my $u = LJ::load_userid($journalid);
    my $user = LJ::ljuser($u);

    if ($arg1 == 0 && $arg2 == 0) {
        return "All comments in $user, on any post.";
    }

    # load ditemid from jtalkid if no ditemid
    my $comment;
    if ($arg2) {
        $comment = LJ::Comment->new($u, jtalkid => $arg2);
        return "(Invalid comment)" unless $comment && $comment->valid;
        $arg1 = $comment->entry->ditemid unless $arg1;
    }

    my $entry = LJ::Entry->new($u, ditemid => $arg1)
        or return "Comments on a deleted post in $user";

    my $entrydesc = $entry->subject_text;
    $entrydesc = $entrydesc ? "\"$entrydesc\"" : "a post";

    my $entryurl  = $entry->url;
    return "All comments on <a href='$entryurl'>$entrydesc</a> in $user" if $arg2 == 0;

    my $threadurl = $comment->url;

    my $posteru = $comment->poster;
    my $posteruser = $posteru ? LJ::ljuser($posteru) : "(Anonymous)";

    return "New comments under <a href='$threadurl'>the thread</a> by $posteruser in <a href='$entryurl'>$entrydesc</a> in $user";
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $sjid = $subscr->journalid;
    my $ejid = $self->journal->{userid};

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

sub comment {
    my $self = shift;
    return LJ::Comment->new($self->journal, jtalkid => $self->jtalkid);
}

sub journal_sub_title { 'Journal' }
sub journal_sub_type  { 'owner' }

1;
