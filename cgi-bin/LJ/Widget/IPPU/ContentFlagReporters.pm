use strict;

package LJ::Widget::IPPU::ContentFlagReporters;
use base "LJ::Widget::IPPU";

sub render_body {
    my ($class, %opts) = @_;

    my $remote = LJ::get_remote();

    return "Unauthorized" unless $remote && $remote->can_admin_content_flagging;
    return "invalid params" unless $opts{journalid} && $opts{typeid} && $opts{catid};

    my $ret = '';

    my @reporters = LJ::ContentFlag->get_reporters(journalid => $opts{journalid},
                                                   typeid    => $opts{typeid},
                                                   catid     => $opts{catid},
                                                   itemid    => $opts{itemid});
    my $usernames = '';

    $ret .= $class->start_form(id => 'banreporters_form');
    $ret .= $class->html_hidden("journalids", join(',', map { $_->id } @reporters));

    my $i = 0;
    foreach my $u (@reporters) {
        my $border = $i ? 1 : 0;

        my $rowcolor = $i % 2 == 0 ? 'EEEEEE' : 'CCCCCC';
        $usernames .= "<div style='padding: 2px; border-top: ${border}px solid #DDDDDD; background-color: #$rowcolor;'>";
        $usernames .= $class->html_check(name => "ban_" . $u->id);
        $usernames .= ' ' . $u->ljuser_display . ' - ' . $u->name_html . '</div>';

        $i++;
    }

    $ret .= qq {
        <div class="su_username_list" style="overflow-y: scroll; max-height: 20em; margin: 4px; border: 1px solid #EEEEEE;">
            $usernames
        </div>
    };

    $ret .= '<p>' . $class->html_check(name => "ban", id => 'banreporters', label => 'Ban selected users') . '</p>';

    $ret .= '<input type="button" name="doban" value="Ban" disabled="1" id="banreporters_do" />';
    $ret .= '<input type="button" name="cancel" value="Cancel" id="banreporters_cancel" />';

    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ($class, $post) = @_;

    my $remote = LJ::get_remote();
    die "Unauthorized" unless $remote && $remote->can_admin_content_flagging;

    my $journalids = $post->{journalids} or return;
    my @jids = split(',', $journalids) or return;

    my @to_ban;

    foreach my $journalid (@jids) {
        next unless $post->{"ban_$journalid"};
        push @to_ban, $journalid;
    }

    my $to_ban_users = LJ::load_userids(@to_ban);

    foreach my $u (values %$to_ban_users) {
        # ban $u
    }
}

1;
