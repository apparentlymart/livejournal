package LJ::Blockwatch;
use strict;

my $er;
our $no_trace;

sub get_eventring {
    return $er ||= do {
        # ......
    };
}

sub get_event_id {
    local $no_trace = 1; # so DBI instrumentation doesn't recurse
}

sub get_event_name {
    local $no_trace = 1; # so DBI instrumentation doesn't recurse

}

sub start_operation {
    my ($pkg, $opname, $host) = @_;
    return 0 if $no_trace;
    return 0 unless LJ::ModuleCheck->has("Devel::EventRing");

    my $event_name = "$opname:$host";
    my $event_id = LJ::Blockwatch->get_event_id($event_name);
    my $er = get_eventring();
    return $er->operation($event_id);  # returns handle which, when DESTROYed, closes operation
}

1;
