package LJ::NewWorker::Reminders;

use strict;
use warnings;

use lib "$ENV{LJHOME}/cgi-bin";

use base qw(Data::ObjectDriver::BaseObject LJ::NewWorker::Manual);

use Data::ObjectDriver::Driver::DBI;
use LJ::PersonalStats::AccessControl;

use Carp qw( croak );
use Digest::MD5 qw( md5_hex );
use List::Util qw( shuffle );

use TheSchwartz::FuncMap;

use LJ;

use constant MAX_RETRIES   => 5;

__PACKAGE__->install_properties({
    columns     => [ qw( reminderid userid funcid arg
                         insert_time scheduled_time run_after
                         grabbed_timestamp priority retries ) ],
    datasource  => 'reminders',
    primary_key => 'reminderid',
});

sub new {
    my $class = shift;

    my $self = bless {}, $class;

    for my $db (map { $LJ::THESCHWARTZ_DBS{$_} } @{ $LJ::THESCHWARTZ_DBS_ROLES{default} }) {
        my $full = join '|', map { $db->{$_} || '' } qw( dsn user pass );
        # FIXME: Different roles can has same $full line!
        $self->{databases}{ md5_hex($full) } = $db;
    }
    
    return $self;
}

sub funcid_to_name {
    my ($self, $hashdsn, $funcid) = @_;
    my $cache = $self->_funcmap_cache($hashdsn);
    return $cache->{funcid2name}{$funcid};
}

sub funcname_to_id {
    my ($self, $hashdsn, $funcname) = @_;
    my $cache = $self->_funcmap_cache($hashdsn);
    unless (exists $cache->{funcname2id}{$funcname}) {
        my $driver = $self->driver_for($hashdsn);
        $driver->begin_work;
        my $map = TheSchwartz::FuncMap->create_or_find($driver, $funcname);
        $driver->commit;
        $cache->{funcname2id}{ $map->funcname } = $map->funcid;
        $cache->{funcid2name}{ $map->funcid }   = $map->funcname;
    }
    return $cache->{funcname2id}{$funcname};
}

sub _funcmap_cache {
    my ($self, $hashdsn) = @_;
    unless (exists $self->{funcmap_cache}{$hashdsn}) {
        my $driver = $self->driver_for($hashdsn);
        my @maps = $driver->search('TheSchwartz::FuncMap');
        my $cache = { funcname2id => {}, funcid2name => {} };
        for my $map (@maps) {
            $cache->{funcname2id}{ $map->funcname } = $map->funcid;
            $cache->{funcid2name}{ $map->funcid }   = $map->funcname;
        }
        $self->{funcmap_cache}{$hashdsn} = $cache;
    }
    return $self->{funcmap_cache}{$hashdsn};
}

sub driver_for {
    my ($self, $hashdsn) = @_;
    my $db = $self->{databases}{$hashdsn}
        or croak "Ouch, I don't know about a database whose hash is $hashdsn";
    
    return Data::ObjectDriver::Driver::DBI->new(
        dsn      => $db->{dsn},
        username => $db->{user},
        password => $db->{pass},
        ($db->{prefix} ? (prefix   => $db->{prefix}) : ()),
    );
}

sub shuffled_databases {
    my $self = shift;
    my @dsns = keys %{ $self->{databases} };
    return shuffle(@dsns);
}

#### API ##############################

sub schedule {
    my $self = shift;
    my $opts = shift;

    return undef unless $opts;
    return undef unless 'HASH' eq ref $opts;

    my ($userid, $funcid, $function, $arg, $run_after, $priority) =
        map { delete $opts->{$_} } qw(userid funcid function arg run_after priority);

    # Check is user valid
    return undef unless $userid;

    if ($arg) {
        if (ref($arg) eq 'SCALAR') {
            $arg = Storable::thaw($$arg);
        } elsif (!ref($arg)) {
            # if a regular scalar, test to see if it's a storable or not.
            $arg = _cond_thaw($arg);
            return undef unless $arg;
        }
    }

    for my $hashdsn ($self->shuffled_databases) {
        unless ($funcid) {
            return undef unless $function;
            $funcid = $self->funcname_to_id($hashdsn, $function);
        }

        $run_after ||= time;
        $priority ||= 0;

        my $driver = $self->driver_for($hashdsn);
        my $unixtime = $driver->dbd->sql_for_unixtime;

        my $reminder = (ref $self)->new;
        $reminder->userid($userid);
        $reminder->funcid($funcid);
        $reminder->arg($arg);
        $reminder->insert_time(time);
        $reminder->scheduled_time(undef);
        $reminder->run_after($run_after);
        $reminder->grabbed_timestamp(undef);
        $reminder->priority($priority);
        $reminder->retries(0);
        $driver->insert($reminder);
        return $reminder->reminderid;
    }
}

#### Worker#############################

sub work {
    my $self = shift;

    my $count = 0;

    for my $hashdsn ($self->shuffled_databases) {
        my $driver = $self->driver_for($hashdsn);
        my $unixtime = $driver->dbd->sql_for_unixtime;

        my @jobs = $driver->search('LJ::NewWorker::Reminders' => {
            run_after           => \ "<= $unixtime",
            grabbed_timestamp   => \ 'IS NULL',
            retries             => { op => '<', value => MAX_RETRIES },
        },
        {
            limit => 100,
            sort => 'insert_time, scheduled_time, run_after, priority'
        });

        my $servertime = $driver->rw_handle->selectrow_array("SELECT $unixtime");

        foreach my $job (@jobs) {
            $job->grabbed_timestamp($servertime);
            if (1 > $driver->update($job, {
                reminderid => $job->reminderid,
                grabbed_timestamp => \ 'IS NULL' } )) {
                # Cannot grab a job. Somebody grab it already.
                next;
            }

            my $funcname = $self->funcid_to_name($hashdsn,$job->funcid);
            my %funcs_hash  = ( # Hash of authorized functions.
               'LJ::PersonalStats::AccessControl::work' => 'LJ::PersonalStats::AccessControl::work',
            );

            eval {
                no strict 'refs';
                $funcs_hash{$funcname}->($job->userid);
                use strict 'refs';
            };
            if ($@) {   # Error: increment retries counter and release a job.
                my $retries = 1 + $job->retries;
                warn "Error: $@, max retries count exceeded." if $retries >= MAX_RETRIES;
                $job->retries($retries);
                $job->grabbed_timestamp(undef); # NULL
                if (1 > $driver->update($job, { reminderid => $job->reminderid })) {
                    warn "Cannot release a job";
                }
            } else {    # All correct: remove a record from reminderstable.
                $driver->remove('LJ::NewWorker::Reminders' => {
                    reminderid  => $job->reminderid,
                },
                {
                    nofetch => 1,
                });
            }

            ++$count;
        }
    }

    return $count;
}

sub on_idle {
    sleep 30;
}

1;
