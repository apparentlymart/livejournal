package LJ::Worker::Gearman;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use Gearman::Worker;
use base 'LJ::Worker';

require "ljlib.pl";
use vars qw(@ISA @EXPORT @EXPORT_OK);
use Getopt::Long;

my $quit_flag = 0;
$SIG{TERM} = sub {
    $quit_flag = 1;
};

my $opt_verbose;
die "Unknown options" unless
    GetOptions("verbose|v" => \$opt_verbose);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(gearman_decl gearman_work);

my $worker = Gearman::Worker->new;

sub gearman_decl {
    my $name = shift;
    my ($subref, $timeout);

    if (ref $_[0] eq 'CODE') {
        $subref = shift;
    } else {
        $timeout = shift;
        $subref = shift;
    }

    $subref = wrapped_verbose($name, $subref) if $opt_verbose;

    if (defined $timeout) {
        $worker->register_function($name => $timeout => $subref);
    } else {
        $worker->register_function($name => $subref);
    }
}

sub gearman_work {
    if ($LJ::IS_DEV_SERVER) {
        die "DEVSERVER help: No gearmand servers listed in \@LJ::GEARMAN_SERVERS.\n"
            unless @LJ::GEARMAN_SERVERS;
        IO::Socket::INET->new(PeerAddr => $LJ::GEARMAN_SERVERS[0])
            or die "First gearmand server in \@LJ::GEARMAN_SERVERS ($LJ::GEARMAN_SERVERS[0]) isn't responding.\n";
    }

    LJ::Worker->setup_mother();

    my $last_death_check = time();

    while (1) {
        LJ::Worker->check_limits();
        # check to see if we should die
        my $now = time();
        if ($now != $last_death_check) {
            $last_death_check = $now;
            exit 0 if -e "/var/run/gearman/$$.please_die" || -e "/var/run/ljworker/$$.please_die";
        }

        $worker->job_servers(@LJ::GEARMAN_SERVERS); # TODO: don't do this everytime, only when config changes?
        warn "waiting for work...\n" if $opt_verbose;
        $worker->work(stop_if => sub { 1 });
        exit 0 if $quit_flag;
        LJ::start_request();
    }
}

# --------------

sub wrapped_verbose {
    my ($name, $subref) = @_;
    return sub {
        warn "  executing '$name'...\n";
        my $ans = eval { $subref->(@_) };
        if ($@) {
            warn "   -> ERR: $@\n";
            die $@; # re-throw
        } elsif (! ref $ans && $ans !~ /^[\0\x7f-\xff]/) {
            my $cleanans = $ans;
            $cleanans =~ s/[^[:print:]]+//g;
            $cleanans = substr($cleanans, 0, 1024) . "..." if length $cleanans > 1024;
            warn "   -> answer: $cleanans\n";
        }
        return $ans;
    };
}

1;
