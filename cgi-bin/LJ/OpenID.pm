package LJ::OpenID;

use strict;
use Digest::SHA1 qw(sha1 sha1_hex);
use LWPx::ParanoidAgent;

BEGIN {
    $LJ::OPTMOD_OPENID_CONSUMER = $LJ::OPENID_CONSUMER ? eval "use Net::OpenID::Consumer; 1;" : 0;
    $LJ::OPTMOD_OPENID_SERVER   = $LJ::OPENID_SERVER   ? eval "use Net::OpenID::Server; 1;" : 0;
}

# returns boolean whether consumer support is enabled and available
sub consumer_enabled {
    return 0 unless $LJ::OPENID_CONSUMER;
    return $LJ::OPTMOD_OPENID_CONSUMER || eval "use Net::OpenID::Consumer; 1;";
}

# returns boolean whether server support is enabled and available
sub server_enabled {
    return 0 unless $LJ::OPENID_SERVER;
    return $LJ::OPTMOD_OPENID_CONSUMER || eval "use Net::OpenID::Server; 1;";
}

sub server {
    my ($get, $post) = @_;

    return Net::OpenID::Server->new(
                                    compat       => $LJ::OPENID_COMPAT,
                                    get_args     => $get  || {},
                                    post_args    => $post || {},

                                    get_user     => \&LJ::get_remote,
                                    is_identity  => sub {
                                        my ($u, $ident) = @_;
                                        return LJ::OpenID::is_identity($u, $ident, $get);
                                    },
                                    is_trusted   => \&LJ::OpenID::is_trusted,

                                    setup_url    => "$LJ::SITEROOT/openid/approve.bml",

                                    server_secret => \&LJ::OpenID::server_secret,
                                    secret_gen_interval => 3600,
                                    secret_expire_age   => 86400 * 14,
                                    endpoint_url => $LJ::OPENID_SERVER,
                                    );
}

# Returns a Consumer object
# When planning to verify identity, needs GET
# arguments passed in
sub consumer {
    return LJ::Identity::OpenID->consumer(@_);
}

sub server_secret {
    my $time = shift;
    my ($t2, $secret) = LJ::get_secret($time);
    die "ASSERT: didn't get t2 (t1=$time)" unless $t2;
    die "ASSERT: didn't get secret (t2=$t2)" unless $secret;
    die "ASSERT: time($time) != t2($t2)\n" unless $t2 == $time;
    return $secret;
}

sub is_trusted {
    my ($u, $trust_root, $is_identity) = @_;
    return 0 unless $u;
    # we always look up $is_trusted, even if $is_identity is false, to avoid timing attacks

    # let certain hostnames be trusted at a site-to-site level, per policy.
    my ($base_domain) = $trust_root =~ m!^https?://([^/]+)!;
    return 1 if $LJ::OPENID_DEST_DOMAIN_TRUSTED{$base_domain};

    my $dbh = LJ::get_db_writer();
    my ($endpointid, $duration) = $dbh->selectrow_array("SELECT t.endpoint_id, t.duration ".
                                                        "FROM openid_trust t, openid_endpoint e ".
                                                        "WHERE t.userid=? AND t.endpoint_id=e.endpoint_id AND e.url=?",
                                                        undef, $u->{userid}, $trust_root);
    return 0 unless $endpointid;
    return 1;
}

sub is_identity {
    my ($u, $ident, $get) = @_;
    return 0 unless $u && $u->is_person;

    # canonicalize trailing slash
    $ident .= "/" unless $ident =~ m!/$!;

    my $user = $u->user;
    my $url  = $u->journal_base . "/";

    return 1 if
        $ident eq $url ||
        # legacy:
        $ident eq "$LJ::SITEROOT/users/$user/" ||
        $ident eq "$LJ::SITEROOT/~$user/" ||
        $ident eq "http://$user.$LJ::USER_DOMAIN/";

    return 0;
}

sub getmake_endpointid {
    my $site = shift;

    my $dbh = LJ::get_db_writer()
        or return undef;

    my $rv = $dbh->do("INSERT IGNORE INTO openid_endpoint (url) VALUES (?)", undef, $site);
    my $end_id;
    if ($rv > 0) {
        $end_id = $dbh->{'mysql_insertid'};
    } else {
        $end_id = $dbh->selectrow_array("SELECT endpoint_id FROM openid_endpoint WHERE url=?",
                                        undef, $site);
    }
    return $end_id;
}

sub add_trust {
    my ($u, $site) = @_;

    my $end_id = LJ::OpenID::getmake_endpointid($site)
        or return 0;

    my $dbh = LJ::get_db_writer()
        or return undef;

    my $rv = $dbh->do("REPLACE INTO openid_trust (userid, endpoint_id, duration, trust_time) ".
                      "VALUES (?,?,?,UNIX_TIMESTAMP())", undef, $u->{userid}, $end_id, "always");
    return $rv;
}

# Returns 1 if destination identity server
# is blocked
sub blocked_hosts {
    return LJ::Identity::OpenID->blocked_hosts(@_);
}

1;
