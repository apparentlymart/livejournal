# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#              WARNING! PELIGROSO! ACHTUNG! VNIMANIYE!
# some fools (aka mischa) try to use this library from web context,
# so make sure it's psuedo-safe to do so.  like don't class-autouse
# Test::FakeApache because that really fucks with things.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

package LJ::Test;

use strict;
use warnings;

use base 'Exporter';

use Class::Autouse qw(
    LJ::OAuth::AccessToken
);

# External modules
use DBI;
use Carp qw();
use Data::Dumper;

# Internal modules
use LJ::ModuleCheck;
use LJ::Test::Mock::User;
use LJ::Test::Mock::MemCache;

# TODO: use EXPORT_OK instead, do not clutter the caller's namespace
# unless asked to specifically
our @EXPORT = qw(
    memcache_stress with_fake_memcache temp_user
    temp_comm temp_feed alloc_sms_num fake_apache

    get_mock_user
);

my @temp_userids;  # to be destroyed later

END {
    return if $LJ::_T_NO_TEMP_USER_DESTROY;
    # clean up temporary usernames
    foreach my $uid (@temp_userids) {
        my $u = LJ::load_userid($uid) or next;
        $u->delete_and_purge_completely;
    }
}

our $VERBOSE = 0;

$LJ::_T_FAKESCHWARTZ = 1 unless $LJ::_T_NOFAKESCHWARTZ;
my $theschwartz = undef;

sub theschwartz {
    return $theschwartz if $theschwartz;

    my $fakedb = "$ENV{LJHOME}/t-theschwartz.sqlite";
    unlink $fakedb, "$fakedb-journal";
    my $fakedsn = "dbi:SQLite:dbname=$fakedb";

    my $load_sql = sub {
        my($file) = @_;
        open my $fh, $file or die "Can't open $file: $!";
        my $sql = do { local $/; <$fh> };
        close $fh;
        split /;\s*/, $sql;
    };

    my $dbh = DBI->connect($fakedsn,
                           '', '', { RaiseError => 1, PrintError => 0 });
    my @sql = $load_sql->("$ENV{LJHOME}/cvs/TheSchwartz/t/schema-sqlite.sql");
    for my $sql (@sql) {
        $dbh->do($sql);
    }
    $dbh->disconnect;

    return $theschwartz = TheSchwartz->new(databases => [{
        dsn => $fakedsn,
        user => '',
        pass => '',
    }]);
}

sub create_user {
    my ( $class, %opts ) = @_;

    my $journaltype = $opts{'journaltype'} || 'P';

    unless ( $opts{'user'} ) {
        my @chars = split //, 'abcdefghijklmnopqrstuvwxyz';
        my $chars_count = scalar(@chars);

        my $u;

        do {
            my $user_prefix = $opts{'user_prefix'} || 't_';
            $opts{'user'} = $user_prefix;

            foreach ( 1 .. ( 15 - length($user_prefix) ) ) {
                $opts{'user'} .= $chars[ rand($chars_count) ];
            }

            $u = LJ::load_user( $opts{'user'} );
        } while ($u);
    }

    # TODO: change these to //= when we finally upgrade our perl
    $opts{'bdate'} = '1980-01-01' unless defined $opts{'bdate'};

    # 0x08 => paid, 0x10 => permanent, 0x400 => sup, see lj-caps-conf.pl
    $opts{'caps'}  = 0x418        unless defined $opts{'caps'};

    if ( $journaltype eq 'P' ) {
        $opts{'password'}   = 'test' unless defined $opts{'password'};
        $opts{'get_ljnews'} = 0      unless defined $opts{'get_ljnews'};
        $opts{'underage'}   = 0      unless defined $opts{'underage'};
        $opts{'ofage'}      = 1      unless defined $opts{'ofage'};
        $opts{'status'}     = 'A'    unless defined $opts{'status'};
    }

    $opts{'email'} = 'do-not-reply@livejournal.com'
        unless defined $opts{'email'};

    $opts{'friends'} ||= [];

    my $u;

    if ( $journaltype eq 'P' ) {
        $u = LJ::Test::Mock::User->create_personal(%opts);
    }
    elsif ( $journaltype eq 'C' ) {
        unless ( defined $opts{'owner'} ) {
            $opts{'owner'} = $class->create_user(
                %opts,
                'journaltype' => 'P',
                'user'        => undef
            );
        }
        $opts{'membership'} ||= 'open';
        $opts{'postlevel'}  ||= 'members'; 
        $u = LJ::Test::Mock::User->create_community(%opts);
    }
    elsif ( $journaltype eq 'Y' ) {
        unless ( defined $opts{'creator'} ) {
            $opts{'creator'} = $class->create_user(
                %opts,
                'journaltype' => 'P',
                'user'        => undef
            );
        }

        $opts{'feedurl'} = "$LJ::SITEROOT/fakerss.xml#"
            unless defined $opts{'feedurl'};

        $u = LJ::Test::Mock::User->create_syndicated(%opts);
    }
    else {
        die "unknown journaltype $journaltype";
    }

    # some hooks override this, so let's switch it back
    LJ::update_user( $u, { 'caps' => $opts{'caps'} } );

    # props
    my $props = delete $opts{props} || {};
    while (my($k,$v) = each %$props){
        $u->set_prop($k, $v);
    }
    
    if ($VERBOSE) {
        warn "created user $opts{'user'}\n";
    }

    if ( $opts{'temporary'} ) {
        push @temp_userids, $u->userid;
    }

    $u = bless { %$u }, 'LJ::Test::Mock::User';
    $u->set_clean_password($opts{'password'}) if defined $opts{'password'};

    return $u;
}


