package LJ::Setting::Email;
use base 'LJ::Setting';
use strict;
use warnings;


sub as_html {
    my ($class, $u) = @_;
    my $key = $class->pkgkey;
    return "What's your email address? " .
        LJ::html_text({
            name  => "${key}email",
            value => $u->{email},
            size  => 40,
        });
}

1;



