package LJ::Setting::Gender;
use base 'LJ::Setting';
use strict;
use warnings;

sub as_html {
    my ($class, $u) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my $gender = $u->prop("gender");
    return "What's your gender? " .
        LJ::html_select({ 'name' => 'gender', 'selected' => $gender },
                        'U' => $BML::ML{'.gender.unspecified'},
                        'M' => $BML::ML{'.gender.male'},
                        'F' => $BML::ML{'.gender.female'} );
}

1;



