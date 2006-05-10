package LJ::CProd::Birthdays;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 1;
}

sub render {
    my ($class, $u) = @_;
    my $user = LJ::ljuser($u);
    my $icon = "<div style=\"float: left; padding-right: 5px;\"><img border=\"1\" src=\"$LJ::SITEROOT/img/cake.jpg\" /></div>";
    my $link = $class->clickthru_link("$LJ::SITEROOT/birthdays.bml","birthdays");
    return qq{
        <p>$icon $user, did you know you can impress your friends by "remembering" their $link?</p>
    };
}

1;
