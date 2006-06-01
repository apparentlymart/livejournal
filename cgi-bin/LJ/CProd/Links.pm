package LJ::CProd::Links;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->in_class('paid') || $u->in_class('perm');
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    # versions based on class
    $version = 1 if $u->in_class('free');
    $version = 2 if $u->in_class('plus');

    my $link = $class->clickthru_link('cprod.links.link', $version);
    my $link2 = BML::ml('cprod.links.link2-2.v'.$version, { aopts => "href='$LJ::SITEROOT/manage/payments/'" });

    return "</td></tr><tr><td colspan='2'>&nbsp;</td><td>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "link2" => $link2 });

}

sub ml { 'cprod.links.text' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }
sub button_text { "Upgrade" }

1;
