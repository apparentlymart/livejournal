package LJ::SiteScheme;
use strict;
use warnings;

use LJ::Lang qw( ml );
use LJ::Widget::SGMessages;

my %CODE_TO_CLASS_MAP;

### PARENT CLASS FUNCTIONS ###
sub render_page {
    my ( $class, $args ) = @_;

    my $handler;

    if ( $class eq __PACKAGE__ ) {
        $handler = $class->find_handler;
    } else {
        $handler = $class;
    }

    $handler->need_res;

    my $filename = "$ENV{'LJHOME'}/templates/SiteScheme/"
        . $handler->template_filename . '.tmpl';

    # cast all keys to lowercase because uppercase everywhere is creepy
    my $args_normalized = {};
    foreach my $k ( keys %$args ) {
        $args_normalized->{ lc $k } = $args->{$k};
    }

    my $params = $handler->template_params($args_normalized);

    if ( LJ::is_web_context() ) {
        $params->{'lj_res_in_bottom'}      = LJ::Request->get_param('res_bottom')? 1 : 0;
        $params->{'lj_res_includes'}       = LJ::res_includes();
        $params->{'lj_res_includes_basic'} = LJ::res_includes({ only_needed => 1 });
        $params->{'lj_res_templates'}      = LJ::res_includes({ only_needed => 1, only_tmpl   => 1 });
        $params->{'lj_res_includes_css'}   = LJ::res_includes({ only_css    => 1 });
        $params->{'lj_res_includes_js'}    = LJ::res_includes({ only_js     => 1 });
    }

    my $template = LJ::HTML::Template->new( { 'use_expr' => 1 },
        'filename' => $filename, );

    $template->param(%$params);

    return $template->output;
}

sub find_handler {
    my ($class) = @_;

    my @candidate_codes = (
        LJ::Request->notes('bml_use_scheme'),
        LJ::run_hook('force_scheme'),
        LJ::Request->get_param('usescheme'),
        LJ::Request->cookie('BMLschemepref'),
        LJ::run_hook('default_scheme'),
        'lynx',
    );

    foreach my $code (@candidate_codes) {
        next unless defined $code;

        my $handler = $class->handler_from_code($code);
        next unless defined $handler;

        return $handler;
    }

    # this shouldn never happen because we always have lynx
    die 'no scheme found';
}

sub handler_from_code {
    my ( $class, $code ) = @_;
    return $CODE_TO_CLASS_MAP{$code};
}

### PARENT CLASS UTILITY FUNCTIONS ###

sub template_param_breadcrumbs {
    my ($class) = @_;

    my @crumbs = LJ::get_crumb_path();
    return [] unless @crumbs;

    my @ret;
    my $count = 0;
    foreach my $crumb (@crumbs) {
        my ( $name, $link, $parent, $type ) = @$crumb;

        # put crumbs together
        next unless $type;    # no blank crumbs
        if ( $type eq 'dynamic' ) {
            unshift @ret, { 'is_dynamic' => 1, 'name' => $name };
        } else {
            unshift @ret, { 'name' => ml("crumb.$type"), 'link' => $link };
        }
    }

    return \@ret;
}

sub show_mobile_link {
    return 1 if LJ::is_enabled('view_mobile_link_always');
    return 1 if Apache::WURFL->is_mobile;
    return 0;
}

