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
