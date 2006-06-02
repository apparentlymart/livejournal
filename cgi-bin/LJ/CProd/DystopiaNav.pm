package LJ::CProd::DystopiaNav;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if LJ::get_cap($u, "paid");
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;

    # versions based on class
    if (LJ::get_cap($u, "ads")) {
        $version = 2;
    } else {
        $version = 1;
    }

    my $user = LJ::ljuser($u);
    my $link = $class->clickthru_link('cprod.dystopia.nav.link3', $version, style => 'class="navlinks"');
    return BML::ml($class->get_ml($version), { "user" => $user, "link" => $link });
}

sub ml { 'cprod.dystopia.nav.text2' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }
sub button_text { "Upgrade" }

1;
