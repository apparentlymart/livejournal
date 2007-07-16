package LJ::Widget::IPPU::ContentFlagReporters;
use base "LJ::Widget::IPPU";
use strict;

sub render_body {
    my ($class, %opts) = @_;

    my $remote = LJ::get_remote();

    return "Unauthorized" unless $remote && $remote->can_admin_content_flagging;
    return "invalid params" unless $opts{journalid} && $opts{typeid};

    my $ret = '';

    my @reporters = LJ::ContentFlag->get_reporters(journalid => $opts{journalid},
                                                   typeid    => $opts{typeid},
                                                   itemid    => $opts{itemid});
    my $usernames = '';

    my $i = 0;
    foreach my $u (@reporters) {
        my $border = $i ? 1 : 0;

        my $rowcolor = $i % 2 == 0 ? 'EEEEEE' : 'CCCCCC';
        $usernames .= "<div style='padding: 2px; border-top: ${border}px solid #DDDDDD; background-color: #$rowcolor;>";
        $usernames .= $u->ljuser_display . ' - ' . $u->name_html . '</div>';

        $i++;
    }

    $ret .= qq {
        <div class="su_username_list" style="overflow-y: scroll; max-height: 20em; margin: 4px; border: 1px solid #EEEEEE;">
            $usernames
        </div>
    };

    return $ret;
}

1;
