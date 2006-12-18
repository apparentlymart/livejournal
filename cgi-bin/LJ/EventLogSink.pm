package LJ::EventLogSink;
use strict;

sub new {
    my $class = shift;
    die "Cannot call new on EventLogSink base class";
}

sub log {
    my ($self, $evt) = @_;
    die "Cannot call log on EventLogSink base class";
}

sub should_log {
    my ($self, $evt) = @_;
    die "Cannot call should_log on EventLogSink base class";
}


my $need_rebuild = 1;
my @sites = ();
# class method.  called after ljconfig.pl is reloaded
# to know we need to reconstruct our list of external site
# instances
sub forget_sink_objs {
    $need_rebuild = 1;
    @sites = ();
}

# class method.
sub sinks {
    _build_sink_objs() if $need_rebuild;
    return @sites;
}

sub _build_sink_objs {
    return unless $need_rebuild;
    $need_rebuild = 0;
    @sites = ();
    foreach my $ci (@LJ::EVENT_LOG_SINKS) {
        my @args = @$ci;
        my $class = shift @args;
        $class = "LJ::EventLogSink::$class" unless $class =~ /::/;
        require $class;
        push @sites, $class->new(@args);
    }
}


1;
