package LJ::CProd::UserPic;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->{defaultpicid};
    return 1;
}

sub render {
    my ($class, $u) = @_;
    my $link = $class->clickthru_link("$LJ::SITEROOT/editpics.bml",BML::ml('userpic.link'));
    my $user = LJ::ljuser($u);
    my $empty = '<div style="overflow: hidden; padding: 5px; width: 100px; 
height: 100px; border: 1px solid #000000;">&nbsp;</div>';
    return "<p>".BML::ml('userpic.text', { "user" => $user,
                                          "link" => $link,
                                          "empty" => $empty }) . "</p>";
}

1;
