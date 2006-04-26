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

sub sub_info {
    return (
            {
                type => 'any',
                title => 'Journal',
            }
            );
}

1;
