package LJ::AccessLogSink;
use strict;

sub new {
    die "this is a base class\n";
}

sub log {
    my ($self, $rec) = @_;
    die "this is a base class\n";
}

1;
