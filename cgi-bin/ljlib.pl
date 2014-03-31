package LJ;

use strict;
no warnings 'uninitialized';
use lib "$ENV{LJHOME}/cgi-bin";
use lib "$ENV{LJHOME}/src/s2";

use Carp;
use DBI;
use DBI::Role;
use Digest::MD5 ();
use Digest::SHA1 ();
use HTTP::Date ();
use LJ::MemCache;
use LJ::Error;
use LJ::Faq;
use LJ::User;      # has a bunch of pkg LJ, non-OO methods at bottom
use LJ::Entry;     # has a bunch of pkg LJ, non-OO methods at bottom
use LJ::Constants;
use LJ::User;
use LJ::Request;
use Time::Local ();
use Storable ();
use HTML::Entities ();
use LJ::Tags;

use Class::Autouse qw(
                      TheSchwartz
                      TheSchwartz::Job
                      LJ::AdTargetedInterests
                      LJ::Auth::Challenge
                      LJ::Comment
                      LJ::Knob
                      LJ::ExternalSite
                      LJ::ExternalSite::Vox
                      LJ::Message
                      LJ::EventLogSink
                      LJ::PageStats
                      LJ::AccessLogSink
                      LJ::ConvUTF8
                      LJ::Userpic
                      LJ::ModuleCheck
                      IO::Socket::INET
                      LJ::UniqCookie
                      LJ::WorkerResultStorage
                      LJ::EventLogRecord
                      LJ::EventLogRecord::DeleteComment
                      LJ::GraphicPreviews
                      LJ::Vertical
                      LJ::Browse
                      LJ::FriendsTags
                      LJ::MemCacheProxy
                      LJ::PushNotification::Storage
                    );

use LJ::Journal::FriendsFeed;
use LJ::TimeUtil;

# make Unicode::MapUTF8 autoload:
sub Unicode::MapUTF8::AUTOLOAD {
    die "Unknown subroutine $Unicode::MapUTF8::AUTOLOAD"
        unless $Unicode::MapUTF8::AUTOLOAD =~ /::(utf8_supported_charset|to_utf8|from_utf8)$/;
    LJ::ConvUTF8->load;
    no strict 'refs';
    goto *{$Unicode::MapUTF8::AUTOLOAD}{CODE};
}


sub END { LJ::end_request(); }

# tables on user databases (ljlib-local should define @LJ::USER_TABLES_LOCAL)
# this is here and no longer in bin/upgrading/update-db-{general|local}.pl
# so other tools (in particular, the inter-cluster user mover) can verify
# that it knows how to move all types of data before it will proceed.
@LJ::USER_TABLES = ("userbio", "birthdays", "cmdbuffer", "dudata",
                    "log2", "logleft", "logtext2", "logprop2", "logsec2",
                    "talk2", "talkprop2", "talktext2", "talkleft",
                    "userpicblob2", "subs", "subsprop", "has_subs",
                    "ratelog", "loginstall", "sessions", "sessions_data",
                    "s1usercache", "modlog", "modblob",
                    "userproplite2", "links", "s1overrides", "s1style",
                    "s1stylecache", "userblob", "userpropblob",
                    "clustertrack2", "captcha_session", "reluser2",
                    "tempanonips", "inviterecv", "invitesent",
                    "memorable2", "memkeyword2", "userkeywords",
                    "friendgroup2", "userpicmap2", "userpic2",
                    "s2stylelayers2", "s2compiled2", "userlog",
                    "logtags", "logtagsrecent", "logkwsum",
                    "recentactions", "usertags", "pendcomments",
                    "user_schools", "portal_config", "portal_box_prop",
                    "loginlog", "active_user", "userblobcache",
                    "notifyqueue", "cprod", "urimap",
                    "sms_msg", "sms_msgprop", "sms_msgack",
                    "sms_msgtext", "sms_msgerror",
                    "jabroster", "jablastseen", "random_user_set",
                    "poll2", "pollquestion2", "pollitem2",
                    "pollresult2", "pollsubmission2", "pollresultaggregated2",
                    "embedcontent", "usermsg", "usermsgtext", "usermsgprop", "usermsgbookmarks",
                    "notifyarchive", "notifybookmarks", "pollprop2", "embedcontent_preview",
                    "logprop_history",
                    "comet_history", "pingrel",
                    "eventrates", "eventratescounters",
                    "friending_actions_q", "delayedlog2", "delayedblob2",
                    "repost2", "subscriptionfilter2","pollsubmissionprop2",
                    "subscribers2", "subscribersleft", "usersingroups2"
                    );

# keep track of what db locks we have out
%LJ::LOCK_OUT = (); # {global|user} => caller_with_lock

require "ljdb.pl";
require "ljtextutil.pl";
require "ljcapabilities.pl";
require "ljmood.pl";
require "ljhooks.pl";
require "ljrelation.pl";
require "ljuserpics.pl";

require "$ENV{'LJHOME'}/cgi-bin/ljlib-local.pl"
    if -e "$ENV{'LJHOME'}/cgi-bin/ljlib-local.pl";

# if this is a dev server, alias LJ::D to Data::Dumper::Dumper
if ($LJ::IS_DEV_SERVER) {
    require "Data/Dumper.pm";
    *LJ::D = \&Data::Dumper::Dumper;
} else {
    *LJ::D = sub { };
}

LJ::MemCache::init();

# $LJ::PROTOCOL_VER is the version of the client-server protocol
# used uniformly by server code which uses the protocol.
$LJ::PROTOCOL_VER = ($LJ::UNICODE ? "1" : "0");

my $__dynamic_enable = {};

# declare views (calls into ljviews.pl)
@LJ::views = qw(lastn friends calendar day);
%LJ::viewinfo = (
                 "lastn" => {
                     "creator" => \&LJ::S1::create_view_lastn,
                     "des" => "Most Recent Events",
                 },
                 "calendar" => {
                     "creator" => \&LJ::S1::create_view_calendar,
                     "des" => "Calendar",
                 },
                 "day" => {
                     "creator" => \&LJ::S1::create_view_day,
                     "des" => "Day View",
                 },
                 "friends" => {
                     "creator" => \&LJ::S1::create_view_friends,
                     "des" => "Friends View",
                     "owner_props" => ["opt_usesharedpic", "friendspagetitle"],
                 },
                 "friendsfriends" => {
                     "creator" => \&LJ::S1::create_view_friends,
                     "des" => "Friends of Friends View",
                     "styleof" => "friends",
                 },
                 "data" => {
                     "creator" => \&LJ::Feed::create_view,
                     "des" => "Data View (RSS, etc.)",
                     "owner_props" => ["opt_whatemailshow", "no_mail_alias"],
                 },
                 "rss" => {  # this is now provided by the "data" view.
                     "des" => "RSS View (XML)",
                 },
                 "res" => {
                     "des" => "S2-specific resources (stylesheet)",
                 },
                 "pics" => {
                     "des" => "FotoBilder pics (root gallery)",
                 },
                 "info" => {
                     # just a redirect to userinfo.bml for now.
                     # in S2, will be a real view.
                     "des" => "Profile Page",
                 },
                 "profile" => {
                     # just a redirect to userinfo.bml for now.
                     # in S2, will be a real view.
                     "des" => "Profile Page",
                 },
                 "wishlist" => {
                     # just a redirect to wishlist.bml.
                     "des" => "WishList Page",
                 },
                 "tag" => {
                     "des" => "Filtered Recent Entries View",
                 },
                 "security" => {
                     "des" => "Filtered Recent Entries View",
                 },
                 "update" => {
                     # just a redirect to update.bml for now.
                     # real solution is some sort of better nav
                     # within journal styles.
                     "des" => "Update Journal",
                 },
                 );

## we want to set this right away, so when we get a HUP signal later
## and our signal handler sets it to true, perl doesn't need to malloc,
## since malloc may not be thread-safe and we could core dump.
## see LJ::clear_caches and LJ::handle_caches
$LJ::CLEAR_CACHES = 0;

# DB Reporting UDP socket object
$LJ::ReportSock = undef;

# DB Reporting handle collection. ( host => $dbh )
%LJ::DB_REPORT_HANDLES = ();

my $GTop;     # GTop object (created if $LJ::LOG_GTOP is true)

## if this library is used in a BML page, we don't want to destroy BML's
## HUP signal handler.
if ($SIG{'HUP'}) {
    my $oldsig = $SIG{'HUP'};
    $SIG{'HUP'} = sub {
        &{$oldsig};
        LJ::clear_caches();
    };
} else {
    $SIG{'HUP'} = \&LJ::clear_caches;
}

sub get_user_by_url
{
    my $url = shift;

    my $username = '';

    # drop protocol
    $url =~ s/http(?:s)?:\/\///;

    #try to get username from domain name
    if ($url =~ /^([\w\-]{1,15})\.\Q$LJ::USER_DOMAIN\E/ &&
        $1 ne "www"
    )
    {
        my $user = $1;

        # see if the "user" is really functional code
        my $func = $LJ::SUBDOMAIN_FUNCTION{$user};
        my $uri = '';
        if ($func eq "journal") {
            ($user, $uri) = $url =~ m!^[\w\-]{1,15}\.\Q$LJ::USER_DOMAIN\E/(\w{1,15})(/.*)?$!;
            $uri ||= "/";
        }

        my $u = LJ::load_user($user);
        if ($u && $u->{'journaltype'} eq 'R' && $u->{'statusvis'} eq 'R') {
            LJ::load_user_props($u, 'renamedto');
            my $renamedto = $u->{'renamedto'};
            if ($renamedto ne '') {
                $username = $renamedto;
            }
        } elsif ($u) {
            $username = $u->user;
        }
    }

    # try to find userid in user domains
    unless ($username) {
        my $dbr = LJ::get_db_reader();
        my ($checkhost) = $url =~ /^([\w\-.]+\.\Q$LJ::USER_DOMAIN\E)/;
        $checkhost = lc($checkhost);
        $checkhost =~ s/^www\.//i;
        return unless $checkhost;
        $checkhost = $dbr->quote($checkhost);
        my $user = $dbr->selectrow_array(qq{
            SELECT u.user FROM useridmap u, domains d WHERE
            u.userid=d.userid AND d.domain=$checkhost
        });
        $username = $user if $user;
    }
    return $username;
}

sub get_blob_domainid
{
    my $name = shift;
    my $id = {
        "userpic" => 1,
        "phonepost" => 2,
        "captcha_audio" => 3,
        "captcha_image" => 4,
        "fotobilder" => 5,
        "photoalbums" => 6,
    }->{$name};
    # FIXME: add hook support, so sites can't define their own
    # general code gets priority on numbers, say, 1-200, so verify
    # hook returns a number 201-255
    return $id if $id;
    die "Unknown blob domain: $name";
}

sub _using_blockwatch {
    if (LJ::conf_test($LJ::DISABLED{blockwatch})) {
        # Config override to disable blockwatch.
        return 0;
    }

    unless (LJ::ModuleCheck->have('LJ::Blockwatch')) {
        # If we don't have or are unable to load LJ::Blockwatch, then give up too
        return 0;
    }
    return 1;
}

sub locker {
    return $LJ::LOCKER_OBJ if $LJ::LOCKER_OBJ;
    eval "use DDLockClient ();";
    die "Couldn't load locker client: $@" if $@;

    $LJ::LOCKER_OBJ =
        new DDLockClient (
                          servers => [ @LJ::LOCK_SERVERS ],
                          lockdir => $LJ::LOCKDIR || "$LJ::HOME/locks",
                          );

    if (_using_blockwatch()) {
        eval { LJ::Blockwatch->setup_ddlock_hooks($LJ::LOCKER_OBJ) };

        warn "Unable to add Blockwatch hooks to DDLock client object: $@"
            if $@;
    }

    return $LJ::LOCKER_OBJ;
}

sub gearman_client {
    my $purpose = shift;

    return undef unless @LJ::GEARMAN_SERVERS;
    eval "use Gearman::Client; 1;" or die "No Gearman::Client available: $@";

    my $client = Gearman::Client->new;
    $client->job_servers(@LJ::GEARMAN_SERVERS);

    if (_using_blockwatch()) {
        eval { LJ::Blockwatch->setup_gearman_hooks($client) };

        warn "Unable to add Blockwatch hooks to Gearman client object: $@"
            if $@;
    }

    return $client;
}

