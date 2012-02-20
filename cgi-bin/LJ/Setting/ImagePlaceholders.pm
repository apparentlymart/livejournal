package LJ::Setting::ImagePlaceholders;
use base 'LJ::Setting';
use strict;
use warnings;
no warnings 'uninitialized';

sub should_render {
    my ($class, $u) = @_;

    return !$u || $u->is_community ? 0 : 1;
}

sub helpurl {
    my ($class, $u) = @_;

    return "image_placeholders_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.imageplaceholders.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $imgplaceholders = $u->get_opt_imagelinks;
    my( $chk1, $chk2 );

    if ( $imgplaceholders =~ /^(\d)\:(\d)$/ ) {
        $chk1 = $1;
        $chk2 = $2;
    }
    else {
        $chk1 = 0;
        $chk2 = 0;
    }

    my $ret = $class->ml('setting.imageplaceholders.option2')
        . "<label for='${key}check1'>"
        . LJ::html_check({
            selected => $chk1,
            name     => "${key}check1",
            id => "${key}check1",
          })
        . $class->ml('setting.imageplaceholders.option2.checkbox1')
        . "</label> "
        . "<label for='${key}check2'>"
        . LJ::html_check({
            selected => $chk2,
            name     => "${key}check2",
            id     => "${key}check2",
          })
        . $class->ml('setting.imageplaceholders.option2.checkbox2')
        . "</label> ";

    my $errdiv = $class->errdiv($errs, "imgplaceholders");
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my @val;
    push @val, $class->get_arg($args, $_) for map { "check$_" } 1..2;
    @val = map { $_ eq 'on' ? 1 : 0 } @val;

    my $val = join( ':', @val );
    $u->set_prop( opt_imagelinks => $val );

    return 1;
}

1;
