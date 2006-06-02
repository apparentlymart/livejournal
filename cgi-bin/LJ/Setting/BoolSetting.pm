package LJ::Setting::BoolSetting;
use base 'LJ::Setting';
use strict;
use warnings;
use Carp qw(croak);

# if override to something non-undef, current_value and save_text work
# assuming a userprop vs. user field.
sub prop_name { undef }
sub user_field { undef }

# must override these with values you want checked/unchecked to be
sub checked_value { croak }
sub unchecked_value { croak }

sub current_value {
    my ($class, $u) = @_;
    if (my $propname = $class->prop_name) {
        return $u->prop($propname);
    } elsif (my $field = $class->user_field) {
        return $u->{$field};
    }
    croak;
}

sub is_selected {
    my ($class, $u) = @_;
    return $class->current_value($u) eq $class->checked_value;
}

sub label { croak; }

sub des { "" }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    my $html =
        LJ::html_check({
            name     => "${key}val",
            value    => 1,
            id       => "${key}check",
            selected => $class->is_selected($u),
        }) . " <label for='${key}check'>" . $class->label . "</label>";
    if (my $des = $class->des) {
        $html .= "<br />$des";
    }
    return $html;
}

sub save {
    my ($class, $u, $args) = @_;
    my $new_val = $args->{val} ? $class->checked_value : $class->unchecked_value;
    return 1 if $new_val eq $class->current_value($u);
    if (my $prop = $class->prop_name) {
        return $u->set_prop($prop, $new_val);
    } elsif (my $field = $class->user_field) {
        return LJ::update_user($u, { $field => $new_val });
    }
    croak "No prop_name or user_field set";
}

1;



