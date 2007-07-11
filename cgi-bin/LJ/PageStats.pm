package LJ::PageStats;
use strict;

# loads a page stat tracker
sub new {
    my ($class) = @_;

    my $self = {
        conf    => \%LJ::PAGESTATS_PLUGIN_CONF,
    };

    bless $self, $class;
    return $self;
}

# render JS output for embedding in pages
#   ctx can be "journal" or "app".  defaults to "app".
sub render {
    my ($self, $ctx) = @_;
    $ctx ||= "app";

    return '' unless $self->should_do_pagestats;

    my $output = '';
    foreach my $plugin ($self->get_active_plugins) {
        my $class = "LJ::PageStats::$plugin";
        eval "use $class; 1;";
        die "Error loading PageStats '$plugin': $@" if $@;
        my $plugin_obj = $class->new;
        next unless $plugin_obj->should_render($ctx);
        $output .= $plugin_obj->render(conf => $self->{conf}->{$plugin});
    }

    # return nothing
    return $output;
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
    my ($self, $ctx) = @_;
    return 0 unless $ctx eq "app";

    my $r = $self->get_request or return 0;

    # Make sure we don't exclude tracking from this page or path
    return 0 if grep { $r->uri =~ /$_/ } @{ $LJ::PAGESTATS_EXCLUDE{'uripath'} };
    return 0 if grep { $r->notes('codepath') eq $_ } @{ $LJ::PAGESTATS_EXCLUDE{'codepath'} };

    # See if their ljuniq cookie has the PageStats flag
    if ($BML::COOKIE{'ljuniq'} =~ /[a-zA-Z0-9]{15}:\d+:pgstats([01])/) {
        return 0 unless $1; # Don't serve PageStats if it is "pgstats:0"
    } else {
        return 0; # They don't have it set this request, but will for the next one
    }

    return 1;
}

sub get_user {
    my ($self) = @_;

    return LJ::get_remote();
}

# return Apache request
sub get_request {
    my ($self) = @_;

    return Apache->request;
}

sub get_root {
    my ($self) = @_;

    return $LJ::IS_SSL ? $LJ::SSLROOT : $LJ::SITEROOT ;
}

sub get_active_plugins {
    my ($self) = @_;

    my $conf = $self->get_conf;

    return () unless $conf;

    return @{$conf->{_active}};
}

sub get_conf {
    my ($self) = @_;

    return $self->{conf};
}

sub filename {
    my ($self) = @_;
    my $r = $self->get_request;

    my $docroot  = $r->document_root;
    my $filename = $r->filename;
    $filename =~ s!^$docroot/!!;

    return $filename;
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

    my $lang = BML::get_language();

    return $lang;
}

sub loggedin {
    my ($self) = @_;

    my $loggedin = $self->get_user ? '1' : '0';

    return $loggedin;
}
1;
