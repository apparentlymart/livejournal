package LJ::CProd::Links;
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

    my $link = $class->clickthru_link('cprod.links.link', $version);
    my $link2 = $class->clickthru_link('cprod.links.link2', $version);

    return "<span style='padding-left: 10px;'>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "link2" => $link2 }) . "</span>";

}

sub ml { 'cprod.links.text' }
sub link { "$LJ::SITEROOT/manage/payments/" }
sub button_text { "Upgrade" }

1;
