package LJ::Setting::TextSetting;
use base 'LJ::Setting';
use strict;
use warnings;
use Carp qw(croak);

# if override to something non-undef, current_value and save_text work
# assuming a userprop
sub prop_name { undef }

sub current_value {
    my ($class, $u) = @_;
    if (my $propname = $class->prop_name) {
        return $u->prop($propname);
    }
    croak;
}

# zero means no limit.
sub max_bytes { 0 }
sub max_chars { 0 }

# display size:
sub text_size { 40 }

sub question { croak; }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    return $class->question .
        "&nbsp;" .
        LJ::html_text({
            name  => "${key}txt",
            value => $class->current_value($u),
            size  => $class->text_size,
        }) .
        $class->errdiv($errs, "txt");
}

sub save {
    my ($class, $u, $args) = @_;
    my $txt = $args->{txt};
    return 1 if $txt eq $class->current_value($u);
    unless (LJ::text_in($txt)) {
        $class->errors(txt => "Invalid UTF-8");
    }
    return $class->save_text($u, $txt);
}

sub save_text {
    my ($class, $u, $txt) = @_;
    if (my $propname = $class->prop_name) {
        return $u->set_prop($propname, $txt);
    }
    croak;
}

1;



