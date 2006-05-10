package LJ::CProd::UserPic;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->{defaultpicid};
    return 1;
}

sub render {
    my ($class, $u) = @_;
    return "<p><div style=\"float: left; padding: 5px;\"><img border=\"1\" src=\"$LJ::SITEROOT/img/userpics.gif\" /></div>". LJ::ljuser($u) . ", did you know you can have a ". 
        $class->clickthru_link("$LJ::SITEROOT/editpics.bml","userpic") . " to compliment your entries?</p>";
}

1;
