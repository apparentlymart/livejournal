package LJ::Setting::PingBackComm;
use base 'LJ::Setting';
use strict;
use warnings;

use LJ::PingBack;

# Check if we can render widget
sub should_render {
    my $class = shift;
    my $u     = shift;

    return 0 unless $u->is_community;

    return 1;
}

# the link to the FAQ
sub helpurl {
    my ($class, $u) = @_;

    return "pingback_faq";
}

# Caption for widget
sub label {
    my $class = shift;

    return $class->ml('settings.pingbackcomm');
}

# Prepare HTML code for widget
sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    ## no value selected == pingback for community is on
    my $value = $u->prop('pingback') || 'O';
    $value = "O" unless $value  =~ /^[OD]$/;
    
    # PingBack options
    my $ret = '';
    $ret .= $class->ml('settings.pingbackcomm.process') . "&nbsp;<br />";
    $ret .= LJ::html_select({ 'name' => "${key}pingback", 'selected' => $value, disabled => LJ::PingBack->has_user_pingback($u) ? 0 : 1 },
                              "O" => $class->ml("settings.pingbackcomm.option.open"),
                              "D" => LJ::Lang::ml("settings.pingbackcomm.option.disabled"),
                            );
    return $ret;
}

# Save user choice
sub save {
    my ($class, $u, $args) = @_;
    
    return unless $class->should_render($u);
    
    my $value = $class->get_arg($args, "pingback");
    $value = "O" unless $value  =~ /^[OD]$/;
    return $u->set_prop('pingback', $value);
}

1;

