package LJ::Setting::WebmasterTools;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    my $remote = LJ::get_remote();
    return 0 if $class eq __PACKAGE__; # this is an abstract class
    return ($u && $u->is_personal) || ($remote && $remote->can_super_manage($u)) ? 1 : 0; 
}

sub code {
    my ($class) = @_;

    $class =~ s/^LJ::Setting:://;
    $class =  lc $class;
    $class =~ s/::/_/g;

    return $class;
}

sub helpurl {
    my ($class, $u) = @_;

    return 'webmaster_tools';
}

sub label {
    my $class = shift;

    return $class->ml('setting.'.$class->code.'.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;
    my $code = $class->code;

    my $value = $class->get_arg($args, $code) || $u->prop($code);

    my $ret = '';

    $ret .= $class->ml('setting.'.$class->code.'.label2') . ' ';
    $ret .= LJ::html_text({
        name => "$key$code",
        id => "$key$code",
        value => $value,
    });
    $ret .=  $class->errdiv($errs, $class->code);

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, $class->code);

    $class->errors( $class->code => $class->ml('setting.webmastertools.error') )
        unless $val =~ /^[a-z0-9\-_]*$/i;

    $u->set_prop( $class->code => $val );

    return 1;
}

sub as_html {
    my ($class, $u, $errs, $args) = @_;

    return $class->option($u, $errs, $args);
}

1;
