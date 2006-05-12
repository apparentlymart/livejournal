package LJ::Setting::MangleEmail;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(mangle_email spam opt_mangleemail) }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my $ret = LJ::html_check({ 'type' => 'check', 'name' => "${key}opt_mangleemail",
                               'id' => 'opt_mangleemail',
                               'selected' => $u->prop("opt_mangleemail") eq 'Y' });
    $ret .= $class->errdiv($errs, "opt_mangleemail");
    $ret .= " <label for='opt_mangleemail'>$BML::ML{'.mangleaddress.header'}</label><br />";
    $ret .= $BML::ML{'.mangleaddress.about'};
    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;
    my $arg = $args->{opt_mangleemail} ? 'Y' : 'N';
    return 1 if $arg eq ($u->prop('opt_mangleemail') || 'N');
    $class->errors("opt_mangleemail" => "Invalid option")  unless $arg =~ /^[YN]$/;
    LJ::update_user($u, { opt_mangleemail => $arg} );
}

1;



