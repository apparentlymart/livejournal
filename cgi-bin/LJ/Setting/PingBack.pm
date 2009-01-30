package LJ::Setting::PingBack;
use base 'LJ::Setting';
use strict;
use warnings;

use LJ::PingBack;

# Check if we can render widget
sub should_render {
    my $class = shift;
    my $u     = shift;
    # Render if widget enabled on server
    return 0 if $LJ::DISABLED{'pingback'};
    return 1;
}

# Caption for widget
sub label {
    my $class = shift;

    return $class->ml('settings.pingback');
}

# Prepare HTML code for widget
sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $upgrade_link = $u->get_cap('pingback') ? "" : (LJ::run_hook("upgrade_link", $u, "paid") || "");

    # PingBack options
    my $ret = '';
    $ret .= $class->ml('settings.pingback.process') . "&nbsp;<br />";
    $ret .= LJ::html_select({ 'name' => "${key}pingback", 'selected' => $u->prop('pingback'), disabled => LJ::PingBack->has_user_pingback($u) ? 0 : 1 },
                              "L" => $class->ml("settings.pingback.option.lj_only"),
                              "O" => $class->ml("settings.pingback.option.open"),
                              "D" => $class->ml("settings.pingback.option.disabled"),
                            );
    $ret .= "&nbsp;" . $upgrade_link;
    return $ret;
}

# Save user choice
sub save {
    my ($class, $u, $args) = @_;
    
    return unless $class->should_render($u);
    
    my $value = $class->get_arg($args, "pingback");
    $value = "D" unless $value  =~ /^[OLD]$/;
    return $u->set_prop('pingback', $value);
}

1;

