package LJ::CProd::EditPics;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 unless $u->in_class('plus') || $u->in_class('free');
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    # versions based on class
    $version = 1 if $u->in_class('free');
    $version = 2 if $u->in_class('plus');

    my $link = $class->clickthru_link('cprod.editpics.link', $version);
    my $link2 = BML::ml('cprod.editpics.link2.v'.$version, { aopts => "href='$LJ::SITEROOT/manage/payments/'" });

    return "<p>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "link2" => $link2 }) . "</p>";

}

sub ml { 'cprod.editpics.text3' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }
sub button_text { "Upgrade" }

1;
