package LJ::Setting::Bio;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(bio biography about) }

sub as_html {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;
    my $ret;
    local $BML::ML_SCOPE = "/manage/profile/index.bml";

    # load and clean bio
    my $saved_bio = $u->bio;
    LJ::text_out(\$saved_bio, "force");

    if (LJ::text_in($saved_bio)) {
        $ret .= "Bio:<br />";
        $ret .= "Tell us a little (or a lot) about yourself. Who you are, what your journal is about, or whatever else you want to put in here.<br />";
        $ret .= LJ::html_textarea({ 'name' => "${key}bio", 'rows' => '10', 'cols' => '50',
                                    'wrap' => 'soft', 'value' => $saved_bio, 'style' => "width: 90%" }) . "<br />";
        $ret .= "<small>Images, counters, and other HTML accepted.</small>";
    } else {
        $ret .= LJ::html_hidden("${key}bio_absent", 'yes');
        $ret .= "<?p <?inerr " . LJ::Lang::ml('.error.invalidbio', {'aopts' => "href='$LJ::SITEROOT/utf8convert.bml'"}) . " inerr?> p?>";
    }
    $ret .= $class->errdiv($errs, "bio");

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;

    unless (LJ::text_in($class->get_arg($args, "bio"))) {
        $class->errors("bio" => "Invalid bio");
    }

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $bio = $class->get_arg($args, "bio");
    my $bio_absent = $class->get_arg($args, "bio_absent");

    $u->set_bio($bio, $bio_absent);
}

1;
