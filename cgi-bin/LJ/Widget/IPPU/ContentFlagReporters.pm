package LJ::Widget::IPPU::ContentFlagReporters;
use base "LJ::Widget::IPPU";
use strict;

sub render_body {
    my ($class, %opts) = @_;

    my $remote = LJ::get_remote();

    return "Unauthorized" unless $remote && $remote->can_admin_content_flagging;
    return "invalid params" unless $opts{journalid} && $opts{typeid} && $opts{itemid};

    my $ret = '';

    my $dbr = LJ::get_db_reader();
    my $rows = $dbr->selectcol_arrayref('SELECT reporterid FROM content_flag WHERE ' .
                                        'journalid=? AND typeid=? AND itemid=? ORDER BY instime DESC LIMIT 1000',
                                        undef, $opts{journalid}, $opts{typeid}, $opts{itemid});
    die $dbr->errstr if $dbr->err;

    my $users = LJ::load_userids(@$rows);

    my @reporters = values %$users;

    my $usernames = '';

    my $i = 0;
    foreach my $u (@reporters) {
        my $border = $i ? 1 : 0;

        my $rowcolor = $i % 2 == 0 ? 'EEEEEE' : 'CCCCCC';
        $usernames .= "<div style='padding: 2px; border-top: ${border}px solid #DDDDDD; background-color: #$rowcolor;>";
            $usernames .= $u->ljuser_display . ' - ' . LJ::ehtml($u->display_name) . '</div>';

        $i++;
    }

    $ret .= qq {
        <div class="su_username_list" style="overflow-y: scroll; height: 20em; margin: 4px; border: 1px solid #EEEEEE;">
            $usernames
        </div>
    };

    return $ret;
}

1;
