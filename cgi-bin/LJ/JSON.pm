package LJ::JSON;
use strict;

my $wrap;

sub to_json {
    my ($class, @args) = @_;

    return $wrap->encode(@args);
}

sub from_json {
    my ($class, $dump) = @_;

    return unless $dump;
    return $wrap->decode($dump);
}

sub class {
    return ref $wrap;
}

sub true  { $wrap->true  };
sub false { $wrap->false };

sub to_boolean {
    my ( $class, $what ) = @_;
    return $what ? $wrap->true : $wrap->false;
}

sub to_number {
    my ( $class, $what ) = @_;

    # not using int deliberately because we may be handling floats here
    return $what + 0;
}

foreach my $class (qw(LJ::JSON::XS LJ::JSON::JSONv2 LJ::JSON::JSONv1)) {
    if ($class->can_load) {
        $wrap = $class->new;
        last;
    }
}
die unless $wrap;

1;

package LJ::JSON::Wrapper;

use Encode qw();

sub traverse {
    my ($class, $what, $sub) = @_;

    my $type = ref $what;

    # simple scalar
    if ($type eq '') {
        return $sub->($what);
    }

    # hashref
    if ($type eq 'HASH') {
        my %ret;
        foreach my $k (keys %$what) {
            $ret{$sub->($k)} = $class->traverse($what->{$k}, $sub);
        }
        return \%ret;
    }

    # arrayref
    if ($type eq 'ARRAY') {
        my @ret;
        foreach my $v (@$what) {
            push @ret, $class->traverse($v, $sub);
        }
        return \@ret;
    }

    # unknown type; let the subclass decode it to a scalar
    # (base class function defaults to plain stringification)
    return $sub->($class->decode_unknown_type($what));
}

sub traverse_fix_encoding {
    my ($class, $what) = @_;

    return $class->traverse($what, sub {
        my ($scalar) = @_;

        return $scalar unless Encode::is_utf8($scalar);

        # if the string does indeed contain wide characters (which happens
        # in case the source string literals contained chars specified as
        # '\u041c'), encode stuff as utf8
        if ($scalar =~ /[^\x01-\xff]/) {
            return Encode::encode("utf8", $scalar);
        }

        return Encode::encode("iso-8859-1", $scalar);
    });
}

sub decode_unknown_type {
    my ($class, $what) = @_;

    return "$what";
}

sub clean_after_encode {
    my ($class, $encoded) = @_;

    unless (Encode::is_utf8($encoded)) {
        $encoded = Encode::decode('utf8', $encoded);
    }

    # Perl 5.10 do not understand \x{00ad} sequence as Unicode char in the regexp s/...|\x{00ad}|.../, therefore we used char class.
    # Dangerous symbols, that were tested on the Chrome and were a reason of its crush: \r \n \x{2028} \x{2029}
    $encoded =~ s/[\r\n\x{0000}\x{0085}\x{00ad}\x{2028}\x{2029}\x{0600}-\x{0604}\x{070f}\x{17b4}\x{17b5}\x{200c}-\x{200f}\x{202a}-\x{202f}\x{2060}-\x{206f}\x{feff}\x{fff0}-\x{ffff}]//gs;

    return Encode::encode('utf8', $encoded);
}

package LJ::JSON::XS;

our @ISA;
BEGIN { @ISA = qw(LJ::JSON::Wrapper JSON::XS); }

sub can_load {
    eval { require JSON::XS; JSON::XS->import; };
    return !$@;
}

sub new {
    my ($class) = @_;
    return $class->SUPER::new->latin1;
}

sub encode {
    my $class = shift;
    my $encoded = $class->SUPER::encode(@_);
    return $class->clean_after_encode($encoded);
}

sub decode {
    my ($class, $dump) = @_;

    my $decoded = $class->SUPER::decode($dump);
    $decoded = $class->traverse_fix_encoding($decoded);
    return $decoded;
}

sub decode_unknown_type {
    my ($class, $what) = @_;

    # booleans get converted to undef for false and 1 for true
    return $what ? 1 : undef if JSON::XS::is_bool($what);

    # otherwise, stringify
    return "$what";
}

1;

package LJ::JSON::JSONv2;

our @ISA;
BEGIN { @ISA = qw(LJ::JSON::Wrapper JSON); }

sub can_load {
    eval { require JSON };
    return !$@ && $JSON::VERSION ge 2;
}

sub new {
    my ($class) = @_;
    return $class->SUPER::new->latin1;
}

sub decode {
    my ($class, $dump) = @_;

    my $decoded = $class->SUPER::decode($dump);
    $decoded = $class->traverse_fix_encoding($decoded);
    return $decoded;
}

sub decode_unknown_type {
    my ($class, $what) = @_;

    # booleans get converted to undef for false and 1 for true
    return $what ? 1 : undef if JSON::is_bool($what);

    # otherwise, stringify
    return "$what";
}

1;

package LJ::JSON::JSONv1;

our @ISA;
BEGIN { @ISA = qw(LJ::JSON::Wrapper JSON); }

sub can_load {
    eval { require JSON };
    return !$@ && $JSON::VERSION ge 1;
}

*encode = \&JSON::objToJson;
*decode = \&JSON::jsonToObj;

1;
