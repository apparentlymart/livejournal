package LJ::ControlStrip;

use strict;
use LJ::Widget::Calendar;
use LJ::Widget::JournalPromoStrip;

sub render {
    my ($class, $user) = @_;
    my $show_strip = 1;

    if (LJ::are_hooks("show_control_strip")) {
        $show_strip = LJ::run_hook("show_control_strip", { user => $user });
    }

    return "" unless $show_strip;

    my $remote = LJ::get_remote();
    my $journal = LJ::load_user($user);
    my $uri = LJ::eurl( LJ::Request->current_page_url );

    my $data_remote = {};
    my $data_journal = {
        user => $journal->{user},
        url => {
            base => $journal->journal_base,
        },
        page => "http://" . LJ::Request->header_in("Host") . LJ::Request->uri,
    };
    my $data_control_strip = {};

    if ($remote && LJ::u_equals($remote, $journal)) {
        $data_journal->{type} = 'own';
    } elsif ($journal->is_personal || $journal->is_identity) {
        $data_journal->{type} = 'personal';
    } elsif ($journal->is_community) {
        $data_journal->{type} = 'community';
    } elsif ($journal->is_syndicated) {
        $data_journal->{type} = 'syndicated';
    } elsif ($journal->is_news) {
        $data_journal->{type} = 'news';
    } else {
        $data_journal->{type} = 'other';
    }

    $data_journal->{'is_' . $data_journal->{type}} = 1;

    $data_journal->{view} = LJ::Request->notes('view');
    $data_journal->{display} = LJ::ljuser($journal);
    $data_journal->{view_tag} = $data_journal->{view} eq 'tag';
    $data_journal->{view_entry} = $data_journal->{view} eq 'entry';
    $data_journal->{view_friends} = $data_journal->{view} eq 'friends';
    $data_journal->{view_entry_is_valid} = 0;
    $data_journal->{view_friendsfriends} = $data_journal->{view} eq 'friendsfriends';
    $data_journal->{has_friendspage_per_day} = ($journal->get_cap('friendspage_per_day') ? 1 : 0);

    if ($data_journal->{view_entry}) {
        my $uri = LJ::Request->uri();

        if ($uri =~ /(\d+)\.html/) {
            my $entry = LJ::Entry->new($journal, ditemid => $1);

            if ($entry and $entry->correct_anum) {
                my $attrs = $entry->sharing_attributes();

                $data_journal->{sharing_attributes}   = join ' ', map {$_.'="'.$attrs->{$_}.'"'} keys %$attrs;
                $data_journal->{view_entry_is_valid}  = 1;
                $data_journal->{view_entry_is_public} = ($entry->is_public() ? 1 : 0);
            }
        }
    }

    if ($remote) {
        $data_remote->{is_logged_in} = 1;
        $data_remote->{user}         = $remote->{user};
        $data_remote->{display}      = LJ::ljuser($remote);
        $data_remote->{sessid}       = ($remote->session ? $remote->{_session}->{sessid} : undef);
        $data_remote->{is_sup}       = (LJ::SUP->is_sup_enabled($remote) ? 1 : 0);
        $data_remote->{is_paid}      = $remote->in_class('paid') || $remote->in_class('sponsored');
        $data_remote->{is_personal}  = ($remote->is_personal() ? 1 : 0);
        $data_remote->{is_identity}  = ($remote->is_identity() ? 1 : 0);

        if ($remote->{defaultpicid}) {
            $data_remote->{userpic} = {
                src   => "$LJ::USERPIC_ROOT/$remote->{defaultpicid}/$remote->{userid}",
                alt   => LJ::Lang::ml('web.controlstrip.userpic.alt'),
                title => LJ::Lang::ml('web.controlstrip.userpic.title'),
            };
        } else {
            my $tinted_nouserpic_img = "";

            if ($journal->prop('stylesys') == 2) {
                my $ctx = $LJ::S2::CURR_CTX;
                my $custom_nav_strip = S2::get_property_value($ctx, "custom_control_strip_colors");

                if ($custom_nav_strip ne "off") {
                    my $linkcolor = S2::get_property_value($ctx, "control_strip_linkcolor");

                    if ($linkcolor ne "") {
                        $tinted_nouserpic_img = S2::Builtin::LJ::palimg_modify($ctx, "controlstrip/nouserpic.gif?v=6802", [S2::Builtin::LJ::PalItem($ctx, 0, $linkcolor)]);
                    }
                }
            }

            $data_remote->{userpic} = {
                src   => $tinted_nouserpic_img || "$LJ::IMGPREFIX/controlstrip/nouserpic.gif?v=6802",
                alt   => LJ::Lang::ml('web.controlstrip.nouserpic.alt'),
                title => LJ::Lang::ml('web.controlstrip.nouserpic.title'),
            };
        }

        my $inbox = $remote->notification_inbox();

        $data_remote->{inbox} = {
            unread_count => $inbox->unread_count,
        };

        $data_remote->{wallet} = {
            balance => int(LJ::Pay::Wallet->get_user_balance($remote)),
        };

        if ($remote->{userid} != $journal->{userid}) {
            $data_remote->{style_always_mine} = LJ::Widget::StyleAlwaysMine->render(u => $remote);
        }

        $data_remote->{url}->{base}                = $remote->journal_base;
        $data_remote->{url}->{inbox}               = "$LJ::SITEROOT/inbox/";
        $data_remote->{url}->{tokens}              = "$LJ::SITEROOT/shop/tokens.bml";
        $data_remote->{url}->{edit_pics}           = "$LJ::SITEROOT/editpics.bml";
        $data_remote->{url}->{manage_tags}         = $LJ::DISABLED{'tags_merge'} ? "$LJ::SITEROOT/manage/tags.bml" : "$LJ::SITEROOT/account/settings/tags";
        $data_remote->{url}->{send_message}        = "$LJ::SITEROOT/inbox/compose.bml";
        $data_remote->{url}->{edit_profile}        = $remote->journal_base . "/profile/";
        $data_remote->{url}->{custom_groups}       = "$LJ::SITEROOT/friends/editgroups.bml";
        $data_remote->{url}->{community_catalogue} = "$LJ::SITEROOT/community/directory.bml";

        if (my $relations_data = $class->relations_data($journal, $remote)) {
            $data_remote = {
                %$data_remote,
                %$relations_data
            };
        }

        if ($data_journal->{is_own}) {
            if ($data_journal->{view_friends}) {
                my %res;
                my %group;
                my @filters = (
                    all             => LJ::Lang::ml('web.controlstrip.select.friends.all'),
                    showpeople      => LJ::Lang::ml('web.controlstrip.select.friends.journals'),
                    showcommunities => LJ::Lang::ml('web.controlstrip.select.friends.communities'),
                    showsyndicated  => LJ::Lang::ml('web.controlstrip.select.friends.feeds'),
                );

                # FIXME: make this use LJ::Protocol::do_request
                LJ::do_request(
                    {
                        'mode' => 'getfriendgroups',
                        'ver'  => $LJ::PROTOCOL_VER,
                        'user' => $remote->{'user'},
                    },
                    \%res,
                    {
                        'noauth' => 1,
                        'userid' => $remote->{'userid'}
                    }
                );

                foreach my $k (keys %res) {
                    if ($k =~ /^frgrp_(\d+)_name/) {
                        $group{$1}->{'name'} = $res{$k};
                    } elsif ($k =~ /^frgrp_(\d+)_sortorder/) {
                        $group{$1}->{'sortorder'} = $res{$k};
                    }
                }

                my $selected_group = undef;

                if (LJ::Request->uri eq "/friends" && LJ::Request->args ne "") {
                    my %GET = LJ::Request->args;

                    if ($GET{show}) {
                        $data_journal->{view_friends_show} = uc(substr($GET{show}, 0, 1));
                    }
                } elsif (LJ::Request->uri =~ /^\/friends\/([^\/]+)/i) {
                    $selected_group = LJ::durl($1);
                    $data_journal->{view_friends_group} = $selected_group;
                }

                foreach my $g (sort { $group{$a}->{'sortorder'} <=> $group{$b}->{'sortorder'} } keys %group) {
                    push @filters, "filter:" . lc($group{$g}->{'name'}), $group{$g}->{'name'};

                    my $item = {
                        name  => lc($group{$g}->{name}),
                        value => $group{$g}->{name},
                    };

                    if ($item->{name} eq lc($selected_group)) {
                        $item->{selected} = 1;
                        $data_remote->{has_selected_groups} = 1;
                    }

                    push @{$data_remote->{friend_groups}}, $item;
                }
            }
        } elsif ($data_journal->{is_community}) {
            my $pending_members = LJ::get_pending_members($journal->id()) || [];

            $data_remote->{can_post}         = LJ::check_rel($journal, $remote, 'P');
            $data_remote->{can_manage}       = $remote->can_manage($journal);
            $data_journal->{pending_members} = scalar(@$pending_members);
        }
    } else {
        $data_remote->{is_logged_in} = 0;

        $data_journal->{login_form}->{use_ssl} = $LJ::USE_SSL_LOGIN;

        if ($LJ::USE_SSL_LOGIN) {
            $data_journal->{login_form}->{root} = $LJ::SSLROOT;
        } else {
            $data_journal->{login_form}->{root} = $LJ::SITEROOT;
            $data_journal->{login_form}->{challenge} = LJ::challenge_generate(300);
        }
    }

    $data_control_strip->{logo} = LJ::run_hook('control_strip_logo', $remote, $journal);

    if (LJ::Widget::SiteMessages->should_render) {
        $data_control_strip->{site_messages} = LJ::Widget::SiteMessages->render;
    } else {
        $data_control_strip->{site_messages} = '';
    }

    if ( $data_journal->{'view_friends'} ) {
        $data_control_strip->{'switch_friendsfeed'} =
            LJ::Widget::FriendsFeedBeta->render( 'placement' => 'legacy' );
    }

    if (LJ::is_enabled('journalpromo')) {
        $data_control_strip->{promo_strip} = LJ::Widget::JournalPromoStrip->should_render(remote => $remote, journal => $journal)
                                            ? LJ::Widget::JournalPromoStrip->render(remote => $remote, journal => $journal)
                                            : '';
    }

    {
        my $extra_cells;
        LJ::run_hooks('add_extra_cells_in_controlstrip', \$extra_cells);

        $data_control_strip->{extra_cells} = $extra_cells || '';
    }

    $data_control_strip->{mode} = 'default';

    if ($data_remote->{is_friend}) {
        $data_control_strip->{mode} = 'friend';
    } elsif ($data_remote->{is_subscribedon}) {
        $data_control_strip->{mode} = 'subscr';
    }

    my $data = {
        lj            => {
            siteroot  => $LJ::SITEROOT,
            sslroot   => $LJ::SSLROOT,
            imgprefix => $LJ::IMGPREFIX,
        },
        widget        => {
            calendar => LJ::Widget::Calendar->render(),
        },
        remote        => $data_remote,
        journal       => $data_journal,
        control_strip => $data_control_strip,
    };

    $data->{remote}->{status} = get_status($journal, {
        %{$data->{remote}},
        journal => $data->{journal},
        journal_display => $data->{journal}->{display},
    });

    my $tmpl = LJ::HTML::Template->new(
        {
            use_expr => 1
        },
        filename => "$ENV{LJHOME}/templates/ControlStrip/main.tmpl",
        die_on_bad_params => 1,
        strict => 0,
    ) or die "Can't open template: $!";

    my $mobile_link = '';

    if (!$LJ::DISABLED{'view_mobile_link_always'} || Apache::WURFL->is_mobile()) {
        my $uri = LJ::Request->uri;
        my $hostname = LJ::Request->hostname;
        my $args = LJ::Request->args;
        my $args_wq = $args ? "?$args" : "";
        my $is_ssl = $LJ::IS_SSL = LJ::run_hook("ssl_check");
        my $proto = $is_ssl ? "https://" : "http://";
        my $url = LJ::eurl ($proto.$hostname.$uri.$args_wq);
        $mobile_link = LJ::Lang::ml('link.mobile', { href => "href='http://m.$LJ::DOMAIN/redirect?from=$url'" });
    }

    if (my $calendar_data = $class->calendar_data($journal, $remote)) {
        $tmpl->param(
            LAST_DATE  => $calendar_data->{lastDate},
            EARLY_DATE => $calendar_data->{earlyDate},
        );
    }

    $tmpl->param(
        flatten($data),
        link_mobile => $mobile_link
    );

    return $tmpl->output;
}

