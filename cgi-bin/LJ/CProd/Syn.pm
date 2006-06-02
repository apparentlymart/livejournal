package LJ::CProd::Syn;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if LJ::get_cap($u, "synd_create");
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    my $link = $class->clickthru_link('cprod.syn.link', $version);

    return "<p>" . BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "link2" => $link2 }) . "</p>";

}

sub ml { 'cprod.syn.text' }
sub link { "$LJ::SITEROOT/manage/payments/modify.bml" }

1;
