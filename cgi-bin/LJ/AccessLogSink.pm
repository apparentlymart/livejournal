package LJ::AccessLogSink;
use strict;
use warnings;
use LJ::ModuleCheck;

sub new {
    die "this is a base class\n";
}

sub log {
    my ($self, $rec) = @_;
    die "this is a base class\n";
}

my $need_rebuild = 1;
my @sinks = ();

sub forget_sink_objs {
    $need_rebuild = 1;
    @sinks = ();
}

1;
