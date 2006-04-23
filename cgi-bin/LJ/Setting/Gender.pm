package LJ::Setting::Gender;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(gender sex male female boy girl) }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my $gender = $u->prop("gender");
    return "What's your gender? " .
        LJ::html_select({ 'name' => "${key}gender", 'selected' => $gender },
                        'U' => $BML::ML{'.gender.unspecified'},
                        'M' => $BML::ML{'.gender.male'},
                        'F' => $BML::ML{'.gender.female'} ) .
                        $class->errdiv($errs, "gender");
}

sub save {
    my ($class, $u, $args) = @_;
    my $gen = $args->{gender} || "U";
    return 1 if $gen eq $u->prop('gender');
    $class->errors("gender" => "Invalid option")  unless $gen =~ /^[UMF]$/;
    $gen = "" if $gen eq "U";
    $u->set_prop("gender", $gen);
}

1;



