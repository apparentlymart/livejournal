package LJ::PageStats;
use strict;
use LJ::Request;
use Digest::MD5 qw/md5_base64/;

# loads a page stat tracker
sub new {
    my ($class) = @_;

    my $self = {
        conf    => \%LJ::PAGESTATS_PLUGIN_CONF,
        ctx     => '',
    };

    bless $self, $class;
    return $self;
}

# render JS output for embedding in pages
#   ctx can be "journal" or "app".  defaults to "app".
sub render {

    my ($self, $params) = @_;

    my $ctx = $self->get_context;

    return '' unless $self->should_do_pagestats;

    my $output = '';
    foreach my $plugin ($self->get_active_plugins) {
        my $class = "LJ::PageStats::$plugin";
        eval "use $class; 1;";
        die "Error loading PageStats '$plugin': $@" if $@;
        my $plugin_obj = $class->new;
        next unless $plugin_obj->should_render;
        $output .= $plugin_obj->render(conf => $self->{conf}->{$plugin}, params => (ref($params) eq 'HASH' ? $params : {}) );
    }

    # return nothing
    return "<div id='hello-world' style='text-align: left; font-size:0; line-height:0; height:0; overflow:hidden;'>$output</div>";
}

# method on root object (LJ::PageStats instance) to decide if user has optted-out of page
# stats tracking, or if it's a bad idea to show one to this user (underage).  but
# this isn't pagestat-specific logic.  that's in the "should_render" method.
sub should_do_pagestats {
    my $self = shift;

    my $u = $self->get_user;

    # Make sure the user isn't underage or said no to tracking
    return 0 if $u && $u->underage;
    return 0 if $u && $u->prop('opt_exclude_stats');
    return 1;
}

# decide if tracker should be embedded in page
sub should_render {
    my ($self) = @_;

    my $ctx = $self->get_context;
    return 0 unless ($ctx && $ctx =~ /^(app|journal)$/);

    LJ::Request->is_inited or return 0;

    # Make sure we don't exclude tracking from this page or path
    return 0 if grep { LJ::Request->uri =~ /$_/ } @{ $LJ::PAGESTATS_EXCLUDE{'uripath'} };
    return 0 if grep { LJ::Request->notes('codepath') eq $_ } @{ $LJ::PAGESTATS_EXCLUDE{'codepath'} };

    # Turned off. AMyshkin
    # See if their ljuniq cookie has the PageStats flag
#    if ($BML::COOKIE{'ljuniq'} =~ /[a-zA-Z0-9]{15}:\d+:pgstats([01])/) {
#        return 0 unless $1; # Don't serve PageStats if it is "pgstats:0"
#    } else {
#        return 0; # They don't have it set this request, but will for the next one
#    }

    return 1;
}

sub get_context {
    my ($self) = @_;

    return $self->get_journal() ? 'journal' : 'app';
}

sub get_user {
    my ($self) = @_;

    return LJ::get_remote();
}

# return Apache request
sub get_request {
    my ($self) = @_;

    return LJ::Request->r;
}

sub get_root {
    my ($self) = @_;

    return $LJ::IS_SSL ? $LJ::SSLROOT : $LJ::SITEROOT ;
}

sub get_active_plugins {
    my ($self) = @_;

    my $conf = $self->get_conf;

    return () unless $conf;

    return @{$conf->{_active} || []};
}

sub get_conf {
    my ($self) = @_;

    return $self->{conf};
}

sub get_plugin_conf {
    my ($self) = @_;

    my $plugin = ref $self; $plugin =~ s/^LJ::PageStats:://;

    return $LJ::PAGESTATS_PLUGIN_CONF{$plugin};
}

sub filename {
    my ($self) = @_;

    my $filename = LJ::Request->uri;

    return $filename;
}

sub codepath {
    my ($self) = @_;

    my $codepath = LJ::Request->notes('codepath');
    # remove 's2.' or 's1.' prefix from codepath
    $codepath =~ s/^[Ss]\d{1}\.(.*)$/$1/;

    # map some s1 codepath names to s2
    my %s1_map = (
        'bml.talkpost'   => "reply",
        'bml.talkread'   => "entry",
        'bml.view.index' => "calendar",
    );

    foreach my $s1code (keys %s1_map) {
        $codepath = $s1_map{$s1code} if ($codepath =~ /^$s1code$/);
    }

    return $codepath;
}

sub pagename {
    my ($self) = @_;

    my $pagename = '';

    if ($self->is_journal_ctx) {
        $pagename = $self->codepath;
    } else {
        $pagename = $self->filename;
    }

    return $pagename;
}