sub need_res {
    my ($class, %args) = @_;
    my $user = $args{user};

    LJ::need_res(qw{
        js/controlstrip.js
        stc/widgets/filter-settings.css
        stc/popup/popupus.css
        stc/popup/popupus-blue.css
        stc/msgsystem.css
    });

    LJ::need_string(qw{
        web.controlstrip.view.calendar
        filterset.title.subscribed.journal
        filterset.title.addfriend.journal
        filterset.subtitle.addfriend.journal
        filterset.title.join
        filterset.subtitle.join
        filterset.submit.subscribe
        filterset.subtitle.filters
        filterset.title.subscribed.community
        filterset.link.addnewfilter
        filterset.button.save
    });

    my $remote  = LJ::get_remote();
    my $journal = LJ::load_user($user);

    return unless $journal;

    my $calendar  = $class->calendar_data($journal, $remote) || {};
    my $relations = $class->relations_data($journal, $remote) || {};

    LJ::need_var({
        remote => $relations,
        controlstrip => {
            status   => get_status($journal, {%$relations}),
            calendar => $calendar,
        }
    });
}

# This metheod use in 'cgi-bin/LJ/API/ChangeRelation.pm' too.
sub get_status {
    my ($journal, $args) = @_;
    my $remote = LJ::get_remote();
    my $journal_display = $args->{journal_display};

    $journal_display ||= LJ::ljuser($journal);

    unless ($remote) {
        return LJ::Lang::ml('web.controlstrip.status.other', {user => $journal_display});
    }

    ### [ Try define options if not defined
        unless (exists $args->{is_friend}) {
            $args->{is_friend} = $remote->is_friend($journal);
        }

        unless (exists $args->{is_friendof}) {
            $args->{is_friendof} = $remote->is_friendof($journal);
        }

        unless (exists $args->{is_subscriber}) {
            $args->{is_subscriber} = $journal->is_subscribedon($remote);
        }

        unless (exists $args->{is_subscribedon}) {
            $args->{is_subscribedon} = $remote->is_subscribedon($journal);
        }

        $args->{journal} ||= {};

        unless (exists $args->{journal}->{view_friends}) {
            if (LJ::Request->notes('view') eq 'friends') {
                $args->{journal}->{view_friends} = 1;
            } else {
                $args->{journal}->{view_friends} = 0;
            }
        }

        unless (exists $args->{journal}->{view_friendsfriends}) {
            if (LJ::Request->notes('view') eq 'friendsfriends') {
                $args->{journal}->{view_friendsfriends} = 1;
            } else {
                $args->{journal}->{view_friendsfriends} = 0;
            }
        }
    ### ]

    if (LJ::u_equals($remote, $journal)) {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return LJ::Lang::ml('web.controlstrip.status.yourjournal');
        }

        if ($args->{journal}->{view_friends}) {
            return LJ::Lang::ml('web.controlstrip.status.yourfriendspage');
        } elsif ($args->{journal}->{view_friendsfriends}) {
            return LJ::Lang::ml('web.controlstrip.status.yourfriendsfriendspage');
        } else {
            return LJ::Lang::ml('web.controlstrip.status.yourjournal');
        }
    } elsif ($journal->is_personal) {
        # Is mutual friend
        if ($args->{is_friend} && $args->{is_friendof}) {
            return LJ::Lang::ml('web.controlstrip.status.mutualfriend', {user => $journal_display});
        } elsif ($args->{is_friend}) {
            return LJ::Lang::ml('web.controlstrip.status.friend', {user => $journal_display});
        } elsif ($args->{is_subscribedon}) {
            return LJ::Lang::ml('web.controlstrip.status.subscribedon', {user => $journal_display});
        } elsif ($args->{is_friendof}) {
            return LJ::Lang::ml('web.controlstrip.status.friendof', {user => $journal_display});
        } elsif ($args->{is_subscriber}) {
            return LJ::Lang::ml('web.controlstrip.status.subscriber', {user => $journal_display});
        }

        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return LJ::Lang::ml('web.controlstrip.status.personal', {user => $journal_display});
        }

        if ($args->{journal}->{view_friends}) {
            return LJ::Lang::ml('web.controlstrip.status.personalfriendspage', {user => $journal_display});
        } elsif ($args->{journal}->{view_friendsfriends}) {
            return LJ::Lang::ml('web.controlstrip.status.personalfriendsfriendspage', {user => $journal_display});
        } else {
            return LJ::Lang::ml('web.controlstrip.status.personal', {user => $journal_display});
        }
    } elsif ($journal->is_community) {
        unless (exists $args->{can_manage}) {
            $args->{can_manage} ||= $remote->can_manage($journal);
        }

        if ($args->{can_manage}) {
            return LJ::Lang::ml('web.controlstrip.status.maintainer', {user => $journal_display});
        } elsif ($args->{is_friend} && $args->{is_friendof}) {
            return LJ::Lang::ml('web.controlstrip.status.memberwatcher', {user => $journal_display});
        } elsif ($args->{is_friend}) {
            return LJ::Lang::ml('web.controlstrip.status.watcher', {user => $journal_display});
        } elsif ($args->{is_subscribedon}) {
            return LJ::Lang::ml('web.controlstrip.status.watcher', {user => $journal_display});
        } elsif ($args->{is_friendof}) {
            return LJ::Lang::ml('web.controlstrip.status.member', {user => $journal_display});
        }

        return LJ::Lang::ml('web.controlstrip.status.community', {user => $journal_display});
    } elsif ($journal->is_syndicated) {
        return LJ::Lang::ml('web.controlstrip.status.syn', {user => $journal_display});
    } elsif ($journal->is_news) {
        return LJ::Lang::ml('web.controlstrip.status.news', {user => $journal_display, sitename => $LJ::SITENAMESHORT});
    } else {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            if ($args->{is_friend} && $args->{is_friendof}) {
                return LJ::Lang::ml('web.controlstrip.status.mutualfriend', {user => $journal_display});
            } elsif ($args->{is_friend}) {
                return LJ::Lang::ml('web.controlstrip.status.friend', {user => $journal_display});
            } elsif ($args->{is_subscribedon}) {
                return LJ::Lang::ml('web.controlstrip.status.subscribedon', {user => $journal_display});
            } elsif ($args->{is_friendof}) {
                return LJ::Lang::ml('web.controlstrip.status.friendof', {user => $journal_display});
            } elsif ($args->{is_subscriber}) {
                return LJ::Lang::ml('web.controlstrip.status.subscriber', {user => $journal_display});
            }
        }

        return LJ::Lang::ml('web.controlstrip.status.other', {user => $journal_display});
    }
}

