package LJ::JSON;

my $wrap;

sub to_json {
    my ($class, @args) = @_;

    return $wrap->encode(@args);
}

sub from_json {
    my ($class, $dump) = @_;

    my $ret = eval { $wrap->decode($dump) };

    return undef if $@;
    return $ret;
}

foreach my $class (qw(LJ::JSON::XS LJ::JSON::JSONv2 LJ::JSON::JSONv1)) {
    if ($class->can_load) {
        $wrap = $class->new;
        last;
    }
}
die unless $wrap;

1;

package LJ::JSON::XS;

BEGIN { @ISA = qw(JSON::XS); }

sub can_load {
    eval { require JSON::XS; JSON::XS->import; };
    return !$@;
}

1;

package LJ::JSON::JSONv2;

BEGIN { @ISA = qw(JSON); }

sub can_load {
    eval { require JSON };
    return !$@ && $JSON::VERSION ge 2;
}

1;

package LJ::JSON::JSONv1;

BEGIN { @ISA = qw(JSON); }

sub can_load {
    eval { require JSON };
    return !$@ && $JSON::VERSION ge 1;
}

*encode = \&JSON::objToJson;
*decode = \&JSON::jsonToObj;

1;
