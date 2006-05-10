package LJ::CProd::Feeds;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 1;
}

sub render {
    my ($class, $u) = @_;
    return "<p><div style=\"float: left; padding-right: 5px;\"><img border=\"1\" src=\"$LJ::SITEROOT/img/syndicated24x24.gif\" /></div>". LJ::ljuser($u) . ", did you know you can add ".
        $class->clickthru_link("$LJ::SITEROOT/syn/list.bml","syndicated feeds") . " to your friends list, and <i>never</i> leave LiveJournal again for your blogging needs?</p>";
}

1;
