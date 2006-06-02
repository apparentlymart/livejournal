package LJ::CProd::EditPics;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;

    my $bit = $LJ::Pay::bonus{'userpic'}->{'cap'};
    my $has_cap = $u->{'caps'} & 1 << $bit;
    my $userpicsaddon = defined $bit && $has_cap;

    return 0 if $userpicsaddon;
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    my $free = 1 << LJ::class_bit('free');
    my $plus = 1 << LJ::class_bit('plus');
    my $paid = 1 << LJ::class_bit('paid');
    my $freenum = LJ::get_cap($free, 'userpics', { no_hook => 1 });
    my $plusnum = LJ::get_cap($plus, 'userpics', { no_hook => 1 });
    my $paidnum = LJ::get_cap($paid, 'userpics', { no_hook => 1 });

    my $num = LJ::get_cap($u, 'userpics', { no_hook => 1 });

    # versions based on class
    if ($num == $freenum) {
        $version = 1;
    } elsif ($num == $plusnum) {
        $version = 2;
    } elsif ($num == $paidnum) {
        $version = 3;
    }

    my $link = $class->clickthru_link('cprod.editpics.link', $version);
    my $link2 = BML::ml('cprod.editpics.link2-2.v'.$version, { aopts => "href='$LJ::SITEROOT/manage/payments/'" });
    my $link3 = BML::ml('cprod.editpics.link3-3.v'.$version, { aopts => "href='$LJ::SITEROOT/shop/view.bml?item=userpics'" });

    return "<p>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "link2" => $link2, "link3" => $link3, "num" => $num, "plusnum" => $plusnum, "paidnum" => $paidnum}) . "</p>";

}

sub ml { 'cprod.editpics.text5' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }
sub button_text { "Upgrade" }

1;
