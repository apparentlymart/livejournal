package LJ::Setting::Gender;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(gender sex male female boy girl) }

sub as_html {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";

    # show the one just posted, else the default one.
    my $gender = $class->get_arg($args, "gender") ||
        $u->prop("gender");

    return "What's your gender? " .
        LJ::html_select({ 'name' => "${key}gender", 'selected' => $gender },
                        'U' => $BML::ML{'.gender.unspecified'},
                        'M' => $BML::ML{'.gender.male'},
                        'F' => $BML::ML{'.gender.female'} ) .
                        $class->errdiv($errs, "gender");
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "gender");
    $class->errors("gender" => "Invalid option") unless $val =~ /^[UMF]$/;
    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $gen = $class->get_arg($args, "gender");
    return 1 if $gen eq ($u->prop('gender') || "U");

    $gen = "" if $gen eq "U";
    $u->set_prop("gender", $gen);
}

1;



