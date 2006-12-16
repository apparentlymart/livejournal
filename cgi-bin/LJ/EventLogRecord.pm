# This is a class that represents any event that happened on LJ
package LJ::EventLogRecord;

use strict;
use Carp qw(croak);
use Class::Autouse qw (
                       LJ::EventLogRecord::NewComment
                       LJ::EventLogRecord::NewEntry
                       LJ::EventLogRecord::SessionExpired
                       );
use TheSchwartz;

sub schwartz_capabilities {
    return (
            "LJ::Worker::EventLogRecord",
            );
}

# Class method
# takes a list of key/value pairs
sub new {
    my ($class, %args) = @_;

    my $self = {
        params => \%args,
    };

    bless $self, $class;
    return $self;
}

# Instance method
# returns a hashref of the key/value pairs of this event
sub params {
    my $self = shift;
    my $params = $self->{params};
    return $params || {};
}

# Instance method
# creates a job to insert into the schwartz to process this firing
sub fire_job {
    my $self = shift;

    my $params = $self->params;
    return TheSchwartz::Job->new_from_array("LJ::Worker::EventLogRecord",
                                            [ $self->event_type, %$params ]);
}

# Instance method
# inserts a job into the schwartz to process this event
sub fire {
    my $self = shift;

    my $sclient = LJ::theschwartz()
        or die "Could not get TheSchwartz client";

    $sclient->insert_jobs($self->fire_job);
}

# Override in subclasses
# returns what type of event this is
sub event_type {
    die "event_type called on EventLogRecord base class";
}

#############
## Schwartz worker methods
#############

package LJ::Worker::EventLogRecord;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;

    my @arglist = @$a;
    my $event_type = shift @arglist or die "No event_type found";

    my %params = @arglist;

    # insert into db
    my $dbh = LJ::get_db_writer()
        or die "Could not get db writer";

    my $encoded_params = join '&', map { LJ::eurl($_) . '=' . LJ::eurl($params{$_}) } keys %params;
    $dbh->do("INSERT INTO eventlogrecord (event, unixtimestamp, info) VALUES (?, UNIX_TIMESTAMP(), ?)", undef,
             $event_type, $encoded_params);

    die $dbh->errstr if $dbh->err;

    $job->completed;
}

1;
