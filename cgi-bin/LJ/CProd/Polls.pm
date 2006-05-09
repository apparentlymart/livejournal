package LJ::CProd::Polls;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 unless LJ::get_cap($u, "makepoll");
    my $dbr = LJ::get_db_reader()
        or return 0;
    my $used_polls = $dbr->selectrow_array("SELECT pollid FROM poll WHERE posterid=?",
                                           undef, $u->{userid});
    return $used_polls ? 0 : 1;
}

sub render {
    my ($class, $u) = @_;
    return LJ::ljuser($u) . ", did you know you can post a poll in your journal using our " .
        $class->clickthru_link("$LJ::SITEROOT/poll/create.bml",
                               "poll creation wizard") . "?  It's easy.

<div style='margin: 1em'>

<div>That's crazy!</div>
<div style='white-space: nowrap'><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' alt='' /><img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='174' alt='' /><img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> <b>283</b> (58.0%)</div>

<div>I can't wait to try.</div>
<div style='white-space: nowrap'><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' alt='' /><img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='81' alt='' /><img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> <b>132</b> (27.0%)</div>

<div>What type of poll am I?</div>
<div style='white-space: nowrap'><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' alt='' /><img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='45' alt='' /><img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> <b>73</b> (15.0%)</div>

</div>
";

}

1;
