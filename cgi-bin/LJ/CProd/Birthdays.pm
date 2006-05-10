package LJ::CProd::Birthdays;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 1;
}

sub render {
    my ($class, $u) = @_;
    return "<p><div style=\"float: left; padding-right: 5px;\"><img border=\"1\" src=\"$LJ::SITEROOT/img/cake.jpg\" /></div>". LJ::ljuser($u) . ", did you know you can impress your friends by ".
        "\"remembering\" their ". $class->clickthru_link("$LJ::SITEROOT/birthdays.bml","birthdays") . "?</p>";
}

1;
