package LJ::CProd::UserPic;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->{defaultpicid};
    return 1;
}

sub render {
    my ($class, $u) = @_;
    my $empty = '<div style="overflow: hidden; padding: 5px; width: 100px; height: 100px; border: 1px solid #000000;">&nbsp;</div>';
        my $link = $class->clickthru_link("$LJ::SITEROOT/editpics.bml","userpic");
    my $user = LJ::ljuser($u);
    return qq {
        <p>$user, this is what you currently look like to your friends: $empty
            Boooring. Be classy and upload a $link</p>
};
}

1;