sub mogclient {
    my (%opts) = @_;

    my $domain = $opts{'domain'} || $LJ::MOGILEFS_CONFIG{'domain'};

    return unless %LJ::MOGILEFS_CONFIG;

    unless ( $LJ::MogileFS{$domain} ) {
        require MogileFS::Client;

        my $mogclient = MogileFS::Client->new(
            'domain'   => $domain,
            'root'     => $LJ::MOGILEFS_CONFIG{'root'},
            'hosts'    => $LJ::MOGILEFS_CONFIG{'hosts'},
            'readonly' => $LJ::DISABLE_MEDIA_UPLOADS,
            'timeout'  => $LJ::MOGILEFS_CONFIG{'timeout'} || 3,
        );

        die 'Could not initialize MogileFS' unless $mogclient;

        # set preferred ip list if we have one
        $mogclient->set_pref_ip(\%LJ::MOGILEFS_PREF_IP)
            if %LJ::MOGILEFS_PREF_IP;

        if (_using_blockwatch()) {
            eval { LJ::Blockwatch->setup_mogilefs_hooks($mogclient) };

            warn "Unable to add Blockwatch hooks to MogileFS client object: $@"
                if $@;
        }

        $LJ::MogileFS{$domain} = $mogclient;
    }

    return $LJ::MogileFS{$domain};
}

sub theschwartz {
    my $opts = shift;

    return LJ::Test->theschwartz() if $LJ::_T_FAKESCHWARTZ;

    if (%LJ::THESCHWARTZ_DBS_ROLES) {
        ## new config - with roles
        my $role = $opts->{'role'} || $LJ::THESCHWARTZ_ROLE_DEFAULT;
        return $LJ::SchwartzClient{$role} if $LJ::SchwartzClient{$role};

        my @dbs;
        die "LJ::theschwartz(): unknown role '$role'" unless $LJ::THESCHWARTZ_DBS_ROLES{$role};
        foreach my $name (@{ $LJ::THESCHWARTZ_DBS_ROLES{$role} }) {
            die "LJ::theschwartz(): unknown database name '$name' in role '$role'"
                unless $LJ::THESCHWARTZ_DBS{$name};
            push @dbs, $LJ::THESCHWARTZ_DBS{$name};
        }
        die "LJ::theschwartz(): no databases for role '$role'" unless @dbs;

        my $client = TheSchwartz->new(databases => \@dbs);

        if ($client && $client->can('delete_every_n_errors')) {
            $client->delete_every_n_errors($LJ::DELETE_EVERY_N_ERRORS);
        }

        $LJ::SchwartzClient{$role} = $client;
        return $client;
    } else {
        ## old config
        $LJ::SchwartzClient ||= TheSchwartz->new(databases => \@LJ::THESCHWARTZ_DBS);
        return $LJ::SchwartzClient;
    }
}

sub sms_gateway {
    my $conf_key = shift;

    # effective config key is 'default' if one wasn't specified or nonexistent
    # config was specified, meaning fall back to default
    unless ($conf_key && $LJ::SMS_GATEWAY_CONFIG{$conf_key}) {
        $conf_key = 'default';
    }

    return $LJ::SMS_GATEWAY{$conf_key} ||= do {
        my $class = "DSMS::Gateway" .
            ($LJ::SMS_GATEWAY_TYPE ? "::$LJ::SMS_GATEWAY_TYPE" : "");

        eval "use $class";
        die "unable to use $class: $@" if $@;

        $class->new(config => $LJ::SMS_GATEWAY_CONFIG{$conf_key});
    };
}

sub gtop {
    return unless $LJ::LOG_GTOP && LJ::ModuleCheck->have("GTop");
    return $GTop ||= GTop->new;
}

# <LJFUNC>
# name: LJ::get_newids
# des: Lookup an old global ID and see what journal it belongs to and its new ID.
# info: Interface to [dbtable[oldids]] table (URL compatability)
# returns: Undef if non-existent or unconverted, or arrayref of [$userid, $newid].
# args: area, oldid
# des-area: The "area" of the id.  Legal values are "L" (log), to lookup an old itemid,
#           or "T" (talk) to lookup an old talkid.
# des-oldid: The old globally-unique id of the item.
# </LJFUNC>
sub get_newids
{
    my $sth;
    my $db = LJ::get_dbh("oldids") || LJ::get_db_reader();
    return $db->selectrow_arrayref("SELECT userid, newid FROM oldids ".
                                   "WHERE area=? AND oldid=?", undef,
                                   $_[0], $_[1]);
}

# <LJFUNC>
# name: LJ::get_timeupdate_multi
# des: Get the last time a list of users updated.
# args: opt?, uids
# des-opt: optional hashref, currently can contain 'memcache_only'
#          to only retrieve data from memcache
# des-uids: list of userids to load timeupdates for
# returns: hashref; uid => unix timeupdate
# </LJFUNC>
sub get_timeupdate_multi {
    my ($opt, @uids) = @_;

    # allow optional opt hashref as first argument
    if ($opt && ref $opt ne 'HASH') {
        push @uids, $opt;
        $opt = {};
    }
    return {} unless @uids;

    my @memkeys = map { [$_, "tu:$_"] } @uids;
    my $mem = LJ::MemCache::get_multi_async(@memkeys) || {};

    my @need;
    my %timeupdate; # uid => timeupdate
    foreach (@uids) {
        if ($mem->{"tu:$_"}) {
            $timeupdate{$_} = unpack("N", $mem->{"tu:$_"});
        } else {
            push @need, $_;
        }
    }

    # if everything was in memcache, return now
    return \%timeupdate if $opt->{'memcache_only'} || ! @need;

    # fill in holes from the database.  safe to use the reader because we
    # only do an add to memcache, whereas postevent does a set, overwriting
    # any potentially old data
    my $dbr = LJ::get_db_reader();
    my $need_bind = join(",", map { "?" } @need);
    my $sth = $dbr->prepare("SELECT userid, UNIX_TIMESTAMP(timeupdate) " .
                            "FROM userusage WHERE userid IN ($need_bind)");
    $sth->execute(@need);
    while (my ($uid, $tu) = $sth->fetchrow_array) {
        $timeupdate{$uid} = $tu;

        # set memcache for this row
        LJ::MemCache::add([$uid, "tu:$uid"], pack("N", $tu), 30*60);
    }

    return \%timeupdate;
}





