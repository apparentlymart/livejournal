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

1;
