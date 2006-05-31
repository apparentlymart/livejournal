package LJ::CProd::FriendsFriendsInline;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if LJ::get_cap($u, "friendsfriendsview");
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    my $link = $class->clickthru_link('cprod.friendsfriendsinline.link2', $version);

    return "<p>$icon ".BML::ml($class->get_ml($version), { "user" => $user,
                                                 "link" => $link }) . "</p>";

}

sub ml { 'cprod.friendsfriendsinline.text2' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }

1;