# <LJFUNC>
# name: LJ::get_times_multi
# des: Get the last update time and time create.
# args: opt?, uids
# des-opt: optional hashref, currently can contain 'memcache_only'
#          to only retrieve data from memcache
# des-uids: list of userids to load timeupdate and timecreate for
# returns: hashref; uid => {timeupdate => unix timeupdate, timecreate => unix timecreate}
# </LJFUNC>
sub get_times_multi {
    my ($opt, @uids) = @_;

    # allow optional opt hashref as first argument
    unless (ref $opt eq 'HASH') {
        push @uids, $opt;
        $opt = {};
    }
    return {} unless @uids;

    my @memkeys = map { [$_, "tu:$_"], [$_, "tc:$_"] } @uids;
    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    my @need  = ();
    my %times = ();
    foreach my $uid (@uids) {
        my ($tc, $tu) = ('', '');
        if ($tu = $mem->{"tu:$uid"}) {
            $times{updated}->{$uid} = unpack("N", $tu);
        }
        if ($tc = $mem->{"tc:$_"}){
            $times{created}->{$_} = $tc;
        }

        push @need => $uid
            unless $tc and $tu;
    }

    # if everything was in memcache, return now
    return \%times if $opt->{'memcache_only'} or not @need;

    # fill in holes from the database.  safe to use the reader because we
    # only do an add to memcache, whereas postevent does a set, overwriting
    # any potentially old data
    my $dbr = LJ::get_db_reader();
    my $need_bind = join(",", map { "?" } @need);

    # Fetch timeupdate and timecreate from DB.
    # Timecreate is loaded in pre-emptive goals.
    # This is tiny optimization for 'get_timecreate_multi',
    # which is called right after this method during
    # friends page generation.
    my $sth = $dbr->prepare("
        SELECT userid,
               UNIX_TIMESTAMP(timeupdate),
               UNIX_TIMESTAMP(timecreate)
        FROM   userusage
        WHERE
               userid IN ($need_bind)");
    $sth->execute(@need);
    while (my ($uid, $tu, $tc) = $sth->fetchrow_array){
        $times{updated}->{$uid} = $tu;
        $times{created}->{$uid} = $tc;

        # set memcache for this row
        LJ::MemCache::add([$uid, "tu:$uid"], pack("N", $tu), 30*60);
        # set this for future use
        LJ::MemCache::add([$uid, "tc:$uid"], $tc, 60*60*24); # as in LJ::User->timecreate
    }

    return \%times;
}

# <LJFUNC>
# name: LJ::get_friend_items
# des: Return friend items for a given user, filter, and period.
# args: opts
# des-opts: Hashref of options:
#           - userid
#           - remoteid
#           - itemshow
#           - skip
#           - filter  (opt) defaults to all
#           - friends (opt) friends rows loaded via [func[LJ::get_friends]]
#           - friends_u (opt) u objects of all friends loaded
#           - idsbycluster (opt) hashref to set clusterid key to [ [ journalid, itemid ]+ ]
#           - dateformat:  either "S2" for S2 code, or anything else for S1
#           - common_filter:  set true if this is the default view
#           - friendsoffriends: load friends of friends, not just friends
#           - u: hashref of journal loading friends of
#           - showtypes: /[PICNY]/
# returns: Array of item hashrefs containing the same elements
# </LJFUNC>
sub get_friend_items {
    my ($opts) = @_;
    return LJ::Journal::FriendsFeed::LegacyAPI->get_items($opts);
}

# <LJFUNC>
# name: LJ::get_recent_items
# class:
# des: Returns journal entries for a given account.
# info:
# args: opts
# des-opts: Hashref of options with keys:
#           -- err: scalar ref to return error code/msg in
#           -- userid
#           -- remote: remote user's $u
#           -- remoteid: id of remote user
#           -- tagids: arrayref of tagids to return entries with
#           -- security: (public|friends|private) or a group number
#           -- clustersource: if value 'slave', uses replicated databases
#           -- order: if 'logtime', sorts by logtime, not eventtime
#           -- friendsview: if true, sorts by logtime, not eventtime
#           -- notafter: upper bound inclusive for rlogtime/revttime (depending on sort mode),
#              defaults to no limit
#           -- afterid: upper bound inclusive for jitemid. defaults to not use
#           -- skip: items to skip
#           -- itemshow: items to show
#           -- viewall: if set, no security is used.
#           -- viewsome: if set, suspended flag is not used
#           -- dateformat: if "S2", uses S2's 'alldatepart' format.
#           -- itemids: optional arrayref onto which itemids should be pushed
#           -- posterid: [userid] optional, return (community) posts made by this poster only
#           -- poster: [username] optional, return (community) posts made by this poster only
#              returns: array of hashrefs containing keys:
#           -- itemid (the jitemid)
#           -- posterid
#           -- security
#           -- alldatepart (in S1 or S2 fmt, depending on 'dateformat' req key)
#           -- system_alldatepart (same as above, but for the system time)
#           -- ownerid (if in 'friendsview' mode)
#           -- rlogtime (if in 'friendsview' mode)
#           -- entry_objects: optional arrayref onto which LJ::Entry objects should be pushed
#           -- load_props: if set, objects into entry_objects comes whis preloaded props
#           -- load_text: if set, objects into entry_objects comes whis preloaded text
# </LJFUNC>
sub get_recent_items {
    my $opts = shift;

    my $sth;

    my @items = ();             # what we'll return
    my $err = $opts->{'err'};

    my $userid = $opts->{'userid'}+0;
    my $u = LJ::load_userid($userid)
        or die "No such userid: $userid";

    # 'remote' opt takes precendence, then 'remoteid'
    my $remote = $opts->{'remote'};
    my $remoteid = $remote ? $remote->{'userid'} : 0;
    if ($remoteid == 0 && $opts->{'remoteid'}) {
        $remoteid = $opts->{'remoteid'} + 0;
        $remote = LJ::load_userid($remoteid);
    }

    my $show_sticky_on_top = $opts->{show_sticky_on_top} || 0;
    $show_sticky_on_top &= LJ::is_enabled("delayed_entries");

    my $max_hints = $LJ::MAX_SCROLLBACK_LASTN;  # temporary
    my $sort_key = "revttime";

    my $logdb = LJ::get_cluster_def_reader($u);

    # community/friend views need to post by log time, not event time
    $sort_key = "rlogtime" if ($opts->{'order'} eq "logtime" ||
                               $opts->{'friendsview'});

    # 'notafter':
    #   the friends view doesn't want to load things that it knows it
    #   won't be able to use.  if this argument is zero or undefined,
    #   then we'll load everything less than or equal to 1 second from
    #   the end of time.  we don't include the last end of time second
    #   because that's what backdated entries are set to.  (so for one
    #   second at the end of time we'll have a flashback of all those
    #   backdated entries... but then the world explodes and everybody
    #   with 32 bit time_t structs dies)
    my $notafter = $opts->{'notafter'} + 0 || $LJ::EndOfTime - 1;

    # sticky entries array
    my $sticky = $u->get_sticky_entry_id();

    my $skip = $opts->{'skip'}+0;
    my $itemshow = $opts->{'itemshow'}+0 || 10;
    if ($itemshow > $max_hints) { $itemshow = $max_hints; }
    my $maxskip = $max_hints - $itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }
    my $itemload = $itemshow + $skip;
    my $usual_show  = $itemshow;
    my $skip_sticky = $skip;

    if ( $show_sticky_on_top && $sticky ) {
        if($skip > 0) {
            $skip -= 1;
        } else {
            $usual_show -= 1;
        }
    }

    my $mask = 0;
    if ($remote && ($remote->{'journaltype'} eq "P" ||
        $remote->{'journaltype'} eq "I") && $remoteid != $userid) {
        $mask = LJ::get_groupmask($userid, $remoteid);
    }

    # decide what level of security the remote user can see
    my $secwhere = "";
    if ($remote && $remote->can_manage($userid) || $opts->{'viewall'}) {
        # no extra where restrictions... user can see all their own stuff
        # alternatively, if 'viewall' opt flag is set, security is off.
    } elsif ($mask) {
        # can see public or things with them in the mask
        $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $mask != 0) OR posterid = $remoteid)";
    } else {
        # not a friend?  only see public.
        $secwhere = "AND (security='public' OR posterid=$remoteid)";
    }

    my $suspend_where = "";
    unless ($opts->{'viewall'} || $opts->{'viewsome'}) {
        $suspend_where = "AND (compressed != 'S' OR posterid = $remoteid)";
    }

    # because LJ::get_friend_items needs rlogtime for sorting.
    my $extra_sql;
    if ($opts->{'friendsview'}) {
        $extra_sql .= "journalid AS 'ownerid', rlogtime, ";
    }

    # if we need to get by tag, get an itemid list now
    my $jitemidwhere;
    if (ref $opts->{tagids} eq 'ARRAY' && @{$opts->{tagids}}) {

        my $jitemids;

        # $opts->{tagmode} = $opts->{getargs}->{mode} eq 'and' ? 'and' : 'or';

        if ($opts->{tagmode} eq 'and') {

            my $limit = $LJ::TAG_INTERSECTION;
            $#{$opts->{tagids}} = $limit - 1 if @{$opts->{tagids}} > $limit;
            my $in = join(',', map { $_+0 } @{$opts->{tagids}});
            my $sth = $logdb->prepare("SELECT jitemid, kwid FROM logtagsrecent WHERE journalid = ? AND kwid IN ($in)");
            $sth->execute($userid);
            die $logdb->errstr if $logdb->err;

            my %mix;
            while (my $row = $sth->fetchrow_arrayref) {
                my ($jitemid, $kwid) = @$row;
                $mix{$jitemid}++;
            }

            my $need = @{$opts->{tagids}};
            foreach my $jitemid (keys %mix) {
                delete $mix{$jitemid} if $mix{$jitemid} < $need;
            }

            $jitemids = [keys %mix];

        } else { # mode: 'or'
            # select jitemids uniquely
            my $in = join(',', map { $_+0 } @{$opts->{tagids}});
            $jitemids = $logdb->selectcol_arrayref(qq{
                    SELECT DISTINCT jitemid FROM logtagsrecent WHERE journalid = ? AND kwid IN ($in)
                }, undef, $userid);
            die $logdb->errstr if $logdb->err;
        }

        # set $jitemidwhere iff we have jitemids
        if (@$jitemids) {
            $jitemidwhere = " AND jitemid IN (" .
                            join(',', map { $_ + 0 } @$jitemids) .
                            ")";
        } else {
            # no items, so show no entries
            return ();
        }
    }

    # if we need to filter by security, build up the where clause for that too
    my $securitywhere;
    if ($opts->{'security'}) {
        my $security = $opts->{'security'};
        if (($security eq "public") || ($security eq "private")) {
            $securitywhere = " AND security = \"$security\"";
        }
        elsif ($security eq "friends") {
            $securitywhere = " AND security = \"usemask\" AND allowmask = 1";
        }
        elsif ($security=~/^\d+$/) {
            $securitywhere = " AND security = \"usemask\" AND (allowmask & " . (1 << $security) . ")";
        }
    }

    my $sql;
    my $sticky_sql;

    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    if ($opts->{'dateformat'} eq "S2") {
        $dateformat = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    }

    my ($sql_limit, $sql_select) = ('', '');
    if ($opts->{'ymd'}) {
        my ($year, $month, $day);
        if ($opts->{'ymd'} =~ m!^(\d\d\d\d)/(\d\d)/(\d\d)\b!) {
            ($year, $month, $day) = ($1, $2, $3);
            # check
            if ($year !~ /^\d+$/) { $$err = "Corrupt or non-existant year."; return (); }
            if ($month !~ /^\d+$/) { $$err = "Corrupt or non-existant month." ; return (); }
            if ($day !~ /^\d+$/) { $$err = "Corrupt or non-existant day." ; return (); }
            if ($month < 1 || $month > 12 || int($month) != $month) { $$err = "Invalid month." ; return (); }
            if ($year < 1970 || $year > 2038 || int($year) != $year) { $$err = "Invalid year: $year"; return (); }
            if ($day < 1 || $day > 31 || int($day) != $day) { $$err = "Invalid day."; return (); }
            if ($day > LJ::TimeUtil->days_in_month($month, $year)) { $$err = "That month doesn't have that many days."; return (); }
        } else {
            $$err = "wrong date: " . $opts->{'ymd'};
            return ();
        }
        $sql_limit  = "LIMIT 200";
        $sql_select = "AND year=$year AND month=$month AND day=$day";
        $extra_sql .= "allowmask, ";
    } else {
        $sql_limit  = "LIMIT $skip, $usual_show";
        $sql_select = "AND $sort_key <= $notafter";
    }

    my $after_sql = '';
    my $afterid = $opts->{'afterid'} + 0;
    if ($afterid) {
        $after_sql = "AND jitemid > $afterid";
    }

    my $before_sql = '';
    my $beforeid = $opts->{'beforeid'} + 0;
    if ($beforeid) {
        $before_sql = "AND jitemid < $beforeid";
    }

    my $exclude_sql = '';
    my $excludeid = $opts->{'excludeid'} + 0;
    if ($excludeid) {
        $exclude_sql = "AND jitemid != $excludeid";
    }

    my $posterwhere;
    if ($opts->{'posterid'} && $opts->{'posterid'} =~ /^(\d+)$/) {
        $posterwhere = " AND posterid=$1";
    } elsif ($opts->{'poster'}) {
        my $posteru = LJ::load_user($opts->{'poster'});
        unless ($posteru) {
            ## silently drop the error, since S2 can't handle it nicely (it dies)
            ## $$err = "No such user: " . LJ::ehtml($opts->{'poster'}) if ref $err eq "SCALAR";
            return;
        }
        $posterwhere = " AND posterid=$posteru->{userid}";
    } else {
        $posterwhere = '';
    }

    my $time_filter = '';
    if ( $opts->{time_begin} && $opts->{time_end} ) {
        my $time_what  = $opts->{time_limitby} &&  $opts->{time_limitby} eq 'eventtime' ? 'revttime' : 'rlogtime';
        my $time_begin = $LJ::EndOfTime - LJ::TimeUtil->mysqldate_to_time($opts->{time_begin});
        my $time_end   = $LJ::EndOfTime - LJ::TimeUtil->mysqldate_to_time($opts->{time_end});
        $time_filter = sprintf("AND $time_what < %s AND $time_what > %s ",
            $time_begin, $time_end );
    }

    $sql = qq{
        SELECT jitemid AS 'itemid', posterid, security, $extra_sql
               DATE_FORMAT(eventtime, "$dateformat") AS 'alldatepart', anum,
               DATE_FORMAT(logtime, "$dateformat") AS 'system_alldatepart',
               allowmask, eventtime, logtime
        FROM log2
        WHERE journalid=$userid $sql_select $secwhere $jitemidwhere $securitywhere $posterwhere $time_filter $after_sql $before_sql $exclude_sql $suspend_where
    };

    if ( $sticky && $show_sticky_on_top ) {
        if ( !$skip_sticky ) {
            my $entry = LJ::Entry->new( $u, 'jitemid' => $sticky );
            if ($entry && $entry->valid) {
                my $alldatepart;
                my $system_alldatepart;

                if ($opts->{'dateformat'} eq "S2") {
                    $alldatepart = LJ::TimeUtil->alldatepart_s2($entry->eventtime_mysql);
                    $system_alldatepart = LJ::TimeUtil->alldatepart_s2($entry->logtime_mysql);
                } else {
                    $alldatepart = LJ::TimeUtil->alldatepart_s1($entry->eventtime_mysql);
                    $system_alldatepart = LJ::TimeUtil->alldatepart_s1($entry->logtime_mysql);
                }

                my $item = { 'itemid' => $sticky,
                             'alldatepart'   => $alldatepart,
                             'allowmask'     => $entry->allowmask,
                             'posterid'      => $entry->posterid,
                             'eventtime'     => $entry->eventtime_mysql,
                             'system_alldatepart' => $system_alldatepart,
                             'security'           => $entry->security,
                             'anum'               => $entry->anum,
                             'logtime'            => $entry->logtime_mysql, };

                push @items, $item;
                push @{$opts->{'entry_objects'}}, $item;
                push @{$opts->{'itemids'}}, $entry->jitemid;
            }
        }

        # sticky exculustion
        $sql .= "AND jitemid <> $sticky";
    }

    $sql .= qq{
        ORDER BY journalid, $sort_key
        $sql_limit };

    unless ($logdb) {
        $$err = "nodb" if ref $err eq "SCALAR";
        return ();
    }

    my $last_time;
    my @buf;

    my $flush = sub {
        return unless @buf;
        push @items, sort { $b->{itemid} <=> $a->{itemid} } @buf;
        @buf = ();
    };

    my $absorb_data = sub {
        my ($sql_request) = @_;
        $sth = $logdb->prepare($sql_request);
        $sth->execute;
        if ($logdb->err) { die $logdb->errstr; }

        # keep track of the last alldatepart, and a per-minute buffer
        while (my $li = $sth->fetchrow_hashref) {
            push @{$opts->{'itemids'}}, $li->{'itemid'};

            $flush->() if $li->{alldatepart} ne $last_time;
            push @buf, $li;
            $last_time = $li->{alldatepart};

            # construct an LJ::Entry singleton
            my $entry = LJ::Entry->new($userid,
                                        jitemid  => $li->{itemid},
                                        rlogtime => $li->{rlogtime},
                                        row      => $li);
            push @{$opts->{'entry_objects'}}, $entry;
        }
    };

    $absorb_data->($sql);
    $flush->();

    if ( exists $opts->{load_props} && $opts->{load_props} ) {
        my %logprops = ();
        LJ::load_log_props2($userid, $opts->{'itemids'}, \%logprops);

        for my $Entry ( @{$opts->{'entry_objects'}} ) {
            $Entry->handle_prefetched_props($logprops{$Entry->{jitemid}});
        }
    }

    if ( exists $opts->{load_text} && $opts->{load_text} ) {
        my $texts = LJ::get_logtext2($u, @{$opts->{'itemids'}});

        for my $Entry ( @{$opts->{'entry_objects'}} ) {
            $Entry->handle_prefetched_text( $texts->{ $Entry->{jitemid} }->[0], $texts->{ $Entry->{jitemid} }->[1] );
        }
    }

    if ( exists $opts->{load_tags} && $opts->{load_tags} ) {
        my $tags = LJ::Tags::get_logtagsmulti( { $u->clusterid => [ map { [ $userid, $_ ] } @{$opts->{'itemids'}} ] } );

        for my $Entry ( @{$opts->{'entry_objects'}} ) {
            $Entry->handle_prefetched_tags( $tags->{ $userid.' '.$Entry->{jitemid} } );
        }
    }

    return @items;
}