sub add_friend {
    my ($class, $uname, $fname) = @_;
    my $u = LJ::load_user($uname) || die "Can't load user '$uname'";
    my $f = LJ::load_user($fname) || die "Can't load user '$fname'";

    $u->add_friend($f);
}

sub temp_user {
    if ($_[0]) {
        if ($_[0] eq __PACKAGE__) {
            shift();
        }
    }
    
    my %args = @_;
    my $underscore  = delete $args{'underscore'};
    my $journaltype = delete $args{'journaltype'}  || 'P';
    die 'unknown args' if %args;

    my $pfx = $underscore ? '_' : 't_';

    return __PACKAGE__->create_user(
        'user_prefix' => $pfx,
        'journaltype' => $journaltype,
        'temporary'   => 1,
    );
}

sub temp_comm {
    return __PACKAGE__->create_user( 'journaltype' => 'C', 'temporary' => 1 );
}

sub temp_feed {
    return __PACKAGE__->create_user( 'journaltype' => 'Y', 'temporary' => 1 );
}

my $fake_apache;

sub fake_apache {
    return $fake_apache if $fake_apache;
    # TODO: load all the right libraries, if they haven't already been loaded before.
    # currently a fakeapache-using test has to start with:
    #   use strict;
    #   use Test::More 'no_plan';
    #   use lib "$ENV{LJHOME}/cgi-bin";
    #   require 'modperl.pl';
    #   use LJ::Test;
    # but that modperl.pl require is kinda ugly.
    die "You don't have Test::FakeApache!" unless LJ::ModuleCheck->have("Test::FakeApache");
    return $fake_apache = Test::FakeApache->new(
                                                PerlInitHandler => \&Apache::LiveJournal::handler,
                                                DocumentRoot => "$LJ::HOME/htdocs/",
                                                );
}

sub with_fake_memcache (&) {
    my $cb = shift;
    my $pre_mem = LJ::MemCache::get_memcache();
    my $fake_memc = LJ::Test::Mock::MemCache->new();

    {
        local @LJ::MEMCACHE_SERVERS = ("fake");
        LJ::MemCache::set_memcache($fake_memc);
        $cb->();
    }

    # restore our memcache client object from before.
    LJ::MemCache::set_memcache($pre_mem);
}

sub memcache_stress (&) {
    my $cb = shift;
    my $pre_mem = LJ::MemCache::get_memcache();
    my $fake_memc = LJ::Test::Mock::MemCache->new();

    # run the callback once with no memcache server existing
    {
        local @LJ::MEMCACHE_SERVERS = ();
        LJ::MemCache::init();
        $cb->();
    }

    # now set a memcache server, but a new empty one, and run it twice
    # so the second invocation presumably has stuff in the cache
    # from the first one
    {
        local @LJ::MEMCACHE_SERVERS = ("fake");
        LJ::MemCache::set_memcache($fake_memc);
        $cb->();
        $cb->();
    }

    # restore our memcache client object from before.
    LJ::MemCache::set_memcache($pre_mem);
}

sub alloc_sms_num {
    my $sms_num;

    for (1..100) {
        $sms_num = '+1';
        $sms_num .= int(rand(10)) foreach (1..10);
        return $sms_num unless LJ::SMS->num_to_uid($sms_num);
    }

    die "Unable to allocate SMS number after 100 tries";
}

sub create_post {
    my ( $class, %opts ) = @_;

    my $userid = delete $opts{userid} or die "Can't create post without userid";

    my $u = LJ::load_userid($userid) or die "Can't load user $userid";

    $u = bless { %$u }, 'LJ::Test::Mock::User';

    return $u->t_post_fake_entry(%opts);
}

sub create_comment {
    my ( $class, %opts ) = @_;

    my $entry = delete $opts{entry};

    $entry = bless { %$entry }, 'LJ::Test::Mock::Entry';

    return $entry->t_enter_comment(%opts);
}

sub create_application {
    my $class = shift;
    my %opts = @_;
    
    my $prefix = "t_" || $opts{prefix};

    $opts{application_key} ||= $prefix . LJ::rand_chars(8);
    $opts{name}            ||= $opts{application_key};
    $opts{type}            ||= 'E'; 
    $opts{status}          ||= 'A';

    unless ($opts{primary} || $opts{secondary} ) {
        $opts{primary}         = [@{$LJ::USERAPPS_ACCESS_LISTS}];
        $opts{secondary}       = [];
    } else {
        $opts{primary}         ||= [];
        $opts{secondary}       ||= [];
    }

    my $res = LJ::UserApps->add_application(%opts);

    if($res->{errors} && @{$res->{errors}}){
        die 'Application errors:'.Dumper($res->{errors});
    }

    my $app = $res->{application};

    $app->set_status($opts{status}) unless $opts{status} eq 'R';
    $app->set_primary($opts{primary}) if $opts{primary};
    $app->set_secondary($opts{secondary}) if $opts{secondary};
    
    my %have_access = map {$_ => 1} ( @{$opts{primary}}, @{$opts{secondary}} );

    $app->{non_access} = [ grep { ! $have_access{$_} } @{$LJ::USERAPPS_ACCESS_LISTS} ];

    return $app;
}

sub get_access_token {
    my $class = shift;
    my %opts = @_;
    $opts{access} ||= [];
    my $app = $opts{app} ? 
        $opts{app} : 
        LJ::UserApps::Application->new( id => $opts{application_id} );
    die "Application is not specified" unless $app;
    $app->authorize( userid => $opts{userid}, access => $opts{access} );
    my $token =  LJ::OAuth::AccessToken->generate(
                                                  consumer_key => $opts{consumer_key},
                                                  userid       => $opts{userid},
                                                  );
    return $token;
}

# Get Mock objects

sub get_mock_user($) {
    my ($args) = shift;
    return bless $args || {}, 'LJ::Test::Mock::User';
}

1;
