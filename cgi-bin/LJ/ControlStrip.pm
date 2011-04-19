package LJ::ControlStrip;

use strict;

sub render
{
    my ($class, $user) = @_;

    my $show_strip = 1;
    if (LJ::are_hooks("show_control_strip")) {
        $show_strip = LJ::run_hook("show_control_strip", { user => $user });
    }
    return "" unless $show_strip;

    my $remote = LJ::get_remote();
    my $journal = LJ::load_user($user);

    my $args = scalar LJ::Request->args;
    my $querysep = $args ? "?" : "";
    my $uri = "http://" . LJ::Request->header_in("Host") . LJ::Request->uri . $querysep . $args;
    $uri = LJ::eurl($uri);

    my $data_remote = {};
    my $data_journal = {
        url => {
            base => $journal->journal_base,
        },
        page => "http://" . LJ::Request->header_in("Host") . LJ::Request->uri,
    };
    my $data_control_strip = {};

    my $data_lj = {
        siteroot  => $LJ::SITEROOT,
        sslroot   => $LJ::SSLROOT,
        imgprefix => $LJ::IMGPREFIX,

        url => {
            send_vgift      => "$LJ::SITEROOT/shop/vgift.bml",
        },
       
        link => {
            login           => html_link("$LJ::SITEROOT/?returnto=$uri", BML::ml('web.controlstrip.links.login')),
            home            => html_link("$LJ::SITEROOT/", BML::ml('web.controlstrip.links.home')),
            create_account  => LJ::run_hook("override_create_link_on_navstrip", $journal) ||
                               html_link("$LJ::SITEROOT/create.bml", BML::ml('web.controlstrip.links.create', {'sitename' => $LJ::SITENAMESHORT})),
            syndicated_list => html_link("$LJ::SITEROOT/syn/list.bml", BML::ml('web.controlstrip.links.popfeeds')),
            learn_more      => LJ::run_hook('control_strip_learnmore_link') ||
                               html_link("$LJ::SITEROOT/", BML::ml('web.controlstrip.links.learnmore')),
            explore         => html_link("$LJ::SITEROOT/explore/", BML::ml('web.controlstrip.links.explore', { sitenameabbrev => $LJ::SITENAMEABBREV })),
            support         => html_link("$LJ::SITEROOT/support/", BML::ml('web.controlstrip.links.support')),
        },
        # login_openid   = "$LJ::SITEROOT/identity/login.bml?type=openid";
        # login_facebook = "$LJ::SITEROOT/identity/login.bml?type=facebook";
        # login_twitter  = "$LJ::SITEROOT/identity/login.bml?type=twitter";
    };

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
    $data_journal->{view_friends} = $data_journal->{view} eq 'friends';
    $data_journal->{view_friendsfriends} = $data_journal->{view} eq 'friendsfriends';
    $data_journal->{view_tag} = $data_journal->{view} eq 'tag';
    $data_journal->{view_entry} = $data_journal->{view} eq 'entry';
    $data_journal->{display} = LJ::ljuser($journal);

    if ($remote)
    {
        $data_remote->{is_logged_in} = 1;
        $data_remote->{user}         = $remote->{user};
        $data_remote->{display}      = LJ::ljuser($remote);
        $data_remote->{sessid}       = ($remote->session ? $remote->{_session}->{sessid} : undef);
        $data_remote->{is_paid}      = $remote->in_class('paid') || $remote->in_class('sponsored');

        if ($remote->{defaultpicid}) {
            $data_remote->{userpic} = {
                src   => "$LJ::USERPIC_ROOT/$remote->{defaultpicid}/$remote->{userid}",
                alt   => BML::ml('web.controlstrip.userpic.alt'),
                title => BML::ml('web.controlstrip.userpic.title'),
            };
        } else {
            my $tinted_nouserpic_img = "";

            if ($journal->prop('stylesys') == 2) {
                my $ctx = $LJ::S2::CURR_CTX;
                my $custom_nav_strip = S2::get_property_value($ctx, "custom_control_strip_colors");

                if ($custom_nav_strip ne "off") {
                    my $linkcolor = S2::get_property_value($ctx, "control_strip_linkcolor");

                    if ($linkcolor ne "") {
                        $tinted_nouserpic_img = S2::Builtin::LJ::palimg_modify($ctx, "controlstrip/nouserpic.gif", [S2::Builtin::LJ::PalItem($ctx, 0, $linkcolor)]);
                    }
                }
            }

            $data_remote->{userpic} = {
                src   => $tinted_nouserpic_img || "$LJ::IMGPREFIX/controlstrip/nouserpic.gif",
                alt   => BML::ml('web.controlstrip.nouserpic.alt'),
                title => BML::ml('web.controlstrip.nouserpic.title'),
            };
        }
        
        my $inbox = $remote->notification_inbox();
        $data_remote->{inbox} = {
            unread_count => $inbox->unread_count,
        };

        $data_remote->{wallet} = {
            balance => int(LJ::Pay::Wallet->get_user_balance($remote)),
        };

        $data_remote->{style_always_mine} = LJ::Widget::StyleAlwaysMine->render( u => $remote )
            if ($remote->{userid} != $journal->{userid});

        $data_remote->{url}->{base} = $remote->journal_base;
        $data_remote->{url}->{inbox} = "$LJ::SITEROOT/inbox/";
        $data_remote->{url}->{tokens} = "$LJ::SITEROOT/shop/tokens.bml";
        $data_remote->{url}->{edit_pics} = "$LJ::SITEROOT/editpics.bml";

        $data_remote->{url}->{custom_groups}       = "$LJ::SITEROOT/friends/editgroups.bml";
        $data_remote->{url}->{manage_tags}         = "$LJ::SITEROOT/manage/tags.bml";
        $data_remote->{url}->{send_message}        = "$LJ::SITEROOT/inbox/compose.bml";
        $data_remote->{url}->{edit_profile}        = $remote->journal_base . "/profile/";
        $data_remote->{url}->{community_catalogue} = "$LJ::SITEROOT/community/directory.bml";

        $data_remote->{link}->{recent_comments} = html_link("$LJ::SITEROOT/tools/recent_comments.bml", BML::ml('web.controlstrip.links.recentcomments'));
        $data_remote->{link}->{manage_friends}  = html_link("$LJ::SITEROOT/friends/", BML::ml('web.controlstrip.links.managefriends'));
        $data_remote->{link}->{manage_entries}  = html_link("$LJ::SITEROOT/editjournal.bml", BML::ml('web.controlstrip.links.manageentries'));
        $data_remote->{link}->{invite_friends}  = html_link("$LJ::SITEROOT/friends/invite.bml", BML::ml('web.controlstrip.links.invitefriends'));
        $data_remote->{link}->{add_friend}      = html_link("$LJ::SITEROOT/friends/add.bml?user=$journal->{user}", BML::ml('web.controlstrip.links.addfriend'));
        $data_remote->{link}->{view_friends}    = html_link($remote->journal_base . "/friends/", BML::ml('web.controlstrip.links.viewfriendspage2'));

        my $friend = LJ::is_friend($remote, $journal);
        my $friendof = LJ::is_friend($journal, $remote);

        $data_remote->{is_mutualfriend} = ($friend && $friendof);
        $data_remote->{is_friend} = $friend;
        $data_remote->{is_friendof} = $friendof;

        if ($data_journal->{is_own})
        {
            if ($data_journal->{view_friends})
            {
                my @filters = (
                    all             => BML::ml('web.controlstrip.select.friends.all'),
                    showpeople      => BML::ml('web.controlstrip.select.friends.journals'),
                    showcommunities => BML::ml('web.controlstrip.select.friends.communities'),
                    showsyndicated  => BML::ml('web.controlstrip.select.friends.feeds'),
                );

                my %res;
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

                my %group;
                foreach my $k (keys %res) {
                    if ($k =~ /^frgrp_(\d+)_name/) {
                        $group{$1}->{'name'} = $res{$k};
                    }
                    elsif ($k =~ /^frgrp_(\d+)_sortorder/) {
                        $group{$1}->{'sortorder'} = $res{$k};
                    }
                }

                foreach my $g (sort { $group{$a}->{'sortorder'} <=> $group{$b}->{'sortorder'} } keys %group) {
                    push @filters, "filter:" . lc($group{$g}->{'name'}), $group{$g}->{'name'};
                    push @{$data_remote->{friend_groups}}, {
                        name  => lc($group{$g}->{name}),
                        value => $group{$g}->{name},
                    };
                }

                my $selected = "all";
                if (LJ::Request->uri eq "/friends" && LJ::Request->args ne "") {
                    $selected = "showpeople"      if LJ::Request->args eq "show=P&filter=0";
                    $selected = "showcommunities" if LJ::Request->args eq "show=C&filter=0";
                    $selected = "showsyndicated"  if LJ::Request->args eq "show=Y&filter=0";
                } elsif (LJ::Request->uri =~ /^\/friends\/?(.+)?/i) {
                    my $filter = $1 || "default view";
                    $selected = "filter:" . LJ::durl(lc($filter));
                }

                $data_remote->{friends_group_select} = LJ::html_select({'name' => "view", 'selected' => $selected }, @filters);
            }
        }
        elsif ($data_journal->{is_personal})
        {
        }
        elsif ($data_journal->{is_community})
        {
            $data_remote->{can_post}    = LJ::check_rel($journal, $remote, 'P');
            $data_remote->{can_manage}  = LJ::can_manage_other($remote, $journal);
            $data_remote->{is_watcher}  = $data_remote->{is_friend};
            $data_remote->{is_memberof} = $data_remote->{is_friendof};

            $data_remote->{link}->{join_community} = html_link(
                "$LJ::SITEROOT/community/join.bml?comm=$journal->{user}",
                BML::ml('web.controlstrip.links.joincomm')
            );
            $data_remote->{link}->{leave_community} = html_link(
                "$LJ::SITEROOT/community/leave.bml?comm=$journal->{user}",
                BML::ml('web.controlstrip.links.leavecomm')
            );
            $data_remote->{link}->{watch_community} = html_link(
                "$LJ::SITEROOT/friends/add.bml?user=$journal->{user}",
                BML::ml('web.controlstrip.links.watchcomm')
            );
            $data_remote->{link}->{unwatch_community} = html_link(
                "$LJ::SITEROOT/community/leave.bml?comm=$journal->{user}",
                BML::ml('web.controlstrip.links.removecomm')
            );
            $data_remote->{link}->{post_to_community} = html_link(
                "$LJ::SITEROOT/update.bml?usejournal=$journal->{user}",
                BML::ml('web.controlstrip.links.postcomm')
            );
            $data_remote->{link}->{edit_community_profile} = html_link(
                "$LJ::SITEROOT/manage/profile/?authas=$journal->{user}",
                BML::ml('web.controlstrip.links.editcommprofile')
            );
            $data_remote->{link}->{edit_community_invites} = html_link(
                "$LJ::SITEROOT/community/sentinvites.bml?authas=$journal->{user}",
                BML::ml('web.controlstrip.links.managecomminvites')
            );
            $data_remote->{link}->{edit_community_members} = html_link(
                "$LJ::SITEROOT/community/members.bml?authas=$journal->{user}",
                BML::ml('web.controlstrip.links.editcommmembers')
            );
        }

        if ($remote->is_person) {
            $data_remote->{link}->{post_journal} = html_link(
                "$LJ::SITEROOT/update.bml",
                BML::ml('web.controlstrip.links.post2')
            );
        }

        if ($data_journal->{is_syndicated} || $data_journal->{is_news})
        {
            $data_remote->{link}->{add_feed} = html_link(
                "$LJ::SITEROOT/friends/add.bml?user=$journal->{user}",
                BML::ml('web.controlstrip.links.addfeed')
            );
            $data_remote->{link}->{remove_feed} = html_link(
                "$LJ::SITEROOT/friends/add.bml?user=$journal->{user}",
                BML::ml('web.controlstrip.links.removefeed')
            );
        }
    }
    else
    {
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

    $data_control_strip->{site_messages} = LJ::Widget::SiteMessages->should_render
                                           ? LJ::Widget::SiteMessages->render
                                           : '';

    {
        my $extra_cells;
        LJ::run_hooks('add_extra_cells_in_controlstrip', \$extra_cells);
        
        $data_control_strip->{extra_cells} = $extra_cells || '';
    }

    my $data = {
        lj            => $data_lj,
        remote        => $data_remote,
        journal       => $data_journal,
        control_strip => $data_control_strip,
    };

    $data->{remote}->{status} = get_status($data);

    # my $h = { flatten($data) };
    # warn join('', map { "$_ => $h->{$_}\n" } sort keys %$h);

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
        $mobile_link = LJ::Lang::ml('link.mobile', { href => "href='http://m.livejournal.com/redirect?from=$url'" });
    }

    $tmpl->param(flatten($data), link_mobile => $mobile_link );

    return $tmpl->output;    
}

