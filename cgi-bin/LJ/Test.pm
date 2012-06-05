# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#              WARNING! PELIGROSO! ACHTUNG! VNIMANIYE!
# some fools (aka mischa) try to use this library from web context,
# so make sure it's psuedo-safe to do so.  like don't class-autouse
# Test::FakeApache because that really fucks with things.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

package LJ::Test;
require Exporter;
use strict;

use base 'Exporter';

use Carp qw();
use DBI;

use LJ::ModuleCheck;

# TODO: use EXPORT_OK instead, do not clutter the caller's namespace
# unless asked to specifically
our @EXPORT = qw(
    memcache_stress with_fake_memcache temp_user
    temp_comm temp_feed alloc_sms_num fake_apache );

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

    my $u;

    if ( $journaltype eq 'P' ) {
        $u = LJ::User->create_personal(%opts);
    } elsif ( $journaltype eq 'C' ) {
        unless ( defined $opts{'owner'} ) {
            $opts{'owner'} = $class->create_user(
                %opts, 'journaltype' => 'P', 'user' => undef );
        }
        $opts{'membership'} ||= 'open';
        $opts{'postlevel'}  ||= 'members'; 
        $u = LJ::User->create_community(%opts);
    } elsif ( $journaltype eq 'Y' ) {
        unless ( defined $opts{'creator'} ) {
            $opts{'creator'} = $class->create_user(
                %opts, 'journaltype' => 'P', 'user' => undef );
        }

        $opts{'feedurl'} = "$LJ::SITEROOT/fakerss.xml#"
            unless defined $opts{'feedurl'};

        $u = LJ::User->create_syndicated(%opts);
    } else {
        die "unknown journaltype $journaltype";
    }

    # some hooks override this, so let's switch it back
    LJ::update_user( $u, { 'caps' => $opts{'caps'} } );

    if ($VERBOSE) {
        warn "created user $opts{'user'}\n";
    }

    if ( $opts{'temporary'} ) {
        push @temp_userids, $u->userid;
    }

    return $u;
}

