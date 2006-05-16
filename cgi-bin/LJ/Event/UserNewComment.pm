package LJ::Event::UserNewComment;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Comment);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $comment) = @_;
    croak 'Not an LJ::Comment' unless blessed $comment && $comment->isa("LJ::Comment");
    return $class->SUPER::new($comment->poster,
                              $comment->journal->{userid}, $comment->jtalkid);
}

sub is_common { 0 }

sub title {
    return 'User Left a Comment';
}

# when was this comment left?
sub eventtime_unix {
    my $self = shift;
    my $cmt = $self->comment;
    return $cmt ? $cmt->unixtime : $self->SUPER::eventtime_unix;
}

sub comment {
    my $self = shift;
    return LJ::Comment->new($self->journal, jtalkid => $self->arg1);
}

sub journal_sub_title { 'Journal' }
sub journal_sub_type  { 'mutual_friend' }

1;
