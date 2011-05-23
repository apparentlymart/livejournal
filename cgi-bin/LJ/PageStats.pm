package LJ::PageStats;
use strict;
use LJ::Request;

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

    # See if their ljuniq cookie has the PageStats flag
    if ($BML::COOKIE{'ljuniq'} =~ /[a-zA-Z0-9]{15}:\d+:pgstats([01])/) {
        return 0 unless $1; # Don't serve PageStats if it is "pgstats:0"
    } else {
        return 0; # They don't have it set this request, but will for the next one
    }

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

1;
