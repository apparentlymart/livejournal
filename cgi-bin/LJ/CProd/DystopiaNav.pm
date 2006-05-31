package LJ::CProd::DystopiaNav;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->in_class('paid') || $u->in_class('perm');
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $link = $class->clickthru_link('cprod.dystopia.nav.link2', $version, style => 'class="navlinks"');
    return BML::ml($class->get_ml($version), { "user" => $user, "link" => $link });
}

sub ml { 'cprod.dystopia.nav.text' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }
sub button_text { "Upgrade" }

1;
