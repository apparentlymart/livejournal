package LJ::Request;
use strict;

use LJ::Text;
use DateTime;

use constant MP2 => (exists $ENV{MOD_PERL_API_VERSION} &&
                     $ENV{MOD_PERL_API_VERSION} == 2) ? 1 : 0;

BEGIN {
    if (MP2){
        require LJ::Request::Apache2;
    } elsif($ENV{MOD_PERL_API_VERSION} or $ENV{MOD_PERL}) {
        require LJ::Request::Apache;
    } elsif ($LJ::TESTING_ENVIRONMENT) {
        require LJ::Request::Test;
    } else {
        *LJ::Request::is_inited = sub { 0 };
    }
}

my ($cookies_parsed, %cookie, @cookie_set);
my $redirected;

=head1 NAME

LJ::Request - the abstraction layer for interfacing with the outside world.

(which currently means Apache, subject to change in the future).

=head1 SYNOPSIS

    sub handler {
        my ($req) = @_;
        LJ::Request->init($req);
    }

    my $uri  = LJ::Request->uri;

    my %get  = LJ::Request->get_params;
    my %post = LJ::Request->post_params;
    my $query_string = LJ::Request->args;

I<This documentation is in progress. You may wish to refer to the source code
for LJ::Request::Apache for the list of methods.>

=head1 FUNCTIONS

=head2 Generic C<GET/POST> parameters.

    my $method = LJ::Request->method;

    my $did_post;
    $did_post = uc $method eq 'POST';
    $did_post = LJ::Request->did_post; # encapsulated check

    if ($did_post) {
        print Data::Dumper::Dumper({ LJ::Request->post_params });
    } else {
        print Data::Dumper::Dumper({ LJ::Request->get_params });
    }

    print LJ::Request->get_param('hello'), LJ::Request->post_param('hello');

=cut

sub did_post {
    my ($class) = @_;
    return uc $class->method eq 'POST';
}

sub get_param {
    my ($class, $key) = @_;
    my %get = $class->get_params;
    return $get{$key};
}

sub post_param {
    my ($class, $key) = @_;
    my %post = $class->post_params;
    return $post{$key};
}

=head2 Cookies

    my %cookies = LJ::Request->cookie;
    my $specific_cookie = LJ::Request->cookie('ljuniq');
    my @all_cookies_for_the_key = LJ::Request->cookie('ljmastersession');

    LJ::Request->set_cookie('ljuniq' => 'VrlKr5esKcj1Kb2',
        'expires' => time + 86400,
        'path' => '/',

        'domain' => '.livejournal.com',
        # or
        'domain' => [ 'www.livejournal.com', '.livejournal.com' ],

        'http_only' => 1,
    );

    LJ::Request->delete_cookie('ljuniq', 'path' => $path, 'domain' => $domain);

    # convert cookies to HTTP headers. BML does this for you.
    LJ::Request->send_cookies;

=cut

sub _parse_cookies {
    my ($class) = @_;

    return if $cookies_parsed;

    foreach my $cookie (split(/;\s+/, $class->header_in("Cookie"))) {
        my ($name, $value) = ($cookie =~ /(.*)=(.*)/);
        $name = LJ::Text->durl($name);
        $value = LJ::Text->durl($value);

        $cookie{$name} ||= [];
        push @{$cookie{$name}}, $value;
    }

    $cookies_parsed = 1;
}

sub cookie {
    my ($class, $key) = @_;

    $class->_parse_cookies;

    return map { $_ => $cookie{$_}->[-1] } keys %cookie unless $key;

    $cookie{$key} ||= [];
    return wantarray ? @{$cookie{$key}} : $cookie{$key}[-1];
}

sub set_cookie {
    my ($class, $key, $value, %opts) = @_;

    $class->_parse_cookies;

    $opts{'path'}    ||= $LJ::COOKIE_PATH;
    $opts{'domain'}  ||= $LJ::COOKIE_DOMAIN;
    $opts{'expires'} ||= 0;

    if (ref $opts{'domain'} eq 'ARRAY') {
        foreach my $specific_domain(@{$opts{'domain'}}) {
            my %modified_opts = %opts;
            $modified_opts{'domain'} = $specific_domain;

            $class->set_cookie($key, $value, %modified_opts);
        }

        return;
    }

    my $dt = DateTime->from_epoch('epoch' => $opts{'expires'});
    my $expires_dump = $dt->strftime('%A, %d-%b-%Y %H:%M:%S GMT');

    my $header = '';
    $header .= LJ::Text->eurl($key) . '=' . LJ::Text->eurl($value);
    $header .= "; expires=$expires_dump" if $opts{'expires'};
    $header .= "; path=$opts{'path'}" if $opts{'path'};
    $header .= "; domain=$opts{'domain'}" if $opts{'domain'};
    $header .= "; HttpOnly" if $opts{'http_only'};

    push @cookie_set, {
        'name' => $key,
        'value' => $value,
        'expires' => $opts{'expires'},
        'expires_dump' => $expires_dump,
        'path' => $opts{'path'},
        'domain' => $opts{'domain'},
        'http_only' => $opts{'http_only'},
        'header' => $header,
    };

    push @{$cookie{$key}}, $value;
}

sub delete_cookie {
    my ($class, $key, %opts) = @_;

    $class->set_cookie($key, undef, time - 86400,
        'domain' => $opts{'domain'},
        'path' => $opts{'path'},
    );
    delete $cookie{$key};
}

sub send_cookies {
    my ($class, @args) = @_;

    return $LJ::Request::SEND_COOKIES_OVERRIDE->(@args)
        if ref $LJ::Request::SEND_COOKIES_OVERRIDE eq 'CODE';

    $class->header_out('Set-Cookie' => $_->{'header'})
        foreach @cookie_set;
}

=head2 Redirects

    LJ::Request->redirect($LJ::SITEROOT);
    die unless LJ::Request->redirected;

=cut

sub redirect {
    my ($class, $url, $code) = @_;

    $code ||= $class->REDIRECT;

    $class->status($code);
    $class->header_out('Location' => $url);
    $redirected = [$code, $url];

    return $code;
}

sub redirected {
    return $redirected;
}

=head2 Cleanup

    # clean internal state variables; this is a hack until we get a cleaner
    # interface for a request-lasting singleton. LJ::start_request (weblib.pl)
    # does this for you.
    LJ::Request->start_request;

=cut

sub start_request {
    my ($class) = @_;
    $cookies_parsed = 0;
    $redirected = undef;
}

1;
