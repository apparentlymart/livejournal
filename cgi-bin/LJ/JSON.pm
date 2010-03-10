package LJ::JSON;

my $wrap = undef;

sub to_json {
    my ($class, @args) = @_;

    return $wrap->encode(@args);
}

sub from_json {
    my ($class, $dump) = @_;

    return $wrap->decode($dump);
}

BEGIN {
    my @classes = qw(JSON::XS JSON);
    foreach my $class (@classes) {
        eval "require $class";
        unless ($@) {
            $wrap = new $class;
            last;
        }
    }
}

1;