sub calendar_data {
    my ($class, $journal, $remote) = @_;

    return unless $journal;

    my $daycounts = LJ::get_daycounts($journal, $remote);

    return unless @$daycounts;

    my @last_date  = @{$daycounts->[-1]};
    my @early_date = @{$daycounts->[0]};

    pop @last_date;
    pop @early_date;

    if ($last_date[1] != 0) {
        $last_date[1] -= 1;
    }

    if ($early_date[1] != 0) {
        $early_date[1] -= 1;
    }

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime();

    if ( $last_date[0] < ($year + 1900) ||
         $last_date[1] < $mon     ||
         $last_date[2] < $mday
    ) {
        @last_date = ($year + 1900, $mon, $mday);
    }

    return {
        lastDate => join(',', @last_date),
        earlyDate => join(',', @early_date),
    };
}

sub relations_data {
    my ($class, $journal, $remote) = @_;
    my $data = {};

    return unless $remote;
    return unless $journal;

    my $friend   = $remote->is_friend($journal);
    my $friendof = $journal->is_friend($remote);

    $data->{is_member}       = $friendof;
    $data->{is_friend}       = $friend;
    $data->{is_friendof}     = $friendof;
    $data->{is_subscriber}   = 0;
    $data->{is_subscribedon} = 0;

    # Subscribe/Unscubscribe to/from user
    if (LJ::is_enabled('new_friends_and_subscriptions')) {
        $data->{is_subscriber}   = $journal->is_subscribedon($remote);
        $data->{is_subscribedon} = $remote->is_subscribedon($journal);
    }

    return $data;
}

# Utils

sub flatten_hashref {
    my ($hashref, $prefix, $out) = @_;

    while (my ($key, $value) = each %$hashref) {
        if (ref($value) eq 'HASH') {
            flatten_hashref($value, $prefix . $key . '_', $out);
        } else {
            $out->{$prefix . $key} = $value;
        }
    }
}

sub flatten {
    my ($hashref) = @_;
    my $out = {};

    flatten_hashref($hashref, '', $out);

    return %$out;
}

1;

