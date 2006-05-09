package LJ::CProd::ControlStrip;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->prop("view_control_strip") || $u->prop("show_control_strip");
    return 1;
}

sub render {
    my ($class, $u) = @_;
    return LJ::ljuser($u) . ", did you know you can enable an easy-to-use ". 
        $class->clickthru_link("$LJ::SITEROOT/manage/settings","navigation strip?");
}

1;
