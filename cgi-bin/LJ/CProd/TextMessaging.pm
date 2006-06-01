package LJ::CProd::TextMessaging;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if (LJ::get_cap($u, "textmessaging"));
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    my $link = $class->clickthru_link('cprod.textmessaging.link', $version);
    my $link2 = BML::ml('cprod.textmessaging.link2-2.v'.$version, { aopts => "href='$LJ::SITEROOT/manage/payments/'" });

    return "<p>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "link2" => $link2 }) . "</p>";

}

sub ml { 'cprod.textmessaging.text2' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }
sub button_text { "Upgrade" }

1;
