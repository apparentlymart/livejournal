package LJ::Widget::SubscribeInterface;

use strict;
use base qw(LJ::Widget);
use LJ::SMS::API::RU::Phone;

sub need_res {
    return qw(
        stc/esn.css
        js/core.js
        js/dom.js
        js/checkallbutton.js
        js/esn.js
    );
};

sub render_body {
    my ($self, $opts) = @_;

    my @groups = @{$opts->{'groups'}};
    my $u = $opts->{'u'} || LJ::get_remote();

    my @ntypes = @LJ::NOTIFY_TYPES;
    my (undef, $country) = LJ::GeoLocation->ip_class;
    if ($country ne 'RU' and
        not LJ::SMS::API::RU::Phone->is_users_number_supported($u)
    ){
        @ntypes = grep { $_ ne 'LJ::NotificationMethod::SMSru' ? 1 : 0 } @ntypes;
    }

    my $colnum = scalar(@ntypes) + 1;

    my %ntypeids = map { $_ => $_->ntypeid } @ntypes;

    my $ret = '';

    $ret .= '<table class="Subscribe" cellspacing="0" cellpadding="0" ' .
        'style="clear:none">' unless $self->{'no_table'};

    $self->{'catnum'} ||= 0;
    $self->{'field_num'} ||= 0;

    my $curcatnum = $self->{'catnum'}++;
    $ret .= '<tbody class="CategoryRow-' . $curcatnum . ' ' .
        'CategoryRow-'.$opts->{'css_class'}.'">';
    
    $ret .= '<tr class="CategoryRow CategoryRowFirst">';
    $ret .= '<td>';
    $ret .= '<span class="CategoryHeading">'.$opts->{'title'}.'</span>';
    $ret .= '<span class="CategoryHeading-notify">'.LJ::Lang::ml('subscribe_interface.notify_me').'</span>';
    $ret .= '<span class="CategoryHeading-delivery">'.LJ::Lang::ml('subscribe_interface.delivery_method').'</span>';

    unless ($self->{'printed_ntypeids_hidden'}) {
        $self->{'printed_ntypeids_hidden'} = 1;
        $ret .= LJ::html_hidden({'id' => 'ntypeids', 'value' => join(',', values %ntypeids)});
    }

    $ret .= '</td>';
    foreach my $ntype (@ntypes) {
        $ret .= "<td>";

        my $class = $ntype;
        my $title = $class->title;
        my $enabled = $class->configured_for_user($u);

        if ($class->disabled_url && !$enabled) {
            $title = "<a href='" . $class->disabled_url . "'>$title</a>";
        } elsif ($class->url) {
            $title = "<a href='" . $class->url . "'>$title</a>";
        }

        $title .= " " . LJ::help_icon($class->help_url) if $class->help_url;

        $ret .= LJ::html_check({
            'name' => 'CheckAll-'.$curcatnum.'-'.$ntypeids{$ntype},
            'class' => 'CheckAll',
            'id' => 'CheckAll-'.$curcatnum.'-'.$ntypeids{$ntype},
            'label' => $title,
            'disabled' => !$enabled,
            'noescape' => 1,
        });
        $ret .= "</td>";
    }
    $ret .= '</tr>';

    my $altrow = 0;
    my $visible_groups = 0;

    foreach my $group (@groups) {
        my $interface = $group->get_interface_status($u);
        next unless $interface->{'visible'};

        $visible_groups++;

        my @classes;
        push @classes, "altrow" if $altrow; $altrow = !$altrow;
        push @classes, "disabled" if $interface->{'disabled'};
        my $field_num = $self->{'field_num'}++;

        $ret .= '<tr class="'.join(' ', @classes).'">';

        my $event_html = $group->event_as_html($field_num);

        if ($self->{'allow_delete'} && $group->is_tracking) {
            my $link;
            my $frozen = $group->freeze;

            $link = $self->{'page'};
            $link .= ($link =~ /\?/ ? '&' : '?');
            $link .= 'delete_group='.$group->freeze . '&';
            $link .= 'auth_token='.LJ::eurl(LJ::Auth->ajax_auth_token(
                $u, $self->{'page'},
                'delete_group' => $group->freeze,
            ));

            $event_html = qq{
                <a href="$link" class="i-basket delete-group">
                    <img src="$LJ::SITEROOT/img/portal/btn_del.gif">
                </a>
                $event_html
            };
        }

        if ($interface->{'disabled'}) {
            $event_html .= ' ' . $interface->{'disabled_pic'};
        }

        $ret .= '<td>' . $event_html . '</td>';
        foreach my $ntype (@ntypes) {
            my $ntypeid = $ntypeids{$ntype};
            my $sub = $group->find_or_insert_ntype($ntypeid);

            my $ntype_interface = $group->get_ntype_interface_status($ntypeid, $u);
            my $value = $ntype_interface->{'disabled'} ?
                $ntype_interface->{'force'} :
                $sub->active;

            my $checkbox = '';
            $checkbox = LJ::html_check({
                'name' => 'sub-' . $field_num . '-' . $ntypeid,
                'id' => 'sub-' . $field_num . '-' . $ntypeid,
                'selected' => $value,
                'disabled' => $ntype_interface->{'disabled'},
                'class' => 'SubscribeCheckbox-'.$curcatnum.'-'.$ntypeids{$ntype},
            }) if $ntype_interface->{'visible'};

            $ret .= '<td>' . $checkbox . '</td>';
        }
        $ret .= '</td>';
    }    

    unless ($visible_groups) {
        my $blurb = "<?p <strong>" . LJ::Lang::ml('subscribe_interface.nosubs.title') . "</strong><br />";
        $blurb .= LJ::Lang::ml('subscribe_interface.nosubs.text', { img => "<img src='$LJ::SITEROOT/img/btn_track.gif' width='22' height='20' align='absmiddle' />" }) . " p?>";

        $ret .= "<tr>";
        $ret .= "<td colspan='$colnum'>$blurb</td>";
        $ret .= "</tr>";
    }

    $ret .= '</tbody>';

    $ret .= '</table>' unless $self->{'no_table'};
    $ret .= LJ::html_hidden({'id' => 'catids', 'value' => $curcatnum})
        unless $self->{'no_table'};

    return $ret;
}

1;