sub html_link
{
    my ($url, $text) = @_;
    
    return "<a href='$url'>$text</a>";
}

sub get_status
{
    my ($data) = @_;

    my $journal_display = $data->{journal}->{display};

    if ($data->{journal}->{is_own})
    {
        # $data->{remote}->{is_logged_in} == true
        if ($data->{journal}->{view_friends}) {
            return BML::ml('web.controlstrip.status.yourfriendspage');
        } elsif ($data->{journal}->{view_friendsfriends}) {
            return BML::ml('web.controlstrip.status.yourfriendsfriendspage');
        } else {
            return BML::ml('web.controlstrip.status.yourjournal');
        }
    }
    elsif ($data->{journal}->{is_personal})
    {
        if ($data->{remote}->{is_logged_in})
        {
            if ($data->{remote}->{is_mutualfriend}) {
                return BML::ml('web.controlstrip.status.mutualfriend', {user => $journal_display});
            } elsif ($data->{remote}->{is_friend}) {
                return BML::ml('web.controlstrip.status.friend', {user => $journal_display});
            } elsif ($data->{remote}->{is_friendof}) {
                return BML::ml('web.controlstrip.status.friendof', {user => $journal_display});
            }
        }

        if ($data->{journal}->{view_friends}) {
            return BML::ml('web.controlstrip.status.personalfriendspage', {user => $journal_display});
        } elsif ($data->{journal}->{view_friendsfriends}) {
            return BML::ml('web.controlstrip.status.personalfriendsfriendspage', {user => $journal_display});
        } else {
            return BML::ml('web.controlstrip.status.personal', {user => $journal_display});
        }
    }
    elsif ($data->{journal}->{is_community})
    {
        if ($data->{remote}->{is_logged_in})
        {
            if ($data->{remote}->{can_manage})
            {
                return BML::ml('web.controlstrip.status.maintainer', {user => $journal_display});
            }
            elsif ($data->{remote}->{is_watcher} && $data->{remote}->{is_memberof})
            {
                return BML::ml('web.controlstrip.status.memberwatcher', {user => $journal_display});
            }
            elsif ($data->{remote}->{is_watcher})
            {
                return BML::ml('web.controlstrip.status.watcher', {user => $journal_display});
            }
            elsif ($data->{remote}->{is_memberof})
            {
                return BML::ml('web.controlstrip.status.member', {user => $journal_display});
            }
        }

        return BML::ml('web.controlstrip.status.community', {user => $journal_display});
    }
    elsif ($data->{journal}->{is_syndicated})
    {
        return BML::ml('web.controlstrip.status.syn', {user => $journal_display});
    }                
    elsif ($data->{journal}->{is_news})
    {
        return BML::ml('web.controlstrip.status.news', {user => $journal_display, sitename => $LJ::SITENAMESHORT});
    }
    else
    {
        return BML::ml('web.controlstrip.status.other', {user => $journal_display});
    }
}

sub flatten_hashref
{
    my ($hashref, $prefix, $out) = @_;

    while (my ($key, $value) = each %$hashref) {
        if (ref($value) eq 'HASH') {
            flatten_hashref($value, $prefix . $key . '_', $out);
        } else {
            $out->{$prefix . $key} = $value;
        }
    }
}

sub flatten
{
    my ($hashref) = @_;

    my $out = {};

    flatten_hashref($hashref, '', $out);

    return %$out;
}

1;

