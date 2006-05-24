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

    return "<p>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link }) . "</p>";

}

sub ml { 'cprod.textmessaging.text' }
sub link { "$LJ::SITEROOT/manage/payments/" }
sub button_text { "Upgrade" }

1;
