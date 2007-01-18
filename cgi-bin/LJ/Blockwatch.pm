package LJ::Blockwatch;

use strict;
use warnings;

# We have to depend on these, so all the subroutines we wrap up are already defined
# by the time we actually do that.
use DBI;
use DDLockClient;
use Gearman::Client;
use MogileFS::Client;

my $er;

our $no_trace;

my %event_by_id;
my %event_by_name;

sub get_eventring {
    return $er if $er;

    my $root = $LJ::BLOCKWATCH_ROOT || return;

    return unless LJ::ModuleCheck->have("Devel::EventRing");

    if (-d $root || mkdir $root) {
        return $er = Devel::EventRing->new("$root/$$", auto_unlink => 1);
    }

    # $root isn't dir, and mkdir failed.
    warn "Unable to create blockwatch path '$root': $!";
    return;
}

sub get_event_id {
    my ($pkg, $name) = @_;

    return $event_by_name{$name} if exists $event_by_name{$name};

    update_from_memcache();
    return $event_by_name{$name} if exists $event_by_name{$name};

    local $no_trace = 1; # so DBI instrumentation doesn't recurse
    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT IGNORE INTO blockwatch_events (name) VALUES (?)",
             undef, $name);

    update_from_dbh();
    return $event_by_name{$name} if exists $event_by_name{$name};

    warn "Unable to allocate event ID for '$name'";
    return;
}

sub get_event_name {
    my ($pkg, $id) = @_;

    return $event_by_id{$id} if exists $event_by_id{$id};

    update_from_memcache();
    return $event_by_id{$id} if exists $event_by_id{$id};


    local $no_trace = 1; # so DBI instrumentation doesn't recurse
    update_from_dbh();

    return $event_by_id{$id} if exists $event_by_id{$id};

    warn "No event named for id:$id";
    return;
}

sub update_from_memcache {
    # TODO load from memcache
}

sub update_from_dbh {
    my $dbh = LJ::get_db_reader();
    my $sth = $dbh->prepare("SELECT id, name FROM blockwatch_events");
    $sth->execute;

    # TODO Catch dbi errors here and return.

    %event_by_id   = ();
    %event_by_name = ();

    while (my ($id, $name) = $sth->fetchrow_array) {
        $event_by_id{$id}     = $name;
        $event_by_name{$name} = $id;
    }

    # TODO Update memcache
}

sub start {
    my ($pkg, @parts) = @_;
    return 0 if $no_trace;
    return 0 unless LJ::ModuleCheck->have("Devel::EventRing");

    my $event_name = join ":", @parts;
    my $event_id = LJ::Blockwatch->get_event_id($event_name) || return;
    my $er = get_eventring();
    $er->start_operation($event_id);
}

sub end {
    my ($pkg, @parts) = @_;
    return 0 if $no_trace;
    return 0 unless LJ::ModuleCheck->have("Devel::EventRing");

    my $event_name = join ":", @parts;
    my $event_id = LJ::Blockwatch->get_event_id($event_name) || return;
    my $er = get_eventring();
    $er->end_operation($event_id);
}

sub operation {
    my ($pkg, @parts) = @_;
    return 0 if $no_trace;
    return 0 unless LJ::ModuleCheck->have("Devel::EventRing");

    my $event_name = join ":", @parts;
    my $event_id = LJ::Blockwatch->get_event_id($event_name) || return;
    my $er = get_eventring();
    my $op = $er->operation($event_id); # returns handle which, when DESTROYed, closes operation
    return $op;
}

sub wrap_sub {
    my ($name, %args) = @_;
    no strict 'refs';
    no warnings 'redefine';
    my $oldcv = *{$name}{CODE};
    *{$name} = sub {
        my @toafter;
        @toafter = $args{before}->(@_) if $args{before};
        my $wa = wantarray;
        my @rv;
        if ($wa) {
            @rv = $oldcv->(@_);
        } else {
            $rv[0] = $oldcv->(@_);
        }
        $args{after}->(\@rv, @toafter) if $args{after};
        return $wa ? @rv : $rv[0];
    };
}

# DBI Hooks
foreach my $towrap (qw(selectrow_array do selectall_hashref selectrow_hashref commit rollback begin_work)) {
    wrap_sub("DBI::db::$towrap",
             before => sub {
                 my ($db) = @_;
                 my $host = $db->{private_dsn} || "unknown_host";
                 return LJ::Blockwatch->operation($towrap, $host);
             });
}

wrap_sub("DBI::db::prepare",
         before => sub {
             my ($db) = @_;
             my $host = $db->{private_dsn} || "unknown_host";
             return $db->{private_dsn}, LJ::Blockwatch->operation('prepare', $host);
         },
         after => sub {
             my ($resarray, $dsn) = @_;
             if ($dsn) {
                 $resarray->[0]->{private_dsn} = $dsn;
             }
         });

foreach my $towrap (qw(execute)) {# fetchrow_array fetchrow_arrayref fetchrow_hashref fetchall_arrayref fetchall_hashref)) {
    wrap_sub("DBI::st::$towrap",
             before => sub {
                 my ($sth) = @_;
                 my $host = $sth->{private_dsn} || "unknown_host";
                 return LJ::Blockwatch->operation($towrap, $host);
             });
}

# Gearman hooks
wrap_sub("Gearman::Client::do_task",
         before => sub {
             my ($client, $func) = @_;

             if (ref($func)) {
                 $func = $func->func; # This is actually a task object, so we pull the func part out of it.
             }

             return LJ::Blockwatch->operation("gearman-$func");
         });

sub setup_gearman_hooks {
    my $class = shift;
    my $gearclient = shift;
}

# MogileFS Hooks

sub setup_mogilefs_hooks {
    my $class = shift;
    my $mogclient = shift;
}

# DDLock Hooks

sub setup_ddlock_hooks {
    my $class = shift;
    my $locker = shift;
    $locker->add_hook('trylock',         \&ddlock_trylock);
    $locker->add_hook('trylock_success', \&ddlock_trylock_success);
    $locker->add_hook('trylock_failure', \&ddlock_trylock_failure);
}

sub ddlock_trylock {
    my ($name) = @_;

    LJ::Blockwatch->start("ddlock");
}

sub ddlock_trylock_success {
    my ($name, $lock) = @_;

    my $done = 0;

    my $hook = sub {
        return if $done;
        my ($lock) = shift;
        my $name = $lock->name;
        LJ::Blockwatch->start("ddlock");
    };

    $lock->add_hook('release', $hook);
    $lock->add_hook('DESTROY', $hook);
}

sub ddlock_trylock_failure {
    my ($name) = @_;
    LJ::Blockwatch->start("ddlock");
}

1;
