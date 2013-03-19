package LJ::Setting::AdultContent;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return !LJ::is_enabled("content_flag") || !$u || $u->is_identity ? 0 : 1;
}

sub helpurl {
    my ($class, $u) = @_;

    return "adult_content_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.adultcontent.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $adultcontent = $class->get_arg($args, "adultcontent") || $u->adult_content;

    my $ret;

    if ( LJ::is_enabled('remove_adult_concepts') ) {

        my $adultcontent = $class->get_arg($args, "adultcontent") || $u->adult_content;

        $ret = LJ::html_check({
            name => "${key}adultcontent",
            id => "${key}adultcontent",
            value => 'explicit',
            selected => $adultcontent eq 'explicit' ? 1 : 0,
        });

        $ret .= "<label for='${key}adultcontent'>" . ($u->is_community ? $class->ml('setting.adultcontent.option.comm2') : $class->ml('setting.adultcontent.option.self2')) . "</label> ";

    } else {

        my @options = (
            none => $class->ml('setting.adultcontent.option.select.none'),
            concepts => $class->ml('setting.adultcontent.option.select.concepts'),
            explicit => $class->ml('setting.adultcontent.option.select.explicit'),
        );

        $ret = "<label for='${key}adultcontent'>" . ($u->is_community ? $class->ml('setting.adultcontent.option.comm') : $class->ml('setting.adultcontent.option.self')) . "</label> ";
        $ret .= LJ::html_select({
            name => "${key}adultcontent",
            id => "${key}adultcontent",
            selected => $adultcontent,
        }, @options);

        my $errdiv = $class->errdiv($errs, "adultcontent");
        $ret .= "<br />$errdiv" if $errdiv;

    }

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "adultcontent");

    $class->errors( adultcontent => $class->ml('setting.adultcontent.error.invalid') )
        unless $val =~ /^(none|concepts|explicit)$/;

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val;

    if ( LJ::is_enabled('remove_adult_concepts') ) {
    
        $val = $class->get_arg($args, "adultcontent") ? "explicit" : "none";

    } else {

        $class->error_check($u, $args);

        $val = $class->get_arg($args, "adultcontent");
    }

    $u->set_prop( adult_content => $val );

    return 1;
}

1;