sub common_template_params {
    my ( $class, $args ) = @_;

    my $remote = LJ::get_remote();
    my $uri    = LJ::Request->uri;

    my $remote_username = '';
    if ($remote) {
        $remote_username = $remote->username;
    }

    my $favicon = '';
    if ( my $journal = LJ::get_active_journal() ) {
        if ( $journal->is_personal ) {
            ($favicon) = $journal->userhead;
            $favicon   = $LJ::IMGPREFIX . "/" . $favicon
                unless $favicon =~ m{^http://};
        }
    }

    my $additional_head_content = '';
    LJ::run_hooks( 'head_content', \$additional_head_content );

    my $error_list = '';
    if ( my @errors = @BMLCodeBlock::errors ) {
        $error_list = LJ::error_list(@errors);
    }

    my $warning_list = '';
    if ( my @warnings = @BMLCodeBlock::warnings ) {
        $warning_list = LJ::warning_list(@warnings);
    }

    my $chalresp_js = '';
    if (   !LJ::get_remote()
        && !$LJ::IS_SSL
        && !$LJ::USE_SSL_LOGIN
        && !$LJ::REQ_HEAD_HAS{'chalresp_js'}++ )
    {
        $chalresp_js = $LJ::COMMON_CODE{'chalresp_js'};
    }

    my $after_bml_title = LJ::run_hook('insert_after_bml_title') || '';

    my $show_mobile_link = $class->show_mobile_link;
    my $ml_mobile_link   = '';
    if ($show_mobile_link) {
        my $uri = '';

        $uri .= $LJ::IS_SSL ? 'http://' : 'https://';
        $uri .= LJ::Request->hostname;
        $uri .= LJ::Request->uri;

        if ( my $args = LJ::Request->args ) {
            $uri .= '?' . $args;
        }

        my $mobile_uri =
            "http://m.$LJ::DOMAIN/redirect?from=" . LJ::eurl($uri);

        $ml_mobile_link =
            ml( 'link.mobile', { 'href' => "href='$mobile_uri'" }, );
    }

    my $initial_body_html = LJ::initial_body_html();

    my $site_messages_html = '';
    if ( LJ::Widget::SiteMessages->should_render ) {
        $site_messages_html = LJ::Widget::SiteMessages->render;
    }

    my @navbar = LJ::Nav->navbar($remote);

    # apparently our HTML::Template doesn't support __index__,
    # let's provide one ourselves; lanzelot requires this for
    # drop-downs to work
    $navbar[$_]->{'idx'} = $_ foreach ( 0 .. $#navbar );

    my $expresslane_html_comment =
        LJ::LJcom::expresslane_html_comment($remote);

    my $remote_logged_in       = $remote ? 1 : 0;
    my $remote_personal        = 0;
    my $remote_identity        = 0;
    my $remote_paid            = 0;
    my $remote_sees_ads        = 0;
    my $logout_link            = '';
    my $remote_sessid          = 0;
    my $remote_userpic_url     = '';
    my $remote_ljuser_display  = '';
    my $remote_display_name    = '';
    my $remote_profile_url     = '';
    my $remote_recent_url      = '';
    my $remote_friends_url     = '';
    my $remote_can_use_esn     = 0;
    my $remote_unread_count    = 0;
    my $remote_wallet_link     = 0;
    my $remote_ljphoto_url     = '';
    my $remote_can_use_ljphoto = 0;

    if ($remote) {
        my $username = $remote->username;

        if ( my $session = $remote->session ) {
            $remote_sessid = $session->id;
            $logout_link =
                "$LJ::SITEROOT/logout.bml?user=$username&sessid=$remote_sessid";
        } else {
            $logout_link = "$LJ::SITEROOT/logout.bml?user=$username";
        }

        if ( my $upi = $remote->userpic ) {
            $remote_userpic_url = $upi->url;
        }

        $remote_personal        = $remote->is_personal;
        $remote_identity        = $remote->is_identity;
        $remote_paid            = $remote->get_cap('paid');
        $remote_sees_ads        = $remote->get_cap('ads');
        $remote_ljuser_display  = $remote->ljuser_display;
        $remote_display_name    = $remote->display_name;
        $remote_profile_url     = $remote->profile_url;
        $remote_recent_url      = $remote->journal_base . '/';
        $remote_friends_url     = $remote->journal_base . '/friends/';
        $remote_can_use_esn     = $remote->can_use_esn;
        $remote_unread_count    = $remote->notification_inbox->unread_count;
        $remote_wallet_link     = LJ::Pay::Wallet->get_wallet_link($remote);
        $remote_ljphoto_url     = $remote->journal_base . '/pics/';
        $remote_can_use_ljphoto = $remote->can_use_ljphoto ? 1 : 0;
    }

    my $need_loginform = 0;

    my $loginform_returnto          = '';
    my $loginform_root              = '';
    my $loginform_challenge         = '';
    my $loginform_need_extra_fields = 0;
    my $loginform_onclick           = '';

    unless ( $remote || $uri eq '/login.bml' || $uri eq '/logout.bml' ) {
        $need_loginform = 1;
    }

    # lanzelot doesn't respect need_loginform; i. e. it renders it on
    # login.bml and logout.bml as well
    unless ($remote) {
        $loginform_returnto = LJ::Request->get_param('returnto') || '';

        if ($LJ::USE_SSL_LOGIN) {
            $loginform_root = $LJ::SSLROOT;
        } else {
            $loginform_root              = $LJ::SITEROOT;
            $loginform_challenge         = LJ::challenge_generate(300);
            $loginform_need_extra_fields = 1;
            $loginform_onclick           = "onclick='return sendForm()'";
        }
    }

    my $dev_banner = '';
    if ($LJ::IS_DEV_SERVER) {
        $dev_banner = $LJ::DEV_BANNER;
    }

    my $pagestats_obj  = LJ::pagestats_obj();
    my $pagestats_html = $pagestats_obj->render;

    my $before_body_close = '';
    if ( LJ::get_active_journal() ) {
        LJ::run_hooks( 'insert_html_before_journalctx_body_close',
            \$before_body_close, );
    }

    my $final_body_html = LJ::final_body_html();

    # ad stuff
    my ( $ad_beforecrumbs, $ad_aftertitle, $ad_bottom, $ad_beforetitle ) =
        ( '', '', '', '' );

    unless ($LJ::IS_SSL) {
        $ad_beforecrumbs =
            LJ::get_ads( { 'location' => 'look.top.beforecrumbs' } );

        $ad_aftertitle =
            LJ::get_ads( { 'location' => 'look.top.aftertitle' } );

        $ad_bottom = LJ::get_ads( { 'location' => 'look.bottom' } );

        $ad_beforetitle =
            LJ::get_ads( { 'location' => 'look.top.beforetitle' } );
    }

    # footer stuff
    my $uri_tos = LJ::run_hook("get_tos_uri")
        || "$LJ::SITEROOT/legal/tos.bml";

    my $uri_privacy = LJ::run_hook("get_privacy_uri")
        || "$LJ::SITEROOT/legal/privacy.bml";

    my $uri_advertising = LJ::run_hook("get_advertising_url") || "#";

    my $uri_policy = LJ::run_hook('get_policy_uri')
        || "$LJ::SITEROOT/abuse/policy.bml";

    my $uri_volunteer = $LJ::HELPURL{'how_to_help'};

    my $uri_developers = do {
        my $lj_dev = LJ::load_user('lj_dev');
        $lj_dev ? $lj_dev->url : '';
    };

    my $uri_merchandise = LJ::run_hook('get_merchandise_link')
        || 'https://www.zazzle.com/livejournal*';

    my $ml_ljlabs_header = ml(
        'horizon.footer.ljlabs.header',
        { 'sitenameabbrev' => $LJ::SITENAMEABBREV },
    );

    my $ml_ljlabs_aqua =
        ml( 'horizon.footer.ljlabs.aqua',
        { 'sitenameabbrev' => $LJ::SITENAMEABBREV },
        );

    my $ml_ljlabs_dashboard = ml(
        'horizon.footer.ljlabs.dashboard',
        { 'sitenameabbrev' => $LJ::SITENAMEABBREV },
    );

    my $version_html        = LJ::run_hook('current_version_html');
    my $ml_copyright_header = ml(
        'horizon.footer.copyright.header_current',
        { 'current_year' => $LJ::CURRENT_YEAR },
    );

    ## service page branding (optional)
    ## see also cgi-bin/LJ/Hooks/Homepage.pm
    my $branding = LJ::run_hook("service_page_branding", { scheme => $class->code }); 

    return {
        'pretitle'           => $args->{'pretitle'},
        'title'              => $args->{'title'},
        'windowtitle'        => $args->{'windowtitle'} || $args->{'title'},
        'meta'               => $args->{'meta'},
        'head'               => $args->{'head'},
        'bodyopts'           => $args->{'bodyopts'},
        'body'               => $args->{'body'},
        'page_is_ssl'        => $LJ::IS_SSL ? 1 : 0,
        'error_list'         => $error_list,
        'warning_list'       => $warning_list,
        'breadcrumbs'        => $class->template_param_breadcrumbs,
        'chalresp_js'        => $chalresp_js,
        'after_bml_title'    => $after_bml_title,
        'show_mobile_link'   => $show_mobile_link,
        'ml_mobile_link'     => $ml_mobile_link,
        'initial_body_html'  => $initial_body_html,
        'site_messages_html' => $site_messages_html,
        'navbar'             => \@navbar,
        'navbar_max_idx'     => $#navbar,
        'server_signature'   => $LJ::SERVER_SIGNATURE_BODY,
        'dev_banner'         => $dev_banner,
        'pagestats_html'     => $pagestats_html,
        'before_body_close'  => $before_body_close,
        'final_body_html'    => $final_body_html,

        'remote_logged_in'       => $remote_logged_in,
        'remote_personal'        => $remote_personal,
        'remote_identity'        => $remote_identity,
        'remote_paid'            => $remote_paid,
        'remote_sees_ads'        => $remote_sees_ads,
        'remote_username'        => $remote_username,
        'remote_sessid'          => $remote_sessid,
        'logout_link'            => $logout_link,
        'remote_userpic_url'     => $remote_userpic_url,
        'remote_ljuser_display'  => $remote_ljuser_display,
        'remote_display_name'    => $remote_display_name,
        'remote_profile_url'     => $remote_profile_url,
        'remote_recent_url'      => $remote_recent_url,
        'remote_friends_url'     => $remote_friends_url,
        'remote_can_use_esn'     => $remote_can_use_esn,
        'remote_unread_count'    => $remote_unread_count,
        'remote_wallet_link'     => $remote_wallet_link,
        'remote_ljphoto_url'     => $remote_ljphoto_url,
        'remote_can_use_ljphoto' => $remote_can_use_ljphoto,

        'need_loginform'              => $need_loginform,
        'loginform_returnto'          => $loginform_returnto,
        'loginform_root'              => $loginform_root,
        'loginform_challenge'         => $loginform_challenge,
        'loginform_need_extra_fields' => $loginform_need_extra_fields,
        'loginform_onclick'           => $loginform_onclick,

        'additional_head_content'  => $additional_head_content,
        'expresslane_html_comment' => $expresslane_html_comment,
        'server_signature_title'   => $LJ::SERVER_SIGNATURE_TITLE || '',

        'ad_beforecrumbs' => $ad_beforecrumbs,
        'ad_aftertitle'   => $ad_aftertitle,
        'ad_bottom'       => $ad_bottom,
        'ad_beforetitle'  => $ad_beforetitle,

        'favicon'             => $favicon,

        'uri_tos'             => $uri_tos,
        'uri_privacy'         => $uri_privacy,
        'uri_advertising'     => $uri_advertising,
        'uri_policy'          => $uri_policy,
        'uri_volunteer'       => $uri_volunteer,
        'uri_developers'      => $uri_developers,
        'uri_merchandise'     => $uri_merchandise,
        'ml_ljlabs_header'    => $ml_ljlabs_header,
        'ml_ljlabs_aqua'      => $ml_ljlabs_aqua,
        'ml_ljlabs_dashboard' => $ml_ljlabs_dashboard,
        'version_html'        => $version_html,
        'ml_copyright_header' => $ml_copyright_header,

        'branding'            => $branding,
    };
}

### OVERRIDABLE FUNCTIONS ###

sub template_filename {
    my ($class) = @_;
    return $class->code;
}

sub code            { die 'abstract method'; }
sub need_res        { die 'abstract method'; }
sub template_params { die 'abstract method'; }

BEGIN {
    require LJ::Config;
    LJ::Config->load;

    foreach my $class (@LJ::SUPPORTED_SCHEMES_LIST) {
        my $filename = $class;
        $filename =~ s{::}{/}g;
        $filename .= '.pm';

        require $filename;
        $CODE_TO_CLASS_MAP{ $class->code } = $class;
    }
}

1;
