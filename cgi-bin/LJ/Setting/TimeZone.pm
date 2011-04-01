package LJ::Setting::TimeZone;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return !$u || $u->is_community ? 0 : 1;
}

sub helpurl {
    my ($class, $u) = @_;

    return "time_zone";
}

sub label {
    my $class = shift;

    return $class->ml('setting.timezone.label');
}

# this one returns a $key => $value list, ordered by keys this way:
# US goes first, then Canada, then all the rest
sub timezone_options {
    my ($class) = @_;

    my $map = DateTime::TimeZone::links();

    my ( @options, %options );

    push @options, '' => $class->ml('setting.timezone.option.select');

    foreach my $key ( sort keys %$map ) {
        if ( $key =~ m!^US/! && $key ne 'US/Pacific-New' ) {
            $options{ $map->{$key} } = $key;
            push @options, $map->{$key} => $key;
        }
    }

    foreach my $key ( sort keys %$map ) {
        if ( $key =~ m!^Canada/! ) {
            $options{ $map->{$key} } = $key;
            push @options, $map->{$key} => $key;
        }
    }

    foreach my $key ( DateTime::TimeZone::all_names() ) {
        next if $options{$key};
        push @options, $key => $key;
    }

    return @options;
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $timezone = $class->get_arg($args, "timezone") || $u->prop("timezone");

    my @options = $class->timezone_options;

    my $ret = LJ::html_select({
        name => "${key}timezone",
        selected => $timezone,
    }, @options);

    my $errdiv = $class->errdiv($errs, "timezone");
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "timezone");

    $class->errors( timezone => $class->ml('setting.timezone.error.invalid') )
        unless !$val || grep { $val eq $_ } DateTime::TimeZone::all_names();

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $val = $class->get_arg($args, "timezone");
    $u->set_prop( timezone => $val );

    return 1;
}

1;
