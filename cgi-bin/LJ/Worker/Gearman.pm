package LJ::Worker::Gearman;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use Gearman::Worker;

require "ljlib.pl";
use vars qw(@ISA @EXPORT @EXPORT_OK);
use Getopt::Long;

my $opt_verbose;
die "Unknown options" unless
    GetOptions("verbose|v" => \$opt_verbose);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(gearman_decl gearman_work);

my $worker = Gearman::Worker->new;

sub gearman_decl {
    my ($name, $subref) = @_;
    if ($opt_verbose) {
        $worker->register_function($name => wrapped_verbose($name, $subref));
    } else {
        $worker->register_function($name => $subref);
    }
}

sub gearman_work {
    while (1) {
        $worker->job_servers(@LJ::GEARMAN_SERVERS); # TODO: don't do this everytime, only when config changes?
        warn "waiting for work...\n" if $opt_verbose;
        $worker->work(stop_if => sub { 1 });
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
            warn "   -> answer: $ans\n";
        }
        return $ans;
    };
}

1;
