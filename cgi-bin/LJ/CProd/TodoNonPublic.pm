package LJ::CProd::TodoNonPublic;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 if LJ::get_cap($u, "todosec");
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $link = $class->clickthru_link('cprod.todononpublic.link', $version);

    return BML::ml($class->get_ml($version), { "user" => $user, "link" => $link });

}

sub ml { 'cprod.todononpublic.text' }
sub link { "$LJ::SITEROOT/manage/payments/" }
sub button_text { "Upgrade" }

1;