# <LJFUNC>
# name: LJ::register_authaction
# des: Registers a secret to have the user validate.
# info: Some things, like requiring a user to validate their e-mail address, require
#       making up a secret, mailing it to the user, then requiring them to give it
#       back (usually in a URL you make for them) to prove they got it.  This
#       function creates a secret, attaching what it's for and an optional argument.
#       Background maintenance jobs keep track of cleaning up old unvalidated secrets.
# args: userid, action, arg?
# des-userid: Userid of user to register authaction for.
# des-action: Action type to register.   Max chars: 50.
# des-arg: Optional argument to attach to the action.  Max chars: 255.
# returns: 0 if there was an error.  Otherwise, a hashref
#          containing keys 'aaid' (the authaction ID) and the 'authcode',
#          a 15 character string of random characters from
#          [func[LJ::make_auth_code]].
# </LJFUNC>
sub register_authaction {
    my $dbh = LJ::get_db_writer();

    my $userid = shift;  $userid += 0;
    my $action = $dbh->quote(shift);
    my $arg1 = $dbh->quote(shift);

    # make the authcode
    my $authcode = LJ::make_auth_code(15);
    my $qauthcode = $dbh->quote($authcode);

    $dbh->do("INSERT INTO authactions (aaid, userid, datecreate, authcode, action, arg1) ".
             "VALUES (NULL, $userid, NOW(), $qauthcode, $action, $arg1)");

    return 0 if $dbh->err;
    return { 'aaid' => $dbh->{'mysql_insertid'},
             'authcode' => $authcode,
         };
}

sub get_authaction {
    my ($id, $action, $arg1, $opts) = @_;

    my $dbh = $opts->{force} ? LJ::get_db_writer() : LJ::get_db_reader();
    return $dbh->selectrow_hashref("SELECT aaid, authcode, datecreate FROM authactions " .
                                   "WHERE userid=? AND arg1=? AND action=? AND used='N' LIMIT 1",
                                   undef, $id, $arg1, $action);
}


# <LJFUNC>
# class: logging
# name: LJ::statushistory_add
# des: Adds a row to a user's statushistory
# info: See the [dbtable[statushistory]] table.
# returns: boolean; 1 on success, 0 on failure
# args: userid, adminid, shtype, notes?
# des-userid: The user being acted on.
# des-adminid: The site admin doing the action.
# des-shtype: The status history type code.
# des-notes: Optional notes associated with this action.
# </LJFUNC>
sub statushistory_add {
    my $dbh = LJ::get_db_writer();

    my $userid = shift;
    $userid = LJ::want_userid($userid) + 0;

    my $actid  = shift;
    $actid = LJ::want_userid($actid) + 0;

    my $qshtype = $dbh->quote(shift);
    my $qnotes  = $dbh->quote(shift);

    $dbh->do("INSERT INTO statushistory (userid, adminid, shtype, notes) ".
             "VALUES ($userid, $actid, $qshtype, $qnotes)");
    return $dbh->err ? 0 : 1;
}

# <LJFUNC>
# name: LJ::make_link
# des: Takes a group of key=value pairs to append to a URL.
# returns: The finished URL.
# args: url, vars
# des-url: A string with the URL to append to.  The URL
#          should not have a question mark in it.
# des-vars: A hashref of the key=value pairs to append with.
# </LJFUNC>
sub make_link
{
    my $url = shift;
    my $vars = shift;
    my $append = "?";
    foreach (keys %$vars) {
        next if ($vars->{$_} eq "");
        $url .= "${append}${_}=$vars->{$_}";
        $append = "&";
    }
    return $url;
}

# <LJFUNC>
# name: LJ::get_authas_user
# des: Given a username, will return a user object if remote is an admin for the
#      username.  Otherwise returns undef.
# returns: user object if authenticated, otherwise undef.
# args: user
# des-opts: Username of user to attempt to auth as.
# </LJFUNC>
sub get_authas_user {
    my $user = shift;
    my $opts = shift;

    return undef unless $user;

    $opts = { type => $opts } unless ref $opts;

    # get a remote
    my $remote = LJ::get_remote();
    return undef unless $remote;

    # remote is already what they want?
    return $remote if $remote->{'user'} eq $user;

    # load user and authenticate
    my $u = LJ::load_user($user);
    return undef unless $u;
    return undef unless $u->{clusterid};

    # does $u have admin access?
    if ($opts->{'type'} eq 'S') {
        return undef unless $remote->can_super_manage($u);
    } else {
        return undef unless $remote->can_manage($u);
    }

    # passed all checks, return $u
    return $u;
}


# <LJFUNC>
# name: LJ::shared_member_request
# des: Registers an authaction to add a user to a
#      shared journal and sends an approval e-mail.
# returns: Hashref; output of LJ::register_authaction()
#          includes datecreate of old row if no new row was created.
# args: ju, u, attr?
# des-ju: Shared journal user object
# des-u: User object to add to shared journal
# </LJFUNC>
sub shared_member_request {
    my ($ju, $u) = @_;
    return undef unless ref $ju && ref $u;

    my $dbh = LJ::get_db_writer();

    # check for duplicates
    my $oldaa = $dbh->selectrow_hashref("SELECT aaid, authcode, datecreate FROM authactions " .
                                        "WHERE userid=? AND action='shared_invite' AND used='N' " .
                                        "AND NOW() < datecreate + INTERVAL 1 HOUR " .
                                        "ORDER BY 1 DESC LIMIT 1",
                                        undef, $ju->{'userid'});
    return $oldaa if $oldaa;

    # insert authactions row
    my $aa = LJ::register_authaction($ju->{'userid'}, 'shared_invite', "targetid=$u->{'userid'}");
    return undef unless $aa;

    # if there are older duplicates, invalidate any existing unused authactions of this type
    $dbh->do("UPDATE authactions SET used='Y' WHERE userid=? AND aaid<>? " .
             "AND action='shared_invite' AND used='N'",
             undef, $ju->{'userid'}, $aa->{'aaid'});

    my $body = "The maintainer of the $ju->{'user'} shared journal has requested that " .
        "you be given posting access.\n\n" .
        "If you do not wish to be added to this journal, just ignore this email.  " .
        "However, if you would like to accept posting rights to $ju->{'user'}, click " .
        "the link below to authorize this action.\n\n" .
        "     $LJ::SITEROOT/approve/$aa->{'aaid'}.$aa->{'authcode'}\n\n" .
        "Regards\n$LJ::SITENAME Team\n";

    LJ::send_mail({
        'to' => $u->email_raw,
        'from' => $LJ::DONOTREPLY_EMAIL,
        'fromname' => $LJ::SITENAME,
        'charset' => 'utf-8',
        'subject' => "Community Membership: $ju->{'name'}",
        'body' => $body
        });

    return $aa;
}

# <LJFUNC>
# name: LJ::is_valid_authaction
# des: Validates a shared secret (authid/authcode pair)
# info: See [func[LJ::register_authaction]].
# returns: Hashref of authaction row from database.
# args: aaid, auth
# des-aaid: Integer; the authaction ID.
# des-auth: String; the auth string. (random chars the client already got)
# </LJFUNC>
sub is_valid_authaction {
    # we use the master db to avoid races where authactions could be
    # used multiple times
    my $dbh = LJ::get_db_writer();
    my ($aaid, $auth) = @_;
    return $dbh->selectrow_hashref("SELECT * FROM authactions WHERE aaid=? AND authcode=? AND used='N'",
                                   undef, $aaid, $auth);
}

# <LJFUNC>
# name: LJ::mark_authaction_used
# des: Marks an authaction as being used.
# args: aaid
# des-aaid: Either an authaction hashref or the id of the authaction to mark used.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub mark_authaction_used
{
    my $aaid = ref $_[0] ? $_[0]->{aaid}+0 : $_[0]+0
        or return undef;
    my $dbh = LJ::get_db_writer()
        or return undef;
    $dbh->do("UPDATE authactions SET used='Y' WHERE aaid = ?", undef, $aaid);
    return undef if $dbh->err;
    return 1;
}