sub temp_user {
    shift() if $_[0] eq __PACKAGE__;
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
    my $fake_memc = LJ::Test::FakeMemCache->new();
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
    my $fake_memc = LJ::Test::FakeMemCache->new();

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


sub create_application {
    my $class = shift;
    my %opts = @_;
    
    my $prefix = "t_" || $opts{prefix};

    $opts{application_key} ||= $prefix . LJ::rand_chars(8);
    $opts{name}            ||= $opts{application_key};
    $opts{type}            ||= 'E'; 

    my $res = LJ::UserApps->add_application(%opts);

    if($res->{errors} && @{$res->{errors}}){
        use Data::Dumper;
        die 'Application errors:'.Dumper($res->{errors});
    }
    
    return $res->{application};
}

package LJ::Test::FakeMemCache;
# duck-typing at its finest!
# this is a fake Cache::Memcached object which implements the
# memcached server locally in-process, for testing.  kinda,
# except it has no LRU or expiration times.

sub new {
    my ($class) = @_;
    return bless {
        'data' => {},
    }, $class;
}

sub add {
    my ($self, $fkey, $val, $exptime) = @_;
    my $key = _key($fkey);
    return 0 if exists $self->{data}{$key};
    $self->{data}{$key} = $val;
    return 1;
}

sub replace {
    my ($self, $fkey, $val, $exptime) = @_;
    my $key = _key($fkey);
    return 0 unless exists $self->{data}{$key};
    $self->{data}{$key} = $val;
    return 1;
}

sub incr {
    my ($self, $fkey, $optval) = @_;
    $optval ||= 1;
    my $key = _key($fkey);
    return 0 unless exists $self->{data}{$key};
    $self->{data}{$key} += $optval;
    return 1;
}

sub decr {
    my ($self, $fkey, $optval) = @_;
    $optval ||= 1;
    my $key = _key($fkey);
    return 0 unless exists $self->{data}{$key};
    $self->{data}{$key} -= $optval;
    return 1;
}

sub set {
    my ($self, $fkey, $val, $exptime) = @_;
    my $key = _key($fkey);
    $self->{data}{$key} = $val;
    return 1;
}

sub delete {
    my ($self, $fkey) = @_;
    my $key = _key($fkey);
    delete $self->{data}{$key};
    return 1;
}

sub get {
    my ($self, $fkey) = @_;
    my $key = _key($fkey);
    return $self->{data}{$key};
}

sub get_multi {
    my $self = shift;
    my $ret = {};
    foreach my $fkey (@_) {
        my $key = _key($fkey);
        $ret->{$key} = $self->{data}{$key} if exists $self->{data}{$key};
    }
    return $ret;
}

sub _key {
    my $fkey = shift;
    return $fkey->[1] if ref $fkey eq "ARRAY";
    return $fkey;
}

# tell LJ::MemCache::reload_conf not to call 'weird' methods on us
# that we don't simulate.
sub doesnt_want_configuration {
    1;
}

sub disconnect_all {}
sub forget_dead_hosts {}


package LJ::User;

# set the user up for sms
sub t_activate_sms {
    my ($u) = @_;
    $u->set_sms_number(
                       LJ::Test::alloc_sms_num(),
                       verified => 'Y'
                       );
}

# pretend the user sent us an SMS
sub t_receive_sms {
    my ($u, $message) = @_;

    my $msg = LJ::SMS::Message->new(
                                    owner => $u,
                                    from => $u,
                                    body_text => $message,
                                    );

    LJ::SMS::MessageHandler->handle($msg);
}

# post a fake entry in a community journal
sub t_post_fake_comm_entry {
    my $u = shift;
    my $comm = shift;
    my %opts = @_;

    # set the 'usejournal' and tell the protocol
    # to not do any checks for posting access
    $opts{usejournal} = $comm->{user};
    $opts{usejournal_okay} = 1;

    return $u->t_post_fake_entry(%opts);
}

# post a fake entry in this user's journal
sub t_post_fake_entry {
    my $u = shift;
    my %opts = @_;

    require 'ljprotocol.pl';

    my $security = delete $opts{security} || 'public';
    my $proto_sec = $security;
    if ($security eq "friends") {
        $proto_sec = "usemask";
    }

    my $subject = delete $opts{subject} || "test suite post.";
    my $body    = delete $opts{body}    || "This is a test post from $$ at " . time() . "\n";

    my %req = (
               mode => 'postevent',
               ver => $LJ::PROTOCOL_VER,
               user => $u->{user},
               password => '',
               event => $body,
               subject => $subject,
               tz => 'guess',
               security => $proto_sec,
               );

    $req{allowmask} = 1 if $security eq 'friends';

    my %res;
    my $flags = { noauth => 1, nomod => 1 };

    # pass-thru opts
    $req{usejournal} = $opts{usejournal} if $opts{usejournal};
    $flags->{usejournal_okay} = $opts{usejournal_okay} if $opts{usejournal_okay};

    LJ::do_request(\%req, \%res, $flags);

    die "Error posting: $res{errmsg}" unless $res{'success'} eq "OK";
    my $jitemid = $res{itemid} or die "No itemid";

    return LJ::Entry->new($u, jitemid => $jitemid);
}

package LJ::Entry;

# returns LJ::Comment object or dies on failure
sub t_enter_comment {
    my ($entry, %opts) = @_;
    my $jitemid = $entry->jitemid;

    require 'talklib.pl';

    # entry journal/u
    my $entryu = $entry->journal;

    # poster u
    my $u = delete $opts{u};
    $u = 0 unless ref $u;

    my $parent = delete $opts{parent};
    my $parenttalkid = $parent ? $parent->jtalkid : 0;

    # add some random stuff for dupe protection
    my $rand = "t=" . time() . " r=" . rand();

    my $subject = delete $opts{subject} || "comment subject [$rand]";
    my $body    = delete $opts{body} || "comment body\n\n$rand";

    my $err;

    my $commentref = {
        u => $u,
        state => 'A',
        subject => $subject,
        body => $body,
        %opts,
        parenttalkid => $parenttalkid,
    };

    LJ::Talk::Post::post_comment(
                                 $entry->poster,
                                 $entry->journal,
                                 $commentref,
                                 {talkid => $parenttalkid, state => 'A'},
                                 {itemid => $jitemid, state => 'A'},
                                 \$err,
                                 );

    my $jtalkid = $commentref->{talkid};

    die "Could not post comment: $err" unless $jtalkid;

    return LJ::Comment->new($entryu, jtalkid => $jtalkid);
}

package LJ::Comment;

# reply to a comment instance, takes same opts as LJ::Entry::t_enter_comment
sub t_reply {
    my ($comment, %opts) = @_;
    my $entry = $comment->entry;
    $opts{parent} = $comment;
    return $entry->t_enter_comment(%opts);
}

1;