sub get_journal {
    my $self = shift;

    my $j = LJ::get_active_journal();
    return $j if $j;

    # Now try to determine active_journal from base request if it is requests chain.
    # Cache it in $self->{active_journal}.
    # This code is necessary for getting active_journal in 'error-page.bml'.

    return $self->{active_journal} if exists $self->{active_journal};

    $self->{active_journal} = undef;

    if (!LJ::Request->is_initial_req())
    {
        my $request = LJ::Request->prev();
        my $host = $request->header_in('Host');
        my $uri = $request->uri;

        if (($LJ::USER_VHOSTS || $LJ::ONLY_USER_VHOSTS) &&
            $host =~ /^([\w\-]{1,15})\.\Q$LJ::USER_DOMAIN\E$/ &&
            $1 ne 'www')
        {
            my $user = $1;

            my $func = $LJ::SUBDOMAIN_FUNCTION{$user};

            if ($func eq 'journal' && $uri =~ m!^/(\w{1,15})(/.*)?$!) {
                $user = $1;
            }
            elsif ($func) {
                $user = '';
            }

            if ($user) {
                my $u = LJ::load_user($user);
                $self->{active_journal} = $u if $u;
            }
        }
    }

    return $self->{active_journal};
}

sub journaltype {
    my $self = shift;

    my $j = $self->get_journal;

    return $j->journaltype_readable;
}

sub journalbase {
    my $self = shift;

    my $j = $self->get_journal;

    return $j->journal_base;
}

sub is_journal_ctx {
    my $self = shift;
    my $ctx = $self->get_context;

    return 1 if ($ctx eq 'journal');
    return 0;
}

# not implemented for livejournal
sub groups {
    my ($self) = @_;

    return undef;
}

sub scheme {
    my ($self) = @_;

    my $scheme = BML::get_scheme();
    $scheme = (LJ::site_schemes())[0]->{'scheme'} unless $scheme;

    return $scheme;
}

sub language {
    my ($self) = @_;

    my $lang = LJ::Lang::get_effective_lang();

    return $lang;
}

sub loggedin {
    my ($self) = @_;

    my $loggedin = $self->get_user ? '1' : '0';

    return $loggedin;
}

sub campaign_tracking {
    my ($self, $opts) = @_;

    return '' unless $self->should_do_pagestats;

    my $output = '';
    foreach my $plugin ($self->get_active_plugins) {
        my $class = "LJ::PageStats::$plugin";
        eval "use $class; 1;";
        die "Error loading PageStats '$plugin': $@" if $@;
        my $plugin_obj = $class->new;
        next unless $plugin_obj->should_render;
        next unless ($plugin_obj->can('campaign_track_html'));
        $output .= $plugin_obj->campaign_track_html($opts);
    }

    return $output;
}

sub account_level {
    my ($self, $u) = @_;
    my $level;

    if ($u) {
        if ($u->identity) {
            $level = 'plus';
        } else { 
            if (LJ::get_cap($u, 'paid')) {
                if ($u->in_class('perm')) {
                    $level = 'perm';
                } elsif ($u->in_class('sponsored')) {
                    $level = 'sponsored';
                } else {
                    $level = 'paid';
                }
            } elsif ($u->in_class('plus')) {
                $level = 'plus';
            } else {
                $level = 'basic';
            }
        }
    }

    return $level;
}

sub style_system { 
    my ($self, $journal) = @_;

    return 'undef' unless $journal;
    return LJ::Request->notes('codepath') =~ m/^([sS]\d)\./ ? lc($1) : 'undef';
}

sub style_layout {
    my ($self, $journal) = @_;

    return 'undef' unless $journal;

    my $style_system = $self->style_system($journal); 
    my $style_layout;
    if ($style_system eq 's1') { 
        $style_layout = $journal->{'_s1styleid'} && LJ::S1::get_style($journal->{'_s1styleid'})->{'styledes'} || 'own_style';
    } elsif ($style_system eq 's2') {
        $style_layout = 'own_style';
            if ($journal->{'_s2styleid'}) {
                my %style = LJ::S2::get_style($journal->{'_s2styleid'});
                $style_layout = defined $style{'layout'} && S2::get_layer_info($style{'layout'}, 'name');
                unless ($style_layout) { 
                    LJ::S2::load_layers($style{'layout'}); 
                    $style_layout = S2::get_layer_info($style{'layout'}, 'name') || 'own_style';
                    S2::unregister_layer($style{'layout'}); 
                }
            } elsif (defined $journal->{'_s2styleid'}) { 
                $style_layout = 'default';
            }
    } else {
        $style_layout = 'undef';
    } 

    return $style_layout;
}