# <LJFUNC>
# name: LJ::get_urls
# des: Returns a list of all referenced URLs from a string.
# args: text
# des-text: Text from which to return extra URLs.
# returns: list of URLs
# </LJFUNC>
sub get_urls
{
    return ($_[0] =~ m!https?://[^\s\"\'\<\>]+!g);
}

# <LJFUNC>
# name: LJ::make_auth_code
# des: Makes a random string of characters of a given length.
# returns: string of random characters, from an alphabet of 30
#          letters & numbers which aren't easily confused.
# args: length
# des-length: length of auth code to return
# </LJFUNC>
sub make_auth_code {
    my $length = shift;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    my $auth;
    for (1..$length) { $auth .= substr($digits, int(rand(30)), 1); }
    return $auth;
}

# <LJFUNC>
# name: LJ::load_props
# des: Loads and caches one or more of the various *proplist tables:
#      [dbtable[logproplist]], [dbtable[talkproplist]], and [dbtable[userproplist]], which describe
#      the various meta-data that can be stored on log (journal) items,
#      comments, and users, respectively.
# args: table*
# des-table: a list of tables' proplists to load. Can be one of
#            "log", "talk", "user", or "rate".
# </LJFUNC>
sub load_props {
    my @tables = @_;
    my $dbr;
    my %keyname = qw(log  propid
                     talk tpropid
                     user upropid
                     rate rlid
                     );

    foreach my $t (@tables) {
        next unless defined $keyname{$t};
        next if defined $LJ::CACHE_PROP{$t};
        my $tablename = $t eq "rate" ? "ratelist" : "${t}proplist";

        my $cache_key = "props:table:data:$tablename";
        my $cache_data  = LJ::MemCache::get($cache_key);
        if ($cache_data) {
            foreach my $p (@$cache_data) {
                $LJ::CACHE_PROP{$t}->{$p->{'name'}} = $p;
                $LJ::CACHE_PROPID{$t}->{$p->{'id'}} = $p;
            }
            next;
        }

        $dbr ||= LJ::get_db_writer();
        my $sth = $dbr->prepare("SELECT * FROM $tablename");
        $sth->execute;

        my @data = ();
        while (my $p = $sth->fetchrow_hashref) {
            $p->{'id'} = $p->{$keyname{$t}};
            $LJ::CACHE_PROP{$t}->{$p->{'name'}} = $p;
            $LJ::CACHE_PROPID{$t}->{$p->{'id'}} = $p;
            push @data, $p;
        }

        LJ::MemCache::set($cache_key, \@data, 180);
    }
}

# <LJFUNC>
# name: LJ::get_prop
# des: This is used to retrieve
#      a hashref of a row from the given tablename's proplist table.
#      One difference from getting it straight from the database is
#      that the 'id' key is always present, as a copy of the real
#      proplist unique id for that table.
# args: table, name
# returns: hashref of proplist row from db
# des-table: the tables to get a proplist hashref from.  Can be one of
#            "log", "talk", or "user".
# des-name: the name of the prop to get the hashref of.
# </LJFUNC>
sub get_prop
{
    my $table = shift;
    my $name = shift;

    unless (defined $LJ::CACHE_PROP{$table} && $LJ::CACHE_PROP{$table}->{$name}) {
        $LJ::CACHE_PROP{$table} = undef;
        LJ::load_props($table);
    }

    unless ($LJ::CACHE_PROP{$table}) {
        warn "Prop table does not exist: $table" if $LJ::IS_DEV_SERVER;
        return undef;
    }

    unless ($LJ::CACHE_PROP{$table}->{$name}) {
        warn "Prop does not exist: $table - $name" if $LJ::IS_DEV_SERVER;
        return undef;
    }

    return $LJ::CACHE_PROP{$table}->{$name};
}

# <LJFUNC>
# name: LJ::load_codes
# des: Populates hashrefs with lookup data from the database or from memory,
#      if already loaded in the past.  Examples of such lookup data include
#      state codes, country codes, color name/value mappings, etc.
# args: whatwhere
# des-whatwhere: a hashref with keys being the code types you want to load
#                and their associated values being hashrefs to where you
#                want that data to be populated.
# </LJFUNC>
sub load_codes {
    my $req = shift;

    my $dbr = LJ::get_db_reader()
        or die "Unable to get database handle";

    foreach my $type (keys %{$req})
    {
        my $memkey = "load_codes:$type";
        unless ($LJ::CACHE_CODES{$type} ||= LJ::MemCache::get($memkey))
        {
            $LJ::CACHE_CODES{$type} = [];
            my $sth = $dbr->prepare("SELECT code, item, sortorder FROM codes WHERE type=?");
            $sth->execute($type);
            while (my ($code, $item, $sortorder) = $sth->fetchrow_array)
            {
                push @{$LJ::CACHE_CODES{$type}}, [ $code, $item, $sortorder ];
            }
            @{$LJ::CACHE_CODES{$type}} =
                sort { $a->[2] <=> $b->[2] } @{$LJ::CACHE_CODES{$type}};
            LJ::MemCache::set($memkey, $LJ::CACHE_CODES{$type}, 60*15);
        }

        foreach my $it (@{$LJ::CACHE_CODES{$type}})
        {
            if (ref $req->{$type} eq "HASH") {
                $req->{$type}->{$it->[0]} = $it->[1];
            } elsif (ref $req->{$type} eq "ARRAY") {
                push @{$req->{$type}}, { 'code' => $it->[0], 'item' => $it->[1] };
            }
        }
    }
}

# <LJFUNC>
# name: LJ::load_state_city_for_zip
# des: Fetches state and city for the given zip-code value
# args: zip
# des-zip: zip code
# </LJFUNC>
sub load_state_city_for_zip {
    my $zip = shift;
    my ($zipcity, $zipstate);

    if ($zip =~ /^\d{5}$/) {
        my $dbr = LJ::get_db_reader()
            or die "Unable to get database handle";

        my $sth = $dbr->prepare("SELECT city, state FROM zip WHERE zip=?");
        $sth->execute($zip) or die "Failed to fetch state and city for zip: $DBI::errstr";
        ($zipcity, $zipstate) = $sth->fetchrow_array;
    }

    return ($zipcity, $zipstate);
}

# Return challenge info.
# This could grow later - for now just return the rand chars used.
sub get_challenge_attributes
{
    return (split /:/, shift)[4];
}

# <LJFUNC>
# name: LJ::get_talktext2
# des: Retrieves comment text. Tries slave servers first, then master.
# info: Efficiently retrieves batches of comment text. Will try alternate
#       servers first. See also [func[LJ::get_logtext2]].
# returns: Hashref with the talkids as keys, values being [ $subject, $event ].
# args: u, opts?, jtalkids
# des-opts: A hashref of options. 'onlysubjects' will only retrieve subjects.
# des-jtalkids: A list of talkids to get text for.
# </LJFUNC>
sub get_talktext2
{
    my $u = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'}+0;

    my $opts = ref $_[0] ? shift : {};

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;
    foreach (@_) {
        my $id = $_+0;
        $need{$id} = 1;
        push @mem_keys, [$journalid,"talksubject:$clusterid:$journalid:$id"];
        unless ($opts->{'onlysubjects'}) {
            push @mem_keys, [$journalid,"talkbody:$clusterid:$journalid:$id"];
        }
    }

    # try the memory cache
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};

    if ($LJ::_T_GET_TALK_TEXT2_MEMCACHE) {
        $LJ::_T_GET_TALK_TEXT2_MEMCACHE->();
    }

    while (my ($k, $v) = each %$mem) {
        $k =~ /^talk(.*):(\d+):(\d+):(\d+)/;
        if ($opts->{'onlysubjects'} && $1 eq "subject") {
            delete $need{$4};
            $lt->{$4} = [ $v ];
        }
        if (! $opts->{'onlysubjects'} && $1 eq "body" &&
            exists $mem->{"talksubject:$2:$3:$4"}) {
            delete $need{$4};
            $lt->{$4} = [ $mem->{"talksubject:$2:$3:$4"}, $v ];
        }
    }
    return $lt unless %need;

    my $bodycol = $opts->{'onlysubjects'} ? "" : ", body";

    # pass 1 (slave) and pass 2 (master)
    foreach my $pass (1, 2) {
        next unless %need;
        my $db = $pass == 1 ? LJ::get_cluster_reader($clusterid) :
            LJ::get_cluster_def_reader($clusterid);

        unless ($db) {
            next if $pass == 1;
            die "Could not get db handle";
        }

        my $in = join(",", keys %need);
        my $sth = $db->prepare("SELECT jtalkid, subject $bodycol FROM talktext2 ".
                               "WHERE journalid=$journalid AND jtalkid IN ($in)");
        $sth->execute;
        while (my ($id, $subject, $body) = $sth->fetchrow_array) {
            $subject = "" unless defined $subject;
            $body = "" unless defined $body;
            LJ::text_uncompress(\$body);
            $lt->{$id} = [ $subject, $body ];
            LJ::MemCache::add([$journalid,"talkbody:$clusterid:$journalid:$id"], $body)
                unless $opts->{'onlysubjects'};
            LJ::MemCache::add([$journalid,"talksubject:$clusterid:$journalid:$id"], $subject);
            delete $need{$id};
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::clear_caches
# des: This function is called from a HUP signal handler and is intentionally
#      very very simple (1 line) so we don't core dump on a system without
#      reentrant libraries.  It just sets a flag to clear the caches at the
#      beginning of the next request (see [func[LJ::handle_caches]]).
#      There should be no need to ever call this function directly.
# </LJFUNC>
sub clear_caches
{
    $LJ::CLEAR_CACHES = 1;
}

# <LJFUNC>
# name: LJ::handle_caches
# des: clears caches if the CLEAR_CACHES flag is set from an earlier
#      HUP signal that called [func[LJ::clear_caches]], otherwise
#      does nothing.
# returns: true (always) so you can use it in a conjunction of
#          statements in a while loop around the application like:
#          while (LJ::handle_caches() && FCGI::accept())
# </LJFUNC>
sub handle_caches
{
    return 1 unless $LJ::CLEAR_CACHES;
    $LJ::CLEAR_CACHES = 0;

    LJ::Config->load;

    $LJ::DBIRole->flush_cache();

    %LJ::CACHE_PROP = ();
    %LJ::CACHE_STYLE = ();
    $LJ::CACHED_MOODS = 0;
    $LJ::CACHED_MOOD_MAX = 0;
    %LJ::CACHE_MOODS = ();
    %LJ::CACHE_MOOD_THEME = ();
    %LJ::CACHE_USERID = ();
    %LJ::CACHE_USERNAME = ();
    %LJ::CACHE_CODES = ();
    %LJ::CACHE_USERPROP = ();  # {$prop}->{ 'upropid' => ... , 'indexed' => 0|1 };
    %LJ::CACHE_ENCODINGS = ();
    return 1;
}

=head2 LJ::show_contextual_hover()

A subroutine that returns a boolean value indicating whether we should
show a contextual hover popup on the current page.

=cut

sub show_contextual_hover {
    my %args = LJ::Request->args;
    return ($LJ::CTX_POPUP and !$LJ::IS_SSL and $args{ctxpp} ne 'no');
}

sub __clean_singletons {
    # clear per-request caches
    LJ::unset_remote();               # clear cached remote
    $LJ::ACTIVE_JOURNAL = undef;      # for LJ::{get,set}_active_journal
    $LJ::ACTIVE_CRUMB = '';           # clear active crumb
    %LJ::CACHE_USERPIC = ();          # picid -> hashref
    %LJ::CACHE_USERPIC_INFO = ();     # uid -> { ... }
    %LJ::REQ_CACHE_USER_NAME = ();    # users by name
    %LJ::REQ_CACHE_USER_ID = ();      # users by id
    %LJ::REQ_CACHE_REL = ();          # relations from LJ::check_rel()
    %LJ::REQ_CACHE_INBOX = ();        # various inbox data
    %LJ::REQ_LANGDATFILE = ();        # caches language files
    %LJ::SMS::REQ_CACHE_MAP_UID = (); # cached calls to LJ::SMS::num_to_uid()
    %LJ::SMS::REQ_CACHE_MAP_NUM = (); # cached calls to LJ::SMS::uid_to_num()
    %LJ::S1::REQ_CACHE_STYLEMAP = (); # styleid -> uid mappings
    %LJ::S2::REQ_CACHE_STYLE_ID = (); # styleid -> hashref of s2 layers for style
    %LJ::S2::REQ_CACHE_LAYER_ID = (); # layerid -> hashref of s2 layer info (from LJ::S2::load_layer)
    %LJ::S2::REQ_CACHE_LAYER_INFO = (); # layerid -> hashref of s2 layer info (from LJ::S2::load_layer_info)
    %LJ::QotD::REQ_CACHE_QOTD = ();   # type ('current' or 'old') -> Question of the Day hashrefs
    $LJ::SiteMessages::REQ_CACHE_MESSAGES = undef; # arrayref of cached site message hashrefs
    %LJ::REQ_HEAD_HAS = ();           # avoid code duplication for js
    %LJ::NEEDED_RES = ();             # needed resources (css/js/etc):
    @LJ::NEEDED_RES = ();             # needed resources, in order requested (implicit dependencies)
                                      #  keys are relative from htdocs, values 1 or 2 (1=external, 2=inline)
    @LJ::INCLUDE_TEMPLATE = ();       # jQuery.tmpl templates (translated from HTML::Template)
    %LJ::JSML  = ();                  # Javascript language variables sent to the page header for further javascript use
    %LJ::JSVAR = ();                  # Javascript variables sent to the page header for further javascript use
    @LJ::INCLUDE_RAW = ();            # raw js/css added after needed resources.
    %LJ::REQ_GLOBAL = ();             # per-request globals
    %LJ::_ML_USED_STRINGS = ();       # strings looked up in this web request
    %LJ::REQ_CACHE_USERTAGS = ();     # uid -> { ... }; populated by get_usertags, so we don't load it twice
    %LJ::LOCK_OUT = ();
    %LJ::SECRET = ();                 # secret key -> secret value


    $LJ::VERTICALS_FORCE_USE_MASTER = 0;    # It need to load a new created category from master insteed slave server.

    $LJ::COUNT_LOAD_PROPS_MULTI    = 0;     # Counter for number of requests function LJ::User::load_user_props_multi()
    $LJ::COUNT_LOAD_PROPS_MULTI_DB = 0;     # Counter for number of requests for props load to DB

    $LJ::CACHE_REMOTE_BOUNCE_URL = undef;

    LJ::Userpic->reset_singletons;
    LJ::Comment->reset_singletons;
    LJ::Entry->reset_singletons;
    LJ::Message->reset_singletons;
    LJ::Vertical->reset_singletons;
    LJ::Browse->reset_singletons;
    LJ::MemCacheProxy->reset_singletons;

    LJ::RelationService->reset_singletons;
    LJ::UniqCookie->clear_request_cache;
    LJ::PushNotification::Storage->clear_data();
    LJ::API::RateLimiter->reset_singleton();

    # we use this to fake out get_remote's perception of what
    # the client's remote IP is, when we transfer cookies between
    # authentication domains.  see the FotoBilder interface.
    $LJ::_XFER_REMOTE_IP = undef;
}

# <LJFUNC>
# name: LJ::start_request
# des: Before a new web request is obtained, this should be called to
#      determine if process should die or keep working, clean caches,
#      reload config files, etc.
# returns: 1 if a new request is to be processed, 0 if process should die.
# </LJFUNC>
sub start_request
{
    LJ::RequestStatistics->start_profile();

    handle_caches();
    # TODO: check process growth size

    # clean sigletons
    __clean_singletons();

    # clear the handle request cache (like normal cache, but verified already for
    # this request to be ->ping'able).
    $LJ::DBIRole->clear_req_cache();

    # need to suck db weights down on every request (we check
    # the serial number of last db weight change on every request
    # to validate master db connection, instead of selecting
    # the connection ID... just as fast, but with a point!)
    $LJ::DBIRole->trigger_weight_reload();

    # reload config if necessary
    LJ::Config->start_request_reload;

    LJ::run_hooks("start_request");

    return 1;
}


# <LJFUNC>
# name: LJ::end_request
# des: Clears cached DB handles (if [ljconfig[disconnect_dbs]] is
#      true), and disconnects memcached handles (if [ljconfig[disconnect_memcache]] is
#      true).
# </LJFUNC>
sub end_request
{
    LJ::work_report_end();
    LJ::flush_cleanup_handlers();
    LJ::disconnect_dbs() if $LJ::DISCONNECT_DBS;
    LJ::MemCache::disconnect_all() if $LJ::DISCONNECT_MEMCACHE;

    LJ::run_hooks("end_request");

    __clean_singletons();

    LJ::RequestStatistics->finish_profile();
    $LJ::__dynamic_enable = {};
}

# <LJFUNC>
# name: LJ::flush_cleanup_handlers
# des: Runs all cleanup handlers registered in @LJ::CLEANUP_HANDLERS
# </LJFUNC>
sub flush_cleanup_handlers {
    while (my $ref = shift @LJ::CLEANUP_HANDLERS) {
        next unless ref $ref eq 'CODE';
        $ref->();
    }
}



# <LJFUNC>
# name: LJ::server_down_html
# des: Returns an HTML server down message.
# returns: A string with a server down message in HTML.
# </LJFUNC>
sub server_down_html
{
    return "<b>$LJ::SERVER_DOWN_SUBJECT</b><br />$LJ::SERVER_DOWN_MESSAGE";
}

# <LJFUNC>
# name: LJ::get_cluster_description
# des: Get descriptive text for a cluster id.
# args: clusterid
# des-clusterid: id of cluster to get description of.
# returns: string representing the cluster description
# </LJFUNC>
sub get_cluster_description {
    my ($cid) = shift;
    $cid += 0;
    my $text = LJ::run_hook('cluster_description', $cid);
    return $text if $text;

    # default behavior just returns clusterid
    return $cid;
}

# <LJFUNC>
# name: LJ::do_to_cluster
# des: Given a subref, this function will pick a random cluster and run the subref,
#      passing it the cluster id.  If the subref returns a 1, this function will exit
#      with a 1.  Else, the function will call the subref again, with the next cluster.
# args: subref
# des-subref: Reference to a sub to call; @_ = (clusterid)
# returns: 1 if the subref returned a 1 at some point, undef if it didn't ever return
#          success and we tried every cluster.
# </LJFUNC>
sub do_to_cluster {
    my $subref = shift;

    # start at some random point and iterate through the clusters one by one until
    # $subref returns a true value
    my $size = @LJ::CLUSTERS;
    my $start = int(rand() * $size);
    my $rval = undef;
    my $tries = $size > 15 ? 15 : $size;
    foreach (1..$tries) {
        # select at random
        my $idx = $start++ % $size;

        # get subref value
        $rval = $subref->($LJ::CLUSTERS[$idx]);
        last if $rval;
    }

    # return last rval
    return $rval;
}

# <LJFUNC>
# name: LJ::get_keyword_id
# class:
# des: Get the id for a keyword.
# args: uuid?, keyword, autovivify?
# des-uuid: User object or userid to use.  Pass this <strong>only</strong> if
#           you want to use the [dbtable[userkeywords]] clustered table!  If you
#           do not pass user information, the [dbtable[keywords]] table
#           on the global will be used.
# des-keyword: A string keyword to get the id of.
# returns: Returns a kwid into [dbtable[keywords]] or
#          [dbtable[userkeywords]], depending on if you passed a user or not.
#          If the keyword doesn't exist, it is automatically created for you.
# des-autovivify: If present and 1, automatically create keyword.
#                 If present and 0, do not automatically create the keyword.
#                 If not present, default behavior is the old
#                 style -- yes, do automatically create the keyword.
# </LJFUNC>
sub get_keyword_id {
    # see if we got a user? if so we use userkeywords on a cluster
    my $u;
    if (@_ >= 2) {
        $u = LJ::want_user(shift);
        return undef unless $u;
    }

    my ($kw, $autovivify) = @_;
    $autovivify = 1 unless defined $autovivify;

    # setup the keyword for use
    unless ($kw =~ /\S/) { return 0; }
    $kw = LJ::text_trim($kw, LJ::BMAX_KEYWORD, LJ::CMAX_KEYWORD);
    #$kw = LJ::Text->normalize_tag_name ($kw);

    # get the keyword and insert it if necessary
    my $kwid;
    if ($u && $u->{dversion} > 5) {
        # new style userkeywords -- but only if the user has the right dversion
        $kwid = $u->selectrow_array('SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                    undef, $u->{userid}, $kw) + 0;
        if ($autovivify && ! $kwid) {
            # create a new keyword
            $kwid = LJ::alloc_user_counter($u, 'K');
            return undef unless $kwid;

            # attempt to insert the keyword
            my $rv = $u->do("INSERT IGNORE INTO userkeywords (userid, kwid, keyword) VALUES (?, ?, ?)",
                            undef, $u->{userid}, $kwid, $kw) + 0;
            return undef if $u->err;

            # at this point, if $rv is 0, the keyword is already there so try again
            unless ($rv) {
                $kwid = $u->selectrow_array('SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                            undef, $u->{userid}, $kw) + 0;
            }

            # nuke cache
            LJ::MemCache::delete([ $u->{userid}, "kws:$u->{userid}" ]);
        }
    } else {
        # old style global
        my $dbh = LJ::get_db_writer();
        my $qkw = $dbh->quote($kw);

        # Making this a $dbr could cause problems due to the insertion of
        # data based on the results of this query. Leave as a $dbh.
        $kwid = $dbh->selectrow_array("SELECT kwid FROM keywords WHERE keyword=$qkw");
        if ($autovivify && ! $kwid) {
            $dbh->do("INSERT INTO keywords (kwid, keyword) VALUES (NULL, $qkw)");
            $kwid = $dbh->{'mysql_insertid'};
        }
    }
    return $kwid;
}

sub get_interest {
    my $intid = shift
        or return undef;

    # FIXME: caching!

    my $dbr = LJ::get_db_reader();
    my ($int, $intcount) = $dbr->selectrow_array
        ("SELECT interest, intcount FROM interests WHERE intid=?",
         undef, $intid);

    return wantarray() ? ($int, $intcount) : $int;
}

sub get_interest_id {
    my $int = shift
        or return undef;

    # FIXME: caching!

    my $dbr = LJ::get_db_reader();
    my ($intid, $intcount) = $dbr->selectrow_array
        ("SELECT intid, intcount FROM interests WHERE interest=?",
         undef, $int);

    return wantarray() ? ($intid, $intcount) : $intid;
}

sub can_use_journal {
    my ($posterid, $reqownername, $res) = @_;

    ## find the journal owner's info
    my $uowner = LJ::load_user($reqownername);
    unless ($uowner) {
        $res->{'errmsg'} = "Journal \"$reqownername\" does not exist.";
        return 0;
    }
    my $ownerid = $uowner->{'userid'};

    # the 'ownerid' necessity came first, way back when.  but then
    # with clusters, everything needed to know more, like the
    # journal's dversion and clusterid, so now it also returns the
    # user row.
    $res->{'ownerid'} = $ownerid;
    $res->{'u_owner'} = $uowner;

    ## check if user has access
    return 1 if LJ::check_rel($ownerid, $posterid, 'P');

    # let's check if this community is allowing post access to non-members
    LJ::load_user_props($uowner, "nonmember_posting");
    if ($uowner->{'nonmember_posting'}) {
        my $dbr = LJ::get_db_reader() or die "nodb";
        my $postlevel = $dbr->selectrow_array("SELECT postlevel FROM ".
                                              "community WHERE userid=$ownerid");
        return 1 if $postlevel eq 'members';
    }

    # is the poster an admin for this community?
    my $poster = LJ::want_user($posterid);
    return 1 if $poster && $poster->can_manage($uowner);

    $res->{'errmsg'} = "You do not have access to post to this journal.";
    return 0;
}

# <LJFUNC>
# name: LJ::load_talk_props2
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_talk_props2
{
    my $db = isdb($_[0]) ? shift @_ : undef;
    my ($uuserid, $listref, $hashref) = @_;

    my $userid = want_userid($uuserid);
    my $u = ref $uuserid ? $uuserid : undef;

    $hashref = {} unless ref $hashref eq "HASH";

    my %need;
    my @memkeys;
    foreach (@$listref) {
        my $id = $_+0;
        $need{$id} = 1;
        push @memkeys, [$userid,"talkprop:$userid:$id"];
    }
    return $hashref unless %need;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    # allow hooks to count memcaches in this function for testing
    if ($LJ::_T_GET_TALK_PROPS2_MEMCACHE) {
        $LJ::_T_GET_TALK_PROPS2_MEMCACHE->();
    }

    while (my ($k, $v) = each %$mem) {
        next unless $k =~ /(\d+):(\d+)/ && ref $v eq "HASH";
        delete $need{$2};
        $hashref->{$2}->{$_[0]} = $_[1] while @_ = each %$v;
    }
    return $hashref unless %need;

    if (!$db || @LJ::MEMCACHE_SERVERS) {
        $u ||= LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) :  LJ::get_cluster_reader($u);
        return $hashref unless $db;
    }

    LJ::load_props("talk");
    my $in = join(',', keys %need);
    my $sth = $db->prepare("SELECT jtalkid, tpropid, value FROM talkprop2 ".
                           "WHERE journalid=? AND jtalkid IN ($in)");
    $sth->execute($userid);
    while (my ($jtalkid, $propid, $value) = $sth->fetchrow_array) {
        my $p = $LJ::CACHE_PROPID{'talk'}->{$propid};
        next unless $p;
        $hashref->{$jtalkid}->{$p->{'name'}} = $value;
    }
    foreach my $id (keys %need) {
        LJ::MemCache::set([$userid,"talkprop:$userid:$id"], $hashref->{$id} || {});
    }
    return $hashref;
}

my $work_open = 0;
sub work_report_start { $work_open = 1; work_report("start"); }
sub work_report_end   { return unless $work_open; work_report("end"); $work_open = 0;   }

# report before/after a request, so a supervisor process can watch for
# hangs/spins
my $udp_sock;
sub work_report {
    my $what = shift;
    my $dest = $LJ::WORK_REPORT_HOST;
    return unless $dest;

    return unless LJ::Request->is_inited;
    return if LJ::Request->method eq "OPTIONS";

    $dest = $dest->() if ref $dest eq "CODE";
    return unless $dest;

    $udp_sock ||= IO::Socket::INET->new(Proto => "udp");
    return unless $udp_sock;

    my ($host, $port) = split(/:/, $dest);
    return unless $host && $port;

    my @fields = ($$, $what);
    if ($what eq "start") {
        my $host = LJ::Request->header_in("Host");
        my $uri = LJ::Request->uri;
        my $args = LJ::Request->args;
        $args = substr($args, 0, 100) if length $args > 100;
        push @fields, $host, $uri, $args;

        my $remote = LJ::User->remote;
        push @fields, $remote->{user} if $remote;
    }

    my $msg = join(",", @fields);

    my $dst = Socket::sockaddr_in($port, Socket::inet_aton($host));
    my $rv = $udp_sock->send($msg, 0, $dst);
}

# <LJFUNC>
# name: LJ::blocking_report
# des: Log a report on the total amount of time used in a slow operation to a
#      remote host via UDP.
# args: host, type, time, notes
# des-host: The DB host the operation used.
# des-type: The type of service the operation was talking to (e.g., 'database',
#           'memcache', etc.)
# des-time: The amount of time (in floating-point seconds) the operation took.
# des-notes: A short description of the operation.
# </LJFUNC>
sub blocking_report {
    my ( $host, $type, $time, $notes ) = @_;

    if ( $LJ::DB_LOG_HOST ) {
        unless ( $LJ::ReportSock ) {
            my ( $host, $port ) = split /:/, $LJ::DB_LOG_HOST, 2;
            return unless $host && $port;

            $LJ::ReportSock = new IO::Socket::INET (
                PeerPort => $port,
                Proto    => 'udp',
                PeerAddr => $host
               ) or return;
        }

        my $msg = join( "\x3", $host, $type, $time, $notes );
        $LJ::ReportSock->send( $msg );
    }
}


# <LJFUNC>
# name: LJ::delete_comments
# des: deletes comments, but not the relational information, so threading doesn't break
# info: The tables [dbtable[talkprop2]] and [dbtable[talktext2]] are deleted from.  [dbtable[talk2]]
#       just has its state column modified, to 'D'.
# args: u, nodetype, nodeid, talkids
# des-nodetype: The thread nodetype (probably 'L' for log items)
# des-nodeid: The thread nodeid for the given nodetype (probably the jitemid
#              from the [dbtable[log2]] row).
# des-talkids: List array of talkids to delete.
# returns: scalar integer; number of items deleted.
# </LJFUNC>
sub delete_comments {
    my ($u, $nodetype, $nodeid, @talkids) = @_;

    return 0 unless $u->writer;

    my $jid = $u->{'userid'}+0;
    my @batch = map { int $_ } @talkids;
    my $in = join(',', @batch);

    # invalidate memcache for this comment
    LJ::Talk::invalidate_comment_cache($u->id, $nodeid, @talkids);

    return 0 unless $in;
    my $where = "WHERE journalid=$jid AND jtalkid IN ($in)";

    my $num_spam = $u->selectrow_array("SELECT COUNT(*) FROM talk2 $where AND state='B'");

    LJ::run_hooks('report_cmt_delete', $jid, \@batch);
    my $num = $u->talk2_do(nodetype => $nodetype, nodeid => $nodeid,
                           sql => "UPDATE talk2 SET state='D' $where");

    return 0 unless $num;
    $num = 0 if $num == -1;

    if ($num > 0) {
        LJ::run_hooks('report_cmt_text_delete', $jid, \@batch);
        $u->do("UPDATE talktext2 SET subject=NULL, body=NULL $where");
        $u->do("DELETE FROM talkprop2 $where");
    }

    my @jobs;
    foreach my $talkid (@talkids) {
        my $cmt = LJ::Comment->new($u, jtalkid => $talkid);
        push @jobs, LJ::EventLogRecord::DeleteComment->new($cmt)->fire_job;
        LJ::run_hooks('delete_comment', $jid, $nodeid, $talkid); # jitemid, jtalkid
    }

    my $sclient = LJ::theschwartz();
    $sclient->insert_jobs(@jobs) if @jobs;

    return ($num, $num_spam);
}

# <LJFUNC>
# name: LJ::color_fromdb
# des: Takes a value of unknown type from the DB and returns an #rrggbb string.
# args: color
# des-color: either a 24-bit decimal number, or an #rrggbb string.
# returns: scalar; #rrggbb string, or undef if unknown input format
# </LJFUNC>
sub color_fromdb
{
    my $c = shift;
    return $c if $c =~ /^\#[0-9a-f]{6,6}$/i;
    return sprintf("\#%06x", $c) if $c =~ /^\d+$/;
    return undef;
}

# <LJFUNC>
# name: LJ::color_todb
# des: Takes an #rrggbb value and returns a 24-bit decimal number.
# args: color
# des-color: scalar; an #rrggbb string.
# returns: undef if bogus color, else scalar; 24-bit decimal number, can be up to 8 chars wide as a string.
# </LJFUNC>
sub color_todb
{
    my $c = shift;
    return undef unless $c =~ /^\#[0-9a-f]{6,6}$/i;
    return hex(substr($c, 1, 6));
}

# <LJFUNC>
# name: LJ::procnotify_add
# des: Sends a message to all other processes on all clusters.
# info: You'll probably never use this yourself.
# args: cmd, args?
# des-cmd: Command name.  Currently recognized: "DBI::Role::reload" and "rename_user"
# des-args: Hashref with key/value arguments for the given command.
#           See relevant parts of [func[LJ::procnotify_callback]], for
#           required args for different commands.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub procnotify_add {
    my ($cmd, $argref) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    my $args = join('&', map { LJ::eurl($_) . "=" . LJ::eurl($argref->{$_}) }
                    sort keys %$argref);
    $dbh->do("INSERT INTO procnotify (cmd, args) VALUES (?,?)",
             undef, $cmd, $args);

    return 0 if $dbh->err;
    return $dbh->{'mysql_insertid'};
}

# <LJFUNC>
# name: LJ::procnotify_callback
# des: Call back function process notifications.
# info: You'll probably never use this yourself.
# args: cmd, argstring
# des-cmd: Command name.
# des-argstring: String of arguments.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub procnotify_callback
{
    my ($cmd, $argstring) = @_;
    my $arg = {};
    LJ::decode_url_string($argstring, $arg);

    if ($cmd eq "failover") {
        $LJ::ExtBlock::LOCAL_CACHE{'cluster_config.rc'} = [];
        return;
    }

    if ($cmd eq "rename_user") {
        # this looks backwards, but the cache hash names are just odd:
        delete $LJ::CACHE_USERNAME{$arg->{'userid'}};
        delete $LJ::CACHE_USERID{$arg->{'user'}};
        return;
    }

    unless ($LJ::DISABLED{'sysban'}) {
        # ip bans
        if ($cmd eq "ban_ip") {
            $LJ::IP_BANNED{$arg->{'ip'}} = $arg->{'exptime'};
            return;
        }

        if ($cmd eq "unban_ip") {
            delete $LJ::IP_BANNED{$arg->{'ip'}};
            return;
        }
    }

    # uniq key bans
    if ($cmd eq "ban_uniq") {
        $LJ::UNIQ_BANNED{$arg->{'uniq'}} = $arg->{'exptime'};
        return;
    }

    if ($cmd eq "unban_uniq") {
        delete $LJ::UNIQ_BANNED{$arg->{'uniq'}};
        return;
    }

    # contentflag key bans
    if ($cmd eq "ban_contentflag") {
        $LJ::CONTENTFLAG_BANNED{$arg->{'username'}} = $arg->{'exptime'};
        return;
    }

    if ($cmd eq "unban_contentflag") {
        delete $LJ::CONTENTFLAG_BANNED{$arg->{'username'}};
        return;
    }

    if ($cmd eq LJ::AdTargetedInterests->procnotify_key) {
        LJ::AdTargetedInterests->reload;
        return;
    }
}

sub procnotify_check
{
    my $now = time;
    return if $LJ::CACHE_PROCNOTIFY_CHECK + 30 > $now;
    $LJ::CACHE_PROCNOTIFY_CHECK = $now;

    my $dbr = LJ::get_db_reader();
    my $max = $dbr->selectrow_array("SELECT MAX(nid) FROM procnotify");
    return unless defined $max;
    my $old = $LJ::CACHE_PROCNOTIFY_MAX;
    if (defined $old && $max > $old) {
        my $sth = $dbr->prepare("SELECT cmd, args FROM procnotify ".
                                "WHERE nid > ? AND nid <= $max ORDER BY nid");
        $sth->execute($old);
        while (my ($cmd, $args) = $sth->fetchrow_array) {
            LJ::procnotify_callback($cmd, $args);
        }
    }
    $LJ::CACHE_PROCNOTIFY_MAX = $max;
}

# We're not always running under mod_perl... sometimes scripts (syndication sucker)
# call paths which end up thinking they need the remote IP, but don't.
sub get_remote_ip
{
    my $ip;
    if ($LJ::IS_DEV_SERVER) {
        return $LJ::_T_FAKE_IP if $LJ::_T_FAKE_IP;
        return $BML::COOKIE{'fake_ip'} if LJ::is_web_context() && $BML::COOKIE{'fake_ip'};
    }
    eval {
        $ip = LJ::Request->remote_ip;
    };
    return $ip || $ENV{'FAKE_IP'};
}

sub md5_struct
{
    my ($st, $md5) = @_;
    $md5 ||= Digest::MD5->new;
    unless (ref $st) {
        # later Digest::MD5s die while trying to
        # get at the bytes of an invalid utf-8 string.
        # this really shouldn't come up, but when it
        # does, we clear the utf8 flag on the string and retry.
        # see http://zilla.livejournal.org/show_bug.cgi?id=851
        eval { $md5->add($st); };
        if ($@) {
            $st = pack('C*', unpack('C*', $st));
            $md5->add($st);
        }
        return $md5;
    }
    if (ref $st eq "HASH") {
        foreach (sort keys %$st) {
            md5_struct($_, $md5);
            md5_struct($st->{$_}, $md5);
        }
        return $md5;
    }
    if (ref $st eq "ARRAY") {
        foreach (@$st) {
            md5_struct($_, $md5);
        }
        return $md5;
    }
}

sub urandom {
    my %args = @_;
    my $length = $args{size} or die 'Must Specify size';

    my $result;
    open my $fh, '<', '/dev/urandom' or die "Cannot open random: $!";
    while ($length) {
        my $chars;
        $fh->read($chars, $length) or die "Cannot read /dev/urandom: $!";
        $length -= length($chars);
        $result .= $chars;
    }
    $fh->close;

    return $result;
}

sub urandom_int {
    my %args = @_;

    return unpack('N', LJ::urandom( size => 4 ));
}

sub rand_chars
{
    my $length = shift;
    my $chal = "";
    my $digits = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    for (1..$length) {
        $chal .= substr($digits, int(rand(62)), 1);
    }
    return $chal;
}

# ($time, $secret) = LJ::get_secret();       # will generate
# $secret          = LJ::get_secret($time);  # won't generate
# ($time, $secret) = LJ::get_secret($time);  # will generate (in wantarray)
sub get_secret
{
    my $time = int($_[0]);
    return undef if $_[0] && ! $time;
    my $want_new = ! $time || wantarray;

    if (! $time) {
        $time = time();
        $time -= $time % 3600;  # one hour granularity
    }

    my $memkey = "secret:$time";
    my $secret = $LJ::SECRET{$memkey};
    if (!$secret) {
        $secret = LJ::MemCache::get($memkey);
        $LJ::SECRET{$memkey} = $secret;
    }

    return $want_new ? ($time, $secret) : $secret if $secret;

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;
    $secret = $dbh->selectrow_array("SELECT secret FROM secrets ".
                                    "WHERE stime=?", undef, $time);
    if ($secret) {
        $LJ::SECRET{$memkey} = $secret;
        LJ::MemCache::set($memkey, $secret) if $secret;
        return $want_new ? ($time, $secret) : $secret;
    }

    # return if they specified an explicit time they wanted.
    # (calling with no args means generate a new one if secret
    # doesn't exist)
    return undef unless $want_new;

    # don't generate new times that don't fall in our granularity
    return undef if $time % 3600;

    $secret = LJ::rand_chars(32);

    ## put it to memcache first
    LJ::MemCache::add($memkey, $secret);

    ## save it to db
    $dbh->do("INSERT IGNORE INTO secrets SET stime=?, secret=?",
             undef, $time, $secret);

    # check for races:
    $secret = get_secret($time);
    return ($time, $secret);
}


# Single-letter domain values are for livejournal-generic code.
#  - 0-9 are reserved for site-local hooks and are mapped from a long
#    (> 1 char) string passed as the $dom to a single digit by the
#    'map_global_counter_domain' hook.
#
# LJ-generic domains:
#  $dom: 'S' == style, 'P' == userpic, 'A' == stock support answer
#        'C' == captcha, 'E' == external user, 'O' == school
#        'L' == poLL,  'M' == Messaging
#
sub alloc_global_counter
{
    my ($dom, $recurse) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # $dom can come as a direct argument or as a string to be mapped via hook
    my $dom_unmod = $dom;
    # Yes, that's a duplicate L in the regex for xtra LOLS
    unless ($dom =~ /^[MLOLSPACE]$/) {
        $dom = LJ::run_hook('map_global_counter_domain', $dom);
    }
    return LJ::errobj("InvalidParameters", params => { dom => $dom_unmod })->cond_throw
        unless defined $dom;

    my $newmax;
    my $uid = 0; # userid is not needed, we just use '0'

    my $rs = $dbh->do("UPDATE counter SET max=LAST_INSERT_ID(max+1) WHERE journalid=? AND area=?",
                      undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");
        return $newmax;
    }

    return undef if $recurse;

    # no prior counter rows - initialize one.
    if ($dom eq "S") {
        $newmax = $dbh->selectrow_array("SELECT MAX(styleid) FROM s1stylemap");
    } elsif ($dom eq "P") {
        $newmax = $dbh->selectrow_array("SELECT MAX(picid) FROM userpic");
    } elsif ($dom eq "C") {
        $newmax = $dbh->selectrow_array("SELECT MAX(capid) FROM captchas");
    } elsif ($dom eq "E" || $dom eq "M") {
        # if there is no extuser or message counter row
        # start at 'ext_1'  - ( the 0 here is incremented after the recurse )
        $newmax = 0;
    } elsif ($dom eq "A") {
        $newmax = $dbh->selectrow_array("SELECT MAX(ansid) FROM support_answers");
    } elsif ($dom eq "O") {
        $newmax = $dbh->selectrow_array("SELECT MAX(schoolid) FROM schools");
    } elsif ($dom eq "L") {
        # pick maximum id from poll and pollowner
        my $max_poll      = $dbh->selectrow_array("SELECT MAX(pollid) FROM poll");
        my $max_pollowner = $dbh->selectrow_array("SELECT MAX(pollid) FROM pollowner");
        $newmax = $max_poll > $max_pollowner ? $max_poll : $max_pollowner;
    } else {
        $newmax = LJ::run_hook('global_counter_init_value', $dom);
        die "No alloc_global_counter initalizer for domain '$dom'"
            unless defined $newmax;
    }
    $newmax += 0;
    $dbh->do("INSERT IGNORE INTO counter (journalid, area, max) VALUES (?,?,?)",
             undef, $uid, $dom, $newmax) or return LJ::errobj($dbh)->cond_throw;
    return LJ::alloc_global_counter($dom, 1);
}

sub system_userid {
    return $LJ::CACHE_SYSTEM_ID if $LJ::CACHE_SYSTEM_ID;
    my $u = LJ::load_user("system")
        or die "No 'system' user available for LJ::system_userid()";
    return $LJ::CACHE_SYSTEM_ID = $u->{userid};
}

sub blobcache_replace {
    my ($key, $value) = @_;

    die "invalid key: $key" unless length $key;

    my $dbh = LJ::get_db_writer()
        or die "Unable to contact global master";

    return $dbh->do("REPLACE INTO blobcache SET bckey=?, dateupdate=NOW(), value=?",
                    undef, $key, $value);
}

sub blobcache_get {
    my $key = shift;

    die "invalid key: $key" unless length $key;

    my $dbr = LJ::get_db_reader()
        or die "Unable to contact global reader";

    my ($value, $timeupdate) =
        $dbr->selectrow_array("SELECT value, UNIX_TIMESTAMP(dateupdate) FROM blobcache WHERE bckey=?",
                              undef, $key);

    return wantarray() ? ($value, $timeupdate) : $value;
}

sub note_recent_action {
    my ($cid, $action) = @_;

    # fall back to selecting a random cluster
    $cid = LJ::random_cluster() unless defined $cid;

    # accept a user object
    $cid = ref $cid ? $cid->{clusterid}+0 : $cid+0;

    return undef unless $cid;

    # make sure they gave us an action
    return undef if !$action || length($action) > 20;;

    my $dbcm = LJ::get_cluster_master($cid)
        or return undef;

    # append to recentactions table
    $dbcm->do("INSERT INTO recentactions (what) VALUES (?)", undef, $action);
    return undef if $dbcm->err;

    return 1;
}

sub is_web_context {
    return $ENV{MOD_PERL} ? 1 : 0;
}

sub is_open_proxy
{
    my $ip = shift;
    eval { $ip ||= LJ::Request->instance; };
    return 0 unless $ip;
    if (ref $ip) { $ip = $ip->connection->remote_ip; }

    my $dbr = LJ::get_db_reader();
    my $stat = $dbr->selectrow_hashref("SELECT status, asof FROM openproxy WHERE addr=?",
                                       undef, $ip);

    # only cache 'clear' hosts for a day; 'proxy' for two days
    $stat = undef if $stat && $stat->{'status'} eq "clear" && $stat->{'asof'} > 0 && $stat->{'asof'} < time()-86400;
    $stat = undef if $stat && $stat->{'status'} eq "proxy" && $stat->{'asof'} < time()-2*86400;

    # open proxies are considered open forever, unless cleaned by another site-local mechanism
    return 1 if $stat && $stat->{'status'} eq "proxy";

    # allow things to be cached clear for a day before re-checking
    return 0 if $stat && $stat->{'status'} eq "clear";

    # no RBL defined?
    return 0 unless @LJ::RBL_LIST;

    my $src = undef;
    my $rev = join('.', reverse split(/\./, $ip));
    foreach my $rbl (@LJ::RBL_LIST) {
        my @res = gethostbyname("$rev.$rbl");
        if ($res[4]) {
            $src = $rbl;
            last;
        }
    }

    my $dbh = LJ::get_db_writer();
    if ($src) {
        $dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
                 $ip, "proxy", time(), $src);
        return 1;
    } else {
        $dbh->do("INSERT IGNORE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
                 $ip, "clear", time(), $src);
        return 0;
    }
}

# loads an include file, given the bare name of the file.
#   ($filename)
# returns the text of the file.  if the file is specified in %LJ::FILEEDIT_VIA_DB
# then it is loaded from memcache/DB, else it falls back to disk.
sub load_include {
    my $file = shift;
    return unless $file && $file =~ /^[a-zA-Z0-9-_\.]{1,80}$/;

    # okay, edit from where?
    if ($LJ::FILEEDIT_VIA_DB || $LJ::FILEEDIT_VIA_DB{$file}) {
        # we handle, so first if memcache...
        my $val = LJ::MemCache::get("includefile:$file");
        return $val if $val;

        # straight database hit
        my $dbh = LJ::get_db_writer();
        $val = $dbh->selectrow_array(qq(
                SELECT   inctext 
                FROM     includetext
                WHERE    incname=?
                ORDER BY rev_id DESC
                LIMIT    1
            ), 
            undef, 
            $file
        );
        
        LJ::MemCache::set("includefile:$file", $val, time() + 3600);
        return $val if $val;
    }

    # hit it up from the file, if it exists
    my $filename = "$ENV{'LJHOME'}/htdocs/inc/$file";
    return unless -e $filename;

    # get it and return it
    return File::Slurp::read_file("$ENV{'LJHOME'}/htdocs/inc/$file");
}

# save an include file, given the bare name of the file.
#   ($filename)
# if the file is specified in %LJ::FILEEDIT_VIA_DB
# then it is saved to memcache/DB, else it falls back to disk.
sub save_include {
    my ($file, $content, $adminid) = @_;
    return unless $file && $file =~ /^[a-zA-Z0-9-_\.]{1,80}$/;

    if ($LJ::FILEEDIT_VIA_DB || $LJ::FILEEDIT_VIA_DB{$file}) {
        my $dbh = LJ::get_db_writer();
        $dbh->do("INSERT INTO includetext (incname, inctext, updatetime, adminid) ".
                   "VALUES (?, ?, UNIX_TIMESTAMP(), ?)", undef, $file, $content, $adminid);
        return 0 if $dbh->err;
        LJ::MemCache::set("includefile:$file", $content, time() + 3600);
        return 1;
    }

    unless (LJ::is_enabled('fileedit_local')) {
        return 0;
    }

    File::Slurp::write_file("$ENV{'LJHOME'}/htdocs/inc/$file", $content);
    return 1;
}

# <LJFUNC>
# name: LJ::bit_breakdown
# des: Breaks down a bitmask into an array of bits enabled.
# args: mask
# des-mask: The number to break down.
# returns: A list of bits enabled.  E.g., 3 returns (0, 2) indicating that bits 0 and 2 (numbering
#          from the right) are currently on.
# </LJFUNC>
sub bit_breakdown {
    my $mask = shift()+0;

    # check each bit 0..31 and return only ones that are defined
    return grep { defined }
           map { $mask & (1<<$_) ? $_ : undef } 0..31;
}

sub last_error_code
{
    return $LJ::last_error;
}

sub last_error
{
    my $err = sub {
        my ($code, $params) = @_;
        return LJ::Lang::ml("ljerror.$code", $params);
    };

    my ($code, $params) = ref($LJ::last_error) eq 'ARRAY' ? @$LJ::last_error : ($LJ::last_error, {});

    my $des = $err->($code, $params);

    if ($code eq "db" && $LJ::db_error) {
        $des .= ": $LJ::db_error";
    }
    return $des || $code;
}

sub error
{
    my $err = shift;
    if (isdb($err)) {
        $LJ::db_error = $err->errstr;
        $err = "db";
    } elsif ($err eq "db") {
        $LJ::db_error = "";
    } elsif (my $params = shift) {
        $err = [$err, $params];
    }
    $LJ::last_error = $err;
    return undef;
}

sub get_error {
    LJ::error(@_);
    LJ::last_error();
}

*errobj = \&LJ::Error::errobj;
*throw = \&LJ::Error::throw;

# Returns a LWP::UserAgent or LWPx::Paranoid agent depending on role
# passed in by the caller.
# Des-%opts:
#           role     => what is this UA being used for? (required)
#           timeout  => seconds before request will timeout, defaults to 10
#           max_size => maximum size of returned document, defaults to no limit
sub get_useragent {
    my %opts = @_;

    my $timeout  = $opts{'timeout'}  || 10;
    my $max_size = $opts{'max_size'} || undef;
    my $role     = $opts{'role'};
    return unless $role;

    my $lib = $LJ::USERAGENT_LIB{$role} || 'LWPx::ParanoidAgent';

    eval "require $lib";
    my $ua = $lib->new(
                       timeout  => $timeout,
                       max_size => $max_size,
                       );
    if (@LJ::PARANOID_AGENT_WHITELISTED_HOSTS && $ua->can('whitelisted_hosts')) {
        $ua->whitelisted_hosts(@LJ::PARANOID_AGENT_WHITELISTED_HOSTS);
    }

    return $ua;
}

sub assert_is {
    my ($va, $ve) = @_;
    return 1 if $va eq $ve;
    LJ::errobj("AssertIs",
               expected => $ve,
               actual => $va,
               caller => [caller()])->throw;
}

sub no_utf8_flag {
    return pack('C*', unpack('C*', $_[0]));
}

# return true if root caller is a test file
sub is_from_test {
    return $0 && $0 =~ m!(^|/)t/!;
}

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    if ($AUTOLOAD eq "LJ::send_mail") {
        require "ljmail.pl";
        goto &$AUTOLOAD;
    }
    Carp::croak("Undefined subroutine: $AUTOLOAD");
}

sub pagestats_obj {
    return LJ::PageStats->new;
}

sub graphicpreviews_obj {
    return $LJ::GRAPHIC_PREVIEWS_OBJ if $LJ::GRAPHIC_PREVIEWS_OBJ;

    my $ret_obj;
    my $plugin = $LJ::GRAPHIC_PREVIEWS_PLUGIN;
    if ($plugin) {
        my $class = "LJ::GraphicPreviews::$plugin";
        $ret_obj = eval "use $class; $class->new";
        if ($@) {
           warn "Error loading GraphicPreviews plugin '$class': $@";
           $ret_obj = LJ::GraphicPreviews->new;
        }
    } else {
        $ret_obj = LJ::GraphicPreviews->new;
    }

    $LJ::GRAPHIC_PREVIEWS_OBJ = $ret_obj;
    return $ret_obj;
}

sub conf_test {
    my ($conf, @args) = @_;
    return 0 unless $conf;
    return $conf->(@args) if ref $conf eq "CODE";
    return $conf;
}

sub is_enabled {
    my $conf = shift;
    return ! LJ::conf_test($LJ::DISABLED{$conf}, @_);
}

sub is_enabled_dynamic {
    my $conf = shift;

    my $redis = LJ::Redis->get_connection();
    if ($redis && !$LJ::__dynamic_enable) {
        $LJ::__dynamic_enable = $redis->hgetall('lj:settings:disabled');
    }

    if ($LJ::__dynamic_enable && exists $LJ::__dynamic_enable->{$conf}) {
        return $LJ::__dynamic_enable->{$conf};
    }

    return ! LJ::conf_test($LJ::DISABLED{$conf}, @_);
}

%LJ::LANG_MAP = (
    af    => "af_ZA",
    be    => "be_BY",
    da    => "da_DK",
    de    => "de_DE",
    eo    => "eo_EO",
    es    => "es_ES",
    fi    => "fi_FI",
    fr    => "fr_FR",
    gr    => "el_GR",
    he    => "he_IL",
    hi    => "hi_IN",
    hu    => "hu_HU",
    is    => "is_IS",
    it    => "it_IT",
    ja    => "ja_JP",
    ms    => "ms_MY",
    nb    => "nb_NO",
    nl    => "nl_NL",
    nn    => "nb_NO",
    pl    => "pl_PL",
    pt    => "pt_PT",
    pt_BR => "pt_BR",
    ru    => "ru_RU",
    sv    => "sv_SE",
    tr    => "tr_TR",
    uk    => "uk_UA",
    zh    => "zh_CN",
    zh_TR => "zh_TW",
);

%LJ::R_LANG_MAP = reverse %LJ::LANG_MAP;

sub lang_to_locale {
    my ($lang) = @_;

    return 'en_US' unless $LJ::LANG_MAP{$lang};
    return $LJ::LANG_MAP{$lang};
}

sub locale_to_lang {
    my ($locale) = @_;

    return $LJ::DEFAULT_LANG unless $LJ::R_LANG_MAP{$locale};
    return $LJ::R_LANG_MAP{$locale};
}

sub compact_dumper {
    my (@args) = @_;

    require Data::Dumper;

    local $Data::Dumper::Indent   = 0;
    local $Data::Dumper::Sortkeys = 1;

    if ( @args <= 1 ) {
        local $Data::Dumper::Terse = 1;
        return Data::Dumper::Dumper(@args);
    }

    return Data::Dumper::Dumper(@args);
}

package LJ::S1;

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    if ($AUTOLOAD eq "LJ::S1::get_public_styles") {
        require "ljviews.pl";
        goto &$AUTOLOAD;
    }
    Carp::croak("Undefined subroutine: $AUTOLOAD");
}

package LJ::CleanHTML;

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    my $lib = "cleanhtml.pl";
    if ($INC{$lib}) {
        Carp::croak("Undefined subroutine: $AUTOLOAD");
    }
    require $lib;
    goto &$AUTOLOAD;
}

package LJ::Error::InvalidParameters;
sub opt_fields { qw(params) }
sub user_caused { 0 }

package LJ::Error::AssertIs;
sub fields { qw(expected actual caller) }
sub user_caused { 0 }

sub as_string {
    my $self = shift;
    my $caller = $self->field('caller');
    my $ve = $self->field('expected');
    my $va = $self->field('actual');
    return "Assertion failure at " . join(', ', (@$caller)[0..2]) . ": expected=$ve, actual=$va";
}

LJ::run_hooks("startup");
## Hook "startup" is run before apaches are forked.
## If a connection to memcached is created in the hook code, they must be disconnected,
## otherwise, several apache processes will share the same socket.
LJ::MemCache->disconnect_all;

1;
