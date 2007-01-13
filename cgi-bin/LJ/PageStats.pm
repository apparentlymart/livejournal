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
sub render {
    my ($self) = @_;
    my $u = $self->get_user;

    return '' unless $self->should_render;
    my $output = '';

    my @plugins = $self->get_active_plugins;
    # return empty string if nothing active
    return '' unless @plugins;

    foreach my $plugin ( @plugins ) {
        my $full_plugin = "LJ::PageStats::$plugin";
        eval "use $full_plugin";
        die "Error loading PageStats '$plugin': $@" if $@;
        my $plugin_obj = $full_plugin->new;
        $output .= $plugin_obj->render(conf => $self->{conf}->{$plugin});
    }

    # return nothing
    return $output;
}

# decide if tracker should be embedded in page
sub should_render {
    my ($self) = @_;

    my $r = $self->get_request or return 0;
    my $u = $self->get_user;

    # Make sure we don't exclude tracking from this page or path
    return 0 if grep { $r->uri =~ /$_/ } @{ $LJ::PAGESTATS_EXCLUDE{'uripath'} };
    return 0 if grep { $r->notes('codepath') eq $_ } @{ $LJ::PAGESTATS_EXCLUDE{'codepath'} };

    # Make sure the user isn't underage or said no to tracking
    return 0 if $u && $u->underage();
    return 0 if $u && $u->prop('opt_exclude_stats');

    # See if their ljuniq cookie has the HitBox flag
    if ($BML::COOKIE{'ljuniq'} =~ /[a-zA-Z0-9]{15}:\d+:hbx([01])/) {
        return 0 unless $1; # Don't serve HBX if it is "hbx:0"
    } else {
        return 0; # They don't have it set this request, but will for the next one
    }

    return 1;
}

sub get_user {
    my ($self) = @_;

    return LJ::get_remote(),
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
    $scheme = $LJ::SCHEMES[0]->{'scheme'} unless $scheme;

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
