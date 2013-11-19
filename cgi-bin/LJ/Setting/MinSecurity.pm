package LJ::Setting::MinSecurity;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "minsecurity_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.minsecurity.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $minsecurity = $class->get_arg($args, "minsecurity") || $u->prop("newpost_minsecurity");

    my @options = (
        "" => $class->ml('setting.minsecurity.option.select.public'),
        friends => $u->is_community ? $class->ml('setting.minsecurity.option.select.members') : $class->ml('setting.minsecurity.option.select.friends'),
    );
    push @options, ( private => $class->ml('setting.minsecurity.option.select.private') )
        if $u->is_personal;

    my $ret = "<label for='${key}minsecurity'>" . $class->ml('setting.minsecurity.option') . "</label> ";
    $ret .= LJ::html_select({
        name => "${key}minsecurity",
        id => "${key}minsecurity",
        selected => $minsecurity,
    }, @options);

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "minsecurity");
    if ($u->is_community) {
        $val = "" unless $val =~ /^(friends)$/;
    } else {
        $val = "" unless $val =~ /^(friends|private)$/;
    }

    my $old_value = $u->prop("newpost_minsecurity");
    $u->set_prop( newpost_minsecurity => $val );

    return 1 if $old_value eq $val;

    LJ::User::UserlogRecord::ChangeSetting->create( $u,
        setting_name => 'newpost_minsecurity',
        new_value    => $val || 'public',
        old_value    => $old_value || 'public',
    );

    return 1;
}

1;
