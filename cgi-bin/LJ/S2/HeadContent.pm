package LJ::S2::HeadContent;
use strict;
use warnings;

use overload q("") => 'as_string';

sub new {
    my ( $class, $self ) = @_;

    return bless( $self, $class );
}

sub set_object_type {
    my ( $self, $type ) = @_;

    $self->{type} = $type;
}

sub set_options {
    my ( $self, $options ) = @_;

    for my $key (keys %$options) {
        $self->{opts}{$key} = $options->{$key};
    }
}

sub as_string {
    my $self = shift;

    my $head_content = $self->_page_head();
    my %handlers = (
        'EntryPage'   => \&_entry_page_head,
        'DayPage'     => \&_day_page_head,
        'FriendsPage' => \&_friends_page_head,
        'MonthPage'   => \&_month_page_head,
        'RecentPage'  => \&_recent_page_head,
        'ReplyPage'   => \&_reply_page_head,
        'TagsPage'    => \&_tags_page_head,
        'YearPage'    => \&_year_page_head,
    );

    my $handler = $handlers{ $self->{type} };
    if ($handler){
        $head_content .= $self->$handler;
    }

    return $head_content;
}

sub _page_head {
    my $self = shift;

    my $u = $self->{u};
    my $remote = $self->{remote};
    my $opts = $self->{opts} || {};

    my $head_content = '';
    my $base_url = $u->{'_journalbase'};

    if ( $LJ::UNICODE ) {
        my $charset = $opts->{'saycharset'} || "utf-8";

        $head_content .= qq(<meta http-equiv="Content-Type" );
        $head_content .= qq(content="text/html;);
        $head_content .= qq(charset=$charset" />\n);
    }

    if ( LJ::are_hooks('s2_head_content_extra') ) {
        LJ::run_hooks('s2_head_content_extra', \$head_content, $remote, $opts->{r});
    }

    # Automatic Discovery of RSS/Atom
    if ( $opts->{'addfeeds'} ) {
        $head_content .= qq(<link rel="alternate" type="application/rss+xml" );
        $head_content .= qq(title="RSS" href="$base_url/data/rss" />\n );

        $head_content .= qq(<link rel="alternate" type="application/atom+xml" );
        $head_content .= qq(title="Atom" href="$base_url/data/atom" />\n);

        $head_content .= qq(<link rel="service.feed" type="application/atom+xml" );
        $head_content .= qq(title="AtomAPI-enabled feed" );
        $head_content .= qq(href="$LJ::SITEROOT/interface/atomapi/$u->{'user'}/feed" />\n);

        $head_content .= qq(<link rel="service.post" type="application/atom+xml" );
        $head_content .= qq(title="Create a new post" );
        $head_content .= qq(href="$LJ::SITEROOT/interface/atomapi/$u->{'user'}/post" />\n);
    }

    # OpenID information if the caller asked us to include it here.
    if ( $opts->{'addopenid'} ) {
        $head_content .= $u->openid_tags;
    }

    # Ads and control strip
    my $ad_base_url = LJ::stat_src_to_url('/ad_base.css');
    $head_content .= qq(<link rel='stylesheet' );
    $head_content .= qq(href='$ad_base_url' type='text/css' />\n);

    # FOAF autodiscovery
    my $foafurl = $u->{external_foaf_url} ?
                      LJ::eurl($u->{external_foaf_url}) : "$base_url/data/foaf";
    $head_content .= qq(<link rel="meta" type="application/rdf+xml" );
    $head_content .= qq(title="FOAF" href="$foafurl" />\n);

    if ( $u->email_visible($remote) ) {
        my $digest = Digest::SHA1::sha1_hex('mailto:' . $u->email_raw);
        $head_content .= qq(<meta name="foaf:maker" );
        $head_content .= qq(content="foaf:mbox_sha1sum $digest" />\n);
    }

    # Include any head stc or js head content
    LJ::run_hooks( "need_res_for_journals", $u );
    my $graphicpreviews_obj = LJ::graphicpreviews_obj();
    $graphicpreviews_obj->need_res($u);
    my $extra_js = LJ::statusvis_message_js($u);

    if ( LJ::is_enabled('sharing') ) {
        LJ::Share->request_resources;
    }

    $head_content .= LJ::res_includes() . $extra_js;
    LJ::run_hooks( 'head_content', \$head_content );

    my $get = $opts->{'getargs'};
    my $need_block_robots = $opts->{entry_block_robots};
    $need_block_robots ||= $opts->{reply_block_robots};
    $need_block_robots ||= $u->should_block_robots;
    $need_block_robots ||= $get->{'skip'};

    ## never have spiders index friends pages (change too much, and some
    ## people might not want to be indexed)
    if ( $need_block_robots || $self->{type} eq 'FriendsPage' ) {
        $head_content .= LJ::robot_meta_tags();
    }
    return $head_content;
}

sub _entry_page_head {
    my ($self) = @_;

    my $u = $self->{u};
    my $remote = $self->{remote};
    my $opts = $self->{opts} || {};

    my $head_content = $opts->{entry_cmtinfo} || '';

    if ( $opts->{entry_metadata} ) {
        my %meta = %{ $opts->{entry_metadata} };
        $head_content .= qq(<meta property="og:title" name="title" );
        $head_content .= qq(content=");
        $head_content .= LJ::ehtml( $meta{'title'} );
        $head_content .= qq(" />\n);

        $head_content .= qq(<meta property="og:description" );
        $head_content .= qq(name="description" content=");
        $head_content .= LJ::ehtml( $meta{'description'} );
        $head_content .= qq(" />\n);

        $head_content .= qq(<meta property="og:image" );
        $head_content .= qq(content=");
        $head_content .= LJ::ehtml( $meta{'image'} );
        $head_content .= qq( " />\n);
    }

    if ( $opts->{dont_show_nav_strip} ) {
        $head_content .= _get_html_dont_show_navstrip();
    }
    return $head_content;
}

sub _get_html_dont_show_navstrip {

    return qq{<style type="text/css">
                html body {
                    padding-top: 0 !important;
                }
                #lj_controlstrip,
                .w-cs,
                .b-message-mobile,
                .appwidget-sitemessages {
                    display: none !important;
                }
            </style>};
}

sub _day_page_head {
    my ($self) = @_;

    my $head_content = '';

    return $head_content;
}

sub _friends_page_head {
    my ($self) = @_;

    my $u = $self->{u};
    my $opts = $self->{opts} || {};

    my $head_content = '';

    # Add a friends-specific XRDS reference
    $head_content .= qq(<meta http-equiv="X-XRDS-Location" content=");
    $head_content .= LJ::ehtml( $u->journal_base );
    $head_content .= qq(/data/yadis/friends" />\n);

    my $get = $opts->{'getargs'};
    my $mode = $get->{'mode'} || '';

    if ( $mode eq "framed" ) {
        $head_content .= "<base target='_top' />";
    }

    return $head_content;
}

sub _month_page_head {
    my ($self) = @_;

    my $head_content = '';

    return $head_content;
}

sub _recent_page_head {
    my ($self) = @_;

    my $u = $self->{u};
    my $remote = $self->{remote};
    my $opts = $self->{opts} || {};

    my $head_content = '';

    # Link to the friends page as a "group",
    # for use with OpenID "Group Membership Protocol"

    my $is_comm = $u->is_community;
    my $friendstitle = $LJ::SITENAMESHORT." ".($is_comm ? "members" : "friends");
    my $rel = "group ".($is_comm ? "members" : "friends made");
    my $friendsurl = $u->journal_base."/friends"; # We want the canonical form here, not the vhost form
    $head_content .= qq(<link rel="$rel" );
    $head_content .= qq(title=");
    $head_content .= LJ::ehtml($friendstitle);
    $head_content .= qq(" );
    $head_content .= qq(href=") .LJ::ehtml($friendsurl). qq(" />\n);

    if ( my $icbm = $u->prop("icbm") ) {
        $head_content .= qq(<meta name="ICBM" content="$icbm" />\n);
    }
    return $head_content;
}

sub _reply_page_head {
    my ($self) = @_;

    my $remote = $self->{remote};
    my $opts = $self->{opts} || {};

    my $head_content = $LJ::COMMON_CODE{'chalresp_js'};

    return $head_content;
}

sub _tags_page_head {
    my ($self) = @_;

    my $u = $self->{u};
    my $head_content =  $u->openid_tags;
    
    return $head_content;
}

sub _year_page_head {
    my ($self) = @_;

    my $head_content = '';

    return $head_content;
}

1;
