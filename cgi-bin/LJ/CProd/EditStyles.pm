package LJ::CProd::EditStyles;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->in_class('paid') || $u->in_class('perm');
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $link = $class->clickthru_link('cprod.editstyles.link', $version);

    return "<p>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link }) . "</p>";

}

sub ml { 'cprod.editstyles.text' }
sub link { "$LJ::SITEROOT/manage/payments/" }
sub button_text { "Upgrade" }

1;
