package LJ::CProd::Links;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    my $paid = 1 << LJ::class_bit('paid');
    return 0 unless LJ::get_cap($u, 'userlinks') < LJ::get_cap($paid, 'userlinks');
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    my $free = 1 << LJ::class_bit('free');
    my $plus = 1 << LJ::class_bit('plus');
    # versions based on class
    if (LJ::get_cap($u, 'userlinks') == LJ::get_cap($free, 'userlinks')) {
        $version = 1;
    } elsif (LJ::get_cap($u, 'userlinks') == LJ::get_cap($plus, 'userlinks')) {
        $version = 2;
    }

    my $link = $class->clickthru_link('cprod.links.link', $version);
    my $link2 = BML::ml('cprod.links.link2-2.v'.$version, { aopts => "href='$LJ::SITEROOT/manage/payments/'" });

    return "</td></tr><tr><td colspan='2'>&nbsp;</td><td>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "link2" => $link2 });

}

sub ml { 'cprod.links.text' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }
sub button_text { "Upgrade" }

1;