sub comments_style {
    my ($self, $journal) = @_;

    return 'undef' unless $journal;

    my $remote    = LJ::get_remote();
    my $style     = LJ::Request->get_param('style');
    my $format    = LJ::Request->get_param('format') || '';
    my $stylemine = ($style && $style eq 'mine') ? 1 : 0;
    my $style_u   = $journal;

    my $comments_style = 's1';

    my ($ctx, $stylesys, $styleid);

    if ($remote && ($stylemine || $remote->opt_stylealwaysmine || $remote->opt_commentsstylemine)) {
        $style_u = $remote;
    }

    LJ::load_user_props($journal, ("stylesys", "s2_style"));

    my $forceflag = 0;

    LJ::run_hooks("force_s1", $journal, \$forceflag);

    if ( not $forceflag and $journal->{'stylesys'} and $journal->{'stylesys'} == 2 ) {
        $stylesys = 2;
        $styleid  = $journal->{'s2_style'};
    } else {
        $stylesys = 1;
        $styleid  = 0;
    }

    if ( $stylesys == 2 ) {
        $ctx = LJ::S2::s2_context('UNUSED', $styleid);
        $LJ::S2::CURR_CTX = $ctx;

        $comments_style = 's2' if (not $ctx->[S2::PROPS()]->{'view_entry_disabled'} and
                       LJ::get_cap($style_u, "s2viewentry")) || $LJ::JOURNALS_WITH_FIXED_STYLE{$journal->user};
    }

    if ( $format eq 'light' ) {
        $comments_style = 's1';
    }

    return $comments_style;
}

sub is_homepage {
    return LJ::Request->current_page_url() =~ m{^$LJ::SITEROOT(?:/welcome/?|/latest/?|/editors/?|/category/\w+/?)?/?$} ? 1 : 0;
}

sub homepage_category {
    my ($self) = @_;

    my $url = LJ::Request->current_page_url(); 

    if (my ($cat_pretty_name) = $url =~ m{^$LJ::SITEROOT/category/(\w+)/?$}) {
        for (@{LJ::HomePage::Category->get_all_categories}) {
            return $cat_pretty_name
                if  $cat_pretty_name eq $_->{'pretty_name'};
        }
    }

    return 'undef';
}

sub homepage_flags {
    my ($self) = @_;

    my $remote = LJ::get_remote();

    return {
        geotargeting => LJ::PersonalStats::Ratings->get_rating_country() || 'undef',
        unique_items => LJ::User::HomePage->homepage_flag ($remote, 'show_unique_items') ? 'show' : 'hide',
        from_friends => LJ::User::HomePage->homepage_flag ($remote, 'show_from_friends') ? 'show' : 'hide',
        hidden_items => LJ::User::HomePage->homepage_flag ($remote, 'show_hidden_items') ? 'show' : 'hide',
    }
}

sub user_params {
    my ($self, $u) = @_;

    my $host = LJ::Request->header_in("Host");
    my $uri  = LJ::Request->uri();
    my $args = LJ::Request->args();

    $args = "?$args" if $args;
 
    # Special requirement from ATI:
    # The character „&“ should not be used, or encoded two times. O_O
    $args =~ s/(&)/LJ::eurl($1)/eg;

    my $url = LJ::eurl("$host$uri$args");

    if ( $u ) {

        my $journaltype  = $u->journaltype_readable;
        my $journal_user = $u->user;

        if ($journaltype eq 'redirect' && (my $renamedto = LJ::load_user($u->prop('renamedto')))) {
            $journaltype = $renamedto->journaltype_readable;
        }

        return {
            userid          => $u->userid(),
            stylealwaysmine => $u->opt_stylealwaysmine ? 'yes' : 'no',
            login_service   => $u->identity ? $u->identity->short_code : 'lj',
            sup_enabled     => LJ::SUP->is_sup_enabled($u) ? 'Cyr' : 'nonCyr',
            premium_package => $u->get_cap('perm') ? 'perm' : $u->get_cap('paid') ? 'paid' : 'no',
            account_level   => $self->account_level($u),
            page_params     => "journal::$journaltype\:\:$journal_user\:\:$url",
            adult_content   => $u->adult_content_calculated,
            early_adopter   => LJ::get_cap($u, 'early') ? 'yes' : 'no',
            user_md5_base64 => md5_base64($u->user, 0, 8),
            user            => $journal_user,
            journaltype     => $journaltype,
        }

    } else {

        my $ip_class = LJ::GeoLocation->ip_class();
 
        return {
            userid          => '',
            stylealwaysmine => 'undef', 
            login_service   => 'undef', 
            sup_enabled     => LJ::SUP->is_sup_ip_class($ip_class) ? 'Cyr' : 'nonCyr', 
            premium_package => 'undef', 
            account_level   => 'undef', 
            page_params     => "service::undef::undef::$url",
            adult_content   => 'undef',
            early_adopter   => 'undef', 
            user_md5_base64 => 'undef',
            user            => 'undef',
            journaltype     => 'undef', 
        }

    } 

}

1;
