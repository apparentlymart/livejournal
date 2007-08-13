package LJ::PersistentQueue;

use strict;
use warnings;
use Data::Queue::Persistent;

sub new {
    my ($class, %opts) = @_;

    return Data::Queue::Persistent->new(
                                        table => 'persistent_queue',
                                        cache => 0,
                                        dbh   => LJ::get_db_writer(),
                                        %opts,
                                        );
}



package LJ;

sub queue {
    my ($id, $size) = @_;

    return LJ::PersistentQueue->new(id => $id, max_size => $size);
}


1;
