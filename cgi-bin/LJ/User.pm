#
# LiveJournal user object
#
# 2004-07-21: we're transitioning from $u hashrefs to $u objects, currently
#             backed by hashrefs, to ease migration.  in the future,
#             more methods from ljlib.pl and other places will move here,
#             and the representation of a $u object will change to 'fields'.
#             at present, the motivation to moving to $u objects is to do
#             all database access for a given user through his/her $u object
#             so the queries can be tagged for use by the star replication
#             daemon.

use strict;
no warnings 'uninitialized';

package LJ::User;
use Carp;
use lib "$ENV{LJHOME}/cgi-bin";
use List::Util ();
use LJ::Request;
use LJ::Constants;
use LJ::MemCache;
use LJ::Session;
use LJ::RateLimit qw//;
use URI qw//;
use LJ::JSON;
use HTTP::Date qw(str2time);
use LJ::TimeUtil;
use LJ::User::PropStorage;
use LJ::FileStore;
use LJ::RelationService;

use Class::Autouse qw(
                      URI
                      LJ::Subscription
                      LJ::SMS
                      LJ::SMS::Message
                      LJ::Identity
                      LJ::Auth
                      LJ::Jabber::Presence
                      LJ::S2
                      IO::Socket::INET
                      Time::Local
                      LJ::M::FriendsOf
                      LJ::BetaFeatures
                      LJ::S2Theme
                      LJ::Subscription
                      LJ::Subscription::GroupSet
                      );

# class method to create a new account.
sub create {
    my ($class, %opts) = @_;

    my $username = LJ::canonical_username($opts{user}) or return;

    my $cluster     = $opts{cluster} || LJ::new_account_cluster();
    my $caps        = $opts{caps} || $LJ::NEWUSER_CAPS;
    my $journaltype = $opts{journaltype} || "P";

    # non-clustered accounts aren't supported anymore
    return unless $cluster;

    my $dbh = LJ::get_db_writer();

    $dbh->do("INSERT INTO user (user, clusterid, dversion, caps, journaltype) " .
             "VALUES (?, ?, ?, ?, ?)", undef,
             $username, $cluster, $LJ::MAX_DVERSION, $caps, $journaltype);
    return if $dbh->err;

    my $userid = $dbh->{'mysql_insertid'};
    return unless $userid;

    $dbh->do("INSERT INTO useridmap (userid, user) VALUES (?, ?)",
             undef, $userid, $username);
    $dbh->do("INSERT INTO userusage (userid, timecreate) VALUES (?, NOW())",
             undef, $userid);

    my $u = LJ::load_userid($userid, "force");

    my $status   = $opts{status}   || ($LJ::EVERYONE_VALID ? 'A' : 'N');
    my $name     = $opts{name}     || $username;
    my $bdate    = $opts{bdate}    || "0000-00-00";
    my $email    = $opts{email}    || "";
    my $password = $opts{password} || "";

    LJ::update_user($u, { 'status' => $status, 'name' => $name, 'bdate' => $bdate,
                          'email' => $email, 'password' => $password, %LJ::USER_INIT });

    my $remote = LJ::get_remote();
    $u->log_event('account_create', { remote => $remote });

    while (my ($name, $val) = each %LJ::USERPROP_INIT) {
        $u->set_prop($name, $val);
    }

    if ($opts{extra_props}) {
        while (my ($key, $value) = each( %{$opts{extra_props}} )) {
            $u->set_prop( $key => $value );
        }
    }

    if ($opts{status_history}) {
        my $system = LJ::load_user("system");
        if ($system) {
            while (my ($key, $value) = each( %{$opts{status_history}} )) {
                LJ::statushistory_add($u, $system, $key, $value);
            }
        }
    }

    LJ::run_hooks("post_create", {
        'userid' => $userid,
        'user'   => $username,
        'code'   => undef,
        'news'   => $opts{get_ljnews},
    });

    return $u;
}

sub create_personal {
    my ($class, %opts) = @_;

    my $u = LJ::User->create(%opts) or return;

    $u->set_prop("init_bdate", $opts{bdate});
    while (my ($name, $val) = each %LJ::USERPROP_INIT_PERSONAL) {
        $u->set_prop($name, $val);
    }

    # so birthday notifications get sent
    $u->set_next_birthday;

    # Set the default style
    LJ::run_hook('set_default_style', $u);

    if (length $opts{inviter}) {
        if ($opts{inviter} =~ /^partner:/) {
            LJ::run_hook('partners_registration_done', $u, $opts{inviter});
        } else {
            # store inviter, if there was one
            my $inviter = LJ::load_user($opts{inviter});
            if ($inviter) {
                LJ::set_rel($u, $inviter, "I");
                LJ::statushistory_add($u, $inviter, 'create_from_invite', "Created new account.");
        
        
                $u->add_friend($inviter);
                LJ::Event::InvitedFriendJoins->new($inviter, $u)->fire;
            }
        }
    }
    # if we have initial friends for new accounts, add them.
    my @initial_friends = LJ::SUP->is_sup_enabled($u) ? @LJ::SUP_INITIAL_FRIENDS : @LJ::INITIAL_FRIENDS;
    foreach my $friend (@initial_friends) {
        my $friendid = LJ::get_userid($friend);
        LJ::add_friend($u->id, $friendid) if $friendid;
    }

    # populate some default friends groups
    my %res;
    LJ::do_request(
                   {
                       'mode'           => 'editfriendgroups',
                       'user'           => $u->user,
                       'ver'            => $LJ::PROTOCOL_VER,
                       'efg_set_1_name' => 'Family',
                       'efg_set_2_name' => 'Local Friends',
                       'efg_set_3_name' => 'Online Friends',
                       'efg_set_4_name' => 'School',
                       'efg_set_5_name' => 'Work',
                       'efg_set_6_name' => 'Mobile View',
                   }, \%res, { 'u' => $u, 'noauth' => 1, }
                   );

    $u->set_prop("newpost_minsecurity", "friends") if $u->is_child;

    # now flag as underage (and set O to mean was old or Y to mean was young)
    $u->underage(1, $opts{ofage} ? 'O' : 'Y', 'account creation') if $opts{underage};

    # For settings that are to be set explicitly
    # on create, with more private settings for non-adults
    if ($u->underage || $u->is_child) {
        $u->set_prop("opt_findbyemail", 'N');
    } else {
        $u->set_prop("opt_findbyemail", 'H');
    }

    return $u;
}

sub create_community {
    my ($class, %opts) = @_;

    $opts{journaltype} = "C";
    my $u = LJ::User->create(%opts) or return;

    $u->set_prop("nonmember_posting", $opts{nonmember_posting}+0);
    $u->set_prop("moderated", $opts{moderated});
    $u->set_prop("adult_content", $opts{journal_adult_settings}) if LJ::is_enabled("content_flag");

    my $remote = LJ::get_remote();

	die "No remote user!\n" unless $remote;

    LJ::set_rel($u, $remote, "A");  # maintainer

    LJ::set_rel($u, $remote, "S");  # supermaintainer
    $u->log_event('set_owner', { actiontarget => $remote->{userid}, remote => $remote });
    LJ::statushistory_add($u, $remote, 'set_owner', "Set supermaintainer on created time as " . $remote->{user});

    LJ::set_rel($u, $remote, "M") if $opts{moderated} =~ /^[AF]$/; # moderator if moderated
    LJ::join_community($remote, $u, 1, 1); # member

    LJ::set_comm_settings($u, $remote, { membership => $opts{membership},
                                         postlevel => $opts{postlevel} });

    my $theme = LJ::S2Theme->load_by_uniq($LJ::DEFAULT_THEME_COMMUNITY);
    LJ::Customize->apply_theme($u, $theme) if $theme;

    return $u;
}

sub create_syndicated {
    my ($class, %opts) = @_;

    return unless $opts{feedurl};

    $opts{caps}        = $LJ::SYND_CAPS;
    $opts{cluster}     = $LJ::SYND_CLUSTER;
    $opts{journaltype} = "Y";

    my $u = LJ::User->create(%opts) or return;

    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT INTO syndicated (userid, synurl, checknext) VALUES (?, ?, NOW())",
             undef, $u->id, $opts{feedurl});
    die $dbh->errstr if $dbh->err;

    my $remote = LJ::get_remote();
    LJ::statushistory_add($remote, $u, "synd_create", "acct: " . $u->user);

    return $u;
}

# retrieve hash of basic syndicated info
sub get_syndicated {
    my $u = shift;

    return unless $u->is_syndicated;
    my $memkey = [$u->{'userid'}, "synd:$u->{'userid'}"];

    my $synd = {};
    $synd = LJ::MemCache::get($memkey);
    unless ($synd) {
        my $dbr = LJ::get_db_reader();
        return unless $dbr;
        $synd = $dbr->selectrow_hashref("SELECT * FROM syndicated WHERE userid=$u->{'userid'}");
        LJ::MemCache::set($memkey, $synd, 60 * 120) if $synd;
    }

    return $synd;
}

sub is_protected_username {
    my ($class, $username) = @_;
    foreach my $re (@LJ::PROTECTED_USERNAMES) {
        return 1 if $username =~ /$re/;
    }
    return 0;
}

sub new_from_row {
    my ($class, $row) = @_;
    my $u = bless $row, $class;

    return $u;
}

sub new_from_url {
    my ($class, $url) = @_;

    my $username = $class->username_from_url($url);
    if ($username){
        return LJ::load_user($username);
    }

    # domains like 'http://news.independent.livejournal.com' or 'http://some.site.domain.com'
    if ($url =~ m!^http://([\w.-]+)/?$!) {
        return $class->new_from_external_domain($1);
    }

    return undef;
}

## Input: domain (e.g. 'news.independent.livejournal.com' or 'some.site.domain.com')
## Output: LJ::User object or undef
sub new_from_external_domain {
    my $class = shift;
    my $host = shift;

    $host = lc($host);
    $host =~ s/^www\.//;

    if (my $user = $LJ::DOMAIN_JOURNALS_REVERSE{$host}) {
        return LJ::load_user($user);
    }

    my $key = "domain:$host";
    my $userid = LJ::MemCache::get($key);

    unless (defined $userid) {
        my $db = LJ::get_db_reader();
        ($userid) = $db->selectrow_array(qq{SELECT userid FROM domains WHERE domain=?}, undef, $host);
        $userid ||= 0; ## we do cache negative results - if no user for such domain, set userid=0
        my $expire = time() + 1800;
        LJ::MemCache::set($key, $userid, $expire);
    }

    my $u = LJ::load_userid($userid);
    return $u if $u;
    return undef;
}

sub username_from_url {
    my ($class, $url) = @_;

    # /users, /community, or /~
    if ($url =~ m!^\Q$LJ::SITEROOT\E/(?:users/|community/|~)([\w-]+)/?!) {
        return $1;
    }

    # subdomains that hold a bunch of users (eg, users.siteroot.com/username/)
    if ($url =~ m!^http://(\w+)\.\Q$LJ::USER_DOMAIN\E/([\w-]+)/?$!) {
        if ( $LJ::IS_USER_DOMAIN->{$1} ) {
            return $2;
        }
    }

    # user subdomains
    my $user_uri_regex = qr{
        # it all starts with a protocol:
        ^http://

        # username:
        ([\w-]+)

        # literal dot separating it from our domain space:
        [.]

        # our domain space:
        \Q$LJ::USER_DOMAIN\E

        # either it ends right there, or there is a forward slash character
        # followed by something (we don't care what):
        (?:$|/)

    }xo; # $LJ::USER_DOMAIN is basically a constant, let Perl know that

    if ( $LJ::USER_DOMAIN && $url =~ $user_uri_regex ) {
        return $1;
    }
   
}

# returns LJ::User class of a random user, undef if we couldn't get one
#   my $random_u = LJ::User->load_random_user();
sub load_random_user {
    my $class = shift;

    # get a random database, but make sure to try them all if one is down or not
    # responding or similar
    my $dbcr;
    foreach (List::Util::shuffle(@LJ::CLUSTERS)) {
        $dbcr = LJ::get_cluster_reader($_);
        last if $dbcr;
    }
    die "Unable to get database cluster reader handle\n" unless $dbcr;

    # get a selection of users around a random time
    my $when = time() - int(rand($LJ::RANDOM_USER_PERIOD * 24 * 60 * 60)); # days -> seconds
    my $uids = $dbcr->selectcol_arrayref(qq{
            SELECT userid FROM random_user_set
            WHERE posttime > $when
            ORDER BY posttime
            LIMIT 10
        });
    die "Failed to execute query: " . $dbcr->errstr . "\n" if $dbcr->err;
    return undef unless $uids && @$uids;

    # try the users we got
    foreach my $uid (@$uids) {
        my $u = LJ::load_userid($uid)
            or next;

        # situational checks to ensure this user is a good one to show
        next unless $u->is_person;         # people accounts only
        next unless $u->is_visible;        # no suspended/deleted/etc users
        next if $u->prop('latest_optout'); # they have chosen to be excluded

        # they've passed the checks, return this user
        return $u;
    }

    # must have failed
    return undef;
}

# class method.  returns remote (logged in) user object.  or undef if
# no session is active.
sub remote {
    my ($class, $opts) = @_;
    return LJ::get_remote($opts);
}

# class method.  set the remote user ($u or undef) for the duration of this request.
# once set, it'll never be reloaded, unless "unset_remote" is called to forget it.
sub set_remote
{
    my ($class, $remote) = @_;
    $LJ::CACHED_REMOTE = 1;
    $LJ::CACHE_REMOTE = $remote;
    1;
}

# class method.  forgets the cached remote user.
sub unset_remote
{
    my $class = shift;
    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE = undef;
    1;
}

sub preload_props {
    my $u = shift;
    LJ::load_user_props($u, @_);
}

sub readonly {
    my $u = shift;
    return LJ::get_cap($u, "readonly");
}

# returns self (the $u object which can be used for $u->do) if
# user is writable, else 0
sub writer {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u);
    return $dbcm || 0;
}

sub userpic {
    my $u = shift;
    return undef unless $u->{defaultpicid};
    return LJ::Userpic->new($u, $u->{defaultpicid});
}

# returns a true value if the user is underage; or if you give it an argument,
# will turn on/off that user's underage status.  can also take a second argument
# when you're setting the flag to also update the underage_status userprop
# which is used to record if a user was ever marked as underage.
sub underage {
    # has no bearing if this isn't on
    return undef unless LJ::class_bit("underage");

    my @args = @_;
    my $ret_zero = 0; # no need to return zero

    # now get the args and continue
    my $u = shift(@args);
    unless (@args) { # we are getter
        my $young = LJ::get_cap($u, 'underage');
        return unless $young; # cap is clear -> return false        

        # here cap is set -> may be we will return it, may be we will update
        return 1 unless $u->underage_status eq 'Y'; # only "provided birthdate" may be updated, "manual" and "cookie" must be preserved
        return 1 if $u->init_age < 14; # yes, user is young -> return true
        
        # here cap is set and user is not young now -> will update
        @args = (0, undef, 'auto clear based on init_age()');
        # fall to setter code
        $ret_zero = 1;
    }

    # now set it on or off
    my $on = shift(@args) ? 1 : 0;
    if ($on) {
        $u->add_to_class("underage");
    } else {
        $u->remove_from_class("underage");
    }

    # now set their status flag if one was sent
    my $status = shift(@args);
    if ($status || $on) {
        # by default, just records if user was ever underage ("Y")
        $u->underage_status($status || 'Y');
    }

    # add to statushistory
    if (my $shwhen = shift(@args)) {
        my $text = $on ? "marked" : "unmarked";
        my $status = $u->underage_status;
        LJ::statushistory_add($u, undef, "coppa", "$text; status=$status; when=$shwhen");
    }

    # now fire off any hooks that are available
    LJ::run_hooks('set_underage', {
        u => $u,
        on => $on,
        status => $u->underage_status,
    });

    # return true if no failures
    return $ret_zero ? 0 : 1;
}
*is_underage = \&underage;

# return true if we know user is a minor (< 18)
sub is_minor {
    my $self = shift;
    my $age = $self->best_guess_age;
    return 0 unless $age;
    return 1 if ($age < 18);
    return 0;
}

# return true if we know user is a child (< 14)
sub is_child {
    my $self = shift;
    my $age = $self->best_guess_age;

    return 0 unless $age;
    return 1 if ($age < 14);
    return 0;
}

# get/set the gizmo account of a user
sub gizmo_account {
    my $u = shift;

    # parse out their account information
    my $acct = $u->prop( 'gizmo' );
    my ($validated, $gizmo);
    if ($acct && $acct =~ /^([01]);(.+)$/) {
        ($validated, $gizmo) = ($1, $2);
    }

    # setting the account
    # all account sets are initially unvalidated
    if (@_) {
        my $newgizmo = shift;
        $u->set_prop( 'gizmo' => "0;$newgizmo" );

        # purge old memcache keys
        LJ::MemCache::delete( "gizmo-ljmap:$gizmo" );
    }

    # return the information (either account + validation or just account)
    return wantarray ? ($gizmo, $validated) : $gizmo unless @_;
}

# get/set the validated status of a user's gizmo account
sub gizmo_account_validated {
    my $u = shift;

    my ($gizmo, $validated) = $u->gizmo_account;

    if ( defined $_[0] && $_[0] =~ /[01]/) {
        $u->set_prop( 'gizmo' => "$_[0];$gizmo" );
        return $_[0];
    }

    return $validated;
}

# log a line to our userlog
sub log_event {
    my $u = shift;

    my ($type, $info) = @_;
    return undef unless $type;
    $info ||= {};

    # now get variables we need; we use delete to remove them from the hash so when we're
    # done we can just encode what's left
    my $ip = delete($info->{ip}) || LJ::get_remote_ip() || undef;
    my $uniq = delete $info->{uniq};
    unless ($uniq) {
        eval {
            $uniq = LJ::Request->notes('uniq');
        };
    }
    my $remote = delete($info->{remote}) || LJ::get_remote() || undef;
    my $targetid = (delete($info->{actiontarget})+0) || undef;
    my $extra = %$info ? join('&', map { LJ::eurl($_) . '=' . LJ::eurl($info->{$_}) } keys %$info) : undef;

    # now insert the data we have
    $u->do("INSERT INTO userlog (userid, logtime, action, actiontarget, remoteid, ip, uniq, extra) " .
           "VALUES (?, UNIX_TIMESTAMP(), ?, ?, ?, ?, ?, ?)", undef, $u->{userid}, $type,
           $targetid, $remote ? $remote->{userid} : undef, $ip, $uniq, $extra);
    return undef if $u->err;
    return 1;
}

# return or set the underage status userprop
sub underage_status {
    return undef unless LJ::class_bit("underage");

    my $u = shift;

    # return if they aren't setting it
    unless (@_) {
        return $u->prop("underage_status");
    }

    # set and return what it got set to
    $u->set_prop('underage_status', shift());
    return $u->{underage_status};
}

# returns a true value if user has a reserved 'ext' name.
sub external {
    my $u = shift;
    return $u->{user} =~ /^ext_/;
}

# this is for debugging/special uses where you need to instruct
# a user object on what database handle to use.  returns the
# handle that you gave it.
sub set_dbcm {
    my $u = shift;
    return $u->{'_dbcm'} = shift;
}

sub nodb_err {
    my $u = shift;
    return "Database handle unavailable [user: " . $u->user . "; cluster: " . $u->clusterid . ", errstr: $DBI::errstr]";
}

sub is_innodb {
    my $u = shift;
    return $LJ::CACHE_CLUSTER_IS_INNO{$u->{clusterid}}
    if defined $LJ::CACHE_CLUSTER_IS_INNO{$u->{clusterid}};

    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;
    my (undef, $ctable) = $dbcm->selectrow_array("SHOW CREATE TABLE log2");
    die "Failed to auto-discover database type for cluster \#$u->{clusterid}: [$ctable]"
        unless $ctable =~ /^CREATE TABLE/;

    my $is_inno = ($ctable =~ /=InnoDB/i ? 1 : 0);
    return $LJ::CACHE_CLUSTER_IS_INNO{$u->{clusterid}} = $is_inno;
}

sub begin_work {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->begin_work;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub commit {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->commit;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub rollback {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->rollback;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

# get an $sth from the writer
sub prepare {
    my $u = shift;

    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->prepare(@_);
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

# $u->do("UPDATE foo SET key=?", undef, $val);
sub do {
    my $u = shift;
    my $query = shift;

    my $uid = $u->{userid}+0
        or croak "Database update called on null user object";

    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    $query =~ s!^(\s*\w+\s+)!$1/* uid=$uid */ !;

    my $rv = $dbcm->do($query, @_);
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    $u->{_mysql_insertid} = $dbcm->{'mysql_insertid'} if $dbcm->{'mysql_insertid'};

    return $rv;
}

sub selectrow_array {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $set_err = sub {
        if ($u->{_dberr} = $dbcm->err) {
            $u->{_dberrstr} = $dbcm->errstr;
        }
    };

    if (wantarray()) {
        my @rv = $dbcm->selectrow_array(@_);
        $set_err->();
        return @rv;
    }

    my $rv = $dbcm->selectrow_array(@_);
    $set_err->();
    return $rv;
}

sub selectcol_arrayref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectcol_arrayref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}


sub selectall_hashref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectall_hashref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}

sub selectall_arrayref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectall_arrayref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}

sub selectrow_hashref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectrow_hashref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}

sub err {
    my $u = shift;
    return $u->{_dberr};
}

sub errstr {
    my $u = shift;
    return $u->{_dberrstr};
}

sub quote {
    my $u = shift;
    my $text = shift;

    my $dbcm = $u->{'_dbcm'} || LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    return $dbcm->quote($text);
}

sub mysql_insertid {
    my $u = shift;
    if ($u->isa("LJ::User")) {
        return $u->{_mysql_insertid};
    } elsif (LJ::isdb($u)) {
        my $db = $u;
        return $db->{'mysql_insertid'};
    } else {
        die "Unknown object '$u' being passed to LJ::User::mysql_insertid.";
    }
}

# <LJFUNC>
# name: LJ::User::dudata_set
# class: logging
# des: Record or delete disk usage data for a journal.
# args: u, area, areaid, bytes
# des-area: One character: "L" for log, "T" for talk, "B" for bio, "P" for pic.
# des-areaid: Unique ID within $area, or '0' if area has no ids (like bio)
# des-bytes: Number of bytes item takes up.  Or 0 to delete record.
# returns: 1.
# </LJFUNC>
sub dudata_set {
    my ($u, $area, $areaid, $bytes) = @_;
    $bytes += 0; $areaid += 0;
    if ($bytes) {
        $u->do("REPLACE INTO dudata (userid, area, areaid, bytes) ".
               "VALUES (?, ?, $areaid, $bytes)", undef,
               $u->{userid}, $area);
    } else {
        $u->do("DELETE FROM dudata WHERE userid=? AND ".
               "area=? AND areaid=$areaid", undef,
               $u->{userid}, $area);
    }
    return 1;
}

sub make_login_session {
    my ($u, $exptype, $ipfixed) = @_;
    $exptype ||= 'short';
    return 0 unless $u;

    eval { LJ::Request->notes('ljuser' => $u->{'user'}); };

    # create session and log user in
    my $sess_opts = {
        'exptype' => $exptype,
        'ipfixed' => $ipfixed,
    };

    my $sess = LJ::Session->create($u, %$sess_opts);
    $sess->update_master_cookie;

    LJ::User->set_remote($u);

    # add a uniqmap row if we don't have one already
    my $uniq = LJ::UniqCookie->current_uniq;
    LJ::UniqCookie->save_mapping($uniq => $u);

    # restore scheme and language
    my $bl = LJ::Lang::get_lang($u->prop('browselang'));
    BML::set_language($bl->{'lncode'}) if $bl;

    # don't set/force the scheme for this page if we're on SSL.
    # we'll pick it up from cookies on subsequent pageloads
    # but if their scheme doesn't have an SSL equivalent,
    # then the post-login page throws security errors
    BML::set_scheme($u->prop('schemepref'))
        unless $LJ::IS_SSL;

    # run some hooks
    my @sopts;
    LJ::run_hooks("login_add_opts", {
        "u" => $u,
        "form" => {},
        "opts" => \@sopts
    });
    my $sopts = @sopts ? ":" . join('', map { ".$_" } @sopts) : "";
    $sess->flags($sopts);

    my $etime = $sess->expiration_time;
    LJ::run_hooks("post_login", {
        "u" => $u,
        "form" => {},
        "expiretime" => $etime,
    });

    # activity for cluster usage tracking
    LJ::mark_user_active($u, 'login');

    # activity for global account number tracking
    $u->note_activity('A');

    return 1;
}

# We have about 10 million different forms of activity tracking.
# This one is for tracking types of user activity on a per-hour basis
#
#    Example: $u had login activity during this out
#
sub note_activity {
    my ($u, $atype) = @_;
    croak ("invalid user") unless ref $u;
    croak ("invalid activity type") unless $atype;

    # If we have no memcache servers, this function would trigger
    # an insert for every logged-in pageview.  Probably not a problem
    # load-wise if the site isn't using memcache anyway, but if the
    # site is that small active user tracking probably doesn't matter
    # much either.  :/
    return undef unless @LJ::MEMCACHE_SERVERS;

    # Also disable via config flag
    return undef if $LJ::DISABLED{active_user_tracking};

    my $now    = time();
    my $uid    = $u->{userid}; # yep, lazy typist w/ rsi
    my $explen = 1800;         # 30 min, same for all types now

    my $memkey = [ $uid, "uactive:$atype:$uid" ];

    # get activity key from memcache
    my $atime = LJ::MemCache::get($memkey);

    # nothing to do if we got an $atime within the last hour
    return 1 if $atime && $atime > $now - $explen;

    # key didn't exist due to expiration, or was too old,
    # means we need to make an activity entry for the user
    my ($hr, $dy, $mo, $yr) = (gmtime($now))[2..5];
    $yr += 1900; # offset from 1900
    $mo += 1;    # 0-based

    # delayed insert in case the table is currently locked due to an analysis
    # running.  this way the apache won't be tied up waiting
    $u->do("INSERT IGNORE INTO active_user " .
           "SET year=?, month=?, day=?, hour=?, userid=?, type=?",
           undef, $yr, $mo, $dy, $hr, $uid, $atype);

    # set a new memcache key good for $explen
    LJ::MemCache::set($memkey, $now, $explen);

    return 1;
}

sub note_transition {
    my ($u, $what, $from, $to) = @_;
    croak "invalid user object" unless LJ::isu($u);

    return 1 if $LJ::DISABLED{user_transitions};

    # we don't want to insert if the requested transition is already
    # the last noted one for this user... in that case there has been
    # no transition at all
    my $last = $u->last_transition($what);
    return 1 if
        $last->{before} eq $from &&
        $last->{after}  eq $to;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master";

    # bleh, need backticks on the 'before' and 'after' columns since those
    # are MySQL reserved words
    $dbh->do("INSERT INTO usertrans " .
             "SET userid=?, time=UNIX_TIMESTAMP(), what=?, " .
             "`before`=?, `after`=?",
             undef, $u->{userid}, $what, $from, $to);
    die $dbh->errstr if $dbh->err;

    # also log account changes to statushistory
    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "account_level_change", "$from -> $to")
        if $what eq "account";

    return 1;
}

sub transition_list {
    my ($u, $what) = @_;
    croak "invalid user object" unless LJ::isu($u);

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master";

    # FIXME: return list of transition object singleton instances?
    my @list = ();
    my $sth = $dbh->prepare("SELECT time, `before`, `after` " .
                            "FROM usertrans WHERE userid=? AND what=?");
    $sth->execute($u->{userid}, $what);
    die $dbh->errstr if $dbh->err;

    while (my $trans = $sth->fetchrow_hashref) {

        # fill in a couple of properties here rather than
        # sending over the network from db
        $trans->{userid} = $u->{userid};
        $trans->{what}   = $what;

        push @list, $trans;
    }

    return wantarray() ? @list : \@list;
}

sub last_transition {
    my ($u, $what) = @_;
    croak "invalid user object" unless LJ::isu($u);

    $u->transition_list($what)->[-1];
}

sub tosagree_set
{
    my ($u, $err) = @_;
    return undef unless $u;

    unless (-f "$LJ::HOME/htdocs/inc/legal-tos") {
        $$err = "TOS include file could not be found";
        return undef;
    }

    my $rev;
    open (TOS, "$LJ::HOME/htdocs/inc/legal-tos");
    while ((!$rev) && (my $line = <TOS>)) {
        my $rcstag = "Revision";
        if ($line =~ /\$$rcstag:\s*(\S+)\s*\$/) {
            $rev = $1;
        }
    }
    close TOS;

    # if the required version of the tos is not available, error!
    my $rev_req = $LJ::REQUIRED_TOS{rev};
    if ($rev_req > 0 && $rev ne $rev_req) {
        $$err = "Required Terms of Service revision is $rev_req, but system version is $rev.";
        return undef;
    }

    my $newval = join(', ', time(), $rev);
    my $rv = $u->set_prop("legal_tosagree", $newval);
    if ($rv) {
        # set in $u object for callers later
        ## hm, doesn't "set_prop" do it?
        $u->{legal_tosagree} = $newval;
        return $rv;
    } else {
        $$err = "Internal error: can't set prop legal_tosagree";
        return;
    }
}

sub tosagree_verify {
    my $u = shift;
    return 1 unless $LJ::TOS_CHECK;

    my $rev_req = $LJ::REQUIRED_TOS{rev};
    return 1 unless $rev_req > 0;

    my $rev_cur = (split(/\s*,\s*/, $u->prop("legal_tosagree")))[1];
    return $rev_cur eq $rev_req;
}

# my $sess = $u->session           (returns current session)
# my $sess = $u->session($sessid)  (returns given session id for user)

sub session {
    my ($u, $sessid) = @_;
    $sessid = $sessid + 0;
    return $u->{_session} unless $sessid;  # should be undef, or LJ::Session hashref
    return LJ::Session->instance($u, $sessid);
}

# in list context, returns an array of LJ::Session objects which are active.
# in scalar context, returns hashref of sessid -> LJ::Session, which are active
sub sessions {
    my $u = shift;
    my @sessions = LJ::Session->active_sessions($u);
    return @sessions if wantarray;
    my $ret = {};
    foreach my $s (@sessions) {
        $ret->{$s->id} = $s;
    }
    return $ret;
}

sub logout {
    my $u = shift;
    if (my $sess = $u->session) {
        $sess->destroy;
    }
    $u->_logout_common;
}

sub logout_all {
    my $u = shift;
    LJ::Session->destroy_all_sessions($u)
        or die "Failed to logout all";
    $u->_logout_common;
}

sub _logout_common {
    my $u = shift;
    LJ::Session->clear_master_cookie;
    LJ::User->set_remote(undef);
    delete $BML::COOKIE{'BMLschemepref'};
    delete $BML::COOKIE{'cart'};
    eval { BML::set_scheme(undef); };
    LJ::run_hooks("user_logout");
}

# returns a new LJ::Session object, or undef on failure
sub create_session
{
    my ($u, %opts) = @_;
    return LJ::Session->create($u, %opts);
}

# $u->kill_session(@sessids)
sub kill_sessions {
    my $u = shift;
    return LJ::Session->destroy_sessions($u, @_);
}

sub kill_all_sessions {
    my $u = shift
        or return 0;

    LJ::Session->destroy_all_sessions($u)
        or return 0;

    # forget this user, if we knew they were logged in
    if ($LJ::CACHE_REMOTE && $LJ::CACHE_REMOTE->{userid} == $u->{userid}) {
        LJ::Session->clear_master_cookie;
        LJ::User->set_remote(undef);
    }

    return 1;
}

sub kill_session {
    my $u = shift
        or return 0;
    my $sess = $u->session
        or return 0;

    $sess->destroy;

    if ($LJ::CACHE_REMOTE && $LJ::CACHE_REMOTE->{userid} == $u->{userid}) {
        LJ::Session->clear_master_cookie;
        LJ::User->set_remote(undef);
    }

    return 1;
}

# <LJFUNC>
# name: LJ::User::mogfs_userpic_key
# class: mogilefs
# des: Make a mogilefs key for the given pic for the user.
# args: pic
# des-pic: Either the userpic hash or the picid of the userpic.
# returns: 1.
# </LJFUNC>
sub mogfs_userpic_key {
    my $self = shift or return undef;
    my $pic = shift or croak "missing required arg: userpic";

    my $picid = ref $pic ? $pic->{picid} : $pic+0;
    return "up:$self->{userid}:$picid";
}

# all reads/writes to talk2 must be done inside a lock, so there's
# no race conditions between reading from db and putting in memcache.
# can't do a db write in between those 2 steps.  the talk2 -> memcache
# is elsewhere (talklib.pl), but this $dbh->do wrapper is provided
# here because non-talklib things modify the talk2 table, and it's
# nice to centralize the locking rules.
#
# return value is return of $dbh->do.  $errref scalar ref is optional, and
# if set, gets value of $dbh->errstr
#
# write:  (LJ::talk2_do)
#   GET_LOCK
#    update/insert into talk2
#   RELEASE_LOCK
#    delete memcache
#
# read:   (LJ::Talk::get_talk_data)
#   try memcache
#   GET_LOCk
#     read db
#     update memcache
#   RELEASE_LOCK

sub talk2_do {
    #my ($u, $nodetype, $nodeid, $errref, $sql, @args) = @_;
    my $u = shift;
    my %args = @_;
    my $nodetype = $args{nodetype};
    my $nodeid   = $args{nodeid};
    my $errref   = $args{errref};
    my $sql      = $args{sql};
    my @bindings = ref $args{bindings} eq 'ARRAY' ? @{$args{bindings}} : ();
    my $flush_cache = exists $args{flush_cache} ? $args{flush_cache} : 1;
    
    # some checks
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;
    return undef unless $u->writer;

    my $dbcm = $u->writer;

    my $memkey = [$u->{'userid'}, "talk2:$u->{'userid'}:$nodetype:$nodeid"];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    my $ret = $u->do($sql, undef, @bindings);
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    # flush talks tree.
    LJ::MemCache::delete($memkey, 0) if int($ret) and $flush_cache;

    return $ret;
}




# log2_do
# see comments for talk2_do

sub log2_do {
    my ($u, $errref, $sql, @args) = @_;
    return undef unless $u->writer;

    my $dbcm = $u->writer;

    my $memkey = [$u->{'userid'}, "log2lt:$u->{'userid'}"];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    my $ret = $u->do($sql, undef, @args);
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    LJ::MemCache::delete($memkey, 0) if int($ret);
    return $ret;
}

sub url {
    my $u = shift;

    my $url;

    if ($u->is_identity && !$u->prop('url')) {
        $u->set_prop( 'url' => $u->identity->url($u) );
    }

    $url ||= $u->prop('url');
    return unless $url;

    $url = "http://$url" unless $url =~ m!^https?://!;

    return $url;
}

# there are two procedures for finding an LJ::Identity object for the given
# user, the difference being that identity() checks for journaltype eq 'I'
# while find_identity() does not. this is done this way for backwards
# compatibility: some parts of LJ code use identity() to check what
# is_identity() checks (suboptimal, yes, but it works that way)

sub find_identity {
    my ($u) = @_;

    return $u->{'_identity'} if $u->{'_identity'};

    my $memkey = [$u->{userid}, "ident:$u->{userid}"];
    my $ident = LJ::MemCache::get($memkey);
    if ($ident) {
        my $i = LJ::Identity->new(
                                  typeid => $ident->[0],
                                  value  => $ident->[1],
                                  );

        return $u->{_identity} = $i;
    }

    my $dbh = LJ::get_db_writer();
    $ident = $dbh->selectrow_arrayref("SELECT idtype, identity FROM identitymap ".
                                      "WHERE userid=? LIMIT 1", undef, $u->{userid});
    if ($ident) {
        LJ::MemCache::set($memkey, $ident);
        my $i = LJ::Identity->new(
                                  typeid => $ident->[0],
                                  value  => $ident->[1],
                                  );
        return $i;
    }

    return;
}

sub identity {
    my ($u) = @_;

    return unless $u->is_identity;
    return $u->find_identity;
}

# returns a URL if account is an OpenID identity.  undef otherwise.
sub openid_identity {
    my $u = shift;
    my $ident = $u->identity;
    return undef unless $ident && $ident->typeid == 0;
    return $ident->value;
}

# returns username or identity display name 
sub display_name {
    my $u = shift;
    return $u->username unless $u->is_identity;

    my $id = $u->identity;
    return "[ERR:unknown_identity]" unless $id;
    return LJ::ehtml( $id->display_name($u) );
}

sub ljuser_display {
    my ($u, $opts) = @_;
    return LJ::ljuser($u, $opts);
}

# class function - load an identity user, but only if they're already known to us
sub load_existing_identity_user {
    my ($type, $ident) = @_;

    my $dbh = LJ::get_db_reader();
    my $uid = $dbh->selectrow_array("SELECT userid FROM identitymap WHERE idtype=? AND identity=?",
                                    undef, $type, $ident);
    return $uid ? LJ::load_userid($uid) : undef;
}

# class function - load an identity user, and if we've never seen them before create a user account for them
sub load_identity_user {
    my ($type, $ident, $extra, $created_ref) = @_;

    my $u = load_existing_identity_user($type, $ident);

    # If the user is marked as expunged, move identity mapping aside
    # and continue to create new account.
    # Otherwise return user if it exists.
    if ($u) {
        if ($u->is_expunged) {
            return undef unless ($u->rename_identity);
        } else {
            return $u;
        }
    }

    # increment ext_ counter until we successfully create an LJ
    # account.  hard cap it at 10 tries. (arbitrary, but we really
    # shouldn't have *any* failures here, let alone 10 in a row)
    my $dbh = LJ::get_db_writer();
    my $uid;

    for (1..10) {
        my $extuser = 'ext_' . LJ::alloc_global_counter('E');

        $uid = LJ::create_account({
            caps => undef,
            user => $extuser,
            name => $extuser,
            journaltype => 'I',
        });

        last if $uid;
        select undef, undef, undef, .10;  # lets not thrash over this
    }
    return undef unless $uid &&
        $dbh->do("INSERT INTO identitymap (idtype, identity, userid) VALUES (?,?,?)",
                 undef, $type, $ident, $uid);

    $u = LJ::load_userid($uid);

    $u->identity->initialize_user($u, $extra);
    $$created_ref = 1 if $created_ref;

    # record create information
    my $remote = LJ::get_remote();
    $u->log_event('account_create', { remote => $remote });

    return $u;
}

sub remove_identity {
    my ($u) = @_;

    my $dbh = LJ::get_db_writer();
    $dbh->do( 'DELETE FROM identitymap WHERE userid=?', undef, $u->id );

    delete $u->{'_identity'};
    
     my $memkey = [$u->{userid}, "ident:$u->{userid}"];
     LJ::MemCache::delete($memkey);     
}

# instance method:  returns userprop for a user.  currently from cache with no
# way yet to force master.
sub prop {
    my ($u, $prop) = @_;

    # some props have accessors which do crazy things, if so they need
    # to be redirected from this method, which only loads raw values
    if ({ map { $_ => 1 }
          qw(opt_sharebday opt_showbday opt_showlocation opt_showmutualfriends
             view_control_strip show_control_strip opt_ctxpopup opt_embedplaceholders
             esn_inbox_default_expand opt_getting_started)
        }->{$prop})
    {
        return $u->$prop;
    }

    return $u->raw_prop($prop);
}

sub raw_prop {
    my ($u, $prop) = @_;
    $u->preload_props($prop) unless exists $u->{$prop};
    return $u->{$prop};
}

sub _lazy_migrate_infoshow {
    my ($u) = @_;
    return 1 if $LJ::DISABLED{infoshow_migrate};

    # 1) column exists, but value is migrated
    # 2) column has died from 'user')
    if ($u->{allow_infoshow} eq ' ' || ! $u->{allow_infoshow}) {
        return 1; # nothing to do
    }

    my $infoval = $u->{allow_infoshow} eq 'Y' ? undef : 'N';

    # need to migrate allow_infoshow => opt_showbday
    if ($infoval) {
        foreach my $prop (qw(opt_showbday opt_showlocation)) {
            $u->set_prop($prop => $infoval);
        }
    }

    # setting allow_infoshow to ' ' means we've migrated it
    LJ::update_user($u, { allow_infoshow => ' ' })
        or die "unable to update user after infoshow migration";
    $u->{allow_infoshow} = ' ';

    return 1;
}

# opt_showbday options
# F - Full Display of Birthday
# D - Only Show Month/Day
# Y - Only Show Year
# N - Do not display
sub opt_showbday {
    my $u = shift;
    # option not set = "yes", set to N = "no"
    $u->_lazy_migrate_infoshow;

    # migrate above did nothing
    # -- if user was already migrated in the past, we'll
    #    fall through and show their prop value
    # -- if user not migrated yet, we'll synthesize a prop
    #    value from infoshow without writing it
    if ($LJ::DISABLED{infoshow_migrate} && $u->{allow_infoshow} ne ' ') {
        return $u->{allow_infoshow} eq 'Y' ? undef : 'N';
    }
    if ($u->raw_prop('opt_showbday') =~ /^(D|F|N|Y)$/) {
        return $u->raw_prop('opt_showbday');
    } else {
        return 'D';
    }
}

# opt_sharebday options
# A - All people
# R - Registered Users
# F - Friends Only
# N - Nobody
sub opt_sharebday {
    my $u = shift;

    if ($u->raw_prop('opt_sharebday') =~ /^(A|F|N|R)$/) {
        return $u->raw_prop('opt_sharebday');
    } else {
        return 'N' if ($u->underage || $u->is_child);
        return 'F' if ($u->is_minor);
        return 'A';
    }
}

# opt_showljtalk options based on user setting
# Y = Show the LJ Talk field on profile (default)
# N = Don't show the LJ Talk field on profile
sub opt_showljtalk {
    my $u = shift;

    # Check for valid value, or just return default of 'Y'.
    if ($u->raw_prop('opt_showljtalk') =~ /^(Y|N)$/) {
        return $u->raw_prop('opt_showljtalk');
    } else {
        return 'Y';
    }
}

# Show LJ Talk field on profile?  opt_showljtalk needs a value of 'Y'.
sub show_ljtalk {
    my $u = shift;
    croak "Invalid user object passed" unless LJ::isu($u);

    # Fail if the user wants to hide the LJ Talk field on their profile,
    # or doesn't even have the ability to show it.
    return 0 if $u->opt_showljtalk eq 'N' || $LJ::DISABLED{'ljtalk'} || !$u->is_person;

    # User either decided to show LJ Talk field or has left it at the default.
    return 1 if $u->opt_showljtalk eq 'Y';
}

# Hide the LJ Talk field on profile?  opt_showljtalk needs a value of 'N'.
sub hide_ljtalk {
    my $u = shift;
    croak "Invalid user object passed" unless LJ::isu($u);

    # ... The opposite of showing the field. :)
    return $u->show_ljtalk ? 0 : 1;
}

sub ljtalk_id {
    my $u = shift;
    croak "Invalid user object passed" unless LJ::isu($u);

    return $u->{'user'}.'@'.$LJ::USER_DOMAIN;
}

sub opt_showlocation {
    my $u = shift;
    # option not set = "yes", set to N = "no"
    $u->_lazy_migrate_infoshow;

    # see comments for opt_showbday
    if ($LJ::DISABLED{infoshow_migrate} && $u->{allow_infoshow} ne ' ') {
        return $u->{allow_infoshow} eq 'Y' ? undef : 'N';
    }
    if ($u->raw_prop('opt_showlocation') =~ /^(N|Y|R|F)$/) {
        return $u->raw_prop('opt_showlocation');
    } else {
        return 'N' if ($u->underage || $u->is_child);
        return 'F' if ($u->is_minor);
        return 'Y';
    }
}

sub opt_showcontact {
    my $u = shift;

    if ($u->{'allow_contactshow'} =~ /^(N|Y|R|F)$/) {
        return $u->{'allow_contactshow'};
    } else {
        return 'N' if ($u->underage || $u->is_child);
        return 'F' if ($u->is_minor);
        return 'Y';
    }
}

# opt_showonlinestatus options
# F = Mutual Friends
# Y = Everybody
# N = Nobody
sub opt_showonlinestatus {
    my $u = shift;

    if ($u->raw_prop('opt_showonlinestatus') =~ /^(F|N|Y)$/) {
        return $u->raw_prop('opt_showonlinestatus');
    } else {
        return 'F';
    }
}

sub can_show_location {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    my %opts = @_;
    my $remote = $opts{remote} || LJ::get_remote();

    return 0 if $u->underage;
    return 0 if ($u->opt_showlocation eq 'N');
    return 0 if ($u->opt_showlocation eq 'R' && !$remote);
    return 0 if ($u->opt_showlocation eq 'F' && !$u->is_friend($remote));
    return 1;
}

sub can_show_onlinestatus {
    my $u = shift;
    my $remote = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    # Nobody can see online status of u
    return 0 if $u->opt_showonlinestatus eq 'N';
    # Everybody can see online status of u
    return 1 if $u->opt_showonlinestatus eq 'Y';
    # Only mutual friends of u can see online status
    if ($u->opt_showonlinestatus eq 'F') {
        return 0 unless $remote;
        return 1 if $u->is_mutual_friend($remote);
        return 0;
    }
    return 0;
}

# return the setting indicating how a user can be found by their email address
# Y - Findable, N - Not findable, H - Findable but identity hidden
sub opt_findbyemail {
    my $u = shift;

    if ($u->raw_prop('opt_findbyemail') =~ /^(N|Y|H)$/) {
        return $u->raw_prop('opt_findbyemail');
    } else {
        return undef;
    }
}

# return user selected mail encoding or undef
sub mailencoding {
    my $u = shift;
    my $enc = $u->prop('mailencoding');

    return undef unless $enc;

    LJ::load_codes({ "encoding" => \%LJ::CACHE_ENCODINGS } )
        unless %LJ::CACHE_ENCODINGS;
    return $LJ::CACHE_ENCODINGS{$enc}
}

# Birthday logic -- show appropriate string based on opt_showbday
# This will return true if the actual birthday can be shown
sub can_show_bday {
    my ($u, %opts) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'D' || $u->opt_showbday eq 'F';
    return 1;
}

# Birthday logic -- can any of the birthday info be shown
# This will return true if any birthday info can be shown
sub can_share_bday {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    my %opts = @_;
    my $with_u = $opts{with} || LJ::get_remote();

    return 0 if ($u->opt_sharebday eq 'N');
    return 0 if ($u->opt_sharebday eq 'R' && !$with_u);
    return 0 if ($u->opt_sharebday eq 'F' && !$u->is_friend($with_u));
    return 1;
}


# This will return true if the actual birth year can be shown
sub can_show_bday_year {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    my %opts = @_;
    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'Y' || $u->opt_showbday eq 'F';
    return 1;
}

# This will return true if month, day, and year can be shown
sub can_show_full_bday {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    my %opts = @_;
    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'F';
    return 1;
}

# This will format the birthdate based on the user prop
sub bday_string {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);
    return 0 if $u->underage;

    my $bdate = $u->{'bdate'};
    my ($year,$mon,$day) = split(/-/, $bdate);
    my $bday_string = '';

    if ($u->can_show_full_bday && $day > 0 && $mon > 0 && $year > 0) {
        $bday_string = $bdate;
    } elsif ($u->can_show_bday && $day > 0 && $mon > 0) {
        $bday_string = "$mon-$day";
    } elsif ($u->can_show_bday_year && $year > 0) {
        $bday_string = $year;
    }
    $bday_string =~ s/^0000-//;
    return $bday_string;
}

# Users age based off their profile birthdate
sub age {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    my $bdate = $u->{bdate};
    return unless length $bdate;

    my ($year, $mon, $day) = $bdate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $age = LJ::TimeUtil->calc_age($year, $mon, $day);
    return $age if $age > 0;
    return;
}

sub age_for_adcall {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);
    
    return undef if $u->underage;
    return eval {$u->age || $u->init_age};
}

# This returns the users age based on the init_bdate (users coppa validation birthdate)
sub init_age {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    my $init_bdate = $u->prop('init_bdate');
    return unless $init_bdate;

    my ($year, $mon, $day) = $init_bdate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $age = LJ::TimeUtil->calc_age($year, $mon, $day);
    return $age if $age > 0;
    return;
}

# Returns the best guess age of the user, which is init_age if it exists, otherwise age
sub best_guess_age {
    my $u = shift;
    return 0 unless $u->is_person || $u->is_identity;
    return $u->init_age || $u->age;
}

sub gender_for_adcall {
    my $u = shift;
    my $format = shift || '6a';
    croak "Invalid user object" unless LJ::isu($u);

    my $gender = $u->prop('gender') || '';
    $gender = uc(substr($gender, 0, 1));
    if ($format eq '6a') {
        if ($gender && $gender !~ /^U/i) {
            return $gender; # M|F
        } else {
            return "unspecified";
        }
    } elsif ($format eq 'dc') {
        return  ($gender eq 'M') ? 1 :
                ($gender eq 'F') ? 2 : 0;
    } elsif ($format eq 'ga') {
        return  ($gender eq 'M') ? 'male' :
                ($gender eq 'F') ? 'female' : 'all';
    } else {
        return;
    }
}

sub should_fire_birthday_notif {
    my $u = shift;

    return 0 unless $u->is_person;
    return 0 unless $u->is_visible;

    # if the month/day can't be shown
    return 0 if $u->opt_showbday =~ /^[YN]$/;

    # if the birthday isn't shown to anyone
    return 0 if $u->opt_sharebday eq "N";

    # note: this isn't intended to capture all cases where birthday
    # info is restricted. we want to pare out as much as possible;
    # individual "can user X see this birthday" is handled in
    # LJ::Event::Birthday->matches_filter

    return 1;
}

sub next_birthday {
    my $u = shift;
    return if $u->is_expunged;

    return $u->selectrow_array("SELECT nextbirthday FROM birthdays " .
                               "WHERE userid = ?", undef, $u->id)+0;
}

# class method, loads next birthdays for a bunch of users
sub next_birthdays {
    my $class = shift;

    # load the users we need, so we can get their clusters
    my $clusters = LJ::User->split_by_cluster(@_);

    my %bdays = ();
    foreach my $cid (keys %$clusters) {
        next unless $cid;

        my @users = @{$clusters->{$cid} || []};
        my $dbcr = LJ::get_cluster_def_reader($cid)
            or die "Unable to load reader for cluster: $cid";

        my $bind = join(",", map { "?" } @users);
        my $sth = $dbcr->prepare("SELECT * FROM birthdays WHERE userid IN ($bind)");
        $sth->execute(@users);
        while (my $row = $sth->fetchrow_hashref) {
            $bdays{$row->{userid}} = $row->{nextbirthday};
        }
    }

    return \%bdays;
}


# this sets the unix time of their next birthday for notifications
sub set_next_birthday {
    my $u = shift;
    return if $u->is_expunged;

    my ($year, $mon, $day) = split(/-/, $u->{bdate});
    unless ($mon > 0 && $day > 0) {
        $u->do("DELETE FROM birthdays WHERE userid = ?", undef, $u->id);
        return;
    }

    my $as_unix = sub {
        return LJ::TimeUtil->mysqldate_to_time(sprintf("%04d-%02d-%02d", @_));
    };

    my $curyear = (gmtime(time))[5]+1900;

    # Calculate the time of their next birthday.

    # Assumption is that birthday-notify jobs won't be backed up.
    # therefore, if a user's birthday is 1 day from now, but
    # we process notifications for 2 days in advance, their next
    # birthday is really a year from tomorrow.

    # We need to do calculate three possible "next birthdays":
    # Current Year + 0: For the case where we it for the first
    #   time, which could happen later this year.
    # Current Year + 1: For the case where we're setting their next
    #   birthday on (approximately) their birthday. Gotta set it for
    #   next year. This works in all cases but...
    # Current Year + 2: For the case where we're processing notifs
    #   for next year already (eg, 2 days in advance, and we do
    #   1/1 birthdays on 12/30). Year + 1 gives us the date two days
    #   from now! So, add another year on top of that.

    # We take whichever one is earliest, yet still later than the
    # window of dates where we're processing notifications.

    my $bday;
    for my $inc (0..2) {
        $bday = $as_unix->($curyear + $inc, $mon, $day);
        last if $bday > time() + $LJ::BIRTHDAY_NOTIFS_ADVANCE;
    }

    # up to twelve hours drift so we don't get waves
    $bday += int(rand(12*3600));

    $u->do("REPLACE INTO birthdays VALUES (?, ?)", undef, $u->id, $bday);
    die $u->errstr if $u->err;

    return $bday;
}


sub include_in_age_search {
    my $u = shift;

    # if they don't display the year
    return 0 if $u->opt_showbday =~ /^[DN]$/;

    # if it's not visible to registered users
    return 0 if $u->opt_sharebday =~ /^[NF]$/;

    return 1;
}


# data for generating packed directory records
sub usersearch_age_with_expire {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    # don't include their age in directory searches
    # if it's not publicly visible in their profile
    my $age = $u->include_in_age_search ? $u->age : 0;
    $age += 0;

    # no need to expire due to age if we don't have a birthday
    my $expire = $u->next_birthday || undef;

    return ($age, $expire);
}

# returns the country specified by the user
sub country {
    my $u = shift;
    return $u->prop('country');
}

# sets prop, and also updates $u's cached version
sub set_prop {
    my ($u, $prop, $value) = @_;

    my $propmap = ref $prop ? $prop : { $prop => $value };

    # filter out props that do not change
    foreach my $propname (keys %$propmap) {
        # it's not loaded, so let's not check it
        next unless exists $u->{$propname};

        if ( (!$propmap->{$propname} && !$u->{$propname})
          || $propmap->{$propname} eq $u->{$propname} )
        {
            delete $propmap->{$propname};
        }
    }

    my @props_affected = keys %$propmap;
    my $groups = LJ::User::PropStorage->get_handler_multi(\@props_affected);
    my $memcache_available = @LJ::MEMCACHE_SERVERS;

    my $memc_expire = time + 3600 * 24;

    foreach my $handler (keys %$groups) {
        my $propnames_handled = $groups->{$handler};
        my %propmap_handled   = map { $_ => $propmap->{$_} }
                                @$propnames_handled;

        # first, actually save stuff to the database;
        # then, delete it from memcache, depending on the memcache
        # policy of the handler
        $handler->set_props( $u, \%propmap_handled );

        # if there is no memcache, or if the handler doesn't wish to use
        # memcache, we don't need to deal with it, yay
        if ( !$memcache_available || !defined $handler->use_memcache )
        {
            next;
        }

        # now let's find out what we're going to do with memcache
        my $memcache_policy = $handler->use_memcache;

        if ( $memcache_policy eq 'lite' ) {
            # the handler loads everything from the corresponding
            # table and uses only one memcache key to cache that

            my $memkey = $handler->memcache_key($u);
            LJ::MemCache::delete([ $u->userid, $memkey ]);
        } elsif ( $memcache_policy eq 'blob' ) {
            # the handler uses one memcache key for each prop,
            # so let's delete them all

            foreach my $propname (@$propnames_handled) {
                my $memkey = $handler->memcache_key( $u, $propname );
                LJ::MemCache::delete([ $u->userid, $memkey ]);
            }
        }
    }

    # now, actually reflect that we've changed the props in the
    # user object
    foreach my $propname (keys %$propmap) {
        $u->{$propname} = $propmap->{$propname};
    }

    # and run the hooks, too
    LJ::run_hooks( 'props_changed', $u, $propmap );

    return $value;
}

sub clear_prop {
    my ($u, $prop) = @_;
    $u->set_prop($prop, undef);
    return 1;
}

sub journal_base {
    my $u = shift;
    return LJ::journal_base($u);
}

sub allpics_base {
    my $u = shift;
    return "$LJ::SITEROOT/allpics.bml?user=" . $u->user;
}

sub get_userpic_count {
    my $u = shift or return undef;
    my $count = scalar LJ::Userpic->load_user_userpics($u);

    return $count;
}

sub userpic_quota {
    my $u = shift or return undef;
    my $quota = $u->get_cap('userpics');

    return $quota;
}

sub friendsfriends_url {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    return $u->journal_base . "/friendsfriends";
}

sub wishlist_url {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    return $u->journal_base . "/wishlist";
}

sub profile_url {
    my ($u, %opts) = @_;

    my $url;
    if ($u->{journaltype} eq "I") {
        $url = "$LJ::SITEROOT/userinfo.bml?userid=$u->{'userid'}&t=I";
        $url .= "&mode=full" if $opts{full};
    } else {
        $url = $u->journal_base . "/profile";
        $url .= "?mode=full" if $opts{full};
    }
    return $url;
}

sub addfriend_url {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    return "$LJ::SITEROOT/friends/add.bml?user=$u->{'user'}";
}

# returns the gift shop URL to buy a gift for that user
sub gift_url {
    my ($u, $opts) = @_;
    croak "invalid user object passed" unless LJ::isu($u);
    my $item = $opts->{item} ? delete $opts->{item} : '';

    return "$LJ::SITEROOT/shop/view.bml?item=$item&gift=1&for=$u->{'user'}";
}

# return the URL to the send message page
sub message_url {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    return undef if $LJ::DISABLED{user_messaging};
    return "$LJ::SITEROOT/inbox/compose.bml?user=$u->{'user'}";
}

# <LJFUNC>
# name: LJ::User::large_journal_icon
# des: get the large icon by journal type.
# returns: HTML to display large journal icon.
# </LJFUNC>
sub large_journal_icon {
    my $u = shift;
    croak "invalid user object"
        unless LJ::isu($u);

    my $wrap_img = sub {
        return "<img src='$LJ::IMGPREFIX/$_[0]' border='0' height='24' " .
            "width='24' style='padding: 0px 2px 0px 0px' />";
    };

    # hook will return image to use if it cares about
    # the $u it's been passed
    my $hook_img = LJ::run_hook("large_journal_icon", $u);
    return $wrap_img->($hook_img) if $hook_img;

    if ($u->is_comm) {
        return $wrap_img->("community24x24.gif");
    }

    if ($u->is_syndicated) {
        return $wrap_img->("syndicated24x24.gif");
    }

    if ($u->is_identity) {
        return $wrap_img->("openid24x24.gif");
    }

    # personal, news, or unknown fallthrough
    return $wrap_img->("userinfo24x24.gif");
}

# <LJFUNC>
# name: LJ::User::caps_icon
# des: get the icon for a user's cap.
# returns: HTML with site-specific cap icon.
# </LJFUNC>
sub caps_icon {
    my $u = shift;
    return LJ::user_caps_icon($u->{caps});
}

# <LJFUNC>
# name: LJ::User::get_friends_birthdays
# des: get the upcoming birthdays for friends of a user. shows birthdays 3 months away by default
#      pass in full => 1 to get all friends' birthdays.
# returns: arrayref of [ month, day, user ] arrayrefs
# </LJFUNC>
sub get_friends_birthdays {
    my $u = shift;
    return undef unless LJ::isu($u);

    my %opts = @_;
    my $months_ahead = $opts{months_ahead} || 3;
    my $full = $opts{full};

    # what day is it now?
    my $now = $u->time_now;
    my ($mnow, $dnow) = ($now->month, $now->day);

    my $bday_sort = sub {
        # first we sort them normally...
        my @bdays = sort {
            ($a->[0] <=> $b->[0]) || # month sort
            ($a->[1] <=> $b->[1])    # day sort
        } @_;

        # fast path out if we're getting all birthdays.
        return @bdays if $full;

        # then we need to push some stuff to the end. consider "three months ahead"
        # from november ... we'd get data from january, which would appear at the
        # head of the list.
        my $nowstr = sprintf("%02d-%02d", $mnow, $dnow);
        my $i = 0;
        while ($i++ < @bdays && sprintf("%02d-%02d", @{ $bdays[0] }) lt $nowstr) {
            push @bdays, shift @bdays;
        }

        return @bdays;
    };

    my $memkey = [$u->userid, 'frbdays:' . $u->userid . ':' . ($full ? 'full' : $months_ahead)];
    my $cached_bdays = LJ::MemCache::get($memkey);
    return $bday_sort->(@$cached_bdays) if $cached_bdays;

    my @friends = $u->friends;
    my @bdays;

    foreach my $friend (@friends) {
        my ($year, $month, $day) = split('-', $friend->{bdate});
        next unless $month > 0 && $day > 0;

        # skip over unless a few months away (except in full mode)
        unless ($full) {
            # the case where months_ahead doesn't wrap around to a new year
            if ($mnow + $months_ahead <= 12) {
                # discard old months
                next if $month < $mnow;
                # discard months too far in the future
                next if $month > $mnow + $months_ahead;

            # the case where we wrap around the end of the year (eg, oct->jan)
            } else {
                # we're okay if the month is in the future, because
                # we KNOW we're wrapping around. but if the month is
                # in the past, we need to verify that we've wrapped
                # around and are still within the timeframe
                next if ($month < $mnow) && ($month > ($mnow + $months_ahead) % 12);
            }

            # month is fine. check the day.
            next if ($month == $mnow && $day < $dnow);
        }

        if ($friend->can_show_bday) {
            push @bdays, [ $month, $day, $friend->user ];
        }
    }

    # set birthdays in memcache for later
    LJ::MemCache::set($memkey, \@bdays, 86400);

    return $bday_sort->(@bdays);
}

# tests to see if a user is in a specific named class. class
# names are site-specific.
sub in_any_class {
    my ($u, @classes) = @_;

    foreach my $class (@classes) {
        return 1 if LJ::caps_in_group($u->{caps}, $class);
    }

    return 0;
}


# get recent talkitems posted to this user
# args: maximum number of comments to retrieve
# returns: array of hashrefs with jtalkid, nodetype, nodeid, parenttalkid, posterid, state
sub get_recent_talkitems {
    my ($u, $maxshow, %opts) = @_;

    $maxshow ||= 15;
    my $max_fetch = int($LJ::TOOLS_RECENT_COMMENTS_MAX*1.5) || 150;
    # We fetch more items because some may be screened
    # or from suspended users, and we weed those out later
    
    my $remote   = $opts{remote} || LJ::get_remote();
    return undef unless LJ::isu($u);
    
    ## $raw_talkitems - contains DB rows that are not filtered 
    ## to match remote user's permissions to see
    my $raw_talkitems;
    my $memkey = [$u->userid, 'rcntalk:' . $u->userid ];
    $raw_talkitems = LJ::MemCache::get($memkey);
    if (!$raw_talkitems) {
        my $sth = $u->prepare(
            "SELECT jtalkid, nodetype, nodeid, parenttalkid, ".
            "       posterid, UNIX_TIMESTAMP(datepost) as 'datepostunix', state ".
            "FROM talk2 ".
            "WHERE journalid=? AND (state <> 'D' AND state <> 'B') " .
            "ORDER BY jtalkid DESC ".
            "LIMIT $max_fetch"
        ); 
        $sth->execute($u->{'userid'});
        $raw_talkitems = $sth->fetchall_arrayref({});
        LJ::MemCache::set($memkey, $raw_talkitems, 60*5);
    }

    ## Check remote's permission to see the comment, and create singletons
    my @recv;
    foreach my $r (@$raw_talkitems) {
        last if @recv >= $maxshow;

        # construct an LJ::Comment singleton
        my $comment = LJ::Comment->new($u, jtalkid => $r->{jtalkid});
        $comment->absorb_row($r);
        next unless $comment->visible_to($remote);
        push @recv, $r;
    }

    # need to put the comments in order, with "oldest first"
    # they are fetched from DB in "recent first" order
    return reverse @recv;
}

sub last_login_time {
    my ($u) = @_;

    my $dbr = LJ::get_cluster_reader($u);
    my ($time) = $dbr->selectrow_array(qq{
        SELECT MAX(logintime) FROM loginlog WHERE userid=?
    }, undef, $u->id);

    $time ||= 0;

    return $time;
}

sub last_password_change_time {
    my ($u) = @_;

    my $dbr = LJ::get_db_reader();
    my ($time) = $dbr->selectrow_array(
        'SELECT UNIX_TIMESTAMP(MAX(timechange)) FROM infohistory ' .
        'WHERE userid=? AND what="password"',
        undef,
        $u->userid,
    );

    $time ||= 0;
    return $time;
}

# THIS IS DEPRECATED DO NOT USE
sub email {
    my ($u, $remote) = @_;
    return $u->emails_visible($remote);
}

sub email_raw {
    my $u = shift;
    $u->{_email} ||= LJ::MemCache::get_or_set([$u->{userid}, "email:$u->{userid}"], sub {
        my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
        return $dbh->selectrow_array("SELECT email FROM email WHERE userid=?",
                                     undef, $u->id);
    });
    return $u->{_email};
}

sub validated_mbox_sha1sum { 
    my $u = shift;

    # must be validated
    return undef unless $u->is_validated;

    # must have one on file
    my $email = $u->email_raw;
    return undef unless $email;

    # return SHA1, which does not disclose the actual value
    return Digest::SHA1::sha1_hex('mailto:' . $email);
}

# in scalar context, returns user's email address.  given a remote user,
# bases decision based on whether $remote user can see it.  in list context,
# returns all emails that can be shown
sub email_visible {
    my ($u, $remote) = @_;

    return scalar $u->emails_visible($remote);
}

sub emails_visible {
    my ($u, $remote) = @_;

    return () if $u->{journaltype} =~ /[YI]/;

    # security controls
    return () unless $u->share_contactinfo($remote);

    my $whatemail = $u->prop("opt_whatemailshow");
    my $useremail_cap = LJ::get_cap($u, 'useremail');

    # some classes of users we want to have their contact info hidden
    # after so much time of activity, to prevent people from bugging
    # them for their account or trying to brute force it.
    my $hide_contactinfo = sub {
        my $hide_after = LJ::get_cap($u, "hide_email_after");
        return 0 unless $hide_after;
        my $memkey = [$u->{userid}, "timeactive:$u->{userid}"];
        my $active;
        unless (defined($active = LJ::MemCache::get($memkey))) {
            my $dbcr = LJ::get_cluster_def_reader($u) or return 0;
            $active = $dbcr->selectrow_array("SELECT timeactive FROM clustertrack2 ".
                                             "WHERE userid=?", undef, $u->{userid});
            LJ::MemCache::set($memkey, $active, 86400);
        }
        return $active && (time() - $active) > $hide_after * 86400;
    };

    return () if $u->{'opt_whatemailshow'} eq "N" ||
        $u->{'opt_whatemailshow'} eq "L" && ($u->prop("no_mail_alias") || ! $useremail_cap || ! $LJ::USER_EMAIL) ||
        $hide_contactinfo->();

    my @emails = ($u->email_raw);
    if ($u->{'opt_whatemailshow'} eq "L") {
        @emails = ();
    }
    if ($LJ::USER_EMAIL && $useremail_cap) {
        unless ($u->{'opt_whatemailshow'} eq "A" || $u->prop('no_mail_alias')) {
            push @emails, "$u->{'user'}\@$LJ::USER_DOMAIN";
        }
    }
    return wantarray ? @emails : $emails[0];
}

sub email_for_feeds {
    my $u = shift;

    # don't display if it's mangled
    return if $u->prop("opt_mangleemail") eq "Y";

    my $remote = LJ::get_remote();
    return $u->email_visible($remote);
}

sub email_status {
    my $u = shift;
    return $u->{status};
}

sub is_validated {
    my $u = shift;
    return $u->email_status eq "A";
}

sub update_email_alias {
    my $u = shift;

    return unless $u && $u->get_cap("useremail");
    return if exists $LJ::FIXED_ALIAS{$u->{'user'}};
    return if $u->prop("no_mail_alias");
    return unless $u->is_validated;

    my $dbh = LJ::get_db_writer();
    $dbh->do("REPLACE INTO email_aliases (alias, rcpt) VALUES (?,?)",
             undef, "$u->{'user'}\@$LJ::USER_DOMAIN", $u->email_raw);

    return 0 if $dbh->err;
    return 1;
}

# this is DEPRECATED in favor of can_reset_password_using_email
sub can_receive_password {
    my ($u, $email) = @_;

    return 0 unless $u && $email;
    return 1 if lc($email) eq lc($u->email_raw);

    my $dbh = LJ::get_db_reader();
    return $dbh->selectrow_array("SELECT COUNT(*) FROM infohistory ".
                                 "WHERE userid=? AND what='email' ".
                                 "AND oldvalue=? AND other='A'",
                                 undef, $u->id, $email);
}

# my $u = LJ::want_user(12);
# my $data = $u->get_email_data('test@test.ru');
# print $data->{'email_state'}; # email status if test@test.ru is the
#                               # current email; "P" otherwise
# print $data->{'time'}; # time when that email was added to the account
sub get_email_data {
    my ($u, $addr) = @_;

    return undef unless $u && $addr;

    my $emails = $u->emails_info;
    my $is_current = lc($addr) eq lc($u->email_raw);

    foreach my $email (@$emails) {
        next unless lc($email->{'email'}) eq lc($addr);
        next if $email->{'deleted'};
        next unless $email->{'status'} eq 'A';
        next if $is_current && !$email->{'current'};

        my $ret = {};
        $ret->{'email_state'} = $is_current ? $email->{'status'} : 'P';
        $ret->{'time'} = $email->{'set'};

        return $ret;
    }

    return undef;
}

# get information about which emails the user has used previously or uses now
# returns:
# [
#     { email => 'test@test.com', current => 1, set => 123142345234, status => 'A' },
#     { email => 'test2@test.com', set => $timestamp, changed => 123142345234, status => 'A' },
#     { email => 'test3@test.com', set => $timestamp2, changed => $timestamp, status => 'T', deleted => $timestamp3 },
# ]
sub emails_info {
    my ($u) = @_;

    return $u->{'_emails'} if defined $u->{'_emails'};

    my @ret;

    my $dbr = LJ::get_db_reader();
    my $infohistory_rows = $dbr->selectall_arrayref(
        'SELECT what, UNIX_TIMESTAMP(timechange) AS timechange, '.
        'oldvalue, other FROM infohistory WHERE userid=? AND '.
        'what IN ("email", "emaildeleted") ORDER BY timechange',
        { Slice => {} }, $u->id
    );
    my @infohistory_rows = @$infohistory_rows;

    # this actually finds the greatest timechange in rows before $rownum;
    # if it fails to find it, it returns $u->timecreate
    my $find_timeset = sub {
        my ($rownum) = @_;

        for (my $rownum2 = $rownum-1; $rownum2 >= 0; $rownum2--) {
            my $row2 = $infohistory_rows->[$rownum2];
            return $row2->{'timechange'} if ($row2->{'what'} eq 'email');
        }

        # in case we found nothing, the address was set when the account
        # was registered
        return $u->timecreate;
    };

    foreach my $rownum (0..$#infohistory_rows) {
        my $row = $infohistory_rows->[$rownum];
        if ($row->{'what'} eq 'email') {
            # new email has been added to the list, but now, we're going to
            # record the old address

            my $email = { email => $row->{'oldvalue'} };
            $email->{'changed'} = $row->{'timechange'};
            $email->{'status'} = $row->{'other'};

            # in case we found nothing, the address was set when the account
            # was registered

            $email->{'set'} = $find_timeset->($rownum);

            push @ret, $email;
        } elsif ($row->{'what'} eq 'emaildeleted') {
            # there may be two cases here: 1) it was something like an admin
            # deletion or 2) it was deletion through /tools/emailmanage.bml,
            # which previously did 'UPDATE infohistory SET what="emaildelete"'
            # (oh weird) and also changed `other` to "A; $timeset".
            # /tools/emailmanage.bml has since been changed to record that
            # change as a new entry, which returns us to the first case

            unless ($row->{'other'} =~ /;/) {
                # first case: find all other occurences of that email
                # and mark them with the date of deletion

                foreach my $email (@ret) {
                    next unless $email->{'email'} eq $row->{'oldvalue'};
                    next unless $email->{'set'} <= $row->{'timechange'};

                    $email->{'deleted'} = $row->{'timechange'}
                        unless $email->{'deleted'};
                }
            } else {
                # second case: parse the timestamp, create an email hashref,
                # find the row with the next address to set "set", and
                # finally, mark it as deleted. ugh.

                my ($status, $time) = split /;/, $row->{'other'};

                # there is no joke here. in infohistory, time is stored as
                # MySQL DATETIME. emailmanage.bml used to just append it to
                # previous status, so now, we need to parse.
                $time = str2time($time);

                my $email = { email => $row->{'oldvalue'} };
                $email->{'changed'} = $time;
                $email->{'status'} = $status;
                $email->{'deleted'} = $row->{'timechange'};

                # now, we need to find the first row which has timestamp more
                # or equal to $time so that we can call $find_timeset
                my $nextrow = 0;
                foreach my $rownum2 (0..$#infohistory_rows) {
                    my $row2 = $infohistory_rows->[$rownum2];
                    next unless $row2->{'what'} eq 'email';
                    next if $row2->{'timechange'} < $time;

                    $nextrow = $rownum2;
                    last;
                }

                $email->{'set'} = $find_timeset->($nextrow);
                push @ret, $email;
            }
        }
    }

    # finally, the current address
    my $email = { email => $u->email_raw, current => 1 };
    $email->{'status'} = $u->email_status;
    $email->{'set'} = $find_timeset->($#infohistory_rows + 1);
    push @ret, $email;

    $u->{'_emails'} = \@ret;
    return \@ret;
}

# returns array (not arrayref) of emails that the user has ever used, including
# deleted ones
sub emails_unique {
    my ($u) = @_;

    my $emails = $u->emails_info;
    my %ret;

    foreach my $email (@$emails) {
        $ret{lc($email->{'email'})} = 1;
    }

    return sort keys %ret;
}

# read emails and calculate primitives:
# date of last leaving
# date of chain start
# returns data of emails_info function with additional keys ('leaving', may be undef, and 'starting')
# skips internal steps of chains
# skips deleted emails
# cleans out all chains, which are unusable for password restoring, i.e. 'leaving' is newer than 6 month old
# must return array for printing on tools/emailmanage.bml
sub emails_chained_info {
    my $u = shift;

    return $u->{'_emails_chained'} if defined $u->{'_emails_chained'};

    my $emails = $u->emails_info;
    my @email_addresses = $u->emails_unique;

    my @chains;

    # process all elements
    foreach my $addr (@email_addresses) {
        # find all information about this element
        my ($starting, $leaving);
        my $lc_addr = lc $addr;

        my @relevant = grep { lc($_->{email}) eq $lc_addr } @$emails;
            # already sorted by MySQL

        my $written_addr;
        foreach my $step (@relevant) {

            $written_addr = $step->{email};

            next unless $step->{status} eq 'A'; # restoring can be done only by validated addressed

            if ($step->{deleted}) {
                undef $starting;
                undef $leaving;
                next;
            }

            if (defined $leaving and $step->{set} - $leaving > $LJ::EMAIL_FORGET_AGE) {
                # forget old chain - because it is unusable for password restoring
                undef $starting; # start new chain
                undef $leaving;
            }

            # most early starting
            $starting = $step->{set} unless defined $starting and $starting < $step->{set};

            # most late leaving
            $leaving = $step->{changed} unless defined $leaving and defined $step->{changed} and $step->{changed} < $leaving;
        }

        if ($starting and time - $leaving < $LJ::EMAIL_FORGET_AGE or not defined $leaving) {
            push @chains, { email => $written_addr, leaving => $leaving, starting => $starting }; # fix this chain
                # we store address with upper case letters possibly,
                # to make it more comfort for user when he/she reads address
        }
    }

    $u->{'_emails_chained'} = \@chains;
    return \@chains;
}

# returns time when the user has last stopped using the given email
# (that is, switched their current address to a different one)
# this ASSUMES that the address is not a current one, but that it was
# validated previously.
sub email_lastchange {
    my ($u, $addr) = @_;

    use Data::Dumper;
    my $emails = $u->emails_info;
    my $lastchange = 0;
    my $found = 0;

    foreach my $email (@$emails) {
        next unless lc($email->{'email'}) eq lc($addr);
        next unless $email->{'status'} eq 'A';
        next if $email->{'current'};
        next if $email->{'deleted'};

        $found = 1;
        $lastchange = $email->{'changed'} if $email->{'changed'} > $lastchange;
    }

    return undef unless $found;
    return $lastchange;
}

# checks whether user is allowed to remove the given email from their history
# and this way, disable themselves from sending a password reset to that address
sub can_delete_email {
    my ($u, $email) = @_;

    my $chains = $u->emails_chained_info;
    my $addr = ref $email ? $email->{email} : $email;
    $addr = lc $addr;

    # reformat as email => parameters hash
    my %chains = map { lc($_->{email}) => $_ } @$chains;

    my $current = lc $u->email_raw;
    my $edge_age = $chains{$current}->{starting};

    my $aim_value = $chains{$addr}->{starting};

    return 0 unless defined $edge_age and $aim_value;
    return $aim_value > $edge_age;
}

# delete the given email from user's history, disabling the user from sending
# a password reset to that address
# this performs the necessary checks by calling can_delete_email() as defined
# above
sub delete_email {
    my ($u, $addr) = @_;

    return unless $u->can_delete_email($addr);

    my $dbh = LJ::get_db_writer();
    $dbh->do(
        'INSERT INTO infohistory SET '.
        'userid=?, what="emaildeleted", timechange=NOW(), '.
        'oldvalue=?', undef, $u->id, $addr
    );

    # update cache now

    my $emails = $u->emails_info;
    foreach my $email (@$emails) {
        next if $email->{'deleted'};

        next unless lc($email->{'email'}) eq lc($addr);
        $email->{'deleted'} = time;
    }
}

# checks whether the given email has been validated, regardless of whether it is
# set to current right now. despite the name, it specifically omits deleted
# emails, too.
sub is_email_validated {
    my ($u, $addr) = @_;

    my $emails = $u->emails_info;
    foreach my $email (@$emails) {
        next unless lc($email->{'email'}) eq lc($addr);
        next if $email->{'deleted'};
        next unless $email->{'status'} eq 'A';

        return 1;
    }

    return 0;
}

# checks whether the user can send a password reset to the given email
# the current logic is:
# case 1: NOT $LJ::DISABLED{'limit_password_reset'}
# yes if the email is set to current OR
# (has been previously validated AND has not been deleted after that AND
# the user has stopped using it no more than 6 months ago);
# no otherwise
# case 2: $LJ::DISABLED{'limit_password_reset'}
# yes if and only if the email is set to current
sub can_reset_password_using_email {
    my ($u, $addr) = @_;

    return 0 unless $LJ::DISABLED{'limit_password_reset'};

    my $current = lc $u->email_raw;
    return 1 if lc($addr) eq $current;

    return 0 unless $u->is_email_validated($addr);

    my $chains = $u->emails_chained_info;

    # reformat as email => parameters hash
    my %chains = map { lc($_->{email}) => $_ } @$chains;

    my $aim_value = $chains{lc $addr}->{leaving};

    return 0 unless defined $aim_value;
    return time - $aim_value < $LJ::EMAIL_FORGET_AGE;
}

# returns date when the user has last changed their email
sub get_current_email_set_date {
    my ($u) = @_;

    my $emails = $u->emails_info;

    foreach my $email (@$emails) {
        next unless $email->{'current'};
        return $email->{'set'};
    }

    return undef;
}

sub share_contactinfo {
    my ($u, $remote) = @_;

    return 0 if ($u->underage || $u->{journaltype} eq "Y");
    return 0 if ($u->opt_showcontact eq 'N');
    return 0 if ($u->opt_showcontact eq 'R' && !$remote);
    return 0 if ($u->opt_showcontact eq 'F' && !$u->is_friend($remote));
    return 1;
}

# <LJFUNC>
# name: LJ::User::activate_userpics
# des: Sets/unsets userpics as inactive based on account caps.
# returns: nothing
# </LJFUNC>
sub activate_userpics {
    my $u = shift;

    # this behavior is optional, but enabled by default
    return 1 if $LJ::ALLOW_PICS_OVER_QUOTA;

    return undef unless LJ::isu($u);

    # can't get a cluster read for expunged users since they are clusterid 0,
    # so just return 1 to the caller from here and act like everything went fine
    return 1 if $u->is_expunged;

    my $userid = $u->{'userid'};

    # active / inactive lists
    my @active = ();
    my @inactive = ();
    my $allow = LJ::get_cap($u, "userpics");

    # get a database handle for reading/writing
    my $dbh = LJ::get_db_writer();
    my $dbcr = LJ::get_cluster_def_reader($u);

    # select all userpics and build active / inactive lists
    my $sth;
    if ($u->{'dversion'} > 6) {
        return undef unless $dbcr;
        $sth = $dbcr->prepare("SELECT picid, state FROM userpic2 WHERE userid=?");
    } else {
        return undef unless $dbh;
        $sth = $dbh->prepare("SELECT picid, state FROM userpic WHERE userid=?");
    }
    $sth->execute($userid);
    while (my ($picid, $state) = $sth->fetchrow_array) {
        next if $state eq 'X'; # expunged, means userpic has been removed from site by admins
        if ($state eq 'I') {
            push @inactive, $picid;
        } else {
            push @active, $picid;
        }
    }

    # inactivate previously activated userpics
    if (@active > $allow) {

        my @ban = sort { $a <=> $b } @active;
        splice(@ban, 0, $allow);

        my $ban_in = join(",", map { $dbh->quote($_) } @ban);
        if ($u->{'dversion'} > 6) {
            $u->do("UPDATE userpic2 SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                   undef, $userid) if $ban_in;
        } else {
            $dbh->do("UPDATE userpic SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                     undef, $userid) if $ban_in;
        }
    }

    # activate previously inactivated userpics
    if (@inactive && @active < $allow) {
        my $to_activate = $allow - @active;
        $to_activate = @inactive if $to_activate > @inactive;

        # take the $to_activate newest (highest numbered) pictures
        # to reactivated
        @inactive = sort @inactive;
        my @activate_picids = splice(@inactive, -$to_activate);

        my $activate_in = join(",", map { $dbh->quote($_) } @activate_picids);
        if ($activate_in) {
            if ($u->{'dversion'} > 6) {
                $u->do("UPDATE userpic2 SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                       undef, $userid);
            } else {
                $dbh->do("UPDATE userpic SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                         undef, $userid);
            }
        }
    }

    # delete userpic info object from memcache
    LJ::Userpic->delete_cache($u);

    return 1;
}


# revert S2 style to the default if the user is using a layout/theme layer that they don't have permission to use
sub revert_style {
    my $u = shift;

    # FIXME: this solution sucks
    # - ensure that these packages are loaded via Class::Autouse by calling a method on them
    LJ::S2->can("dostuff");
    LJ::S2Theme->can("dostuff");
    LJ::Customize->can("dostuff");

    my $current_theme = LJ::Customize->get_current_theme($u);
    return unless $current_theme;
    my $default_theme_of_current_layout = LJ::S2Theme->load_default_of($current_theme->layoutid, user => $u);
    return unless $default_theme_of_current_layout;

    my $default_style = LJ::run_hook('get_default_style', $u) || $LJ::DEFAULT_STYLE;
    my $default_layout_uniq = exists $default_style->{layout} ? $default_style->{layout} : '';
    my $default_theme_uniq = exists $default_style->{theme} ? $default_style->{theme} : '';

    my %style = LJ::S2::get_style($u, "verify");
    my $public = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    # check to see if the user is using a custom layout or theme
    # if so, we want to let them keep using it
    foreach my $layerid (keys %$userlay) {
        return if $current_theme->layoutid == $layerid;
        return if $current_theme->themeid == $layerid;
    }

    # if the user cannot use the layout or the default theme of that layout, switch to the default style (if it's defined)
    if (($default_layout_uniq || $default_theme_uniq) && (!LJ::S2::can_use_layer($u, $current_theme->layout_uniq) || !$default_theme_of_current_layout->available_to($u))) {
        my $new_theme;
        if ($default_theme_uniq) {
            $new_theme = LJ::S2Theme->load_by_uniq($default_theme_uniq);
        } else {
            my $layoutid = '';
            $layoutid = $public->{$default_layout_uniq}->{s2lid} 
                if $public->{$default_layout_uniq} && $public->{$default_layout_uniq}->{type} eq "layout";
            $new_theme = LJ::S2Theme->load_default_of($layoutid, user => $u) if $layoutid;
        }

        return unless $new_theme;

        # look for a style that uses the default layout/theme, and use it if it exists
        my $styleid = $new_theme->get_styleid_for_theme($u);
        my $style_exists = 0;
        if ($styleid) {
            $style_exists = 1;
            $u->set_prop("s2_style", $styleid);

            my $stylelayers = LJ::S2::get_style_layers($u, $u->prop('s2_style'));
            foreach my $layer (qw(user i18nc i18n core)) {
                $style{$layer} = exists $stylelayers->{$layer} ? $stylelayers->{$layer} : 0;
            }
        }

        # set the layers that are defined by $default_style
        while (my ($layer, $name) = each %$default_style) {
            next if $name eq "";
            next unless $public->{$name};
            my $id = $public->{$name}->{s2lid};
            $style{$layer} = $id if $id;
        }

        # make sure core was set
        $style{core} = $new_theme->coreid
            if $style{core} == 0;

        # make sure the other layers were set
        foreach my $layer (qw(user i18nc i18n)) {
            $style{$layer} = 0 unless $style{$layer} || $style_exists;
        }

        # create the style
        if ($style_exists) {
            LJ::Customize->implicit_style_create($u, %style);
        } else {
            LJ::Customize->implicit_style_create({ 'force' => 1 }, $u, %style);
        }

    # if the user can use the layout but not the theme, switch to the default theme of that layout
    # we know they can use this theme at this point because if they couldn't, the above block would have caught it
    } elsif (LJ::S2::can_use_layer($u, $current_theme->layout_uniq) && !LJ::S2::can_use_layer($u, $current_theme->uniq)) {
        $style{theme} = $default_theme_of_current_layout->themeid;
        LJ::Customize->implicit_style_create($u, %style);
    }

    return;
}

sub uncache_prop {
    my ($u, $name) = @_;
    
    my $handler = LJ::User::PropStorage->get_handler ($name);
    $handler->delete_prop_memcache ($u, $name);
    delete $u->{$name};

    return 1;
}

sub set_draft_text {
    my ($u, $draft) = @_;
    my $old = $u->draft_text;

    $LJ::_T_DRAFT_RACE->() if $LJ::_T_DRAFT_RACE;

    # try to find a shortcut that makes the SQL shorter
    my @methods;  # list of [ $subref, $cost ]

    # one method is just setting it all at once.  which incurs about
    # 75 bytes of SQL overhead on top of the length of the draft,
    # not counting the escaping
    push @methods, [ "set", sub { $u->set_prop('entry_draft', $draft); 1 },
                     75 + length $draft ];

    # stupid case, setting the same thing:
    push @methods, [ "noop", sub { 1 }, 0 ] if $draft eq $old;

    # simple case: appending
    if (length $old && $draft =~ /^\Q$old\E(.+)/s) {
        my $new = $1;
        my $appending = sub {
            my $prop = LJ::get_prop("user", "entry_draft") or die; # FIXME: use exceptions
            my $rv = $u->do("UPDATE userpropblob SET value = CONCAT(value, ?) WHERE userid=? AND upropid=? AND LENGTH(value)=?",
                            undef, $new, $u->{userid}, $prop->{id}, length $old);
            return 0 unless $rv > 0;
            $u->uncache_prop("entry_draft");
            return 1;
        };
        push @methods, [ "append", $appending, 40 + length $new ];
    }

    # TODO: prepending/middle insertion (the former being just the latter), as well
    # appending, wihch we could then get rid of

    # try the methods in increasing order
    foreach my $m (sort { $a->[2] <=> $b->[2] } @methods) {
        my $func = $m->[1];
        if ($func->()) {
            $LJ::_T_METHOD_USED->($m->[0]) if $LJ::_T_METHOD_USED; # for testing
            return 1;
        }
    }
    return 0;
}

sub draft_text {
    my ($u) = @_;
    return $u->prop('entry_draft');
}

sub notable_interests {
    my ($u, $n) = @_;
    $n ||= 20;

    # arrayref of arrayrefs of format [intid, intname, intcount];
    my $ints = LJ::get_interests($u)
        or return ();

    my @ints = map { $_->[1] } @$ints;

    # sorta arrayref inline
    LJ::AdTargetedInterests->sort_interests(\@ints);
    
    return @ints[0..$n-1] if @ints > $n;
    return @ints;
}

# returns $n number of communities that $u is a member of, sorted by update time (most recent to least recent)
sub notable_communities {
    my ($u, $n) = @_;
    $n ||= 3;

    my $friends = $u->friends;

    my $fro_m = LJ::M::FriendsOf->new(
        $u,
        sloppy => 1, # approximate if no summary info
        friends => { map {$_ => 1} keys %$friends },
    );

    my $update_times = LJ::get_timeupdate_multi( map { $_->id } $fro_m->member_of );

    my @ret_commids;
    my $count = 1;
    foreach my $commid (sort {$update_times->{$b} <=> $update_times->{$a}} keys %$update_times) {
        last if $count > $n;
        push @ret_commids, $commid;
        $count++;
    }

    my $us = LJ::load_userids(@ret_commids);

    return map { $us->{$_} } @ret_commids;
}

# returns the max capability ($cname) for all the classes
# the user is a member of
sub get_cap {
    my ($u, $cname) = @_;
    return 1 if $LJ::T_HAS_ALL_CAPS;
    return LJ::get_cap($u, $cname);
}

# tests to see if a user is in a specific named class. class
# names are site-specific.
sub in_class {
    my ($u, $class) = @_;
    return LJ::caps_in_group($u->{caps}, $class);
}

sub add_to_class {
    my ($u, $class) = @_;
    my $bit = LJ::class_bit($class);
    die "unknown class '$class'" unless defined $bit;

    # call add_to_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs the new we say we'll be adding
    if (LJ::are_hooks('add_to_class')) {
        LJ::run_hooks('add_to_class', $u, $class);
    }

    return LJ::modify_caps($u, [$bit], []);
}

sub remove_from_class {
    my ($u, $class) = @_;
    my $bit = LJ::class_bit($class);
    die "unknown class '$class'" unless defined $bit;

    # call remove_from_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs what we'll be removing
    if (LJ::are_hooks('remove_from_class')) {
        LJ::run_hooks('remove_from_class', $u, $class);
    }

    return LJ::modify_caps($u, [], [$bit]);
}

sub cache {
    my ($u, $key) = @_;
    my $val = $u->selectrow_array("SELECT value FROM userblobcache WHERE userid=? AND bckey=?",
                                  undef, $u->{userid}, $key);
    return undef unless defined $val;
    if (my $thaw = eval { Storable::thaw($val); }) {
        return $thaw;
    }
    return $val;
}

sub set_cache {
    my ($u, $key, $value, $expr) = @_;
    my $now = time();
    $expr ||= $now + 86400;
    $expr += $now if $expr < 315532800;  # relative to absolute time
    $value = Storable::nfreeze($value) if ref $value;
    $u->do("REPLACE INTO userblobcache (userid, bckey, value, timeexpire) VALUES (?,?,?,?)",
           undef, $u->{userid}, $key, $value, $expr);
}

# returns array of LJ::Entry objects, ignoring security
sub recent_entries {
    my ($u, %opts) = @_;
    my $remote = delete $opts{'filtered_for'} || LJ::get_remote();
    my $count  = delete $opts{'count'}        || 50;
    my $order  = delete $opts{'order'}        || "";
    die "unknown options" if %opts;

    my $err;
    my @recent = LJ::get_recent_items({
        itemshow  => $count,
        err       => \$err,
        userid    => $u->{userid},
        clusterid => $u->{clusterid},
        remote    => $remote,
        order     => $order,
    });
    die "Error loading recent items: $err" if $err;

    my @objs;
    foreach my $ri (@recent) {
        my $entry = LJ::Entry->new($u, jitemid => $ri->{itemid});
        push @objs, $entry;
        # FIXME: populate the $entry with security/posterid/alldatepart/ownerid/rlogtime
    }
    return @objs;
}

# front-end to recent_entries, which forces the remote user to be
# the owner, so we get everything.
sub all_recent_entries {
    my $u = shift;
    my %opts = @_;
    $opts{filtered_for} = $u;
    return $u->recent_entries(%opts);
}

sub sms_active_number {
    my $u = shift;
    return LJ::SMS->uid_to_num($u, verified_only => 1);
}

sub sms_pending_number {
    my $u = shift;
    my $num = LJ::SMS->uid_to_num($u, verified_only => 0);
    return undef unless $num;
    return $num if LJ::SMS->num_is_pending($num);
    return undef;
}

# this method returns any mapped number for the user,
# regardless of its verification status
sub sms_mapped_number {
    my $u = shift;
    return LJ::SMS->uid_to_num($u, verified_only => 0);
}

sub sms_active {
    my $u = shift;

    # active if the user has a verified sms number
    return LJ::SMS->configured_for_user($u);
}

sub sms_pending {
    my $u = shift;

    # pending if user has an unverified number
    return LJ::SMS->pending_for_user($u);
}

sub sms_register_time_remaining {
    my $u = shift;

    return LJ::SMS->num_register_time_remaining($u);
}

sub sms_num_instime {
    my $u = shift;

    return LJ::SMS->num_instime($u->sms_mapped_number);
}

sub set_sms_number {
    my ($u, $num, %opts) = @_;
    my $verified = delete $opts{verified};

    # these two are only checked if $num, because it's possible
    # to just pass ($u, undef, undef) to delete the mapping
    if ($num) {
        croak "invalid number" unless $num =~ /^\+\d+$/;
        croak "invalid verified flag" unless $verified =~ /^[YN]$/;
    }

    return LJ::SMS->replace_mapping($u, $num, $verified);
}

sub set_sms_number_verified {
    my ($u, $verified) = @_;

    return LJ::SMS->set_number_verified($u, $verified);
}

sub sms_message_count {
    my $u = shift;
    return LJ::SMS->message_count($u, @_);
}

sub sms_sent_message_count {
    my $u = shift;
    return LJ::SMS->sent_message_count($u, @_);
}

sub delete_sms_number {
    my $u = shift;
    return LJ::SMS->replace_mapping($u, undef);
}

# opts:
#   no_quota = don't check user quota or deduct from their quota for sending a message
sub send_sms {
    my ($u, $msg, %opts) = @_;

    return 0 unless $u;

    croak "invalid user object for object method"
        unless LJ::isu($u);
    croak "invalid LJ::SMS::Message object to send"
        unless $msg && $msg->isa("LJ::SMS::Message");

    my $ret = $msg->send(%opts);

    return $ret;
}

sub send_sms_text {
    my ($u, $msgtext, %opts) = @_;

    my $msg = LJ::SMS::Message->new(
                                    owner => $u,
                                    to    => $u,
                                    type  => 'outgoing',
                                    body_text => $msgtext,
                                    );

    # if user specified a class_key for send, set it on
    # the msg object
    if ($opts{class_key}) {
        $msg->class_key($opts{class_key});
    }

    $msg->send(%opts);
}

sub sms_quota_remaining {
    my ($u, $type) = @_;

    return LJ::SMS->sms_quota_remaining($u, $type);
}

sub add_sms_quota {
    my ($u, $qty, $type) = @_;

    return LJ::SMS->add_sms_quota($u, $qty, $type);
}

sub set_sms_quota {
    my ($u, $qty, $type) = @_;

    return LJ::SMS->set_sms_quota($u, $qty, $type);
}

sub max_sms_bytes {
    my $u = shift;
    return LJ::SMS->max_sms_bytes($u);
}

sub max_sms_substr {
    my ($u, $text, %opts) = @_;
    return LJ::SMS->max_sms_substr($u, $text, %opts);
}

sub subtract_sms_quota {
    my ($u, $qty, $type) = @_;

    return LJ::SMS->subtract_sms_quota($u, $qty, $type);
}

sub is_syndicated {
    my $u = shift;
    return $u->{journaltype} eq "Y";
}

sub is_community {
    my $u = shift;
    return $u->{journaltype} eq "C";
}
*is_comm = \&is_community;

sub is_shared {
    my $u = shift;
    return $u->{journaltype} eq "S";
}

sub is_news {
    my $u = shift;
    return $u->{journaltype} eq "N";
}

sub is_person {
    my $u = shift;
    return $u->{journaltype} eq "P";
}
*is_personal = \&is_person;

sub is_identity {
    my $u = shift;
    return $u->{journaltype} eq "I";
}

## Can we add this account to someone's friendsOf list
sub can_be_counted_as_friendof {
    my $u = shift;
    return 0 unless $u->statusvis =~ /^[VML]$/o;
    return 0 unless $u->journaltype =~ /^[PI]$/o;
    return 1;
}

## We trust OpenID users if they are either from trusted OpenID provider or
## have e-mail validated. During e-mail validation, they answer CAPTCHA test.
## Trusted OpenID users are like registered user, untrusted are like anonymous
sub is_trusted_identity {
    my $u = shift;
    return unless $u->is_identity;
    
    return 1 if $u->is_validated;

    my $id = $u->identity;

    if ($id->short_code eq 'openid') {
        ## Check top-to-down domain names in list of trusted providers:
        ## asdf.openid.somewhere.com -> openid.somewhere.com -> somewhere.com
        my $url = $id->url;
        if ($url and my $uri = URI->new($url)) {
            return unless $uri->can('host');
            my $host = $uri->host;
            while ($host =~ /\./) {
                return 1 if $LJ::TRUSTED_OPENID_PROVIDERS{$host};
                # remove first domain name (or whatever) with dot
                $host =~ s/^.*?\.//;
            }
        }

        return;
    }

    return;
}

# return the journal type as a name
sub journaltype_readable {
    my $u = shift;

    return {
        R => 'redirect',
        I => 'identity',
        P => 'personal',
        S => 'shared',
        Y => 'syndicated',
        N => 'news',
        C => 'community',
    }->{$u->{journaltype}};
}

*has_friend = \&is_friend;
sub is_friend {
    my $ua = shift;
    my $ub = shift;

    return LJ::is_friend($ua, $ub);
}

sub is_mutual_friend {
    my $ua = shift;
    my $ub = shift;

    return 1 if ($ua->is_friend($ub) && $ub->is_friend($ua));
    return 0;
}

sub who_invited {
    my $u = shift;
    my $inviterid = LJ::load_rel_user($u, 'I');

    return LJ::load_userid($inviterid);
}

sub subscriptions {
    my $u = shift;
    return LJ::Subscription->subscriptions_of_user($u);
}

sub subscription_count {
    my $u = shift;
    return scalar LJ::Subscription->subscriptions_of_user($u);
}

# this is the count used to check the maximum subscription count
sub active_inbox_subscription_count {
    my $u = shift;
    return $u->subscriptions_count;
}

sub max_subscriptions {
    my $u = shift;
    return $u->get_cap('subscriptions');
}

sub can_add_inbox_subscription {
    my $u = shift;
    return $u->active_inbox_subscription_count >= $u->max_subscriptions ? 0 : 1;
}

# subscribe to an event
sub subscribe {
    my ($u, %opts) = @_;
    croak "No subscription options" unless %opts;

    return LJ::Subscription->create($u, %opts);
}

# unsubscribe from an event(s)
sub unsubscribe {
    my ($u, %opts) = @_;
    croak "No subscription options" unless %opts;

    # find all matching subscriptions
    my @subs = LJ::Subscription->find($u, %opts);
    
    return 0 
        unless @subs;

    foreach (@subs) {
        # run delete method on each subscription
        $_->delete();
    }

    return 1;
}



sub subscribe_entry_comments_via_sms {
    my ($u, $entry) = @_;
    croak "Invalid LJ::Entry passed"
        unless $entry && $entry->isa("LJ::Entry");

    # don't subscribe if user is over subscription limit
    return unless $u->can_add_inbox_subscription;

    my %sub_args =
        ( event   => "LJ::Event::JournalNewComment",
          journal => $u,
          arg1    => $entry->ditemid, );

    $u->subscribe
        ( method  => "LJ::NotificationMethod::SMS",
          %sub_args, );

    $u->subscribe
        ( method  => "LJ::NotificationMethod::Inbox",
          %sub_args, );

    return 1;
}

# search for a subscription
*find_subscriptions = \&has_subscription;
sub has_subscription {
    my ($u, %params) = @_;
    croak "No parameters" unless %params;

    return LJ::Subscription->find($u, %params);
}

# interim solution while legacy/ESN notifications are both happening:
# checks possible subscriptions to see if user will get an ESN notification
# THIS IS TEMPORARY. should only be called by talklib.
# params: journal, arg1 (entry ditemid), arg2 (comment talkid)
sub gets_notified {
    my ($u, %params) = @_;

    $params{event} = "LJ::Event::JournalNewComment";
    $params{method} = "LJ::NotificationMethod::Email";

    my $has_sub;

    # did they subscribe to the parent comment?
    $has_sub = LJ::Subscription->find($u, %params);
    return $has_sub if $has_sub;

    # remove the comment-specific parameter, then check for an entry subscription
    $params{arg2} = 0;
    $has_sub = LJ::Subscription->find($u, %params);
    return $has_sub if $has_sub;

    # remove the entry-specific parameter, then check if they're subscribed to the entire journal
    $params{arg1} = 0;
    $has_sub = LJ::Subscription->find($u, %params);
    return $has_sub;
}

# delete all of a user's subscriptions
sub delete_all_subscriptions {
    my $u = shift;

    ## Logging for delete all subscriptions
    my $remote = LJ::get_remote();
    my $admin = $remote || LJ::load_user('system');
    my $subs_number = scalar $u->subscriptions;
    LJ::statushistory_add ( $u, $admin, 'remove_subs', $subs_number )
        if $subs_number;

    return LJ::Subscription->delete_all_subs($u);
}

# delete all of a user's subscriptions
sub delete_all_inactive_subscriptions {
    my $u = shift;
    my $dryrun = shift;

    ## Logging for delete all subscriptions
    my $remote = LJ::get_remote();
    my $admin = $remote || LJ::load_user('system');
    my $set = LJ::Subscription::GroupSet->fetch_for_user($u);
    my @inactive_groups = grep { !$_->active } $set->groups;
    my $subs_number = scalar @inactive_groups;
    LJ::statushistory_add ( $u, $admin, 'remove_subs', $subs_number )
        if $subs_number;

    return LJ::Subscription->delete_all_inactive_subs($u, $dryrun);
}

# What journals can this user post to?
sub posting_access_list {
    my $u = shift;

    my @res;

    my $ids = LJ::load_rel_target($u, 'P');
    my $us = LJ::load_userids(@$ids);
    foreach (values %$us) {
        next unless $_->is_visible;
        push @res, $_;
    }

    return sort { $a->{user} cmp $b->{user} } @res;
}

# can $u post to $targetu?
sub can_post_to {
    my ($u, $targetu) = @_;
    return unless $u && $targetu;
    return LJ::can_use_journal($u->id, $targetu->user);
}

sub delete_and_purge_completely {
    my $u = shift;
    # TODO: delete from user tables
    # TODO: delete from global tables
    my $dbh = LJ::get_db_writer();

    my @tables = qw(user friends useridmap reluser priv_map infohistory email password);
    foreach my $table (@tables) {
        $dbh->do("DELETE FROM $table WHERE userid=?", undef, $u->id);
    }

    $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $u->id);
    $dbh->do("DELETE FROM reluser WHERE targetid=?", undef, $u->id);
    $dbh->do("DELETE FROM email_aliases WHERE alias=?", undef, $u->user . "\@$LJ::USER_DOMAIN");

    $dbh->do("DELETE FROM community WHERE userid=?", undef, $u->id)
        if $u->is_community;
    $dbh->do("DELETE FROM syndicated WHERE userid=?", undef, $u->id)
        if $u->is_syndicated;
    $dbh->do("DELETE FROM content_flag WHERE journalid=? OR reporterid=?", undef, $u->id, $u->id);

    return 1;
}

# Returns 'rich' or 'plain' depending on user's
# setting of which editor they would like to use
# and what they last used
sub new_entry_editor {
    my $u = shift;

    my $editor = $u->prop('entry_editor');
    return 'plain' if $editor eq 'always_plain'; # They said they always want plain
    return 'rich' if $editor eq 'always_rich'; # They said they always want rich
    return $editor if $editor =~ /(rich|plain)/; # What did they last use?
    return $LJ::DEFAULT_EDITOR; # Use config default
}

# Returns the NotificationInbox for this user
*inbox = \&notification_inbox;
sub notification_inbox {
    my $u = shift;
    return LJ::NotificationInbox->new($u);
}

sub new_message_count {
    my $u = shift;
    my $inbox = $u->notification_inbox;
    my $count = $inbox->unread_count;

    return $count || 0;
}

sub notification_archive {
    my $u = shift;
    return LJ::NotificationArchive->new($u);
}

#
sub can_receive_message {
    my ($u, $sender) = @_;

    my $opt_usermsg = $u->opt_usermsg;
    return 0 if ($opt_usermsg eq 'N' || !$sender);
    return 0 if ($u->has_banned($sender));
    return 0 if ($opt_usermsg eq 'M' && !$u->is_mutual_friend($sender));
    return 0 if ($opt_usermsg eq 'F' && !$u->is_friend($sender));

    return 1;
}

# opt_usermsg options
# Y - Registered Users
# F - Friends
# M - Mutual Friends
# N - Nobody
sub opt_usermsg {
    my $u = shift;

    if ($u->raw_prop('opt_usermsg') =~ /^(Y|F|M|N)$/) {
        return $u->raw_prop('opt_usermsg');
    } else {
        return 'N' if ($u->underage || $u->is_child);
        return 'M' if ($u->is_minor);
        return 'Y';
    }
}

sub add_friend {
    my ($u, $target, $opts) = @_;
    $opts->{nonotify} = 1 if $u->is_friend($target);
    return LJ::add_friend($u, $target, $opts);
}

sub friend_and_watch {
    my ($u, $target, $opts) = @_;
    $opts->{defaultview} = 1;
    $u->add_friend($target, $opts);
}

sub remove_friend {
    my ($u, $target, $opts) = @_;

    $opts->{nonotify} = 1 unless $u->has_friend($target);
    return LJ::remove_friend($u, $target, $opts);
}

sub view_control_strip {
    my $u = shift;

    LJ::run_hook('control_strip_propcheck', $u, 'view_control_strip') unless $LJ::DISABLED{control_strip_propcheck};

    my $prop = $u->raw_prop('view_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}

sub show_control_strip {
    my $u = shift;

    LJ::run_hook('control_strip_propcheck', $u, 'show_control_strip') unless $LJ::DISABLED{control_strip_propcheck};

    my $prop = $u->raw_prop('show_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}

# when was this account created?
# returns unixtime
sub timecreate {
    my $u = shift;

    return $u->{_cache_timecreate} if $u->{_cache_timecreate};

    my $memkey = [$u->id, "tc:" . $u->id];
    my $timecreate = LJ::MemCache::get($memkey);
    if ($timecreate) {
        $u->{_cache_timecreate} = $timecreate;
        return $timecreate;
    }

    my $dbr = LJ::get_db_reader() or die "No db";
    my $when = $dbr->selectrow_array("SELECT timecreate FROM userusage WHERE userid=?", undef, $u->id);

    $timecreate = LJ::TimeUtil->mysqldate_to_time($when);
    $u->{_cache_timecreate} = $timecreate;
    LJ::MemCache::set($memkey, $timecreate, 60*60*24);

    return $timecreate;
}

# when was last time this account updated?
# returns unixtime
sub timeupdate {
    my $u = shift;
    my $timeupdate = LJ::get_timeupdate_multi($u->id);
    return $timeupdate->{$u->id};
}

# can this user use ESN?
sub can_use_esn {
    my $u = shift;
    return 0 if $LJ::DISABLED{esn};
    my $disable = $LJ::DISABLED{esn_ui};
    return 1 unless $disable;

    if (ref $disable eq 'CODE') {
        return $disable->($u) ? 0 : 1;
    }

    return $disable ? 0 : 1;
}

sub can_use_sms {
    my $u = shift;
    return LJ::SMS->can_use_sms($u);
}

sub can_use_ljphoto {
    my $u = shift;

    return 0 if $LJ::DISABLED{'new_ljphoto'};

    foreach my $comm_name (@LJ::LJPHOTO_ALLOW_FROM_COMMUNITIES) {
        my $comm = LJ::load_user ($comm_name);
        next unless $comm && $comm->is_visible;
        return 1 if $u->can_manage ($comm) or $comm->is_friend($u); 
    }

    return 1 if $u->prop ('fotki_migration_status');

    return 0;
}

sub can_upload_photo {
    my $u = shift;

    return 0 unless $u->can_use_ljphoto();

    ## Basic user has no access to ljphoto
    return 0 if not ($u->get_cap('paid') or $u->in_class('plus') );

    return 1;
}

sub ajax_auth_token {
    my $u = shift;
    return LJ::Auth->ajax_auth_token($u, @_);
}

sub check_ajax_auth_token {
    my $u = shift;
    return LJ::Auth->check_ajax_auth_token($u, @_);
}

# returns username
*username = \&user;
sub user {
    my $u = shift;
    return $u->{user};
}

sub user_url_arg {
    my $u = shift;
    return "I,$u->{userid}" if $u->{journaltype} eq "I";
    return $u->{user};
}

# returns username for display
sub display_username {
    my $u = shift;
    my $need_cut = shift || 0;

    my $username = $u->{user};
    if ($u->is_identity){
        $username = $u->display_name;
        if ($need_cut){
            my $short_name = substr ($username, 0, 16);
            if ($username eq $short_name) {
                $username = $short_name;
            } else {
                $username = $short_name . "...";
            }
        }
    }

    return LJ::ehtml($username);
}

# returns the user-specified name of a journal exactly as entered
sub name_orig {
    my $u = shift;
    return $u->{name};
}

# returns the user-specified name of a journal in valid UTF-8
sub name_raw {
    my $u = shift;
    LJ::text_out(\$u->{name});
    return $u->{name};
}

# returns the user-specified name of a journal in valid UTF-8
# and with HTML escaped
sub name_html {
    my $u = shift;
    return LJ::ehtml($u->name_raw);
}

# userid
*userid = \&id;
sub id {
    my $u = shift;
    return int($u->{userid});
}

sub clusterid {
    my $u = shift;
    return $u->{clusterid};
}

# class method, returns { clusterid => [ uid, uid ], ... }
sub split_by_cluster {
    my $class = shift;

    my @uids = @_;
    my $us = LJ::load_userids(@uids);

    my %clusters;
    foreach my $u (values %$us) {
        next unless $u;
        push @{$clusters{$u->clusterid}}, $u->id;
    }

    return \%clusters;
}

## Returns current userhead for user.
sub userhead {
    my $u    = shift;
    my $opts = +shift || {};

    my $head_size = $opts->{head_size};

    my $userhead   = 'userinfo.gif';
    my $userhead_w = 16;
    my $userhead_h = undef;

    ## special icon?
    my ($icon, $size) = LJ::run_hook("head_icon",
                                     $u, head_size => $head_size);
    if ($icon){
        ## yeap.
        $userhead = $icon;
        $userhead_w = $size || 16;
        $userhead_h = $userhead_w;
        return $userhead, $userhead_w, $userhead_h;
    }

    ## default way
    if (!$LJ::IS_SSL && ($icon = $u->custom_usericon)) {
        $userhead = $icon;
        $userhead_w = 16;
    } elsif ($u->is_community) {
        if ($head_size) {
            $userhead = "comm_${head_size}.gif";
            $userhead_w = $head_size;
        } else {
            $userhead = "community.gif";
            $userhead_w = 16;
        }
    } elsif ($u->is_syndicated) {
        if ($head_size) {
            $userhead = "syn_${head_size}.gif";
            $userhead_w = $head_size;
        } else {
            $userhead = "syndicated.gif";
            $userhead_w = 16;
        }
    } elsif ($u->is_news) {
        if ($head_size) {
            $userhead = "news_${head_size}.gif";
            $userhead_w = $head_size;
        } else {
            $userhead = "newsinfo.gif";
            $userhead_w = 16;
        }
    } elsif ($u->is_identity) {
        my $params = $u->identity->ljuser_display_params($u, $opts);
        $userhead     = $params->{'userhead'}     || $userhead;
        $userhead_w   = $params->{'userhead_w'}   || $userhead_w;
        $userhead_h   = $params->{'userhead_h'}   || $userhead_h;
    } else {
        if ($head_size) {
            $userhead = "user_${head_size}.gif";
            $userhead_w = $head_size;
        } else {
            $userhead = "userinfo.gif";
            $userhead_w = 16;
        }
    }
    $userhead_h ||= $userhead_w;
    return $userhead, $userhead_w, $userhead_h;
}



sub bio {
    my $u = shift;
    return LJ::get_bio($u);
}

# if bio_absent is set to "yes", bio won't be updated
sub set_bio {
    my ($u, $text, $bio_absent) = @_;
    $bio_absent = "" unless $bio_absent;

    my $oldbio = $u->bio;
    my $newbio = $bio_absent eq "yes" ? $oldbio : $text;
    my $has_bio = ($newbio =~ /\S/) ? "Y" : "N";

    my %update = (
        'has_bio' => $has_bio,
    );
    LJ::update_user($u, \%update);

    # update their bio text
    if (($oldbio ne $text) && $bio_absent ne "yes") {
        if ($has_bio eq "N") {
            $u->do("DELETE FROM userbio WHERE userid=?", undef, $u->id);
            $u->dudata_set('B', 0, 0);
        } else {
            $u->do("REPLACE INTO userbio (userid, bio) VALUES (?, ?)",
                   undef, $u->id, $text);
            $u->dudata_set('B', 0, length($text));
        }
        LJ::MemCache::set([$u->id, "bio:" . $u->id], $text);
    }
}

sub opt_ctxpopup {
    my $u = shift;

    # if unset, default to on
    my $prop = $u->raw_prop('opt_ctxpopup') || 'Y';

    return $prop eq 'Y';
}

# opt_imagelinks format:
# 0|1 - replace images with placeholders at friends page
# :   - delimiter
# 0|1 - replace images with placeholders in comments at entry page
sub get_opt_imagelinks {
    my $u = shift;
    my $opt = $u->prop("opt_imagelinks") || "0:0";
    $opt = "0:0" unless $opt;
    $opt = "1:0" unless $opt =~ /^\d\:\d$/;
    return $opt;
}

sub opt_placeholders_friendspage {
    my $u = shift;
    my $opt = $u->get_opt_imagelinks;

    if ( $opt =~ /^(\d)\:\d$/ ) {
        return $1;
    }

    return 0;
}

sub opt_placeholders_comments {
    my $u = shift;
    my $opt = $u->get_opt_imagelinks;

    if ( $opt =~ /^\d\:(\d)$/ ) {
        return $1;
    }

    return 0;
}

sub get_opt_videolinks {
    my $u = shift;
    my $opt = $u->raw_prop("opt_embedplaceholders") || "0:0";
    $opt = "0:0" unless $opt || $opt eq 'N';
    $opt = "1:0" unless $opt =~ /^\d\:\d$/;
    return $opt;
}

sub opt_embedplaceholders {
    my $u = shift;
    my $opt = $u->get_opt_videolinks;

    if ( $opt =~ /^(\d)\:\d$/ ) {
        return $1;
    }

    return 0;
}

sub opt_videoplaceholders_comments {
    my $u = shift;
    my $opt = $u->get_opt_videolinks;

    if ( $opt =~ /^\d\:(\d)$/ ) {
        return $1;
    }

    return 0;
}

sub opt_showmutualfriends {
    my $u = shift;
    return $u->raw_prop('opt_showmutualfriends') ? 1 : 0;
}

# only certain journaltypes can show mutual friends
sub show_mutualfriends {
    my $u = shift;

    return 0 unless $u->journaltype =~ /[PSI]/;
    return $u->opt_showmutualfriends ? 1 : 0;
}

sub opt_getting_started {
    my $u = shift;

    # if unset, default to on
    my $prop = $u->raw_prop('opt_getting_started') || 'Y';

    return $prop;
}

sub opt_stylealwaysmine {
    my $u = shift;

    return 0 unless $u->can_use_stylealwaysmine;
    return $u->raw_prop('opt_stylealwaysmine') eq 'Y' ? 1 : 0;
}

sub can_use_stylealwaysmine {
    my $u = shift;
    my $ret = 0;

    return 0 if $LJ::DISABLED{stylealwaysmine};
    $ret = LJ::run_hook("can_use_stylealwaysmine", $u);
    return $ret;
}

sub opt_commentsstylemine {
    my $u = shift;

    return 0 unless $u->can_use_commentsstylemine;

    if ( $u->raw_prop('opt_stylemine') ) {
        $u->set_prop( opt_stylemine => 0 );
        $u->set_prop( opt_commentsstylemine => 'Y' );
    }

    return $u->raw_prop('opt_commentsstylemine') eq 'Y'? 1 : 0;
}

sub can_use_commentsstylemine {
    return 0 unless LJ::is_enabled('comments_style_mine');
    return 1;
}

sub has_enabled_getting_started {
    my $u = shift;

    return $u->opt_getting_started eq 'Y' ? 1 : 0;
}


# ***                                                                      *** #
# ***************************** OBSOLETE ************************************* #
# ***                                                                      *** #
# This method sends messages using djabberd servers
# which have been changed with Ejabberd. So method is obsolete.
# Code to send messages to Ejabberd is in cgi-bin/LJ/NotificationMethod/IM.pm
#
#
# find what servers a user is logged in to, and send them an IM
# returns true if sent, false if failure or user not logged on
# Please do not call from web context
sub send_im {
    my ($self, %opts) = @_;

    croak "Can't call in web context" if LJ::is_web_context();

    my $from = delete $opts{from};
    my $msg  = delete $opts{message} or croak "No message specified";

    croak "No from or bot jid defined" unless $from || $LJ::JABBER_BOT_JID;

    my @resources = keys %{LJ::Jabber::Presence->get_resources($self)} or return 0;

    my $res = $resources[0] or return 0; # FIXME: pick correct server based on priority?
    my $pres = LJ::Jabber::Presence->new($self, $res) or return 0;
    my $ip = $LJ::JABBER_SERVER_IP || '127.0.0.1';

    my $sock = IO::Socket::INET->new(PeerAddr => "${ip}:5200")
        or return 0;

    my $vhost = $LJ::DOMAIN;

    my $to_jid   = $self->user   . '@' . $LJ::DOMAIN;
    my $from_jid = $from ? $from->user . '@' . $LJ::DOMAIN : $LJ::JABBER_BOT_JID;

    my $emsg = LJ::exml($msg);
    my $stanza = LJ::eurl(qq{<message to="$to_jid" from="$from_jid"><body>$emsg</body></message>});

    print $sock "send_stanza $vhost $to_jid $stanza\n";

    my $start_time = time();

    while (1) {
        my $rin = '';
        vec($rin, fileno($sock), 1) = 1;
        select(my $rout=$rin, undef, undef, 1);
        if (vec($rout, fileno($sock), 1)) {
            my $ln = <$sock>;
            return 1 if $ln =~ /^OK/;
        }

        last if time() > $start_time + 5;
    }

    return 0;
}

# returns whether or not the user is online on jabber
sub jabber_is_online {
    my $u = shift;

    return keys %{LJ::Jabber::Presence->get_resources($u)} ? 1 : 0;
}

sub esn_inbox_default_expand {
    my $u = shift;

    my $prop = $u->raw_prop('esn_inbox_default_expand');
    return $prop ne 'N';
}

sub rate_log {
    my ($u, $ratename, $count, $opts) = @_;
    LJ::rate_log($u, $ratename, $count, $opts);
}

sub rate_check {
    my ($u, $ratename, $count, $opts) = @_;
    LJ::rate_check($u, $ratename, $count, $opts);
}

sub statusvis {
    my $u = shift;
    return $u->{statusvis};
}

sub statusvisdate {
    my $u = shift;
    return $u->{statusvisdate};
}

sub statusvisdate_unix {
    my $u = shift;
    return LJ::TimeUtil->mysqldate_to_time($u->{statusvisdate});
}

# returns list of all previous statuses of the journal
# in order from newest to oldest
sub get_previous_statusvis {
    my $u = shift;
    
    my $extra = $u->selectcol_arrayref(
        "SELECT extra FROM userlog WHERE userid=? AND action='accountstatus' ORDER BY logtime DESC",
        undef, $u->{userid});
    my @statusvis;
    foreach my $e (@$extra) {
        my %fields;
        LJ::decode_url_string($e, \%fields, []);
        push @statusvis, $fields{old};
    }
    return @statusvis;
}

# set_statusvis only change statusvis parameter, all accompanied actions are done in set_* methods
sub set_statusvis {
    my ($u, $statusvis) = @_;

    croak "Invalid statusvis: $statusvis"
        unless $statusvis =~ /^(?:
            V|       # visible
            D|       # deleted
            X|       # expunged
            S|       # suspended
            L|       # locked
            M|       # memorial
            O|       # read-only
            R        # renamed
                                )$/x;

    # log the change to userlog
    $u->log_event('accountstatus', {
            # remote looked up by log_event
            old => $u->statusvis,
            new => $statusvis,
        }) if $u->clusterid; # purged user can get suspended, but have no clusterid at that moment

    # do update
    my $ret = LJ::update_user($u, { statusvis => $statusvis,
                                 raw => 'statusvisdate=NOW()' });

    LJ::run_hook("props_changed", $u, {statusvis => $statusvis});

    $u->fb_push;

    return $ret;
}

sub set_visible {
    my $u = shift;

    LJ::run_hooks("account_will_be_visible", $u);
    return $u->set_statusvis('V');
}

sub set_deleted {
    my $u = shift;
    my $res = $u->set_statusvis('D');

    # run any account cancellation hooks
    LJ::run_hooks("account_delete", $u);
    return $res;
}

sub set_expunged {
    my $u = shift;
    return $u->set_statusvis('X');
}

sub set_suspended {
    my ($u, $who, $reason, $errref) = @_;
    die "Not enough parameters for LJ::User::set_suspended call" unless $who and $reason;

    my $res = $u->set_statusvis('S');
    unless ($res) {
        $$errref = "DB error while setting statusvis to 'S'" if ref $errref;
        return $res;
    }

    LJ::statushistory_add($u, $who, "suspend", $reason);

    # close all spamreports on this user
    my $dbh = LJ::get_db_writer();
    $dbh->do("UPDATE spamreports SET state='closed' WHERE posterid = ? AND state='open'", undef, $u->userid);
    
    # close all botreports on this user
    require LJ::BotReport;
    LJ::BotReport->close_requests($u->userid);

    #
    LJ::run_hooks("account_cancel", $u);
    LJ::run_hooks("account_suspend", $u);

    if (my $err = LJ::run_hook("cdn_purge_userpics", $u)) {
        $$errref = $err if ref $errref and $err;
        return 0;
    }

    return $res; # success
}

# sets a user to visible, but also does all of the stuff necessary when a suspended account is unsuspended
# this can only be run on a suspended account
sub set_unsuspended {
    my ($u, $who, $reason, $errref) = @_;
    die "Not enough parameters for LJ::User::set_unsuspended call" unless $who and $reason;

    unless ($u->is_suspended) {
        $$errref = "User isn't suspended" if ref $errref;
        return 0;
    }

    my $res = $u->set_statusvis('V');
    unless ($res) {
        $$errref = "DB error while setting statusvis to 'V'" if ref $errref;
        return $res;
    }

    LJ::statushistory_add($u, $who, "unsuspend", $reason);
    LJ::run_hooks("account_unsuspend", $u);

    return $res; # success
}

sub set_locked {
    my $u = shift;
    return $u->set_statusvis('L');
}

sub set_memorial {
    my $u = shift;
    return $u->set_statusvis('M');
}

sub set_readonly {
    my $u = shift;
    return $u->set_statusvis('O');
}

sub set_renamed {
    my $u = shift;
    return $u->set_statusvis('R');
}

# returns if this user is considered visible
sub is_visible {
    my $u = shift;
    return ($u->statusvis eq 'V' && $u->clusterid != 0);
}

sub is_deleted {
    my $u = shift;
    return $u->statusvis eq 'D';
}

sub is_expunged {
    my $u = shift;
    return $u->statusvis eq 'X' || $u->clusterid == 0;
}

sub is_suspended {
    my $u = shift;
    return $u->statusvis eq 'S';
}

sub is_locked {
    my $u = shift;
    return $u->statusvis eq 'L';
}

sub is_memorial {
    my $u = shift;
    return $u->statusvis eq 'M';
}

sub is_readonly {
    my $u = shift;
    return $u->statusvis eq 'O';
}

sub is_renamed {
    my $u = shift;
    return $u->statusvis eq 'R';
}

sub caps {
    my $u = shift;
    return $u->{caps};
}

*get_post_count = \&number_of_posts;
sub number_of_posts {
    my ($u, %opts) = @_;

    # to count only a subset of all posts
    if (%opts) {
        $opts{return} = 'count';
        return $u->get_post_ids(%opts);
    }

    my $memkey = [$u->{userid}, "log2ct:$u->{userid}"];
    my $expire = time() + 3600*24*2; # 2 days
    return LJ::MemCache::get_or_set($memkey, sub {
        return $u->selectrow_array("SELECT COUNT(*) FROM log2 WHERE journalid=?",
                                   undef, $u->{userid});
    }, $expire);
}

# return the number if public posts
sub number_of_public_posts {
    my ($u) = @_;
    my $memkey = [$u->{userid}, "log2publicct:$u->{userid}"];
    my $expire = time() + 300;  # 5 min
    return LJ::MemCache::get_or_set($memkey, sub {
        return $u->get_post_ids(return => 'count', security => 'public');
    }, $expire);
}


# return the number of posts that the user actually posted themselves
sub number_of_posted_posts {
    my $u = shift;

    my $num = $u->number_of_posts;
    $num-- if LJ::run_hook('user_has_auto_post', $u);

    return $num;
}

# <LJFUNC>
# name: LJ::get_post_ids
# des: Given a user object and some options, return the number of posts or the
#      posts'' IDs (jitemids) that match.
# returns: number of matching posts, <strong>or</strong> IDs of
#          matching posts (default).
# args: u, opts
# des-opts: 'security' - [public|private|usemask]
#           'allowmask' - integer for friends-only or custom groups
#           'start_date' - UTC date after which to look for match
#           'end_date' - UTC date before which to look for match
#           'return' - if 'count' just return the count
#           TODO: Add caching?
# </LJFUNC>
sub get_post_ids {
    my ($u, %opts) = @_;

    my $query = 'SELECT';
    my @vals; # parameters to query

    if ($opts{'start_date'} || $opts{'end_date'}) {
        croak "start or end date not defined"
            if (!$opts{'start_date'} || !$opts{'end_date'});

        if (!($opts{'start_date'} >= 0) || !($opts{'end_date'} >= 0) ||
            !($opts{'start_date'} <= $LJ::EndOfTime) ||
            !($opts{'end_date'} <= $LJ::EndOfTime) ) {
            return undef;
        }
    }

    # return count or jitemids
    if ($opts{'return'} eq 'count') {
        $query .= " COUNT(*)";
    } else {
        $query .= " jitemid";
    }

    # from the journal entries table for this user
    $query .= " FROM log2 WHERE journalid=?";
    push(@vals, $u->{userid});

    # filter by security
    if ($opts{'security'}) {
        $query .= " AND security=?";
        push(@vals, $opts{'security'});
        # If friends-only or custom
        if ($opts{'security'} eq 'usemask' && $opts{'allowmask'}) {
            $query .= " AND allowmask=?";
            push(@vals, $opts{'allowmask'});
        }
    }

    if ($opts{posterid}){
        $query .= " AND posterid = ? ";
        push @vals => $opts{posterid};
    }
    if ($opts{afterid}){
        $query .= " AND jitemid > ? ";
        push @vals => $opts{afterid};
    }

    # filter by date, use revttime as it is indexed
    if ($opts{'start_date'} && $opts{'end_date'}) {
        # revttime is reverse event time
        my $s_date = $LJ::EndOfTime - $opts{'start_date'};
        my $e_date = $LJ::EndOfTime - $opts{'end_date'};
        $query .= " AND revttime<?";
        push(@vals, $s_date);
        $query .= " AND revttime>?";
        push(@vals, $e_date);
    }

    # return count or jitemids
    if ($opts{'return'} eq 'count') {
        return $u->selectrow_array($query, undef, @vals);
    } else {
        my $jitemids = $u->selectcol_arrayref($query, undef, @vals) || [];
        die $u->errstr if $u->err;
        return @$jitemids;
    }
}

sub password {
    my $u = shift;
    return unless $u->is_person;
    $u->{_password} ||= LJ::MemCache::get_or_set([$u->{userid}, "pw:$u->{userid}"], sub {
        my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
        return $dbh->selectrow_array("SELECT password FROM password WHERE userid=?",
                                     undef, $u->id);
    });
    return $u->{_password};
}

sub journaltype {
    my $u = shift;
    return $u->{journaltype};
}

sub friends {
    my $u = shift;
    my @friendids = $u->friend_uids;
    my $users = LJ::load_userids(@friendids);
    while(my ($uid, $u) = each %$users){
        delete $users->{$uid} unless $u;
    }
    return values %$users if wantarray;
    return $users;
}

# Returns a list of friends who are actual people, not communities or feeds
sub people_friends {
    my $u = shift;

    return grep { $_->is_person || $_->is_identity } $u->friends;
}

# the count of friends that the user has added
# -- eg, not initial friends auto-added for them
sub friends_added_count {
    my $u = shift;
    my %init_friends_ids;

    for ( @LJ::INITIAL_FRIENDS, @LJ::INITIAL_OPTIONAL_FRIENDS, $u->user ) {
        my $u = LJ::load_user($_);
        $init_friends_ids{ $u->id }++ if $u;
    }

    return scalar grep { ! $init_friends_ids{$_} } $u->friend_uids;
}

sub set_password {
    my ($u, $password) = @_;
    return LJ::set_password($u->id, $password);
}

sub set_email {
    my ($u, $email) = @_;
    return LJ::set_email($u->id, $email);
}

# returns array of friendof uids.  by default, limited at 50,000 items.
sub friendof_uids {
    my ($u, %args) = @_;
    my $limit = int(delete $args{limit}) || 50000;
    Carp::croak("unknown option") if %args;

    return LJ::RelationService->find_relation_sources($u, 'F', limit => $limit);
}

# returns array of friend uids.  by default, limited at 50,000 items.
sub friend_uids {
    my ($u, %args) = @_;
    my $limit = int(delete $args{limit}) || 50000;
    Carp::croak("unknown option") if %args;

    return LJ::RelationService->find_relation_destinations($u, 'F', limit => $limit);
}

# helper method since the logic for both friends and friendofs is so similar
sub _friend_friendof_uids {
    my $u = shift;
    my %args = @_;

    ## check cache first
    my $res = $u->_load_friend_friendof_uids_from_memcache($args{mode}, $args{limit});
    return @$res if defined $res;

    # call normally if no gearman/not wanted
    my $gc = '';
    return $u->_friend_friendof_uids_do(skip_memcached => 1, %args) # we've already checked memcached above
        unless LJ::conf_test($LJ::LOADFRIENDS_USING_GEARMAN, $u->id) and $gc = LJ::gearman_client();

    # invoke gearman
    my @uids;
    my $args = Storable::nfreeze({uid => $u->id, opts => \%args});
    my $task = Gearman::Task->new("load_friend_friendof_uids", \$args,
                                  {
                                      uniq => join("-", $args{mode}, $u->id, $args{limit}),
                                      on_complete => sub {
                                          my $res = shift;
                                          return unless $res;
                                          my $uidsref = Storable::thaw($$res);
                                          @uids = @{$uidsref || []};
                                      }
                                  });
    my $ts = $gc->new_task_set();
    $ts->add_task($task);
    $ts->wait(timeout => 30); # 30 sec timeout

    return @uids;

}

# actually get friend/friendof uids, should not be called directly
sub _friend_friendof_uids_do {
    my ($u, %args) = @_;
## method is also called from load-friends-gm worker.

    my $limit = int(delete $args{limit}) || 50000;
    my $mode  = delete $args{mode};
    my $skip_memcached = delete $args{skip_memcached};
    Carp::croak("unknown option") if %args;

    ## cache
    unless ($skip_memcached){
        my $res = $u->_load_friend_friendof_uids_from_memcache($mode, $limit);
        return @$res if $res;
    }

    ## db
    my $uids = $u->_load_friend_friendof_uids_from_db($mode, $limit);

    # if the list of uids is greater than 950k
    # -- slow but this definitely works
    my $pack = pack("N*", $limit);
    foreach (@$uids) {
        last if length $pack > 1024*950;
        $pack .= pack("N*", $_);
    }

    ## memcached
    my $memkey = $u->_friend_friendof_uids_memkey($mode);
    LJ::MemCache::add($memkey, $pack, 3600) if $uids;

    return @$uids;
}

sub _friend_friendof_uids_memkey {
    my ($u, $mode) = @_;
    my $memkey;

    if ($mode eq "friends") {
        $memkey = [$u->id, "friends2:" . $u->id];
    } elsif ($mode eq "friendofs") {
        $memkey = [$u->id, "friendofs2:" . $u->id];
    } else {
        Carp::croak("mode must either be 'friends' or 'friendofs'");
    }

    return $memkey;
}

sub _load_friend_friendof_uids_from_memcache {
    my ($u, $mode, $limit) = @_;

    my $memkey = $u->_friend_friendof_uids_memkey($mode);

    if (my $pack = LJ::MemCache::get($memkey)) {
        my ($slimit, @uids) = unpack("N*", $pack);
        # value in memcache is good if stored limit (from last time)
        # is >= the limit currently being requested.  we just may
        # have to truncate it to match the requested limit
        if ($slimit >= $limit) {
            @uids = @uids[0..$limit-1] if @uids > $limit;
            return \@uids;
        }

        # value in memcache is also good if number of items is less
        # than the stored limit... because then we know it's the full
        # set that got stored, not a truncated version.
        return \@uids if @uids < $slimit;
    }

    return undef;
}

## Attention: if 'limit' arg is omited, this method loads all userid from friends table.
sub _load_friend_friendof_uids_from_db {
    my $u     = shift;
    my $mode  = shift;
    my $limit = shift;

    $limit = " LIMIT $limit" if $limit;

    my $sql = '';
    if ($mode eq 'friends'){
        $sql = "SELECT friendid FROM friends WHERE userid=? $limit";
    } elsif ($mode eq 'friendofs'){
        $sql = "SELECT userid FROM friends WHERE friendid=? $limit";
    } else {
        Carp::croak("mode must either be 'friends' or 'friendofs'");
    }

    my $dbh = LJ::get_db_reader();
    my $uids = $dbh->selectcol_arrayref($sql, undef, $u->id);
    return $uids;
}

## Returns exact friendsOf count. Whitout limit.
## Use it with care.
sub precise_friendsof_count {
    my $u = shift;

    my $cnt_key = "friendof:person_cnt:" . $u->userid;
    my $counter = LJ::MemCache::get([ $u->userid, $cnt_key ]);
    return $counter if $counter;

    ## arrayref with all users friends
    my $uids = $u->_load_friend_friendof_uids_from_db('friendofs');

    my $res = 0;
    ## work with batches
    while (my @uid_batch = splice @$uids, 0 => 5000){
        my $us = LJ::load_userids(@uid_batch);
        foreach my $fuid (@uid_batch){
            my $fu = $us->{$fuid};
            next unless $fu;
            next unless $fu->can_be_counted_as_friendof;
            
            ## Friend!!!
            $res++;
        }
    }

    ## actual data
    LJ::MemCache::set([ $u->userid, $cnt_key ]  => $res, 24*3600);

    return $res;
}

## Class method
sub increase_friendsof_counter {
    my $class = shift;
    my $uid   = shift;
    $class->_incr_decr_friendsof_counter($uid, 'incr');
}
sub decrease_friendsof_counter {
    my $class = shift;
    my $uid   = shift;
    $class->_incr_decr_friendsof_counter($uid, 'decr');
}
sub _incr_decr_friendsof_counter {
    my $class  = shift;
    my $uid    = shift;
    my $action = shift;

    ## it takes a lot of time (>5 seconds) to calculate 'friendof:person_cnt:X' counter.
    ## So update it with a bit of intellect.
    my $precise_friendsof_counter = [ $uid, "friendof:person_cnt:$uid" ];
    my $counter = LJ::MemCache::get($precise_friendsof_counter);

    if ($counter){
        my $u = LJ::load_userid($uid);
        ## Memcached: http://code.sixapart.com/svn/memcached/trunk/server/doc/protocol.txt
        ##  the item must already
        ##  exist for incr/decr to work; these commands won't pretend that a
        ##  non-existent key exists with value 0; instead, they will fail.
        ##
        ## Incr/Decr doesn't change a key expiration time, 
        ##
        if ($action eq 'incr'){
            LJ::MemCache::incr($precise_friendsof_counter);
        } elsif ($action eq 'decr'){
            LJ::MemCache::decr($precise_friendsof_counter);
        }
    }

}

sub fb_push {
    my $u = shift;
    eval {
        if ($u) {
            require LJ::FBInterface;
            LJ::FBInterface->push_user_info( $u->id );
        }
    };
    warn "Error running fb_push: $@\n" if $@ && $LJ::IS_DEV_SERVER;
}

sub grant_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||= "";
    my $dbh = LJ::get_db_writer();

    return 1 if LJ::check_priv($u, $priv, $arg);

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("INSERT INTO priv_map (userid, prlid, arg) VALUES (?, ?, ?)",
             undef, $u->id, $privid, $arg);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    return 1;
}

sub revoke_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||="";
    my $dbh = LJ::get_db_writer();

    return 1 unless LJ::check_priv($u, $priv, $arg);

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("DELETE FROM priv_map WHERE userid = ? AND prlid = ? AND arg = ?",
             undef, $u->id, $privid, $arg);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    undef $u->{'_priv'};
    return 1;
}

sub revoke_priv_all {
    my ($u, $priv) = @_;
    my $dbh = LJ::get_db_writer();

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("DELETE FROM priv_map WHERE userid = ? AND prlid = ?",
             undef, $u->id, $privid);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    undef $u->{'_priv'};
    return 1;
}

# must be called whenever birthday, location, journal modtime, journaltype, etc.
# changes.  see LJ/Directory/PackedUserRecord.pm
sub invalidate_directory_record {
    my $u = shift;

    # Future: ?
    # LJ::try_our_best_to("invalidate_directory_record", $u->id);
    # then elsewhere, map that key to subref.  if primary run fails,
    # put in schwartz, then have one worker (misc-deferred) to
    # redo...
    
    my $dbs = defined $LJ::USERSEARCH_DB_WRITER ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER) : LJ::get_db_writer();
    $dbs->do("UPDATE usersearch_packdata SET good_until=0 WHERE userid=?",
             undef, $u->id);
}

# Used to promote communities in interest search results
sub render_promo_of_community {
    my ($comm, $style) = @_;

    return undef unless $comm;

    $style ||= 'Vertical';

    # get the ljuser link
    my $commljuser = $comm->ljuser_display;

    # link to journal
    my $journal_base = $comm->journal_base;

    # get default userpic if any
    my $userpic = $comm->userpic;
    my $userpic_html = '';
    if ($userpic) {
        my $userpic_url = $userpic->url;
        $userpic_html = qq { <a href="$journal_base"><img src="$userpic_url" /></a> };
    }

    my $blurb = $comm->prop('comm_promo_blurb') || '';

    my $join_link = "$LJ::SITEROOT/community/join.bml?comm=$comm->{user}";
    my $watch_link = "$LJ::SITEROOT/friends/add.bml?user=$comm->{user}";
    my $read_link = $comm->journal_base;

    LJ::need_res("stc/lj_base.css");

    # if horizontal, userpic needs to come before everything
    my $box_class;
    my $comm_display;

    if (lc $style eq 'horizontal') {
        $box_class = 'Horizontal';
        $comm_display = qq {
            <div class="Userpic">$userpic_html</div>
            <div class="Title">Community Promo</div>
            <div class="CommLink">$commljuser</div>
        };
    } else {
        $box_class = 'Vertical';
        $comm_display = qq {
            <div class="Title">Community Promo</div>
            <div class="CommLink">$commljuser</div>
            <div class="Userpic">$userpic_html</div>
        };
    }


    my $html = qq {
        <div class="CommunityPromoBox">
            <div class="$box_class">
                $comm_display
                <div class="Blurb">$blurb</div>
                <div class="Links"><a href="$join_link">Join</a> | <a href="$watch_link">Watch</a> |
                    <a href="$read_link">Read</a></div>

                <div class='ljclear'>&nbsp;</div>
            </div>
        </div>
    };

    return $html;
}

sub can_expunge {
    my $u = shift;

    my $statusvisdate = $u->statusvisdate_unix;

    # check admin flag "this journal must not be expunged for abuse team
    # investigation". hack: if flag is on, then set statusvisdate to now,
    # so that the next time worker bin/worker/expunge-users won't check
    # this user again.
    #
    # optimization concern: isn't it too much strain checking this prop
    # for every user? well, we've got to check this prop for every user
    # that seems eligible anyway, and moveucluster isn't supposed to send
    # us users who got too recent statusvisdate or something.
    if ($u->prop('dont_expunge_journal')) {
        LJ::update_user($u, { raw => 'statusvisdate=NOW()' });
        return 0;
    }

    if ($u->is_deleted) {
        my $expunge_days =
            LJ::conf_test($LJ::DAYS_BEFORE_EXPUNGE) || 30;

        return 0 unless $statusvisdate < time() - 86400 * $expunge_days;

        return 1;
    }

    if ($u->is_suspended) {
        return 0 if $LJ::DISABLED{'expunge_suspended'};

        my $expunge_days =
            LJ::conf_test($LJ::DAYS_BEFORE_EXPUNGE_SUSPENDED) || 30;

        return 0 unless $statusvisdate < time() - 86400 * $expunge_days;

        return 1;
    }

    return 0;
}

# Check to see if the user can use eboxes at all
sub can_use_ebox {
    my $u = shift;

    return ref $LJ::DISABLED{ebox} ? !$LJ::DISABLED{ebox}->($u) : !$LJ::DISABLED{ebox};
}

# Allow users to choose eboxes if:
# 1. The entire ebox feature isn't disabled AND
# 2. The option to choose eboxes isn't disabled OR
# 3. The option to choose eboxes is disabled AND
# 4. The user already has eboxes turned on
sub can_use_ebox_ui {
    my $u = shift;
    my $allow_ebox = 1;

    if ($LJ::DISABLED{ebox_option}) {
        $allow_ebox = $u->prop('journal_box_entries');
    }

    return $u->can_use_ebox && $allow_ebox;
}

# return hashref with intname => intid
sub interests {
    my $u = shift;
    my $uints = LJ::get_interests($u);
    my %interests;

    foreach my $int (@$uints) {
        $interests{$int->[1]} = $int->[0];  # $interests{name} = intid
    }

    return \%interests;
}

sub interest_list {
    my $u = shift;

    return map { $_->[1] } @{ LJ::get_interests($u) };
}

sub interest_count {
    my $u = shift;

    # FIXME: fall back to SELECT COUNT(*) if not cached already?
    return scalar @{LJ::get_interests($u, { justids => 1 })};
}

sub set_interests {
    my $u = shift;
    LJ::set_interests($u, @_);
}

sub lazy_interests_cleanup {
    my $u = shift;

    my $dbh = LJ::get_db_writer();

    if ($u->is_community) {
        $dbh->do("INSERT IGNORE INTO comminterests SELECT * FROM userinterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM userinterests WHERE userid=?", undef, $u->id);
    } else {
        $dbh->do("INSERT IGNORE INTO userinterests SELECT * FROM comminterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM comminterests WHERE userid=?", undef, $u->id);
    }

    LJ::memcache_kill($u, "intids");
    return 1;
}

# this will return a hash of information about this user.
# this is useful for JavaScript endpoints which need to dump
# JSON data about users.
sub info_for_js {
    my $u = shift;

    my %ret = (
               username         => $u->user,
               display_username => $u->display_username,
               display_name     => $u->display_name,
               userid           => $u->userid,
               url_journal      => $u->journal_base,
               url_profile      => $u->profile_url,
               url_allpics      => $u->allpics_base,
               ljuser_tag       => $u->ljuser_display,
               is_comm          => $u->is_comm,
               is_person        => $u->is_person,
               is_syndicated    => $u->is_syndicated,
               is_identity      => $u->is_identity,
               is_shared        => $u->is_shared,
               );
    # Without url_message "Send Message" link should not display
    $ret{url_message} = $u->message_url unless ($u->opt_usermsg eq 'N');

    LJ::run_hook("extra_info_for_js", $u, \%ret);

    my $up = $u->userpic;

    if ($up) {
        $ret{url_userpic} = $up->url;
        $ret{userpic_w}   = $up->width;
        $ret{userpic_h}   = $up->height;
    }

    return %ret;
}

sub postreg_completed {
    my $u = shift;

    return 0 unless $u->bio;
    return 0 unless $u->interest_count;
    return 1;
}

# return if $target is banned from $u's journal
*has_banned = \&is_banned;
sub is_banned {
    my ($u, $target) = @_;
    return LJ::is_banned($target->userid, $u->userid);
}

sub ban_user {
    my ($u, $ban_u) = @_;

    my $remote = LJ::get_remote();
    $u->log_event('ban_set', { actiontarget => $ban_u->id, remote => $remote });
    LJ::run_hooks('ban_set', $u, $ban_u);

    return LJ::set_rel($u->id, $ban_u->id, 'B');
}

sub ban_user_multi {
    my ($u, @banlist) = @_;

    LJ::set_rel_multi(map { [$u->id, $_, 'B'] } @banlist);

    my $us = LJ::load_userids(@banlist);
    foreach my $banuid (@banlist) {
        $u->log_event('ban_set', { actiontarget => $banuid, remote => LJ::get_remote() });
        LJ::run_hooks('ban_set', $u, $us->{$banuid}) if $us->{$banuid};
    }

    return 1;
}

sub unban_user_multi {
    my ($u, @unbanlist) = @_;

    LJ::clear_rel_multi(map { [$u->id, $_, 'B'] } @unbanlist);

    my $us = LJ::load_userids(@unbanlist);
    foreach my $banuid (@unbanlist) {
        $u->log_event('ban_unset', { actiontarget => $banuid, remote => LJ::get_remote() });
        LJ::run_hooks('ban_unset', $u, $us->{$banuid}) if $us->{$banuid};
    }

    return 1;
}

# return if $target is in $fgroupid
sub user_in_friend_group {
    my ($u, $target, $fgroupid) = @_;
    return 0 unless $u->is_friend($target);

    my $grpmask = 1 << $fgroupid;
    my $frmask = LJ::get_groupmask($u, $target);
    return 0 unless $grpmask && $frmask;

    return $grpmask & $frmask;
}

# returns if this user's polls are clustered
sub polls_clustered {
    my $u = shift;
    return $u->dversion >= 8;
}

sub dversion {
    my $u = shift;
    return $u->{dversion};
}

# take a user on dversion 7 and upgrade them to dversion 8 (clustered polls)
sub upgrade_to_dversion_8 {
    my $u = shift;
    my $dbh = shift;
    my $dbhslo = shift;
    my $dbcm = shift;

    # If user has been purged, go ahead and update version
    # Otherwise move their polls
    my $ok = $u->is_expunged ? 1 : LJ::Poll->make_polls_clustered($u, $dbh, $dbhslo, $dbcm);

    LJ::update_user($u, { 'dversion' => 8 }) if $ok;

    return $ok;
}

# can this user add any more friends?
sub can_add_friends {
    my ($u, $err, $opts) = @_;

    if ($u->is_suspended) {
        $$err = "Suspended journals cannot add friends.";
        return 0;
    }

    if ($u->{'status'} ne 'A') {
        $$err = qq|Sorry, you aren't allowed to add to friends until your email address has been validated. If you've lost the confirmation email to do this, you can <a href="http://www.livejournal.com/register.bml">have it re-sent.</a>|;
        return 0;
    }

    # have they reached their friend limit?
    my $fr_count = $opts->{'numfriends'} || $u->friend_uids;
    my $maxfriends = $u->get_cap('maxfriends');
    if ($fr_count >= $maxfriends) {
        $$err = "You have reached your limit of $maxfriends friends.";
        return 0;
    }

    # are they trying to add friends too quickly?

    # don't count mutual friends
    if (exists($opts->{friend})) {
        my $fr_user = $opts->{friend};
        # we needed LJ::User object, not just a hash.
        if (ref($fr_user) eq 'HASH') {
            $fr_user = LJ::load_user($fr_user->{username});
        } else {
            $fr_user = LJ::want_user($fr_user);
        }

        return 1 if $fr_user && $fr_user->is_friend($u);
    }

    unless ($u->rate_log('addfriend', 1)) {
        $$err = "You are trying to add too many friends in too short a period of time.";
        return 0;
    }

    return 1;
}

# returns if this user can join an adult community or not
# adultref will hold the value of the community's adult content flag
sub can_join_adult_comm {
    my ($u, %opts) = @_;

    return 1 unless LJ::is_enabled('content_flag');

    my $adultref = $opts{adultref};
    my $comm = $opts{comm} or croak "No community passed";

    my $adult_content = $comm->adult_content_calculated;
    $$adultref = $adult_content;

    if ($adult_content eq "concepts" && ($u->is_child || !$u->best_guess_age)) {
        return 0;
    } elsif ($adult_content eq "explicit" && ($u->is_minor || !$u->best_guess_age)) {
        return 0;
    }

    return 1;
}
        

sub is_in_beta {
    my ($u, $key) = @_;
    return LJ::BetaFeatures->user_in_beta( $u => $key );
}

# return the user's timezone based on the prop if it's defined, otherwise best guess
sub timezone {
    my $u = shift;

    my $offset = 0;
    LJ::get_timezone($u, \$offset);
    return $offset;
}

# returns a DateTime object corresponding to a user's "now"
sub time_now {
    my $u = shift;

    my $now = DateTime->now;

    # if user has timezone, use it!
    my $tz = $u->prop("timezone");
    return $now unless $tz;

    $now = eval { DateTime->from_epoch(
                                       epoch => time(),
                                       time_zone => $tz,
                                       );
              };

    return $now;
}

sub can_admin_content_flagging {
    my $u = shift;

    return 0 unless LJ::is_enabled("content_flag");
    return 1 if $LJ::IS_DEV_SERVER;
    return LJ::check_priv($u, "siteadmin", "contentflag");
}

sub can_see_content_flag_button {
    my $u = shift;
    my %opts = @_;

    return 0 unless LJ::is_enabled("content_flag");

    my $content = $opts{content};

    # user can't flag any journal they manage nor any entry they posted
    # user also can't flag non-public entries
    if (LJ::isu($content)) {
        return 0 if $u->can_manage($content);
    } elsif ($content->isa("LJ::Entry")) {
        return 0 if $u->equals($content->poster);
        return 0 unless $content->security eq "public";
    }

    # user can't flag anything if their account isn't at least one month old
    my $one_month = 60*60*24*30;
    return 0 unless time() - $u->timecreate >= $one_month;

    return 1;
}

sub can_flag_content {
    my $u = shift;
    my %opts = @_;

    return 0 unless $u->can_see_content_flag_button(%opts);
    return 0 if LJ::sysban_check("contentflag", $u->user);
    return 0 unless $u->rate_check("ctflag", 1);
    return 1;
}

# sometimes when the app throws errors, we want to display "nice"
# text to end-users, while allowing admins to view the actual error message
sub show_raw_errors {
    my $u = shift;

    return 1 if $LJ::IS_DEV_SERVER;

    return 1 if LJ::check_priv($u, "supporthelp");
    return 1 if LJ::check_priv($u, "supportviewscreened");
    return 1 if LJ::check_priv($u, "siteadmin");

    return 0;
}

# defined by the user
# returns 'none', 'concepts' or 'explicit'
sub adult_content {
    my $u = shift;

    my $prop_value = $u->prop('adult_content'); 

    return $prop_value ? $prop_value : "none";
}

# defined by an admin
sub admin_content_flag {
    my $u = shift;

    return $u->prop('admin_content_flag');
}

# uses both user- and admin-defined props to figure out the adult content level
sub adult_content_calculated {
    my $u = shift;

    $u->preload_props(qw/admin_content_flag adult_content/);
    return "explicit" if $u->admin_content_flag eq "explicit_adult";
    return $u->adult_content;
}

sub show_graphic_previews {
    my $u = shift;

    my $prop_value = $u->prop('show_graphic_previews');

    my $hook_rv = LJ::run_hook("override_show_graphic_previews", $u, $prop_value);
    return $hook_rv if defined $hook_rv;

    if (!$prop_value) {
        return "on";
    } elsif ($prop_value eq "explicit_on") {
        return "on";
    } elsif ($prop_value eq "explicit_off") {
        return "off";
    }

    return "off";
}

sub should_show_graphic_previews {
    my $u = shift;

    return $u->show_graphic_previews eq "on" ? 1 : 0;
}

# name: can_super_manage
# des: Given a target user and determines that the user is an supermaintainer of community
# returns: bool: true if supermaitainer, otherwise fail
# args: u
# des-u: user object or userid of community
sub can_super_manage {
    my $remote  = shift;
    my $u       = LJ::want_user(shift);

    return undef unless $remote && $u;

    # is same user?
    return 1 if LJ::u_equals($u, $remote);

    # do not allow suspended users manage other accounts
    return 0 if $remote->is_suspended;

    # people/syn/rename accounts can only be managed by the one account
    return undef if $u->{journaltype} =~ /^[PYR]$/;

    # check for supermaintainer access
    return 1 if LJ::check_rel($u, $remote, 'S');

    # not passed checks, return false
    return undef;
}

# name: can_moderate
# des: Given a target user and determines that the user is an moderator for the target user
# returns: bool: true if authorized, otherwise fail
# args: u
# des-u: user object or userid of target user
sub can_moderate {
    my $remote  = shift;
    my $u       = LJ::want_user(shift);

    return undef unless $remote && $u;

    # can moderate only community
    return undef unless $u->is_community;

    # do not allow suspended users manage other accounts
    return 0 if $remote->is_suspended;

    # people/syn/rename accounts can only be managed by the one account
    return undef if $u->{journaltype} =~ /^[PYR]$/;

    # check for moderate access
    return 1 if LJ::check_rel($u, $remote, 'M');

    # passed not checks, return false
    return undef;
}

# name: can_manage
# des: Given a target user and determines that the user is an admin for the taget  user
# returns: bool: true if authorized, otherwise fail
# args: u
# des-u: user object or userid of target user
sub can_manage {
    my $remote  = shift;
    my $u       = LJ::want_user(shift);

    return undef unless $remote && $u;

    # is same user?
    return 1 if LJ::u_equals($u, $remote);

    # people/syn/rename accounts can only be managed by the one account
    return undef if $u->{journaltype} =~ /^[PYR]$/;

    # do not allow suspended users manage other accounts
    return 0 if $remote->is_suspended;

    # check for supermaintainer
    return 1 if $remote->can_super_manage($u);

    # check for admin access
    return undef unless LJ::check_rel($u, $remote, 'A');

    # passed checks, return true
    return 1;
}

sub can_sweep {
    my $remote  = shift;
    my $u       = LJ::want_user(shift);

    return undef unless $remote && $u;

    # is same user?
    return 1 if LJ::u_equals($u, $remote);

    # do not allow suspended users to be watchers of other accounts.
    return 0 if $remote->is_suspended;

    # only personal journals can have watchers
    return undef unless $u->journaltype eq 'P';

    # check for admin access
    return undef unless LJ::check_rel($u, $remote, 'W');

    return 1;
}

sub hide_adult_content {
    my $u = shift;

    my $prop_value = $u->prop('hide_adult_content');

    if ($u->is_child || !$u->best_guess_age) {
        return "concepts";
    }

    if ($u->is_minor && $prop_value ne "concepts") {
        return "explicit";
    }

    return $prop_value ? $prop_value : "none";
}

# returns a number that represents the user's chosen search filtering level
# 0 = no filtering
# 1-10 = moderate filtering
# >10 = strict filtering
sub safe_search {
    my $u = shift;

    my $prop_value = $u->prop('safe_search');

    # current user 18+ default is 0
    # current user <18 default is 10
    # new user default (prop value is "nu_default") is 10
    return 0 if $prop_value eq "none";
    return $prop_value if $prop_value && $prop_value =~ /^\d+$/;
    return 0 if $prop_value ne "nu_default" && $u->best_guess_age && !$u->is_minor;
    return 10;
}

# determine if the user in "for_u" should see $u in a search result
sub should_show_in_search_results {
    my $u = shift;
    my %opts = @_;

    return 1 unless LJ::is_enabled("content_flag") && LJ::is_enabled("safe_search");

    my $adult_content = $u->adult_content_calculated;
    my $admin_flag = $u->admin_content_flag;

    my $for_u = $opts{for};
    unless (LJ::isu($for_u)) {
        return $adult_content ne "none" || $admin_flag ? 0 : 1;
    }

    my $safe_search = $for_u->safe_search;
    return 1 if $safe_search == 0;

    my $adult_content_flag_level = $LJ::CONTENT_FLAGS{$adult_content} ? $LJ::CONTENT_FLAGS{$adult_content}->{safe_search_level} : 0;
    my $admin_flag_level = $LJ::CONTENT_FLAGS{$admin_flag} ? $LJ::CONTENT_FLAGS{$admin_flag}->{safe_search_level} : 0;

    return 0 if $adult_content_flag_level && ($safe_search >= $adult_content_flag_level);
    return 0 if $admin_flag_level && ($safe_search >= $admin_flag_level);
    return 1;
}

sub equals {
    my ($u, $target) = @_;

    return LJ::u_equals($u, $target);
}

sub tags {
    my $u = shift;

    return LJ::Tags::get_usertags($u);
}

sub newpost_minsecurity {
    my $u = shift;

    my $val = $u->raw_prop('newpost_minsecurity') || 'public';

    $val = 'friends'
        if ($u->journaltype ne 'P' && $val eq 'private');

    return $val;
}

sub third_party_notify_list {
    my $u = shift;

    my $val = $u->prop('third_party_notify_list');
    my @services = split(',', $val);

    return @services;
}

# Check if the user's notify list contains a particular service
sub third_party_notify_list_contains {
    my $u = shift;
    my $val = shift;

    return 1 if grep { $_ eq $val } $u->third_party_notify_list;

    return 0;
}

# Add a service to a user's notify list
sub third_party_notify_list_add {
    my $u = shift;
    my $svc = shift;
    return 0 unless $svc;

    # Is it already there?
    return 1 if $u->third_party_notify_list_contains($svc);

    # Create the new list of services
    my @cur_services = $u->third_party_notify_list;
    push @cur_services, $svc;
    my $svc_list = join(',', @cur_services);

    # Trim a service from the list if it is too long
    if (length $svc_list > 255) {
        shift @cur_services;
        $svc_list = join(',', @cur_services)
    }

    # Set it
    $u->set_prop('third_party_notify_list', $svc_list);
    return 1;
}

# Remove a service to a user's notify list
sub third_party_notify_list_remove {
    my $u = shift;
    my $svc = shift;
    return 0 unless $svc;

    # Is it even there?
    return 1 unless $u->third_party_notify_list_contains($svc);

    # Remove it!
    $u->set_prop('third_party_notify_list',
                 join(',',
                      grep { $_ ne $svc } $u->third_party_notify_list
                      )
                 );
    return 1;
}

# can $u add existing tags to $targetu's entries?
sub can_add_tags_to {
    my ($u, $targetu) = @_;

    return LJ::Tags::can_add_tags($targetu, $u);
}

sub qct_value_for_ads {
    my $u = shift;

    return 0 unless LJ::is_enabled("content_flag");

    my $adult_content = $u->adult_content_calculated;
    my $admin_flag = $u->admin_content_flag;

    if ($LJ::CONTENT_FLAGS{$adult_content} && $LJ::CONTENT_FLAGS{$adult_content}->{qct_value_for_ads}) {
        return $LJ::CONTENT_FLAGS{$adult_content}->{qct_value_for_ads};
    }
    if ($LJ::CONTENT_FLAGS{$admin_flag} && $LJ::CONTENT_FLAGS{$admin_flag}->{qct_value_for_ads}) {
        return $LJ::CONTENT_FLAGS{$admin_flag}->{qct_value_for_ads};
    }

    return 0;
}

sub should_block_robots {
    my $u = shift;

    return 1 if $u->prop('opt_blockrobots');

    return 0 unless LJ::is_enabled("content_flag");

    my $adult_content = $u->adult_content_calculated;
    my $admin_flag = $u->admin_content_flag;

    return 1 if $LJ::CONTENT_FLAGS{$adult_content} && $LJ::CONTENT_FLAGS{$adult_content}->{block_robots};
    return 1 if $LJ::CONTENT_FLAGS{$admin_flag} && $LJ::CONTENT_FLAGS{$admin_flag}->{block_robots};
    return 0;
}

# memcache key that holds the number of times a user performed one of the rate-limited actions
sub rate_memkey {
    my ($u, $rp) = @_;

    return [$u->id, "rate:" . $u->id . ":$rp->{id}"];
}

sub opt_exclude_from_verticals {
    my $u = shift;

    my $prop_val = $u->prop('opt_exclude_from_verticals');

    return $prop_val if $prop_val =~ /^(?:entries)$/;
    return "none";
}

sub set_opt_exclude_from_verticals {
    my $u = shift;
    my $val = shift;

    # only set the "none" value if the prop is currently set to something (explicit off)
    my $prop_val = $val ? "entries" : undef;
    $prop_val = "none" if !$val && $u->prop('opt_exclude_from_verticals');

    $u->set_prop( opt_exclude_from_verticals => $prop_val );

    return;
}

# prepare OpenId part of html-page, if needed
sub openid_tags {
    my $u = shift;

    my $head = '';

    # OpenID Server and Yadis
    if (LJ::OpenID->server_enabled and defined $u) {
        my $journalbase = $u->journal_base;
        $head .= qq{<link rel="openid2.provider" href="$LJ::OPENID_SERVER" />\n};
        $head .= qq{<link rel="openid.server" href="$LJ::OPENID_SERVER" />\n};
        $head .= qq{<meta http-equiv="X-XRDS-Location" content="$journalbase/data/yadis" />\n};
    }

    return $head;
}

# return the number of comments a user has posted
sub num_comments_posted {
    my $u = shift;

    my $ret = $u->prop('talkleftct2');

    unless (defined $ret) {
        my $dbr = LJ::get_cluster_reader($u);
        $ret = $dbr->selectrow_array(qq{
            SELECT COUNT(*) FROM talkleft WHERE userid=?
        }, undef, $u->id);

        $u->set_prop('talkleftct2' => $ret);
    }

    return $ret;
}

# increase the number of comments a user has posted by 1
sub incr_num_comments_posted {
    my $u = shift;

    $u->set_prop('talkleftct2' => $u->num_comments_posted + 1);
}

# return the number of comments a user has received
sub num_comments_received {
    my $u = shift;
    my %opts = @_;

    my $userid = $u->id;
    my $memkey = [$userid, "talk2ct:$userid"];
    my $count = LJ::MemCache::get($memkey);
    unless ($count) {
        my $dbcr = $opts{dbh} || LJ::get_cluster_reader($u);
        my $expire = time() + 3600*24*2; # 2 days;
        $count = $dbcr->selectrow_array("SELECT COUNT(*) FROM talk2 ".
                                        "WHERE journalid=?", undef, $userid);
        LJ::MemCache::set($memkey, $count, $expire) if defined $count;
    }

    return $count;
}

# returns undef if there shouldn't be an option for this user
# B = show ads [B]oth to logged-out traffic on the user's journal and on the user's app pages
# J = show ads only to logged-out traffic on the user's [J]ournal
# A = show ads only on the user's [A]pp pages
sub ad_visibility {
    my $u = shift;

    return undef unless LJ::is_enabled("basic_ads") && LJ::run_hook("user_is_basic", $u);
    return 'J' unless LJ::is_enabled("basic_ad_options") && $u->is_personal;

    my $prop_val = $u->prop("ad_visibility");
    return $prop_val =~ /^[BJA]$/ ? $prop_val : 'B';
}

sub wants_ads_on_app {
    my $u = shift;

    my $ad_visibility = $u->ad_visibility;
    return $ad_visibility eq "B" || $ad_visibility eq "A" ? 1 : 0;
}

sub wants_ads_in_journal {
    my $u = shift;

    my $ad_visibility = $u->ad_visibility;
    return $ad_visibility eq "B" || $ad_visibility eq "J" ? 1 : 0;
}

# format unixtimestamp according to the user's timezone setting
sub format_time {
    my $u = shift;
    my $time = shift;

    return undef unless $time;

    return eval { DateTime->from_epoch(epoch=>$time, time_zone=>$u->prop("timezone"))->ymd('-') } ||
                  DateTime->from_epoch(epoch => $time)->ymd('-');
}

sub support_points_count {
    my $u = shift;

    my $dbr = LJ::get_db_reader();
    my $userid = $u->id;
    my $count;

    $count = $u->{_supportpointsum};
    return $count if defined $count;

    my $memkey = [$userid, "supportpointsum:$userid"];
    $count = LJ::MemCache::get($memkey);
    if (defined $count) {
        $u->{_supportpointsum} = $count;
        return $count;
    }

    $count = $dbr->selectrow_array("SELECT totpoints FROM supportpointsum WHERE userid=?", undef, $userid) || 0;
    $u->{_supportpointsum} = $count;
    LJ::MemCache::set($memkey, $count, 60*5);

    return $count;
}

sub can_be_nudged_by {
    my ($u, $nudger) = @_;

    return 0 unless LJ::is_enabled("nudge");
    return 0 if $u->equals($nudger);
    return 0 unless $u->is_personal;
    return 0 unless $u->is_visible;
    return 0 if $u->prop("opt_no_nudge");
    return 0 unless $u->is_mutual_friend($nudger);
    return 0 unless time() - $u->timeupdate >= 604800; # updated in the past week

    return 1;
}

sub should_show_schools_to {
    my ($u, $targetu) = @_;

    return 0 unless LJ::is_enabled("schools");
    return 1 if $u->prop('opt_showschools') eq '' || $u->prop('opt_showschools') eq 'Y';
    return 1 if $u->prop('opt_showschools') eq 'F' && $u->has_friend($targetu);

    return 0;
}

sub can_be_text_messaged_by {
    my ($u, $sender) = @_;

    return 0 unless $u->get_cap("textmessaging");

    my $tminfo = LJ::TextMessage->tm_info($u);

    ## messaging is disabled for some providers
    my $provider = $tminfo ? $tminfo->{provider} : '';
    return 0 if $provider eq 'beeline';
    return 0 if $provider eq 'megafon';

    ##
    my $security = $tminfo && $tminfo->{security} ? $tminfo->{security} : "none";
    return 0 if $security eq "none";
    return 1 if $security eq "all";

    if ($sender) {
        return 1 if $security eq "reg";
        return 1 if $security eq "friends" && $u->has_friend($sender);
    }

    return 0;
}

# <LJFUNC>
# name: LJ::User::rename_identity
# des: Change an identity user's 'identity', update DB,
#      clear memcache and log change.
# args: user
# returns: Success or failure.
# </LJFUNC>
sub rename_identity {
    my $u = shift;
    return 0 unless ($u && $u->is_identity && $u->is_expunged);

    my $id = $u->identity;
    return 0 unless $id;

    my $dbh = LJ::get_db_writer();

    # generate a new identity value that looks like ex_oldidvalue555
    my $tempid = sub {
        my $ident = shift;
        my $idtype = shift;
        my $temp = (length($ident) > 249) ? substr($ident, 0, 249) : $ident;
        my $exid;

        for (1..10) {
            $exid = "ex_$temp" . int(rand(999));

            # check to see if this identity already exists
            unless ($dbh->selectrow_array("SELECT COUNT(*) FROM identitymap WHERE identity=? AND idtype=? LIMIT 1", undef, $exid, $idtype)) {
                # name doesn't already exist, use this one
                last;
            }
            # name existed, try and get another

            if ($_ >= 10) {
                return 0;
            }
        }
        return $exid;
    };

    my $from = $id->value;
    my $to = $tempid->($id->value, $id->typeid);

    return 0 unless $to;

    $dbh->do("UPDATE identitymap SET identity=? WHERE identity=? AND idtype=?",
             undef, $to, $from, $id->typeid);

    LJ::memcache_kill($u, "userid");

    LJ::infohistory_add($u, 'identity', $from);

    return 1;
}

#<LJFUNC>
# name: LJ::User::get_renamed_user
# des: Get the actual user of a renamed user
# args: user
# returns: user
# </LJFUNC>
sub get_renamed_user {
    my $u = shift;
    my %opts = @_;
    my $hops = $opts{hops} || 5;

    # Traverse the renames to the final journal
    if ($u) {
        while ($u and $u->journaltype eq 'R' and $hops-- > 0) {
            my $rt = $u->prop("renamedto");
            last unless length $rt;
            if ($rt =~ /^https?:\/\//){
                if ( my $newu = LJ::User->new_from_url($rt) ) {
                    $u = $newu;
                } else {
                    warn $u->username . " links to non-existent user at $rt";
                    return $u;
                }
            } else {
                if ( my $newu = LJ::load_user($rt) ) {
                    $u = $newu;
                } else {
                    warn $u->username . " links to non-existent user at $rt";
                    return $u;
                }
            }
        }
    }

    return $u;
}

sub dismissed_page_notices {
    my $u = shift;

    my $val = $u->prop("dismissed_page_notices");
    my @notices = split(",", $val);

    return @notices;
}

sub has_dismissed_page_notice {
    my $u = shift;
    my $notice_string = shift;

    return 1 if grep { $_ eq $notice_string } $u->dismissed_page_notices;
    return 0;
}

# add a page notice to a user's dismissed page notices list
sub dismissed_page_notices_add {
    my $u = shift;
    my $notice_string = shift;
    return 0 unless $notice_string && $LJ::VALID_PAGE_NOTICES{$notice_string};

    # is it already there?
    return 1 if $u->has_dismissed_page_notice($notice_string);

    # create the new list of dismissed page notices
    my @cur_notices = $u->dismissed_page_notices;
    push @cur_notices, $notice_string;
    my $cur_notices_string = join(",", @cur_notices);

    # remove the oldest notice if the list is too long
    if (length $cur_notices_string > 255) {
        shift @cur_notices;
        $cur_notices_string = join(",", @cur_notices);
    }

    # set it
    $u->set_prop("dismissed_page_notices", $cur_notices_string);

    return 1;
}

# remove a page notice from a user's dismissed page notices list
sub dismissed_page_notices_remove {
    my $u = shift;
    my $notice_string = shift;
    return 0 unless $notice_string && $LJ::VALID_PAGE_NOTICES{$notice_string};

    # is it even there?
    return 0 unless $u->has_dismissed_page_notice($notice_string);

    # remove it
    $u->set_prop("dismissed_page_notices", join(",", grep { $_ ne $notice_string } $u->dismissed_page_notices));

    return 1;
}

sub custom_usericon {
    my ($u) = @_;

    my $url = $u->prop('custom_usericon') || '';
    if (
           $url =~ /userhead/
        && $url !~ /v=\d+/
        && (my ($uh_id) = $url =~ m/\/userhead\/(\d+)$/)
    ) {
        my $uh = LJ::UserHead->get_userhead ($uh_id);
        if ($uh) {
            my $uh_fs = LJ::FileStore->get_path_info ( path => "/userhead/".$uh->get_uh_id );
            $url .= "?v=".$uh_fs->{'change_time'} if $uh_fs->{'change_time'};
        }
    }
    $url =~ s#^http://files\.livejournal\.com#$LJ::FILEPREFIX#;
    return $url;
}

sub custom_usericon_appid {
    my ($u) = @_;
    return $u->prop('custom_usericon_appid') || 0;
}

sub set_custom_usericon {
    my ($u, $url, %opts) = @_;

    $u->set_prop( 'custom_usericon' => $url );

    if ($opts{application_id}) {
        $u->set_prop( 'custom_usericon_appid' => $opts{application_id});
    } else {
        $u->clear_prop( 'custom_usericon_appid' );
    }
}

sub _subscriptions_count {
    my ($u) = @_;

    my $set = LJ::Subscription::GroupSet->fetch_for_user($u, sub { 0 });

    return $set->{'active_count'};
}

sub subscriptions_count {
    my ($u) = @_;

    my $cached = LJ::MemCache::get('subscriptions_count:'.$u->id);
    return $cached if defined $cached;

    my $count = $u->_subscriptions_count;
    LJ::MemCache::set('subscriptions_count:'.$u->id, $count);
    return $count;
}

sub packed_props {
    my ($u) = @_;
    return $u->{'packed_props'};
}

sub set_packed_props {
    my ($u, $newprops) = @_;

    LJ::update_user($u, { 'packed_props' => $newprops });
    $u->{'packed_props'} = 1;
}

sub init_userprop_def {
    my ($class) = @_;

    # defaults for S1 style IDs in config file are magic: really
    # uniq strings representing style IDs, so on first use, we need
    # to map them
    unless ($LJ::CACHED_S1IDMAP) {
        my $pubsty = LJ::S1::get_public_styles();
        foreach (values %$pubsty) {
            my $k = "s1_$_->{'type'}_style";
            my $needval = "$_->{'type'}/$_->{'styledes'}";
            next unless $LJ::USERPROP_DEF{$k} eq $needval;

            $LJ::USERPROP_DEF{$k} = $_->{'styleid'};
        }

        $LJ::CACHED_S1IDMAP = 1;
    }
}

sub reset_cache {
    my $u = shift;

    my $dbcm = LJ::get_cluster_master($u);
    return 0 unless $dbcm;

    my @keys = qw(
        bio:*
        cctry_uid:*
        commsettings:*
        dayct:*
        fgrp:*
        friendofs:*
        friendofs2:*
        friends:*
        friends2:*
        ident:*
        inbox:newct:*
        intids:*
        invites:*
        jablastseen:*
        jabuser:*
        kws:*
        lastcomm:*
        linkobj:*
        log2ct:*
        log2lt:*
        logtag:*
        mcrate:*
        memct:*
        memkwcnt:*
        memkwid:*
        msn:mutual_friends_wlids:uid=*
        prtcfg:*
        pw:*
        rate:tracked:*
        rcntalk:*
        s1overr:*
        s1uc:*
        saui:*
        subscriptions_count:*
        supportpointsum:*
        synd:*
        tags2:*
        talk2ct:*
        talkleftct:*
        tc:*
        timeactive:*
        timezone_guess:*
        tu:*
        txtmsgsecurity:*
        uid2uniqs:*
        upiccom:*
        upicinf:*
        upicquota:*
        upicurl:*
        userid:*
    );

    foreach my $key (@keys) {
        $key =~ s/\*/$u->{userid}/g;
        LJ::MemCache::delete([ $u->{userid}, $key ]);
    }

    my $bio = $dbcm->selectrow_array('SELECT bio FROM userbio WHERE userid = ?', undef, $u->{userid});
    if ($bio =~ /\S/ && $u->{has_bio} ne 'Y') {
        LJ::update_user($u, { has_bio => 'Y' });
    }

    $u->do("UPDATE s1usercache SET override_stor = NULL WHERE userid = ?", undef, $u->{userid});

    my $dbh = LJ::get_db_writer();
    my $themeids = $dbh->selectcol_arrayref('SELECT moodthemeid FROM moodthemes WHERE ownerid = ?', undef, $u->{userid});
    if ($themeids && @$themeids) {
        foreach my $themeid (@$themeids) {
            LJ::MemCache::delete([ $themeid, "moodthemedata:$themeid" ]);
        }
    }

    my $picids = $dbcm->selectcol_arrayref('SELECT picid FROM userpic2 WHERE userid = ?', undef, $u->{userid});
    if ($picids && @$picids) {
        foreach my $picid (@$picids) {
            LJ::MemCache::delete([ $picid, "mogp.up.$picid" ]);
            LJ::MemCache::delete([ $picid, "mogp.up.$picid.alt" ]); # alt-zone (only zone at this time)
        }
    }

    my $s2ids = $dbh->selectcol_arrayref('SELECT styleid FROM s2styles WHERE userid = ?', undef, $u->{userid});
    if ($s2ids && @$s2ids) {
        foreach my $s2id (@$s2ids) {
            LJ::MemCache::delete([ $s2id, "s2s:$s2id" ]);
            LJ::MemCache::delete([ $s2id, "s2sl:$s2id" ]);
        }
    }

    my $s2lids = $dbcm->selectcol_arrayref('SELECT s2lid FROM s2stylelayers2 WHERE userid = ?', undef, $u->{userid});
    if ($s2lids) {
        # put it in a hash to remove duplicates so we don't purge one layer twice
        my %s2lids = ( map { $_ => 1 } grep { $_ } @$s2lids );
        if (keys %s2lids) {
            foreach my $s2lid (keys %s2lids) {
                LJ::MemCache::delete([ $s2lid, "s2lo:$s2lid" ]);
                LJ::MemCache::delete([ $s2lid, "s2c:$s2lid" ]);
            }
        }
    }

    return 1;
}

## Check for activity user at last N days
## args: days - how many days to check
## return:
##      1 - user logs in the last 'days' days
##      0 - user NOT logs in the last 'days' days
sub check_activity {
    my $u    = shift;
    my $days = shift;

    return 0 unless $days;

    my $sth = $u->prepare ("SELECT logintime FROM loginlog WHERE userid=? ORDER BY logintime DESC");
    $sth->execute ($u->userid);

    if (my @row = $sth->fetchrow_array) {
        my $logintime = $row[0];
        return 1 if time - $logintime < $days * 86400;
    }

    return 0;
}

sub is_spamprotection_enabled {
    my $u = shift;
    return 0 if $LJ::DISABLED{'spam_button'};
    my $spamprotection = $u->prop('spamprotection');
    return 1 if (!defined($spamprotection) || $spamprotection eq 'Y');
    return 0;
}

# return sticky entries existing
sub has_sticky_entry {
    my ($self) = @_;
    my $sticky_id  = $self->prop("sticky_entry_id");
    if ($sticky_id) {
        return 1;
    }
    return 0;
}

# returns sticky entry jitemid
sub get_sticky_entry_id {
    my ($self) = @_;
    return $self->prop("sticky_entry_id") || '';
}

# returns sticky entry jitemid
sub remove_sticky_entry_id {
    my ($self) = @_;
    my $ownerid = $self->userid;
    LJ::MemCache::delete([$ownerid, "log2lt:$ownerid"]);
    $self->clear_prop("sticky_entry_id");
}

# set sticky entry? 
sub set_sticky_id {
    my ($self, $itemid) = @_;
    die "itemid is not set" unless ($itemid);

    my $ownerid = $self->userid;
    LJ::MemCache::delete([$ownerid, "log2lt:$ownerid"]);
    $self->set_prop( sticky_entry_id => $itemid );
}

# set socical influence  information
sub set_social_influence {
    my ($self, $social_influence_infornation) = @_;

    # update user cached 'social_influence_info'
    $self->{'__social_influence_info'} = $social_influence_infornation;

    my $new_prop_value = LJ::JSON->to_json($social_influence_infornation) ;
    $self->set_prop( 'social_influence_info' => $new_prop_value);
}

# get socical influence  information
sub get_social_influence {
    my ($self) = @_;

    # Does user contains cache?
    if ( !$self->{'__social_influence_info'} ) {
        my $prop_value = $self->prop("social_influence_info");
        if (!$prop_value) {
            return {};
        }

        $self->{'__social_influence_info'} = LJ::JSON->from_json($prop_value);
    }
    return $self->{'__social_influence_info'};
}

sub push_subscriptions {
    my $u    = shift;
    my %opts = @_;

    $u->{push_subscriptions} = LJ::PushNotification::Storage->get_all($u)
        if !$u->{push_subscriptions} || $opts{flush};

    return keys %{$u->{push_subscriptions}};
}

sub push_subscription {
    my $u = shift;
    my $key = shift;
    return $u->{push_subscriptions}{$key} || {};
}


package LJ;

use Carp;

# <LJFUNC>
# name: LJ::get_authas_list
# des: Get a list of usernames a given user can authenticate as.
# returns: an array of usernames.
# args: u, opts?
# des-opts: Optional hashref.  keys are:
#           - type: 'P' to only return users of journaltype 'P'.
#                   'S' return users of Supermaintainer type instead Maintainer type.
#           - cap:  cap to filter users on.
# </LJFUNC>
sub get_authas_list {
    my ($u, $opts) = @_;

    return unless $u;

    # used to accept a user type, now accept an opts hash
    $opts = { 'type' => $opts } unless ref $opts;

    # Two valid types, Personal or Community
    $opts->{'type'} = undef unless $opts->{'type'} =~ m/^(P|C|S)$/;

    my $ids = LJ::load_rel_target($u, 'S') || [];
    if ($opts->{'type'} ne 'S') {
        my $a_ids = LJ::load_rel_target($u, 'A') || [];
        push @$ids, @$a_ids;
    }
    return $u->{'user'} unless $ids && @$ids;

    $opts->{'type'} = '' if $opts->{'type'} eq 'S';

    # load_userids_multiple
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);

    return map { $_->{'user'} }
               grep { ! $opts->{'cap'} || LJ::get_cap($_, $opts->{'cap'}) }
               grep { ! $opts->{'type'} || $opts->{'type'} eq $_->{'journaltype'} }

               # unless overridden, hide non-visible/non-read-only journals. always display the user's acct
               grep { $opts->{'showall'} || $_->is_visible || $_->is_readonly || LJ::u_equals($_, $u) }

               # can't work as an expunged account
               grep { $_ && !$_->is_expunged && $_->{clusterid} > 0 }
               $u,  sort { $a->{'user'} cmp $b->{'user'} } values %users;
}

# <LJFUNC>
# name: LJ::get_postto_list
# des: Get the list of usernames a given user can post to.
# returns: an array of usernames
# args: u, opts?
# des-opts: Optional hashref.  keys are:
#           - type: 'P' to only return users of journaltype 'P'.
#           - cap:  cap to filter users on.
# </LJFUNC>
sub get_postto_list {
    my ($u, $opts) = @_;

    # used to accept a user type, now accept an opts hash
    $opts = { 'type' => $opts } unless ref $opts;

    # only one valid type right now
    $opts->{'type'} = 'P' if $opts->{'type'};

    my $ids = LJ::load_rel_target($u, 'P');
    return undef unless $ids;

    # load_userids_multiple
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);

    return $u->{'user'}, sort map { $_->{'user'} }
                         grep { ! $opts->{'cap'} || LJ::get_cap($_, $opts->{'cap'}) }
                         grep { ! $opts->{'type'} || $opts->{'type'} eq $_->{'journaltype'} }
                         grep { $_->clusterid > 0 }
                         grep { $_->is_visible }
                         values %users;
}

# <LJFUNC>
# name: LJ::trusted
# des: Checks to see if the remote user can use javascript in S2 layers.
# returns: boolean; 1 if remote user can use javascript
# args: userid
# des-userid: id of user to check
# </LJFUNC>
sub trusted {
    my ($userid) = @_;

    my $u = LJ::load_userid($userid);
    return 0 unless $u;

    return $u->prop('javascript');
}

# <LJFUNC>
# name: LJ::can_view
# des: Checks to see if the remote user can view a given journal entry.
#      <b>Note:</b> This is meant for use on single entries at a time,
#      not for calling many times on every entry in a journal.
# returns: boolean; 1 if remote user can see item
# args: remote, item
# des-item: Hashref from the 'log' table.
# </LJFUNC>
sub can_view
{
    &nodb;
    my $remote = shift;
    my $item = shift;

    # public is okay
    return 1 if $item->{'security'} eq "public";

    # must be logged in otherwise
    return 0 unless $remote;

    my $userid = int($item->{'ownerid'} || $item->{'journalid'});
    my $u = LJ::load_userid($userid);
    my $journal_name = $u ? $u->user : '';
    my $remoteid = int($remote->{'userid'});

    # owners can always see their own.
    return 1 if ($userid == $remoteid);

    # author in community can always see their post
    return 1 if $remoteid == $item->{'posterid'} and not $LJ::JOURNALS_WITH_PROTECTED_CONTENT{ $journal_name };;

    # other people can't read private
    return 0 if ($item->{'security'} eq "private");

    # should be 'usemask' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless ($item->{'security'} eq "usemask");

    # if it's usemask, we have to refuse non-personal journals,
    # so we have to load the user
    return 0 unless $remote->{'journaltype'} eq 'P' || $remote->{'journaltype'} eq 'I';

    # TAG:FR:ljlib:can_view  (turn off bit 0 for just watching?  hmm.)
    my $gmask = LJ::get_groupmask($userid, $remoteid);
    my $allowed = (int($gmask) & int($item->{'allowmask'}));
    return $allowed ? 1 : 0;  # no need to return matching mask
}

# <LJFUNC>
# name: LJ::wipe_major_memcache
# des: invalidate all major memcache items associated with a given user.
# args: u
# returns: nothing
# </LJFUNC>
sub wipe_major_memcache
{
    my $u = shift;
    my $userid = LJ::want_userid($u);
    foreach my $key ("userid","bio","talk2ct","log2ct",
                     "log2lt","memkwid","dayct2","s1overr","s1uc","fgrp",
                     "friends","friendofs","tu","upicinf","upiccom",
                     "upicurl", "intids", "memct", "lastcomm")
    {
        LJ::memcache_kill($userid, $key);
    }
}

# <LJFUNC>
# name: LJ::load_user_props
# des: Given a user hashref, loads the values of the given named properties
#      into that user hashref.
# args: dbarg?, u, opts?, propname*
# des-opts: hashref of opts.  set key 'cache' to use memcache.
# des-propname: the name of a property from the [dbtable[userproplist]] table.
# </LJFUNC>
sub load_user_props {
    &nodb;

    my $u = shift;
    return unless isu($u);
    return if $u->is_expunged;

    my $opts = ref $_[0] ? shift : {};
    my (@props) = @_;

    my $extend_user_object = sub {
        my ($propmap) = @_;

        foreach my $propname ( keys %$propmap ) {
            $u->{$propname} = $propmap->{$propname};
        }
    };

    unless ( $opts->{'reload'} ) {
        @props = grep { ! exists $u->{$_} } @props;
    }

    return unless @props;

    my $groups = LJ::User::PropStorage->get_handler_multi(\@props);
    my $memcache_available = @LJ::MEMCACHE_SERVERS;
    my $use_master = $memcache_available || $opts->{'use_master'};

    my $memc_expire = time() + 3600 * 24;

    foreach my $handler (keys %$groups) {
        # if there is no memcache, or if the handler doesn't wish to use
        # memcache, hit the storage directly, update the user object,
        # and get straight to the next handler
        if ( !$memcache_available || !defined $handler->use_memcache )
        {
            my $propmap
                = $handler->get_props( $u, $groups->{$handler},
                                       { 'use_master' => $use_master } );

            $extend_user_object->($propmap);

            next;
        }

        # now let's find out what we're going to do with memcache
        my $memcache_policy = $handler->use_memcache;

        if ( $memcache_policy eq 'lite' ) {
            # the handler loads everything from the corresponding
            # table and uses only one memcache key to cache that

            my $memkey = $handler->memcache_key($u);
            if ( my $packed = LJ::MemCache::get([ $u->userid, $memkey ]) ) {
                my $propmap
                    = LJ::User::PropStorage->unpack_from_memcache($packed);

                $extend_user_object->($propmap);

                # we've loaded everything handled by this handler,
                # let's get to the next one
                next;
            }

            # actually load everything from DB, cache it, and update
            # the user object
            my $propmap
                = $handler->get_props( $u, [],
                                       { 'use_master' => $use_master } );

            my $packed = LJ::User::PropStorage->pack_for_memcache($propmap);
            LJ::MemCache::set( [$u->userid, $memkey],
                               $packed, $memc_expire );

            $extend_user_object->($propmap);
        } elsif ( $memcache_policy eq 'blob' ) {
            # the handler uses one memcache key for each prop
            # hit memcache for them first, then hit db and update
            # memcache

            my $handled_props = $groups->{$handler};

            my $propmap_memc
                = $handler->fetch_props_memcache( $u, $handled_props );

            $extend_user_object->($propmap_memc);

            my @load_from_db = grep { !exists $propmap_memc->{$_} }
                               @$handled_props;

            # if we can avoid hitting the db, avoid it
            next unless @load_from_db;

            my $propmap_db
                = $handler->get_props( $u, \@load_from_db,
                                       { 'use_master' => $use_master } );

            $extend_user_object->($propmap_db);

            # now, update memcache
            $handler->store_props_memcache( $u, $propmap_db );
        }
    }

    LJ::User->init_userprop_def;
    foreach my $propname (@props) {
        next if defined $u->{$propname};
        next unless defined $LJ::USERPROP_DEF{$propname};
        $u->{$propname} = $LJ::USERPROP_DEF{$propname};
    }
}

sub load_user_props_multi {
    my ($class, $users, $props, $opts) = @_;
    my $use_master = $opts->{'use_master'};

    $props = [grep { defined and not ref } @$props];
    return unless @$props;

    $users = { map { $_->{'userid'} => $_ } grep { $_->{'statusvis'} ne 'X' and $_->{'clusterid'} } grep { ref } @$users };
    return unless %$users;

    my $groups = LJ::User::PropStorage->get_handler_multi(\@$props);
    my $memcache_available = @LJ::MEMCACHE_SERVERS;
    my $use_master = $memcache_available || $use_master;
    my $memc_expire = time() + 3600 * 24;

    foreach my $handler (keys %$groups) {
        my %propkeys = map { $_ => '' } @{ $groups->{$handler} };

        # if there is no memcache, or if the handler doesn't wish to use
        # memcache, hit the storage directly, update the user object,
        # and get straight to the next handler
        if ( not $memcache_available or not defined $handler->use_memcache ) {
            foreach my $u (values %$users) {
                my $propmap = {
                    %propkeys,
                    %{  $handler->get_props($u, $groups->{$handler},
                            {
                                use_master => $use_master
                            }
                        ) || {}
                    },
                };

                _extend_user_object->($u, $propmap);
            }

            next;
        }

        # now let's find out what we're going to do with memcache
        my $memcache_policy = $handler->use_memcache;

        if ( $memcache_policy eq 'lite' ) {
            my %memkeys;
            my $propmaps = LJ::MemCache::get_multi(map {
                [
                    ($_ => ($memkeys{$_} = $handler->memcache_key($users->{$_})))
                ]
            } keys %$users);

            my ($userid, $v);
            my $rmemkeys = { map { $memkeys{$_} => $_ } keys %memkeys };

            while (($userid, $v) = each %$propmaps) {
                next unless $v;
                $userid = $rmemkeys->{$userid};

                delete $memkeys{$userid}; # Loading is successfull

                # Hack to init keys for empty props
                my $packed = { 
                    %propkeys,
                    %{ LJ::User::PropStorage->unpack_from_memcache($v) },
                };

                _extend_user_object($users->{$userid}, $packed);
            }

            while (($userid, $v) = each %memkeys) {
                my $propmap = $handler->get_props(
                    $users->{$userid}, [],
                    { 'use_master' => $use_master }
                );

                my $packed = LJ::User::PropStorage->pack_for_memcache($propmap);
                LJ::MemCache::set([$userid, $v], $packed, $memc_expire);

                $packed = {
                    %$propmap,
                    %$packed,
                };

                _extend_user_object($users->{$userid}, $packed);
            }
        } elsif ( $memcache_policy eq 'blob' ) {
            my $handled_props = $groups->{$handler};

            foreach my $u (values %$users) {
                my $propmap_memc = {
                    %propkeys,
                    %{ $handler->fetch_props_memcache($u, $handled_props) },
                };

                _extend_user_object($u, $propmap_memc);

                my @load_from_db = grep { !exists $propmap_memc->{$_} }
                                   @$handled_props;

                # if we can avoid hitting the db, avoid it
                next unless @load_from_db;

                my $propmap_db = $handler->get_props(
                    $u, \@load_from_db,
                    { 'use_master' => $use_master }
                );

                _extend_user_object($u, $propmap_db);

                # now, update memcache
                $handler->store_props_memcache( $u, $propmap_db );
            }
        }
    }
}

sub _extend_user_object {
    my ($u, $propmap) = @_;
    return unless ref $u;
    return unless ref $propmap eq 'HASH';
    my ($k, $v);

    $u->{$k} = $v while ($k, $v) = each %$propmap;
}


# <LJFUNC>
# name: LJ::load_userids
# des: Simple interface to [func[LJ::load_userids_multiple]].
# args: userids
# returns: hashref with keys ids, values $u refs.
# </LJFUNC>
sub load_userids
{
    my %u;
    LJ::load_userids_multiple([ map { $_ => \$u{$_} } @_ ]);
    return \%u;
}

# <LJFUNC>
# name: LJ::load_userids_multiple
# des: Loads a number of users at once, efficiently.
# info: loads a few users at once, their userids given in the keys of $map
#       listref (not hashref: can't have dups).  values of $map listref are
#       scalar refs to put result in.  $have is an optional listref of user
#       object caller already has, but is too lazy to sort by themselves.
#       <strong>Note</strong>: The $have parameter is deprecated,
#       as is $memcache_only; but it is still preserved for now. 
#       Really, this whole API (i.e. LJ::load_userids_multiple) is clumsy. 
#       Use [func[LJ::load_userids]] instead.
# args: dbarg?, map, have, memcache_only?
# des-map: Arrayref of pairs (userid, destination scalarref).
# des-have: Arrayref of user objects caller already has.
# des-memcache_only: Flag to only retrieve data from memcache.
# returns: Nothing.
# </LJFUNC>
sub load_userids_multiple
{
    &nodb;
    # the $have parameter is deprecated, as is $memcache_only, but it's still preserved for now.
    # actually this whole API is crap.  use LJ::load_userids() instead.
    my ($map, undef, $memcache_only) = @_;

    my $sth;
    my @have;
    my %need;
    while (@$map) {
        my $id = shift @$map;
        my $ref = shift @$map;
        next unless int($id);
        push @{$need{$id}}, $ref;

        if ($LJ::REQ_CACHE_USER_ID{$id}) {
            push @have, $LJ::REQ_CACHE_USER_ID{$id};
        }
    }

    my $satisfy = sub {
        my $u = shift;
        return unless ref $u eq "LJ::User";

        # this could change the $u returned to an
        # existing one we already have loaded in memory,
        # once it's been upgraded.  then everybody points
        # to the same one.
        $u = _set_u_req_cache($u);

        foreach (@{$need{$u->{'userid'}}}) {
            # check if existing target is defined and not what we already have.
            if (my $eu = $$_) {
                LJ::assert_is($u->{userid}, $eu->{userid});
            }
            $$_ = $u;
        }

        delete $need{$u->{'userid'}};
    };

    unless ($LJ::_PRAGMA_FORCE_MASTER) {
        foreach my $u (@have) {
            $satisfy->($u);
        }

        if (%need) {
            foreach (LJ::memcache_get_u(map { [$_,"userid:$_"] } keys %need)) {
                $satisfy->($_);
            }
        }
    }

    if (%need && ! $memcache_only) {
        my $db = @LJ::MEMCACHE_SERVERS || $LJ::_PRAGMA_FORCE_MASTER ?
            LJ::get_db_writer() : LJ::get_db_reader();

        _load_user_raw($db, "userid", [ keys %need ], sub {
            my $u = shift;
            LJ::memcache_set_u($u);
            $satisfy->($u);
        });
    }
}

# des-db:  $dbh/$dbr
# des-key:  either "userid" or "user"  (the WHERE part)
# des-vals: value or arrayref of values for key to match on
# des-hook: optional code ref to run for each $u
# returns: last $u found
sub _load_user_raw
{
    my ($db, $key, $vals, $hook) = @_;
    $hook ||= sub {};
    $vals = [ $vals ] unless ref $vals eq "ARRAY";

    my $use_isam;
    unless ($LJ::CACHE_NO_ISAM{user} || scalar(@$vals) > 10) {
        eval { $db->do("HANDLER user OPEN"); };
        if ($@ || $db->err) {
            $LJ::CACHE_NO_ISAM{user} = 1;
        } else {
            $use_isam = 1;
        }
    }

    my $last;

    if ($use_isam) {
        $key = "PRIMARY" if $key eq "userid";
        foreach my $v (@$vals) {
            my $sth = $db->prepare("HANDLER user READ `$key` = (?) LIMIT 1");
            $sth->execute($v);
            my $row = $sth->fetchrow_hashref;
            if ($row) {
                my $u = LJ::User->new_from_row($row);
                $hook->($u);
                $last = $u;
            }
        }
        $db->do("HANDLER user close");
    } else {
        my $in = join(", ", map { $db->quote($_) } @$vals);
        my $sth = $db->prepare("SELECT * FROM user WHERE $key IN ($in)");
        $sth->execute;
        while (my $row = $sth->fetchrow_hashref) {
            my $u = LJ::User->new_from_row($row);
            $hook->($u);
            $last = $u;
        }
    }

    return $last;
}

sub _set_u_req_cache {
    my $u = shift or die "no u to set";

    # if we have an existing user singleton, upgrade it with
    # the latested data, but keep using its address
    if (my $eu = $LJ::REQ_CACHE_USER_ID{$u->{'userid'}}) {
        LJ::assert_is($eu->{userid}, $u->{userid});

        $eu->{$_} = $u->{$_} foreach keys %$u;
        $u = $eu;
    }
    $LJ::REQ_CACHE_USER_NAME{$u->{'user'}} = $u;
    $LJ::REQ_CACHE_USER_ID{$u->{'userid'}} = $u;
    return $u;
}

sub load_user_or_identity {
    my $arg = shift;

    my $user = LJ::canonical_username($arg);
    return LJ::load_user($user) if $user;

    # return undef if not dot in arg (can't be a URL)
    return undef unless $arg =~ /\./;

    my $dbh = LJ::get_db_writer();
    my $url = lc($arg);
    $url = "http://$url" unless $url =~ m!^http://!;
    $url .= "/" unless $url =~ m!/$!;
    my $uid = $dbh->selectrow_array("SELECT userid FROM identitymap WHERE idtype=? AND identity=?",
                                    undef, 'O', $url);
    return LJ::load_userid($uid) if $uid;
    return undef;
}

# load either a username, or a "I,<userid>" parameter.
sub load_user_arg {
    my ($arg) = @_;
    my $user = LJ::canonical_username($arg);
    return LJ::load_user($user) if length $user;
    if ($arg =~ /^I,(\d+)$/) {
        my $u = LJ::load_userid($1);
        return $u if $u->is_identity;
    }
    return; # undef/()
}

# <LJFUNC>
# name: LJ::load_user
# des: Loads a user record, from the [dbtable[user]] table, given a username.
# args: dbarg?, user, force?
# des-user: Username of user to load.
# des-force: if set to true, won't return cached user object and will
#            query a dbh.
# returns: Hashref, with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_user
{
    &nodb;
    my ($user, $force) = @_;

    $user = LJ::canonical_username($user);
    return undef unless length $user;
    
    my $get_user = sub {
        my $use_dbh = shift;
        my $db = $use_dbh ? LJ::get_db_writer() : LJ::get_db_reader();
        my $u = _load_user_raw($db, "user", $user)
            or return undef;

        # set caches since we got a u from the master
        LJ::memcache_set_u($u) if $use_dbh;

        return _set_u_req_cache($u);
    };

    # caller is forcing a master, return now
    return $get_user->("master") if $force || $LJ::_PRAGMA_FORCE_MASTER;
    
    my $u;
 
    # return process cache if we have one
    if ($u = $LJ::REQ_CACHE_USER_NAME{$user}) {
        return $u;
    }

    # check memcache
    {
        my $uid = LJ::MemCache::get("uidof:$user");
        $u = LJ::memcache_get_u([$uid, "userid:$uid"]) if $uid;
        return _set_u_req_cache($u) if $u;
    }

    # try to load from master if using memcache, otherwise from slave
    $u = $get_user->(scalar @LJ::MEMCACHE_SERVERS);
    return $u if $u;

    # setup LDAP handler if this is the first time
    if ($LJ::LDAP_HOST && ! $LJ::AUTH_EXISTS) {
        require LJ::LDAP;
        $LJ::AUTH_EXISTS = sub {
            my $user = shift;
            my $rec = LJ::LDAP::load_ldap_user($user);
            return $rec ? $rec : undef;
        };
    }

    # if user doesn't exist in the LJ database, it's possible we're using
    # an external authentication source and we should create the account
    # implicitly.
    my $lu;
    if (ref $LJ::AUTH_EXISTS eq "CODE" && ($lu = $LJ::AUTH_EXISTS->($user)))
    {
        my $name = ref $lu eq "HASH" ? ($lu->{'nick'} || $lu->{name} || $user) : $user;
        if (LJ::create_account({
            'user' => $user,
            'name' => $name,
            'email' => ref $lu eq "HASH" ? $lu->email_raw : "",
            'password' => "",
        }))
        {
            # this should pull from the master, since it was _just_ created
            return $get_user->("master");
        }
    }

    return undef;
}

sub load_users {
    my @users = @_;
    
    my %need = map {$_ => 1} @users;

    ## skip loaded
    my %loaded;
    foreach my $user (@users){
        if (my $u = $LJ::REQ_CACHE_USER_NAME{$user}) {
            $loaded{$u->userid} = $u;
            delete $need{$u->userid};
        }
    }

    ## username to userid
    my $uids = LJ::MemCache::get_multi( map {"uidof:$_"} keys %need );
    my $us = LJ::load_userids( values %$uids );
    while (my ($k, $v) = each %loaded){
        $us->{$k} = $v;
    }
    return $us;
}

# <LJFUNC>
# name: LJ::u_equals
# des: Compares two user objects to see if they are the same user.
# args: userobj1, userobj2
# des-userobj1: First user to compare.
# des-userobj2: Second user to compare.
# returns: Boolean, true if userobj1 and userobj2 are defined and have equal userids.
# </LJFUNC>
sub u_equals {
    my ($u1, $u2) = @_;
    return $u1 && $u2 && $u1->{'userid'} == $u2->{'userid'};
}

# <LJFUNC>
# name: LJ::load_userid
# des: Loads a user record, from the [dbtable[user]] table, given a userid.
# args: dbarg?, userid, force?
# des-userid: Userid of user to load.
# des-force: if set to true, won't return cached user object and will
#            query a dbh
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_userid
{
    &nodb;
    my ($userid, $force) = @_;
    return undef unless $userid;

    my $get_user = sub {
        my $use_dbh = shift;
        my $db = $use_dbh ? LJ::get_db_writer() : LJ::get_db_reader();
        my $u = _load_user_raw($db, "userid", $userid)
            or return undef;

        LJ::memcache_set_u($u) if $use_dbh;
        return _set_u_req_cache($u);
    };

    # user is forcing master, return now
    return $get_user->("master") if $force || $LJ::_PRAGMA_FORCE_MASTER;

    my $u;

    # check process cache
    $u = $LJ::REQ_CACHE_USER_ID{$userid};
    if ($u) {
        return $u;
    }

    # check memcache
    $u = LJ::memcache_get_u([$userid,"userid:$userid"]);
    return _set_u_req_cache($u) if $u;

    # get from master if using memcache
    return $get_user->("master") if @LJ::MEMCACHE_SERVERS;

    # check slave
    $u = $get_user->();
    return $u if $u;

    # if we didn't get a u from the reader, fall back to master
    return $get_user->("master");
}

sub memcache_get_u
{
    my @keys = @_;
    my @ret;
    my $users = LJ::MemCache::get_multi(@keys) || {};
    while (my ($key, $ar) = each %$users) {
        my $row = LJ::MemCache::array_to_hash("user", $ar, $key)
            or next;
        my $u = LJ::User->new_from_row($row);
        push @ret, $u;
    }
    return wantarray ? @ret : $ret[0];
}

sub memcache_set_u
{
    my $u = shift;
    return unless $u;
    my $expire = time() + 1800;
    my $ar = LJ::MemCache::hash_to_array("user", $u);
    return unless $ar;
    LJ::MemCache::set([$u->{'userid'}, "userid:$u->{'userid'}"], $ar, $expire);
    LJ::MemCache::set("uidof:$u->{user}", $u->{userid});
}

# <LJFUNC>
# name: LJ::get_bio
# des: gets a user bio, from DB or memcache.
# args: u, force
# des-force: true to get data from cluster master.
# returns: string
# </LJFUNC>
sub get_bio {
    my ($u, $force) = @_;
    return unless $u && $u->{'has_bio'} eq "Y";

    my $bio;

    my $memkey = [$u->{'userid'}, "bio:$u->{'userid'}"];
    unless ($force) {
        my $bio = LJ::MemCache::get($memkey);
        return $bio if defined $bio;
    }

    # not in memcache, fall back to disk
    my $db = @LJ::MEMCACHE_SERVERS || $force ?
      LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
    $bio = $db->selectrow_array("SELECT bio FROM userbio WHERE userid=?",
                                undef, $u->{'userid'});

    # set in memcache
    LJ::MemCache::add($memkey, $bio);

    return $bio;
}

# <LJFUNC>
# name: LJ::journal_base
# des: Returns URL of a user's journal.
# info: The tricky thing is that users with underscores in their usernames
#       can't have some_user.example.com as a hostname, so that's changed into
#       some-user.example.com.
# args: uuser, vhost?
# des-uuser: LJ::User object, user hashref or username of user whose URL to make.
# des-vhost: What type of URL.  Acceptable options: "users", to make a
#            http://user.example.com/ URL; "tilde" for http://example.com/~user/;
#            "community" for http://example.com/community/user; or the default
#            will be http://example.com/users/user.  If unspecified and uuser
#            is a user hashref, then the best/preferred vhost will be chosen.
# returns: scalar; a URL.
# </LJFUNC>
sub journal_base
{
    my ($user, $vhost) = @_;

    return unless $user;
    
    if (LJ::are_hooks("journal_base")) {
        ## We must pass a real LJ::User object into hook
        if (isu($user)) {
            ## $user is either LJ::User object or plain hash with 'userid' field
            if (!UNIVERSAL::isa($user, "LJ::User")) {
                $user = LJ::load_userid($user->{userid});
            }
        } else {
            ## $user is plain username
            $user = LJ::load_user($user);
        }

        my $hookurl = LJ::run_hook("journal_base", $user, $vhost);
        return $hookurl if $hookurl;
    }

    if (isu($user)) {
        my $u = $user;
        $user = $u->{'user'};
        unless (defined $vhost) {
            if ($LJ::FRONTPAGE_JOURNAL eq $user) {
                $vhost = "front";
            } elsif ($u->{'journaltype'} eq "P") {
                $vhost = "";
            }

        }
    }

    if ($vhost eq "users") {
        my $he_user = $user;
        $he_user =~ s/_/-/g;
        return "http://$he_user.$LJ::USER_DOMAIN";
    } elsif ($vhost eq "tilde") {
        return "$LJ::SITEROOT/~$user";
    } elsif ($vhost eq "community") {
        return "$LJ::SITEROOT/community/$user";
    } elsif ($vhost eq "front") {
        return $LJ::SITEROOT;
    } elsif ($vhost =~ /^other:(.+)/) {
        return "http://$1";
    } else {
        return "$LJ::SITEROOT/users/$user";
    }
}


# <LJFUNC>
# name: LJ::load_user_privs
# class:
# des: loads all of the given privs for a given user into a hashref, inside
#      the user record.  See also [func[LJ::check_priv]].
# args: u, priv, arg?
# des-priv: Priv names to load (see [dbtable[priv_list]]).
# des-arg: Optional argument.  See also [func[LJ::check_priv]].
# returns: boolean
# </LJFUNC>
sub load_user_privs
{
    &nodb;
    my $remote = shift;
    my @privs = @_;
    return unless $remote and @privs;

    # return if we've already loaded these privs for this user.
    @privs = grep { ! $remote->{'_privloaded'}->{$_} } @privs;
    return unless @privs;

    my $dbr = LJ::get_db_reader();
    return unless $dbr;
    foreach (@privs) { $remote->{'_privloaded'}->{$_}++; }
    @privs = map { $dbr->quote($_) } @privs;
    my $sth = $dbr->prepare("SELECT pl.privcode, pm.arg ".
                            "FROM priv_map pm, priv_list pl ".
                            "WHERE pm.prlid=pl.prlid AND ".
                            "pl.privcode IN (" . join(',',@privs) . ") ".
                            "AND pm.userid=$remote->{'userid'}");
    $sth->execute;
    while (my ($priv, $arg) = $sth->fetchrow_array) {
        unless (defined $arg) { $arg = ""; }  # NULL -> ""
        $remote->{'_priv'}->{$priv}->{$arg} = 1;
    }
}

# <LJFUNC>
# name: LJ::check_priv
# des: Check to see if a user has a certain privilege.
# info: Usually this is used to check the privs of a $remote user.
#       See [func[LJ::get_remote]].  As such, a $u argument of undef
#       is okay to pass: 0 will be returned, as an unknown user can't
#       have any rights.
# args: dbarg?, u, priv, arg?
# des-priv: Priv name to check for (see [dbtable[priv_list]])
# des-arg: Optional argument.  If defined, function only returns true
#          when $remote has a priv of type $priv also with arg $arg, not
#          just any priv of type $priv, which is the behavior without
#          an $arg. Arg can be "*", for all args.
# returns: boolean; true if user has privilege
# </LJFUNC>
sub check_priv
{
    &nodb;
    my ($u, $priv, $arg) = @_;
    return 0 unless $u;

    LJ::load_user_privs($u, $priv)
        unless $u->{'_privloaded'}->{$priv};

    # no access if they don't have the priv
    return 0 unless defined $u->{'_priv'}->{$priv};

    # at this point we know they have the priv
    return 1 unless defined $arg;

    # check if they have the right arguments
    return 1 if defined $u->{'_priv'}->{$priv}->{$arg};
    return 1 if defined $u->{'_priv'}->{$priv}->{"*"};

    # don't have the right argument
    return 0;
}

#
#
# <LJFUNC>
# name: LJ::users_by_priv
# class:
# des: Return users with a certain privilege.
# args: priv, arg?
# des-args: user privilege to searching. arg can be "*" for all args.
# return: Userids or empty list.
# TODO Add store to MemCache
sub users_by_priv {
    my ($priv, $arg) = @_;
    
    my $dbr = LJ::get_db_reader();
    return unless $dbr;

    return unless $priv;
    $arg ||= '*';
    my $users = $dbr->selectcol_arrayref ("SELECT userid FROM priv_list pl, priv_map pm
                                           WHERE pl.prlid = pm.prlid 
                                                AND privcode = ?
                                                AND arg = ?
                                        ", undef, $priv, $arg);

    return unless ref $users eq 'ARRAY';
    return $users;
}

#
#
# <LJFUNC>
# name: LJ::remote_has_priv
# class:
# des: Check to see if the given remote user has a certain privilege.
# info: <strong>Deprecated</strong>.  You should
#       use [func[LJ::load_user_privs]] + [func[LJ::check_priv]], instead.
# args:
# des-:
# returns:
# </LJFUNC>
sub remote_has_priv
{
    &nodb;
    my $remote = shift;
    my $privcode = shift;     # required.  priv code to check for.
    my $ref = shift;  # optional, arrayref or hashref to populate
    return 0 unless ($remote);

    ### authentication done.  time to authorize...

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT pm.arg FROM priv_map pm, priv_list pl WHERE pm.prlid=pl.prlid AND pl.privcode=? AND pm.userid=?");
    $sth->execute($privcode, $remote->{'userid'});

    my $match = 0;
    if (ref $ref eq "ARRAY") { @$ref = (); }
    if (ref $ref eq "HASH") { %$ref = (); }
    while (my ($arg) = $sth->fetchrow_array) {
        $match++;
        if (ref $ref eq "ARRAY") { push @$ref, $arg; }
        if (ref $ref eq "HASH") { $ref->{$arg} = 1; }
    }
    return $match;
}

# $dom: 'L' == log, 'T' == talk, 'M' == modlog, 'S' == session,
#       'R' == memory (remembrance), 'K' == keyword id,
#       'P' == phone post, 'C' == pending comment
#       'O' == pOrtal box id, 'V' == 'vgift', 'E' == ESN subscription id
#       'Q' == Notification Inbox, 'G' == 'SMS messaGe'
#       'D' == 'moDule embed contents', 'W' == 'Wish-list element'
#       'F' == Photo ID, 'A' == Album ID, 'Y' == delaYed entries
#       'I' == Fotki migration log ID
#
# FIXME: both phonepost and vgift are ljcom.  need hooks. but then also
#        need a separate namespace.  perhaps a separate function/table?
sub alloc_user_counter
{
    my ($u, $dom, $opts) = @_;
    $opts ||= {};

    ##################################################################
    # IF YOU UPDATE THIS MAKE SURE YOU ADD INITIALIZATION CODE BELOW #
    return undef unless $dom =~ /^[LTMPSRKCOVEQGDWFAYI]$/;             #
    ##################################################################

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $newmax;
    my $uid = $u->{'userid'}+0;
    return undef unless $uid;
    my $memkey = [$uid, "auc:$uid:$dom"];

    # in a master-master DB cluster we need to be careful that in
    # an automatic failover case where one cluster is slightly behind
    # that the same counter ID isn't handed out twice.  use memcache
    # as a sanity check to record/check latest number handed out.
    my $memmax = int(LJ::MemCache::get($memkey) || 0);

    my $rs = $dbh->do("UPDATE usercounter SET max=LAST_INSERT_ID(GREATEST(max,$memmax)+1) ".
                      "WHERE journalid=? AND area=?", undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");

        # if we've got a supplied callback, lets check the counter
        # number for consistency.  If it fails our test, wipe
        # the counter row and start over, initializing a new one.
        # callbacks should return true to signal 'all is well.'
        if ($opts->{callback} && ref $opts->{callback} eq 'CODE') {
            my $rv = 0;
            eval { $rv = $opts->{callback}->($u, $newmax) };
            if ($@ or ! $rv) {
                $dbh->do("DELETE FROM usercounter WHERE " .
                         "journalid=? AND area=?", undef, $uid, $dom);
                return LJ::alloc_user_counter($u, $dom);
            }
        }

        LJ::MemCache::set($memkey, $newmax);
        return $newmax;
    }

    if ($opts->{recurse}) {
        # We shouldn't ever get here if all is right with the world.
        return undef;
    }

    my $qry_map = {
        # for entries:
        'log'         => "SELECT MAX(jitemid) FROM log2     WHERE journalid=?",
        'logtext'     => "SELECT MAX(jitemid) FROM logtext2 WHERE journalid=?",
        'talk_nodeid' => "SELECT MAX(nodeid)  FROM talk2    WHERE nodetype='L' AND journalid=?",
        # for comments:
        'talk'     => "SELECT MAX(jtalkid) FROM talk2     WHERE journalid=?",
        'talktext' => "SELECT MAX(jtalkid) FROM talktext2 WHERE journalid=?",
    };

    my $consider = sub {
        my @tables = @_;
        foreach my $t (@tables) {
            my $res = $u->selectrow_array($qry_map->{$t}, undef, $uid);
            $newmax = $res if $res > $newmax;
        }
    };

    # Make sure the counter table is populated for this uid/dom.
    if ($dom eq "L") {
        # back in the ol' days IDs were reused (because of MyISAM)
        # so now we're extra careful not to reuse a number that has
        # foreign junk "attached".  turns out people like to delete
        # each entry by hand, but we do lazy deletes that are often
        # too lazy and a user can see old stuff come back alive
        $consider->("log", "logtext", "talk_nodeid");
    } elsif ($dom eq "T") {
        # just paranoia, not as bad as above.  don't think we've ever
        # run into cases of talktext without a talk, but who knows.
        # can't hurt.
        $consider->("talk", "talktext");
    } elsif ($dom eq "M") {
        $newmax = $u->selectrow_array("SELECT MAX(modid) FROM modlog WHERE journalid=?",
                                      undef, $uid);
    } elsif ($dom eq "S") {
        $newmax = $u->selectrow_array("SELECT MAX(sessid) FROM sessions WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "R") {
        $newmax = $u->selectrow_array("SELECT MAX(memid) FROM memorable2 WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "K") {
        $newmax = $u->selectrow_array("SELECT MAX(kwid) FROM userkeywords WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "P") {
        my $userblobmax = $u->selectrow_array("SELECT MAX(blobid) FROM userblob WHERE journalid=? AND domain=?",
                                              undef, $uid, LJ::get_blob_domainid("phonepost"));
        my $ppemax = $u->selectrow_array("SELECT MAX(blobid) FROM phonepostentry WHERE userid=?",
                                         undef, $uid);
        $newmax = ($ppemax > $userblobmax) ? $ppemax : $userblobmax;
    } elsif ($dom eq "C") {
        $newmax = $u->selectrow_array("SELECT MAX(pendcid) FROM pendcomments WHERE jid=?",
                                      undef, $uid);
    } elsif ($dom eq "O") {
        $newmax = $u->selectrow_array("SELECT MAX(pboxid) FROM portal_config WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "V") {
        $newmax = $u->selectrow_array("SELECT MAX(giftid) FROM vgifts WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "E") {
        $newmax = $u->selectrow_array("SELECT MAX(subid) FROM subs WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "Q") {
        $newmax = $u->selectrow_array("SELECT MAX(qid) FROM notifyqueue WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "G") {
        $newmax = $u->selectrow_array("SELECT MAX(msgid) FROM sms_msg WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "D") {
        $newmax = $u->selectrow_array("SELECT MAX(moduleid) FROM embedcontent WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "W") {
        $newmax = $u->selectrow_array("SELECT MAX(wishid) FROM wishlist2 WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "F") {
        $newmax = $u->selectrow_array("SELECT MAX(photo_id) FROM fotki_photos WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "A") {
        $newmax = $u->selectrow_array("SELECT MAX(album_id) FROM fotki_albums WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "Y") {
        $newmax = $u->selectrow_array("SELECT MAX(delayedid) FROM delayedlog2 WHERE journalid=?",
                                      undef, $uid);
    } elsif ( $dom eq 'I' ) {
        $newmax = $u->selectrow_array("SELECT MAX(logid) FROM fotki_migration_log WHERE userid=?",
                                      undef, $uid);
    } else {
        die "No user counter initializer defined for area '$dom'.\n";
    }
    $newmax += 0;
    $dbh->do("INSERT IGNORE INTO usercounter (journalid, area, max) VALUES (?,?,?)",
             undef, $uid, $dom, $newmax) or return undef;

    # The 2nd invocation of the alloc_user_counter sub should do the
    # intended incrementing.
    return LJ::alloc_user_counter($u, $dom, { recurse => 1 });
}

# <LJFUNC>
# name: LJ::make_user_active
# des:  Record user activity per cluster, on [dbtable[clustertrack2]], to
#       make per-activity cluster stats easier.
# args: userid, type
# des-userid: source userobj ref
# des-type: currently unused
# </LJFUNC>
sub mark_user_active {
    my ($u, $type) = @_;  # not currently using type
    return 0 unless $u;   # do not auto-vivify $u
    my $uid = $u->{userid};
    return 0 unless $uid && $u->{clusterid};

    # Update the clustertrack2 table, but not if we've done it for this
    # user in the last hour.  if no memcache servers are configured
    # we don't do the optimization and just always log the activity info
    if (@LJ::MEMCACHE_SERVERS == 0 ||
        LJ::MemCache::add("rate:tracked:$uid", 1, 3600)) {

        return 0 unless $u->writer;
        $u->do("REPLACE INTO clustertrack2 SET ".
               "userid=?, timeactive=?, clusterid=?", undef,
               $uid, time(), $u->{clusterid}) or return 0;
    }
    return 1;
}

# <LJFUNC>
# name: LJ::infohistory_add
# des: Add a line of text to the [[dbtable[infohistory]] table for an account.
# args: uuid, what, value, other?
# des-uuid: User id or user object to insert infohistory for.
# des-what: What type of history is being inserted (15 chars max).
# des-value: Value for the item (255 chars max).
# des-other: Optional. Extra information / notes (30 chars max).
# returns: 1 on success, 0 on error.
# </LJFUNC>
sub infohistory_add {
    my ($uuid, $what, $value, $other) = @_;
    $uuid = LJ::want_userid($uuid);
    return unless $uuid && $what && $value;

    # get writer and insert
    my $dbh = LJ::get_db_writer();
    my $gmt_now = LJ::TimeUtil->mysql_time(time(), 1);
    $dbh->do("INSERT INTO infohistory (userid, what, timechange, oldvalue, other) VALUES (?, ?, ?, ?, ?)",
             undef, $uuid, $what, $gmt_now, $value, $other);
    return $dbh->err ? 0 : 1;
}

# <LJFUNC>
# name: LJ::get_shared_journals
# des: Gets an array of shared journals a user has access to.
# returns: An array of shared journals.
# args: u
# </LJFUNC>
sub get_shared_journals
{
    my $u = shift;
    my $ids = LJ::load_rel_target($u, 'A') || [];

    # have to get usernames;
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);
    return sort map { $_->{'user'} } values %users;
}

## my $text = LJ::ljuser_alias($u)
## returns note text (former 'alias') for current remote user
sub ljuser_alias {
    my $user = shift;

    return if $LJ::DISABLED{'aliases'};

    my $remote = LJ::get_remote();
    return unless $remote;
    return unless $remote->get_cap('aliases');

    my $u = LJ::load_user($user);
    return unless $u;
   
    if (!$remote->{_aliases}) {
        my $prop_aliases = LJ::text_uncompress( $remote->prop('aliases') );
        $remote->{_aliases} = ($prop_aliases) ? LJ::JSON->from_json($prop_aliases) : {};
    }
    return $remote->{_aliases}->{ $u->{userid} };
}

##
## LJ::set_alias($u, $text, \$error)
## LJ::set_alias([ $u1, $text1, $u2, $text2], \$error);
##
## Sets notes (alias) text for user $u to the current $remote user
## $u is either user object or userid (number)
## If aliases cannot be updated, undef value is returned and optional \$error reference is set
## Use empty text for deleting alias
##
sub set_alias {
    my $list = (ref $_[0] eq 'ARRAY') ? shift : [shift, shift];
    my $err = shift;
    
    if ($LJ::DISABLED{'aliases'}) {
        $$err = "Notes (aliases) are disabled" if $err;
        return;
    }

    my $remote = LJ::get_remote();
    unless ($remote) {
        $$err = "No remote user" if $err;
        return;
    }
    unless ($remote->get_cap('aliases')) {
        $$err = "Remote user can't manage notes (aliases)" if $err;
        return;
    }

    ## load alias data
    if (!$remote->{_aliases}) {
        my $prop_aliases = LJ::text_uncompress( $remote->prop('aliases') );
        $remote->{_aliases} = $prop_aliases ? LJ::JSON->from_json($prop_aliases) : {};
    }
    
    ## modify (edit, add or delete)
    for (my $i = 0; $i < @$list / 2; ++$i) {
        my $userid = $list->[$i * 2];
        my $alias  = $list->[$i * 2 + 1];
        $alias = substr($alias, 0, 400);
        $userid = $userid->{userid} if ref $userid;
        die "Numeric id is expected, not $userid" unless $userid =~ /^\d+$/;
        
        if ($alias) {
            $remote->{_aliases}->{$userid} = $alias;
        } else {
            delete $remote->{_aliases}->{$userid};
        }
    }
    
    ## save data back
    my $serialized_text = LJ::JSON->to_json($remote->{_aliases});
    $serialized_text = LJ::text_compress( $serialized_text ) unless $LJ::DISABLED{'aliases_compress'};
    if (length $serialized_text < 65536) {
        return $remote->set_prop( aliases => $serialized_text );
    } else {
        delete $remote->{_aliases}; ## drop unsuccessfully modified data
        $$err = BML::ml('widget.addalias.too.long') if $err;
        return 0;
    }
}

## my %all_aliases = LJ::get_all_aliases();
## Returns all aliases for current remote user as hash userid => alias
sub get_all_aliases {

    return if $LJ::DISABLED{'aliases'};

    my $remote = LJ::get_remote();
    return unless $remote and $remote->get_cap('aliases');

    if (!$remote->{_aliases}) {
        my $prop_aliases = LJ::text_uncompress($remote->prop('aliases'));
        $remote->{_aliases} = ($prop_aliases) ? LJ::JSON->from_json($prop_aliases) : {};
    }

    return %{$remote->{_aliases}};
}

# <LJFUNC>
# class: component
# name: LJ::ljuser
# des: Make link to userinfo/journal of user.
# info: Returns the HTML for a userinfo/journal link pair for a given user
#       name, just like LJUSER does in BML.  This is for files like cleanhtml.pl
#       and ljpoll.pl which need this functionality too, but they aren't run as BML.
# args: user, opts?
# des-user: Username to link to, or user hashref.
# des-opts: Optional hashref to control output.  Key 'full' when true causes
#           a link to the mode=full userinfo.   Key 'type' when 'C' makes
#           a community link, when 'Y' makes a syndicated account link,
#           when 'I' makes an identity account link (e.g. OpenID),
#           when 'N' makes a news account link, otherwise makes a user account
#           link. If user parameter is a hashref, its 'journaltype' overrides
#           this 'type'.  Key 'del', when true, makes a tag for a deleted user.
#           If user parameter is a hashref, its 'statusvis' overrides 'del'.
#           Key 'no_follow', when true, disables traversal of renamed users.
# returns: HTML with a little head image & bold text link.
# </LJFUNC>
sub ljuser {
    my ($user, $opts) = @_;

    my ($u, $username);
    if (isu($user)) {
        $u = $user;
        $username = $u->username;
    } else {
        $u = LJ::load_user($user);
        $username = $user;
    }

    my ( @span_classes,
         @span_styles,
         $profile_url,
         @profile_link_tag_extra,
         $userhead,
         $userhead_w,
         $userhead_h,
         $journal_url,
         @link_tag_extra,
         $journal_name,
         @link_extra,
         @extra,
         $journal,
    );

    $profile_url = $opts->{'profile_url'};

    # if invalid user, link to dummy userinfo page
    if (!$u || !LJ::isu($u)) {
        $username = LJ::canonical_username($username);
        $journal_url = "$LJ::SITEROOT/userinfo.bml?user=$username";
        $profile_url ||= $journal_url;
        $userhead = 'userinfo.gif';
        $userhead_w = 16;
    } else {
        # Traverse the renames to the final journal
        if (!$opts->{'no_follow'}) {
            $u = $u->get_renamed_user;
            $username = $u->username;
        }

        if (!$profile_url) {
            $profile_url = $u->profile_url;
            $profile_url .= '?mode=full' if $opts->{'full'};
        }

        # Mark accounts as deleted that aren't visible, memorial, locked, or
        # read-only
        if ($u->statusvis !~ /[VMLO]/) {
            push @span_styles, 'text-decoration:line-through';
        }

        $journal_name = $username;

        $journal_url = $u->journal_base . "/";
        ($userhead, $userhead_w, $userhead_h) = $u->userhead($opts);
        if ($u->is_identity) {
            my $params = $u->identity->ljuser_display_params($u, $opts);
            $profile_url  = $params->{'profile_url'}  || $profile_url;
            $journal_url  = $params->{'journal_url'}  || $journal_url;
            $journal_name = $params->{'journal_name'} || $journal_name;
        }
    }

    my $user_alias       = LJ::ljuser_alias($username);
    my $side_alias       = $opts->{'side_alias'};
    my $show_alias_popup = $user_alias && !$side_alias;
    my $target           = $opts->{'target'};
    my $link_color       = $opts->{'link_color'};

    # verify that it's indeed a color:
    if ($link_color !~ /^#([a-fA-F0-9]{3}|[a-fA-F0-9]{6})$/) {
        $link_color = '';
    }

    ### populate @span_classes
    unshift @span_classes, 'ljuser';
    if ($show_alias_popup)   { push @span_classes, 'with-alias'; }
    if ($opts->{side_alias}) { push @span_classes, 'with-alias-value'; }

    # add class as "ljuser-name_*username*" for find user on page to
    # change alias
    push @span_classes, 'ljuser-name_' . LJ::canonical_username($user);
    my $span_classes = join(' ', @span_classes);

    ### populate @span_styles
    unshift @span_styles, 'white-space:nowrap';
    my $span_styles = join(';', @span_styles);

    ### populate @profile_link_tag_extra
    if ($target) { push @profile_link_tag_extra, " target=\"$target\""; }
    my $profile_link_tag_extra = join('', @profile_link_tag_extra);

    ### populate userhead data
    if ($userhead !~ /^https?:\/\//) {
        my $imgroot = $opts->{'imgroot'} || $LJ::IMGPREFIX;
        $userhead = $imgroot . '/' . $userhead . "?v=$LJ::CURRENT_VERSION";
    }

    $userhead_h ||= $userhead_w;  # make square if only one dimension given

    ### populate @link_tag_extra
    if ($link_color) { push @link_tag_extra, " style=\"color:$link_color\""; }
    if ($target)     { push @link_tag_extra, " target=\"$target\""; }
    if ($show_alias_popup) {
        push @link_tag_extra, " title=\"" . LJ::ehtml($user_alias) . "\"";
    }
    my $link_tag_extra = join('', @link_tag_extra);

    ### fix $journal_name
    if ($opts->{'title'}) {
        $journal_name = $opts->{'title'};
    }
    if (!exists $opts->{'bold'} || $opts->{'bold'} != 0) {
        $journal_name = "<b>$journal_name</b>";
    }

    ### populate @link_extra
    if ($show_alias_popup) {
        push @link_extra, "<span class='useralias-value'>*</span>";
    }
    my $link_extra = join('', @link_extra);

    ### populate @extra
    if ($user_alias and $side_alias) {
        push @extra, "<span class='alias-value'> &mdash; " .
                     LJ::ehtml($user_alias) . "</span>";
    }
    my $extra = join('', @extra);

    if ( exists $opts->{in_journal} && $opts->{in_journal} ) {
        my $cu = LJ::load_user( $opts->{in_journal} );
        $journal = $cu ? ' data-journal="' . $cu->journal_base . '"' : '';
    }

    return
        "<span class='$span_classes' lj:user='$username'$journal style='$span_styles'>" .
        "<a href='$profile_url'$profile_link_tag_extra>" .
        "<img src='$userhead' alt='[info]' " .
            "width='$userhead_w' height='$userhead_h' " .
            "style='vertical-align: bottom; border: 0; padding-right: 1px;'" .
        "/>" .
        "</a>" .
        "<a href='$journal_url'$link_tag_extra>" .
        $journal_name . $link_extra .
        "</a>" .
        "</span>" .
        $extra;
}

sub set_email {
    my ($userid, $email) = @_;

    my $dbh = LJ::get_db_writer();
    if ($LJ::DEBUG{'write_emails_to_user_table'}) {
        $dbh->do("UPDATE user SET email=? WHERE userid=?", undef,
                 $email, $userid);
    }
    $dbh->do("REPLACE INTO email (userid, email) VALUES (?, ?)",
             undef, $userid, $email);

    # update caches
    LJ::memcache_kill($userid, "userid");
    LJ::MemCache::delete([$userid, "email:$userid"]);
    my $cache = $LJ::REQ_CACHE_USER_ID{$userid} or return;
    $cache->{'_email'} = $email;
}

sub get_uids {
    my @friends_names = @_;
    my @ret;
    push @ret, grep { $_ } map { LJ::load_user($_) } @friends_names;
    return @ret;
}

sub set_password {
    my ($userid, $password) = @_;

    my $dbh = LJ::get_db_writer();
    if ($LJ::DEBUG{'write_passwords_to_user_table'}) {
        $dbh->do("UPDATE user SET password=? WHERE userid=?", undef,
                 $password, $userid);
    }
    $dbh->do("REPLACE INTO password (userid, password) VALUES (?, ?)",
             undef, $userid, $password);

    # update caches
    LJ::memcache_kill($userid, "userid");
    LJ::MemCache::delete([$userid, "pw:$userid"]);
    my $cache = $LJ::REQ_CACHE_USER_ID{$userid} or return;
    $cache->{'_password'} = $password;
}

sub update_user
{
    my ($arg, $ref) = @_;
    my @uid;

    if (ref $arg eq "ARRAY") {
        @uid = @$arg;
    } else {
        @uid = want_userid($arg);
    }
    @uid = grep { $_ } map { $_ + 0 } @uid;
    return 0 unless @uid;

    my @sets;
    my @bindparams;
    my $used_raw = 0;
    while (my ($k, $v) = each %$ref) {
        if ($k eq "raw") {
            $used_raw = 1;
            push @sets, $v;
        } elsif ($k eq 'email') {
            set_email($_, $v) foreach @uid;
        } elsif ($k eq 'password') {
            set_password($_, $v) foreach @uid;
        } else {
            push @sets, "$k=?";
            push @bindparams, $v;
        }
    }
    return 1 unless @sets;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;
    {
        local $" = ",";
        my $where = @uid == 1 ? "userid=$uid[0]" : "userid IN (@uid)";
        $dbh->do("UPDATE user SET @sets WHERE $where", undef,
                 @bindparams);
        return 0 if $dbh->err;
    }
    if (@LJ::MEMCACHE_SERVERS) {
        LJ::memcache_kill($_, "userid") foreach @uid;
    }

    if ($used_raw) {
        # for a load of userids from the master after update
        # so we pick up the values set via the 'raw' option
        require_master(sub { LJ::load_userids(@uid) });
    } else {
        foreach my $uid (@uid) {
            while (my ($k, $v) = each %$ref) {
                my $cache = $LJ::REQ_CACHE_USER_ID{$uid} or next;
                $cache->{$k} = $v;
            }
        }
    }

    # log this updates
    LJ::run_hooks("update_user", userid => $_, fields => $ref)
        for @uid;

    return 1;
}

# <LJFUNC>
# name: LJ::get_timezone
# des: Gets the timezone offset for the user.
# args: u, offsetref, fakedref
# des-u: user object.
# des-offsetref: reference to scalar to hold timezone offset;
# des-fakedref: reference to scalar to hold whether this timezone was
#               faked.  0 if it is the timezone specified by the user.
# returns: nonzero if successful.
# </LJFUNC>
sub get_timezone {
    my ($u, $offsetref, $fakedref) = @_;

    # See if the user specified their timezone
    if (my $tz = $u->prop('timezone')) {
        # If the eval fails, we'll fall through to guessing instead
        my $dt = eval {
            DateTime->from_epoch(
                                 epoch => time(),
                                 time_zone => $tz,
                                 );
        };

        if ($dt) {
            $$offsetref = $dt->offset() / (60 * 60); # Convert from seconds to hours
            $$fakedref  = 0 if $fakedref;

            return 1;
        }
    }

    # Either the user hasn't set a timezone or we failed at
    # loading it.  We guess their current timezone's offset
    # by comparing the gmtime of their last post with the time
    # they specified on that post.

    # first, check request cache
    my $timezone = $u->{_timezone_guess};
    if ($timezone) {
        $$offsetref = $timezone;
        return 1;
    }

    # next, check memcache
    my $memkey = [$u->userid, 'timezone_guess:' . $u->userid];
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $u->{_timezone_guess} = $memcache_data;
        $$offsetref = $memcache_data;
        return 1;
    }

    # nothing in cache; check db
    my $dbcr = LJ::get_cluster_def_reader($u);
    return 0 unless $dbcr;

    $$fakedref = 1 if $fakedref;

    # grab the times on the last post that wasn't backdated.
    # (backdated is rlogtime == $LJ::EndOfTime)
    if (my $last_row = $dbcr->selectrow_hashref(
        qq{
            SELECT rlogtime, eventtime
            FROM log2
            WHERE journalid = ? AND rlogtime <> ?
            ORDER BY rlogtime LIMIT 1
        }, undef, $u->{userid}, $LJ::EndOfTime)) {
        my $logtime = $LJ::EndOfTime - $last_row->{'rlogtime'};
        my $eventtime = LJ::TimeUtil->mysqldate_to_time($last_row->{'eventtime'}, 1);
        my $hourdiff = ($eventtime - $logtime) / 3600;

        # if they're up to a quarter hour behind, round up.
        $hourdiff = $hourdiff > 0 ? int($hourdiff + 0.25) : int($hourdiff - 0.25);

        # if the offset is more than 24h in either direction, then the last
        # entry is probably unreliable. don't use any offset at all.
        $$offsetref = (-24 < $hourdiff && $hourdiff < 24) ? $hourdiff : 0;

        # set the caches
        $u->{_timezone_guess} = $$offsetref;
        my $expire = 60*60*24; # 24 hours
        LJ::MemCache::set($memkey, $$offsetref, $expire);
    }

    return 1;
}

# returns undef on error, or otherwise arrayref of arrayrefs,
# each of format [ year, month, day, count ] for all days with
# non-zero count.  examples:
#  [ [ 2003, 6, 5, 3 ], [ 2003, 6, 8, 4 ], ... ]
#
sub get_daycounts
{
    my ($u, $remote) = @_;
    my $uid = LJ::want_userid($u) or return undef;

    my $memkind = 'p'; # public only, changed below
    my $secwhere = "AND security='public'";
    my $viewall = 0;
    if ($remote) {
        # do they have the viewall priv?
        my %getargs = eval { LJ::Request->args } || (); # eval for check web context
        if (defined $getargs{'viewall'} and $getargs{'viewall'} eq '1' and LJ::check_priv($remote, 'canview', '*')) {
            $viewall = 1;
            LJ::statushistory_add($u->{'userid'}, $remote->{'userid'},
                "viewall", "calendar");
        }

        if ($remote->{'userid'} == $uid || $viewall) {
            $secwhere = "";   # see everything
            $memkind = 'a'; # all
        } elsif ($remote->{'journaltype'} eq 'P') {
            my $gmask = LJ::get_groupmask($u, $remote);
            if ($gmask) {
                $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))";
                $memkind = 'g' . $gmask; # friends case: allowmask == gmask == 1
            }
        }
    }

    ##
    ## the first element of array, that is stored in memcache, 
    ## is the time of the creation of the list. The memcache is 
    ## invalid if there are new entries in journal since that time.
    ##
    my $memkey = [$uid, "dayct2:$uid:$memkind"];
    my $list = LJ::MemCache::get($memkey);
    if ($list) {
        my $list_create_time = shift @$list;
        return $list if $list_create_time >= $u->timeupdate;
    }

    my $dbcr = LJ::get_cluster_def_reader($u) or return;
    
    ## get lock to prevent multiple apache processes to execute the sql below.
    ## one process runs, the other wait for results 
    my $release_lock = sub { $dbcr->selectrow_array("SELECT RELEASE_LOCK('$memkey')"); };
    my $locked = $dbcr->selectrow_array("SELECT GET_LOCK('$memkey',10)");
    return unless $locked; ## 10 seconds expired

    $list = LJ::MemCache::get($memkey);
    if ($list) {
        ## other process may have filled the data while we waited for the lock
        my $list_create_time = shift @$list;
        if ($list_create_time >= $u->timeupdate) {
            $release_lock->();
            return $list;
        }
    }

    my $sth = $dbcr->prepare("SELECT year, month, day, COUNT(*) ".
                             "FROM log2 WHERE journalid=? $secwhere GROUP BY 1, 2, 3");
    $sth->execute($uid);
    my @days;
    while (my ($y, $m, $d, $c) = $sth->fetchrow_array) {
        # we force each number from string scalars (from DBI) to int scalars,
        # so they store smaller in memcache
        push @days, [ int($y), int($m), int($d), int($c) ];
    }

    LJ::MemCache::set($memkey, [time, @days]);

    $release_lock->();
    return \@days;
}

## input: $u, $remote, $year, $month
## output: hashref with data for rendering calendar for given month,
##      days:       arrayref [ count of entries for each day]
##                  days[1] = count of entries for the 1st day, days[0] is always null
##      prev_month: arrayref [year, month] - previous month that has entries
##      next_month, prev_year, next_year - arrayref of the same format
##
sub get_calendar_data_for_month {
    my ($u, $remote, $year, $month) = @_;

    $remote ||= LJ::get_remote();
    unless ($year || $month) {
        ($month, $year) = (localtime)[4, 5];
        $year += 1900;
        $month++;
    }

    my %ret = (journal => $u->user, year => $year, month => $month);
    my $days = LJ::get_daycounts($u, $remote);
    foreach my $d (@$days) {
        ## @$d = ($y, $m, $d, $count)
        if ($d->[0]==$year && $d->[1]==$month) {
            $ret{days}->[ $d->[2] ] = $d->[3]+0;
        }
    }
    ## $prev_month  = max(  grep { $day < Date($year, $month) }  @$days  );
    ## max @list    = List::Util::reduce {  ($a < $b) ? $b : $a } @list
    ## min @list    = List::Util::reduce { !($a < $b) ? $b : $a } @list
    my $current_month   = [$year, $month];
    my $less_year       = sub { my ($a, $b) = @_; return $a->[0]<$b->[0];  };
    my $less            = sub { my ($a, $b) = @_; return $a->[0]<$b->[0] || $a->[0]==$b->[0] && $a->[1]<$b->[1] };
    $ret{'prev_month'}  = List::Util::reduce {  $less->($a, $b) ? $b : $a } grep { $less->($_, $current_month) }        @$days;
    $ret{'next_month'}  = List::Util::reduce { !$less->($a, $b) ? $b : $a } grep { $less->($current_month, $_) }        @$days;
    $ret{'prev_year'}   = List::Util::reduce {  $less->($a, $b) ? $b : $a } grep { $less_year->($_, $current_month) }   @$days;
    $ret{'next_year'}   = List::Util::reduce { !$less->($a, $b) ? $b : $a } grep { $less_year->($current_month, $_) }   @$days;
    foreach my $k (qw/prev_month next_month prev_year next_year/) {
        if ($ret{$k}) {
            $ret{$k} = [ $ret{$k}->[0]+0, $ret{$k}->[1]+0];
        }
    }
 
    return \%ret;
}


# <LJFUNC>
# name: LJ::set_interests
# des: Change a user's interests.
# args: dbarg?, u, old, new
# des-old: hashref of old interests (hashing being interest => intid)
# des-new: listref of new interests
# returns: 1 on success, undef on failure
# </LJFUNC>
sub set_interests
{
    my ($u, $old, $new) = @_;

    $u = LJ::want_user($u);
    my $userid = $u->{'userid'};
    return undef unless $userid;

    return undef unless ref $old eq 'HASH';
    return undef unless ref $new eq 'ARRAY';

    my $dbh = LJ::get_db_writer();
    my %int_new = ();
    my %int_del = %$old;  # assume deleting everything, unless in @$new

    # user interests go in a different table than user interests,
    # though the schemas are the same so we can run the same queries on them
    my $uitable = $u->{'journaltype'} eq 'C' ? 'comminterests' : 'userinterests';

    # track if we made changes to refresh memcache later.
    my $did_mod = 0;

    my @valid_ints = LJ::validate_interest_list(@$new);
    foreach my $int (@valid_ints)
    {
        $int_new{$int} = 1 unless $old->{$int};
        delete $int_del{$int};
    }

    ### were interests removed?
    if (%int_del)
    {
        ## easy, we know their IDs, so delete them en masse
        my $intid_in = join(", ", values %int_del);
        $dbh->do("DELETE FROM $uitable WHERE userid=$userid AND intid IN ($intid_in)");
        $dbh->do("UPDATE interests SET intcount=intcount-1 WHERE intid IN ($intid_in) AND intcount > 0");
        $did_mod = 1;
    }

    ### do we have new interests to add?
    my @new_intids = ();  ## existing IDs we'll add for this user
    if (%int_new)
    {
        $did_mod = 1;

        ## difficult, have to find intids of interests, and create new ints for interests
        ## that nobody has ever entered before
        my $int_in = join(", ", map { $dbh->quote($_); } keys %int_new);
        my %int_exist;

        ## find existing IDs
        my $sth = $dbh->prepare("SELECT interest, intid FROM interests WHERE interest IN ($int_in)");
        $sth->execute;
        while (my ($intr, $intid) = $sth->fetchrow_array) {
            push @new_intids, $intid;       # - we'll add this later.
            delete $int_new{$intr};         # - so we don't have to make a new intid for
                                            #   this next pass.
        }

        if (@new_intids) {
            my $sql = "";
            foreach my $newid (@new_intids) {
                if ($sql) { $sql .= ", "; }
                else { $sql = "REPLACE INTO $uitable (userid, intid) VALUES "; }
                $sql .= "($userid, $newid)";
            }
            $dbh->do($sql);

            my $intid_in = join(", ", @new_intids);
            $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid IN ($intid_in)");
        }
    }

    ### do we STILL have interests to add?  (must make new intids)
    if (%int_new)
    {
        foreach my $int (keys %int_new)
        {
            my $intid;
            my $qint = $dbh->quote($int);

            $dbh->do("INSERT INTO interests (intid, intcount, interest) ".
                     "VALUES (NULL, 1, $qint)");
            if ($dbh->err) {
                # somebody beat us to creating it.  find its id.
                $intid = $dbh->selectrow_array("SELECT intid FROM interests WHERE interest=$qint");
                $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid=$intid");
            } else {
                # newly created
                $intid = $dbh->{'mysql_insertid'};
            }
            if ($intid) {
                ## now we can actually insert it into the userinterests table:
                $dbh->do("INSERT INTO $uitable (userid, intid) ".
                         "VALUES ($userid, $intid)");
                push @new_intids, $intid;
            }
        }
    }
    LJ::run_hooks("set_interests", $u, \%int_del, \@new_intids); # interest => intid

    # do migrations to clean up userinterests vs comminterests conflicts
    $u->lazy_interests_cleanup;

    LJ::memcache_kill($u, "intids") if $did_mod;
    $u->{_cache_interests} = undef if $did_mod;

    return 1;
}

sub validate_interest_list {
    my $interrors = ref $_[0] eq "ARRAY" ? shift : [];
    my @ints = @_;

    my @valid_ints = ();
    foreach my $int (@ints) {
        $int = lc($int);       # FIXME: use utf8?
        $int =~ s/^i like //;  # *sigh*
        next unless $int;

        # Specific interest failures
        my ($bytes,$chars) = LJ::text_length($int);
        my @words = split(/\s+/, $int);
        my $word_ct = scalar @words;

        my $error_string = '';
        if ($int =~ /[\<\>]/) {
            $int = LJ::ehtml($int);
            $error_string .= '.invalid';
        } else {
            $error_string .= '.bytes' if $bytes > LJ::BMAX_INTEREST;
            $error_string .= '.chars' if $chars > LJ::CMAX_INTEREST;
            $error_string .= '.words' if $word_ct > 4;
        }

        if ($error_string) {
            $error_string = "error.interest$error_string";
            push @$interrors, [ $error_string,
                                { int => $int,
                                  bytes => $bytes,
                                  bytes_max => LJ::BMAX_INTEREST,
                                  chars => $chars,
                                  chars_max => LJ::CMAX_INTEREST,
                                  words => $word_ct,
                                  words_max => 4
                                }
                              ];
            next;
        }
        push @valid_ints, $int;
    }
    return @valid_ints;
}
sub interest_string_to_list {
    my $intstr = shift;

    $intstr =~ s/^\s+//;  # strip leading space
    $intstr =~ s/\s+$//;  # strip trailing space
    $intstr =~ s/\n/,/g;  # newlines become commas
    $intstr =~ s/\s+/ /g; # strip duplicate spaces from the interest

    # final list is ,-sep
    return grep { length } split (/\s*,\s*/, $intstr);
}

# $opts is optional, with keys:
#    forceids => 1   : don't use memcache for loading the intids
#    forceints => 1   : don't use memcache for loading the interest rows
#    justids => 1 : return arrayref of intids only, not names/counts
# returns otherwise an arrayref of interest rows, sorted by interest name
sub get_interests
{
    my ($u, $opts) = @_;
    $opts ||= {};
    return undef unless $u;

    # first check request cache inside $u
    if (my $ints = $u->{_cache_interests}) {
        if ($opts->{justids}) {
            return [ map { $_->[0] } @$ints ];
        }
        return $ints;
    }

    my $uid = $u->{userid};
    my $uitable = $u->{'journaltype'} eq 'C' ? 'comminterests' : 'userinterests';

    # load the ids
    my $ids;
    my $mk_ids = [$uid, "intids:$uid"];
    $ids = LJ::MemCache::get($mk_ids) unless $opts->{'forceids'};
    unless ($ids && ref $ids eq "ARRAY") {
        $ids = [];
        my $dbh = LJ::get_db_writer();
        my $sth = $dbh->prepare("SELECT intid FROM $uitable WHERE userid=?");
        $sth->execute($uid);
        push @$ids, $_ while ($_) = $sth->fetchrow_array;
        LJ::MemCache::add($mk_ids, $ids);
    }

    # FIXME: set a 'justids' $u cache key in this case, then only return that 
    #        later if 'justids' is requested?  probably not worth it.
    return $ids if $opts->{'justids'};

    # load interest rows
    my %need;
    $need{$_} = 1 foreach @$ids;
    my @ret;

    unless ($opts->{'forceints'}) {
        if (my $mc = LJ::MemCache::get_multi(map { [$_, "introw:$_"] } @$ids)) {
            while (my ($k, $v) = each %$mc) {
                next unless $k =~ /^introw:(\d+)/;
                delete $need{$1};
                push @ret, $v;
            }
        }
    }

    if (%need) {
        my $ids = join(",", map { $_+0 } keys %need);
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT intid, interest, intcount FROM interests ".
                                "WHERE intid IN ($ids)");
        $sth->execute;
        my $memc_store = 0;
        while (my ($intid, $int, $count) = $sth->fetchrow_array) {
            # minimize latency... only store 25 into memcache at a time
            # (too bad we don't have set_multi.... hmmmm)
            my $aref = [$intid, $int, $count];
            if ($memc_store++ < 25) {
                # if the count is fairly high, keep item in memcache longer,
                # since count's not so important.
                my $expire = $count < 10 ? 3600*12 : 3600*48;
                LJ::MemCache::add([$intid, "introw:$intid"], $aref, $expire);
            }
            push @ret, $aref;
        }
    }

    @ret = sort { $a->[1] cmp $b->[1] } @ret;
    return $u->{_cache_interests} = \@ret;
}

# <LJFUNC>
# name: LJ::modify_caps
# des: Given a list of caps to add and caps to remove, updates a user's caps.
# args: uuid, cap_add, cap_del, res
# des-cap_add: arrayref of bit numbers to turn on
# des-cap_del: arrayref of bit numbers to turn off
# des-res: hashref returned from 'modify_caps' hook
# returns: updated u object, retrieved from $dbh, then 'caps' key modified
#          otherwise, returns 0 unless all hooks run properly.
# </LJFUNC>
sub modify_caps {
    my ($argu, $cap_add, $cap_del, $res) = @_;
    my $userid = LJ::want_userid($argu);
    return undef unless $userid;

    $cap_add ||= [];
    $cap_del ||= [];
    my %cap_add_mod = ();
    my %cap_del_mod = ();

    # convert capnames to bit numbers
    if (LJ::are_hooks("get_cap_bit")) {
        foreach my $bit (@$cap_add, @$cap_del) {
            next if $bit =~ /^\d+$/;

            # bit is a magical reference into the array
            $bit = LJ::run_hook("get_cap_bit", $bit);
        }
    }

    # get a u object directly from the db
    my $u = LJ::load_userid($userid, "force");

    # add new caps
    my $newcaps = int($u->{'caps'});
    foreach (@$cap_add) {
        my $cap = 1 << $_;

        # about to turn bit on, is currently off?
        $cap_add_mod{$_} = 1 unless $newcaps & $cap;
        $newcaps |= $cap;
    }

    # remove deleted caps
    foreach (@$cap_del) {
        my $cap = 1 << $_;

        # about to turn bit off, is it currently on?
        $cap_del_mod{$_} = 1 if $newcaps & $cap;
        $newcaps &= ~$cap;
    }

    # run hooks for modified bits
    if (LJ::are_hooks("modify_caps")) {
        my @res = LJ::run_hooks("modify_caps",
                            { 'u' => $u,
                              'newcaps' => $newcaps,
                              'oldcaps' => $u->{'caps'},
                              'cap_on_req'  => { map { $_ => 1 } @$cap_add },
                              'cap_off_req' => { map { $_ => 1 } @$cap_del },
                              'cap_on_mod'  => \%cap_add_mod,
                              'cap_off_mod' => \%cap_del_mod,
                          });

        # hook should return a status code
        foreach my $status (@res) {
            return undef unless ref $status and defined $status->[0];
        }
    }

    # update user row
    return 0 unless LJ::update_user($u, { 'caps' => $newcaps });

    $u->{caps} = $newcaps;
    $argu->{caps} = $newcaps if ref $argu; # temp hack

    LJ::run_hook("props_changed", $u, {caps => $newcaps});
    
    return $u;
}

# returns 1 if action is permitted.  0 if above rate or fail.
# action isn't logged on fail.
#
# opts keys:
#   -- "limit_by_ip" => "1.2.3.4"  (when used for checking rate)
#   --
sub rate_log
{
    my ($u, $ratename, $count, $opts) = @_;
    my $rateperiod = LJ::get_cap($u, "rateperiod-$ratename");
    return 1 unless $rateperiod;

    return 0 unless $u->writer;

    my $rp = LJ::get_prop("rate", $ratename);
    return 0 unless $rp;
    $opts->{'rp'} = $rp;

    my $now = time();
    $opts->{'now'} = $now;
    my $udbr = LJ::get_cluster_reader($u);
    my $ip = $udbr->quote($opts->{'limit_by_ip'} || "0.0.0.0");
    $opts->{'ip'} = $ip;
    return 0 unless LJ::rate_check($u, $ratename, $count, $opts);

    # log current
    $count = $count + 0;
    $u->do("INSERT INTO ratelog (userid, rlid, evttime, ip, quantity) VALUES ".
           "($u->{'userid'}, $rp->{'id'}, $now, INET_ATON($ip), $count)");

    # delete memcache, except in the case of rate limiting by ip
    unless ($opts->{limit_by_ip}) {
        LJ::MemCache::delete($u->rate_memkey($rp));
    }

    return 1;
}

# returns 1 if action is permitted.  0 if above rate or fail.
sub rate_check {
    my ($u, $ratename, $count, $opts) = @_;

    return 1 if grep { $_ eq $u->username } @LJ::NO_RATE_CHECK_USERS;

    my $rateperiod = LJ::get_cap($u, "rateperiod-$ratename");
    return 1 unless $rateperiod;

    my $rp = defined $opts->{'rp'} ? $opts->{'rp'}
             : LJ::get_prop("rate", $ratename);
    return 0 unless $rp;

    my $now = defined $opts->{'now'} ? $opts->{'now'} : time();
    my $beforeperiod = $now - $rateperiod;

    # check rate.  (okay per period)
    my $opp = LJ::get_cap($u, "rateallowed-$ratename");
    return 1 unless $opp;

    # check memcache, except in the case of rate limiting by ip
    my $memkey = $u->rate_memkey($rp);
    unless ($opts->{limit_by_ip}) {
        my $attempts = LJ::MemCache::get($memkey);
        if ($attempts) {
            my $num_attempts = 0;
            foreach my $attempt (@$attempts) {
                next if $attempt->{evttime} < $beforeperiod;
                $num_attempts += $attempt->{quantity};
            }

            return $num_attempts + $count > $opp ? 0 : 1;
        }
    }

    return 0 unless $u->writer;

    # delete inapplicable stuff (or some of it)
    $u->do("DELETE FROM ratelog WHERE userid=$u->{'userid'} AND rlid=$rp->{'id'} ".
           "AND evttime < $beforeperiod LIMIT 1000");

    my $udbr = LJ::get_cluster_reader($u);
    my $ip = defined $opts->{'ip'}
             ? $opts->{'ip'}
             : $udbr->quote($opts->{'limit_by_ip'} || "0.0.0.0");
    my $sth = $udbr->prepare("SELECT evttime, quantity FROM ratelog WHERE ".
                             "userid=$u->{'userid'} AND rlid=$rp->{'id'} ".
                             "AND ip=INET_ATON($ip) ".
                             "AND evttime > $beforeperiod");
    $sth->execute;

    my @memdata;
    my $sum = 0;
    while (my $data = $sth->fetchrow_hashref) {
        push @memdata, $data;
        $sum += $data->{quantity};
    }

    # set memcache, except in the case of rate limiting by ip
    unless ($opts->{limit_by_ip}) {
        LJ::MemCache::set( $memkey => \@memdata || [] );
    }

    # would this transaction go over the limit?
    if ($sum + $count > $opp) {
        # TODO: optionally log to rateabuse, unless caller is doing it themselves
        # somehow, like with the "loginstall" table.
        return 0;
    }

    return 1;
}


sub login_ip_banned
{
    my ($u, $ip) = @_;
    return 0 unless $u;

    $ip ||= LJ::get_remote_ip();
    return 0 unless $ip;

    my $udbr;
    my $rateperiod = LJ::get_cap($u, "rateperiod-failed_login");
    if ($rateperiod && ($udbr = LJ::get_cluster_reader($u))) {
        my $bantime = $udbr->selectrow_array("SELECT time FROM loginstall WHERE ".
                                             "userid=$u->{'userid'} AND ip=INET_ATON(?)",
                                             undef, $ip);
        if ($bantime && $bantime > time() - $rateperiod) {
            return 1;
        }
    }
    return 0;
}

sub handle_bad_login
{
    my ($u, $ip) = @_;
    return 1 unless $u;

    $ip ||= LJ::get_remote_ip();
    return 1 unless $ip;

    # an IP address is permitted such a rate of failures
    # until it's banned for a period of time.
    my $udbh;
    if (! LJ::rate_log($u, "failed_login", 1, { 'limit_by_ip' => $ip }) &&
        ($udbh = LJ::get_cluster_master($u)))
    {
        $udbh->do("REPLACE INTO loginstall (userid, ip, time) VALUES ".
                  "(?,INET_ATON(?),UNIX_TIMESTAMP())", undef, $u->{'userid'}, $ip);
    }
    return 1;
}

# <LJFUNC>
# name: LJ::userpic_count
# des: Gets a count of userpics for a given user.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
#             also supports deprecated old method, of an array ref of picids.
# </LJFUNC>
sub userpic_count {
    my $u = shift or return undef;

    if ($u->{'dversion'} > 6) {
        my $dbcr = LJ::get_cluster_def_reader($u) or return undef;
        return $dbcr->selectrow_array("SELECT COUNT(*) FROM userpic2 " .
                                      "WHERE userid=? AND state <> 'X'", undef, $u->{'userid'});
    }

    my $dbh = LJ::get_db_writer() or return undef;
    return $dbh->selectrow_array("SELECT COUNT(*) FROM userpic " .
                                 "WHERE userid=? AND state <> 'X'", undef, $u->{'userid'});
}

# <LJFUNC>
# name: LJ::_friends_do
# des: Runs given SQL, then deletes the given userid's friends from memcache.
# args: uuserid, sql, args
# des-uuserid: a userid or u object
# des-sql: SQL to run via $dbh->do()
# des-args: a list of arguments to pass use via: $dbh->do($sql, undef, @args)
# returns: return false on error
# </LJFUNC>
sub _friends_do {
    my ($uuid, $sql, @args) = @_;
    my $uid = want_userid($uuid);
    return undef unless $uid && $sql;

    my $dbh = LJ::get_db_writer() or return 0;

    my $ret = $dbh->do($sql, undef, @args);
    return 0 if $dbh->err;

    LJ::memcache_kill($uid, "friends");

    # pass $uuid in case it's a $u object which mark_dirty wants
    LJ::mark_dirty($uuid, "friends");

    return 1;
}

# <LJFUNC>
# name: LJ::add_friend
# des: Simple interface to add a friend edge.
# args: uuid, to_add, opts?
# des-to_add: a single uuid or an arrayref of uuids to add (befriendees)
# des-opts: hashref; 'defaultview' key means add target uuids to $uuid's Default View friends group,
#                    'groupmask' key means use this group mask
# returns: boolean; 1 on success (or already friend), 0 on failure (bogus args)
# </LJFUNC>
sub add_friend
{
    &nodb;
    my ($userid, $to_add, $opts) = @_;

    $userid = LJ::want_userid($userid);
    return 0 unless $userid;

    my @add_ids = ref $to_add eq 'ARRAY' ? map { LJ::want_userid($_) } @$to_add : ( LJ::want_userid($to_add) );
    return 0 unless @add_ids;

    my $friender = LJ::load_userid($userid);

    # check action rate
    ## TODO: rate check of adding friends needs PM elaboration
    ## Remove '1 ||' when specification is complete  
    unless (1 || $opts->{no_rate_check}){
        my $cond = ["ratecheck:add_friend:$userid",
                    [ $LJ::ADD_FRIEND_RATE_LIMIT || [ 1, 3600 ] ]
                   ];
        return 0 unless LJ::RateLimit->check($friender, [ $cond ]);
    }

    my $dbh      = LJ::get_db_writer();
    my $sclient  = LJ::theschwartz();

    my $fgcol = LJ::color_todb($opts->{'fgcolor'}) || LJ::color_todb("#000000");
    my $bgcol = LJ::color_todb($opts->{'bgcolor'});
    # in case the background color is #000000, in which case the || falls through
    # so only overwrite what we got if what we got was undef (invalid input)
    $bgcol = LJ::color_todb("#ffffff") unless defined $bgcol;

    $opts ||= {};

    my $groupmask = 1;
    if (defined $opts->{groupmask}) {
        $groupmask = $opts->{groupmask};
    } elsif ($opts->{'defaultview'}) {
        # TAG:FR:ljlib:add_friend_getdefviewmask
        my $group = LJ::get_friend_group($userid, { name => 'Default View' });
        my $grp = $group ? $group->{groupnum}+0 : 0;
        $groupmask |= (1 << $grp) if $grp;
    }

    foreach my $add_id (@add_ids) {
        my $cnt = $dbh->do("REPLACE INTO friends (userid, friendid, fgcolor, bgcolor, groupmask) " .
                           "VALUES ($userid, $add_id, $fgcol, $bgcol, $groupmask)");

        if (!$dbh->err && $cnt == 1) {
            LJ::run_hooks('befriended', $friender, LJ::load_userid($add_id));
            LJ::User->increase_friendsof_counter($add_id);
        }
    }
    
    # part of the criteria for whether to fire befriended event
    my $notify = !$LJ::DISABLED{esn} && !$opts->{nonotify}
                 && $friender->is_visible && $friender->is_person;

    # delete friend-of memcache keys for anyone who was added
    foreach my $fid (@add_ids) {
        LJ::MemCache::delete([ $userid, "frgmask:$userid:$fid" ]);
        LJ::memcache_kill($fid, 'friendofs');
        LJ::memcache_kill($fid, 'friendofs2');

        if ($sclient) {
            my @jobs;

            # only fire event if the friender is a person and not banned and visible
            my $friender = LJ::load_userid($userid);
            my $friendee = LJ::load_userid($fid);
            if ($notify && !$friendee->is_banned($friender)) {
                require LJ::Event::BefriendedDelayed;
                LJ::Event::BefriendedDelayed->send($friendee, $friender);
            }

            push @jobs, TheSchwartz::Job->new(
                                              funcname => "LJ::NewWorker::TheSchwartz::FriendChange",
                                              arg      => [$userid, 'add', $fid],
                                              ) unless $LJ::DISABLED{'friendchange-schwartz'};

            $sclient->insert_jobs(@jobs) if @jobs;
        }
    }

    LJ::memcache_kill($userid, 'friends');
    LJ::memcache_kill($userid, 'friends2');
    LJ::mark_dirty($userid, "friends");

    # WARNING: always returns "true". Check result of executing "REPLACE INTO friends ..." statement above.
    return 1;
}

# <LJFUNC>
# name: LJ::remove_friend
# des: delete existing friends.
# args: uuid, to_del
# des-to_del: a single uuid or an arrayref of uuids to remove.
# returns: boolean
# </LJFUNC>
sub remove_friend {
    my ($userid, $to_del, $opts) = @_;

    $userid = LJ::want_userid($userid);
    return undef unless $userid;

    my @del_ids = ref $to_del eq 'ARRAY' ? map { LJ::want_userid($_) } @$to_del : ( LJ::want_userid($to_del) );
    return 0 unless @del_ids;

    my $u = LJ::load_userid($userid);

    my $dbh = LJ::get_db_writer() or return 0;

    foreach my $del_id (@del_ids) {
        my $cnt = $dbh->do("DELETE FROM friends WHERE userid=$userid AND friendid=$del_id");

        if (!$dbh->err && $cnt > 0) {
            LJ::run_hooks('defriended', $u, LJ::load_userid($del_id));
            LJ::User->decrease_friendsof_counter($del_id);
        }
    }
    
    my $sclient = LJ::theschwartz();
    # part of the criteria for whether to fire defriended event
    my $notify = !$LJ::DISABLED{esn} && !$opts->{nonotify} && $u->is_visible && $u->is_person;

    # delete friend-of memcache keys for anyone who was removed
    foreach my $fid (@del_ids) {
        LJ::MemCache::delete([ $userid, "frgmask:$userid:$fid" ]);
        LJ::memcache_kill($fid, 'friendofs');
        LJ::memcache_kill($fid, 'friendofs2');

        my $friendee = LJ::load_userid($fid);
        if ($sclient) {
            my @jobs;

            # only fire event if the friender is a person and not banned and visible
            if ($notify && !$friendee->has_banned($u)) {
                require LJ::Event::DefriendedDelayed;
                LJ::Event::DefriendedDelayed->send($friendee, $u);
            }

            push @jobs, TheSchwartz::Job->new(
                                              funcname => "LJ::NewWorker::TheSchwartz::FriendChange",
                                              arg      => [$userid, 'del', $fid],
                                              ) unless $LJ::DISABLED{'friendchange-schwartz'};
 
            $sclient->insert_jobs(@jobs);
        }
    }

    LJ::memcache_kill($userid, 'friends');
    LJ::memcache_kill($userid, 'friends2');
    LJ::mark_dirty($userid, "friends");

    return 1;
}
*delete_friend_edge = \&LJ::remove_friend;

# <LJFUNC>
# name: LJ::get_friends
# des: Returns friends rows for a given user.
# args: uuserid, mask?, memcache_only?, force?
# des-uuserid: a userid or u object.
# des-mask: a security mask to filter on.
# des-memcache_only: flag, set to only return data from memcache
# des-force: flag, set to ignore memcache and always hit DB.
# returns: hashref; keys = friend userids
#                   values = hashrefs of 'friends' columns and their values
# </LJFUNC>
sub get_friends {
    # TAG:FR:ljlib:get_friends
    my ($uuid, $mask, $memcache_only, $force) = @_;
    my $userid = LJ::want_userid($uuid);
    return undef unless $userid;
    return undef if $LJ::FORCE_EMPTY_FRIENDS{$userid};

    my $u = LJ::load_userid($userid);

    return LJ::RelationService->load_relation_destinations(
            $u, 'F',
                uuid          => $uuid,
                mask          => $mask,
                memcache_only => $memcache_only,
                force_db      => $force,
                );
}

# <LJFUNC>
# name: LJ::get_friendofs
# des: Returns userids of friendofs for a given user.
# args: uuserid, opts?
# des-opts: options hash, keys: 'force' => don't check memcache
# returns: userid for friendofs
# </LJFUNC>
sub get_friendofs {
    # TAG:FR:ljlib:get_friends
    my ($uuid, $opts) = @_;
    my $userid = LJ::want_userid($uuid);
    return undef unless $userid;

    my $u = LJ::load_userid($userid);
    return LJ::RelationService->find_relation_sources($u, 'F', 
            nolimit        => $opts->{force} || 0,
            skip_memcached => $opts->{force},
            );
}

# <LJFUNC>
# name: LJ::get_friend_group
# des: Returns friendgroup row(s) for a given user.
# args: uuserid, opt?
# des-uuserid: a userid or u object
# des-opt: a hashref with keys: 'bit' => bit number of group to return
#                               'name' => name of group to return
# returns: hashref; if bit/name are specified, returns hashref with keys being
#                   friendgroup rows, or undef if the group wasn't found.
#                   otherwise, returns hashref of all group rows with keys being
#                   group bit numbers and values being row col => val hashrefs
# </LJFUNC>
sub get_friend_group {
    my ($uuid, $opt) = @_;
    my $u = LJ::want_user($uuid);
    return undef unless $u;
    my $uid = $u->{userid};

    # data version number
    my $ver = 1;

    # sanity check bitnum
    delete $opt->{'bit'} if
        $opt->{'bit'} > 31 || $opt->{'bit'} < 0;

    my $fg;
    my $find_grp = sub {

        # $fg format:
        # [ version, [userid, bitnum, name, sortorder, public], [...], ... ]

        my $memver = shift @$fg;
        return undef unless $memver == $ver;

        # bit number was specified
        if ($opt->{'bit'}) {
            foreach (@$fg) {
                return LJ::MemCache::array_to_hash("fgrp", [$memver, @$_])
                    if $_->[1] == $opt->{'bit'};
            }
            return undef;
        }

        # group name was specified
        if ($opt->{'name'}) {
            foreach (@$fg) {
                return LJ::MemCache::array_to_hash("fgrp", [$memver, @$_])
                    if lc($_->[2]) eq lc($opt->{'name'});
            }
            return undef;
        }

        # no arg, return entire object
        return { map { $_->[1] => LJ::MemCache::array_to_hash("fgrp", [$memver, @$_]) } @$fg };
    };

    # check memcache
    my $memkey = [$uid, "fgrp:$uid"];
    $fg = LJ::MemCache::get($memkey);
    return $find_grp->() if $fg;

    # check database
    $fg = [$ver];
    my ($db, $fgtable) = $u->{dversion} > 5 ?
                         (LJ::get_cluster_def_reader($u), 'friendgroup2') : # if dversion is 6+, use definitive reader
                         (LJ::get_db_writer(), 'friendgroup');              # else, use regular db writer
    return undef unless $db;

    my $sth = $db->prepare("SELECT userid, groupnum, groupname, sortorder, is_public " .
                           "FROM $fgtable WHERE userid=?");
    $sth->execute($uid);
    return LJ::error($db) if $db->err;

    my @row;
    push @$fg, [ @row ] while @row = $sth->fetchrow_array;

    # set in memcache
    LJ::MemCache::set($memkey, $fg);

    return $find_grp->();
}


# <LJFUNC>
# name: LJ::fill_groups_xmlrpc
# des: Fills a hashref (presumably to be sent to an XML-RPC client, e.g. FotoBilder)
#      with user friend group information
# args: u, ret
# des-ret: a response hashref to fill with friend group data
# returns: undef if called incorrectly, 1 otherwise
# </LJFUNC>
sub fill_groups_xmlrpc {
    my ($u, $ret) = @_;
    return undef unless ref $u && ref $ret;

    # best interface ever...
    $RPC::XML::ENCODING = "utf-8";

    # layer on friend group information in the following format:
    #
    # grp:1 => 'mygroup',
    # ...
    # grp:30 => 'anothergroup',
    #
    # grpu:whitaker => '0,1,2,3,4',
    # grpu:test => '0',

    my $grp = LJ::get_friend_group($u) || {};

    # we don't always have RPC::XML loaded (in web context), and it doesn't really
    # matter much anyway, since our only consumer is also perl which will take
    # the occasional ints back to strings.
    my $str = sub {
        my $str = shift;
        my $val = eval { RPC::XML::string->new($str); };
        return $val unless $@;
        return $str;
    };

    $ret->{"grp:0"} = $str->("_all_");
    foreach my $bit (1..30) {
        next unless my $g = $grp->{$bit};
        $ret->{"grp:$bit"} = $str->($g->{groupname});
    }

    my $fr = LJ::get_friends($u) || {};
    my $users = LJ::load_userids(keys %$fr);
    while (my ($fid, $f) = each %$fr) {
        my $u = $users->{$fid};
        next unless $u->{journaltype} =~ /[PSI]/;

        my $fname = $u->{user};
        $ret->{"grpu:$fid:$fname"} =
            $str->(join(",", 0, grep { $grp->{$_} && $f->{groupmask} & 1 << $_ } 1..30));
    }

    return 1;
}

# <LJFUNC>
# name: LJ::mark_dirty
# des: Marks a given user as being $what type of dirty.
# args: u, what
# des-what: type of dirty being marked (e.g. 'friends')
# returns: 1
# </LJFUNC>
sub mark_dirty {
    my ($uuserid, $what) = @_;

    my $userid = LJ::want_userid($uuserid);
    return 1 if $LJ::REQ_CACHE_DIRTY{$what}->{$userid};

    my $u = LJ::want_user($userid);

    # friends dirtiness is only necessary to track
    # if we're exchange XMLRPC with fotobilder
    if ($what eq 'friends') {
        return 1 unless $LJ::FB_SITEROOT;
        my $sclient = LJ::theschwartz();

        push @LJ::CLEANUP_HANDLERS, sub {
            if ($sclient) {
                my $job = TheSchwartz::Job->new(
                                                funcname => "LJ::Worker::UpdateFotobilderFriends",
                                                coalesce => "uid:$u->{userid}",
                                                arg      => $u->{userid},
                                                );
                $sclient->insert($job);
            } else {
                die "No schwartz client found";
            }
        };
    }

    $LJ::REQ_CACHE_DIRTY{$what}->{$userid}++;

    return 1;
}

# <LJFUNC>
# name: LJ::memcache_kill
# des: Kills a memcache entry, given a userid and type.
# args: uuserid, type
# des-uuserid: a userid or u object
# des-type: memcached key type, will be used as "$type:$userid"
# returns: results of LJ::MemCache::delete
# </LJFUNC>
sub memcache_kill {
    my ($uuid, $type) = @_;
    my $userid = want_userid($uuid);
    return undef unless $userid && $type;

    return LJ::MemCache::delete([$userid, "$type:$userid"]);
}

# <LJFUNC>
# name: LJ::delete_all_comments
# des: deletes all comments from a post, permanently, for when a post is deleted
# info: The tables [dbtable[talk2]], [dbtable[talkprop2]], [dbtable[talktext2]],
#       are deleted from, immediately.
# args: u, nodetype, nodeid
# des-nodetype: The thread nodetype (probably 'L' for log items).
# des-nodeid: The thread nodeid for the given nodetype (probably the jitemid
#             from the [dbtable[log2]] row).
# returns: boolean; success value
# </LJFUNC>
sub delete_all_comments {
    my ($u, $nodetype, $nodeid) = @_;

    my $dbcm = LJ::get_cluster_master($u);
    return 0 unless $dbcm && $u->writer;

    # delete comments
    my ($t, $loop) = (undef, 1);
    my $chunk_size = 200;
    while ($loop &&
           ($t = $dbcm->selectcol_arrayref("SELECT jtalkid FROM talk2 WHERE ".
                                           "nodetype=? AND journalid=? ".
                                           "AND nodeid=? LIMIT $chunk_size", undef,
                                           $nodetype, $u->{'userid'}, $nodeid))
           && $t && @$t)
    {
        my @batch = map { int $_ } @$t;
        my $in = join(',', @batch);
        return 1 unless $in;

        LJ::run_hooks('report_cmt_delete', $u->{'userid'}, \@batch);
        LJ::run_hooks('report_cmt_text_delete', $u->{'userid'}, \@batch);
        foreach my $table (qw(talkprop2 talktext2 talk2)) {
            $u->do("DELETE FROM $table WHERE journalid=? AND jtalkid IN ($in)",
                   undef, $u->{'userid'});
        }
        # decrement memcache
        LJ::MemCache::decr([$u->{'userid'}, "talk2ct:$u->{'userid'}"], scalar(@$t));
        $loop = 0 unless @$t == $chunk_size;
    }
    return 1;

}

# is a user object (at least a hashref)
sub isu {
    return unless ref $_[0];
    return 1 if UNIVERSAL::isa($_[0], "LJ::User");

    if (ref $_[0] eq "HASH" && $_[0]->{userid}) {
        carp "User HASH objects are deprecated from use." if $LJ::IS_DEV_SERVER;
        return 1;
    }
}

# create externally mapped user.
# return uid of LJ user on success, undef on error.
# opts = {
#     extuser or extuserid (or both, but one is required.),
#     caps
# }
# opts also can contain any additional options that create_account takes. (caps?)
sub create_extuser
{
    my ($type, $opts) = @_;
    return undef unless $type && $LJ::EXTERNAL_NAMESPACE{$type}->{id};
    return undef unless ref $opts &&
        ($opts->{extuser} || defined $opts->{extuserid});

    my $uid;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # make sure a mapping for this user doesn't already exist.
    $uid = LJ::get_extuser_uid( $type, $opts, 'force' );
    return $uid if $uid;

    # increment ext_ counter until we successfully create an LJ account.
    # hard cap it at 10 tries. (arbitrary, but we really shouldn't have *any*
    # failures here, let alone 10 in a row.)
    for (1..10) {
        my $extuser = 'ext_' . LJ::alloc_global_counter( 'E' );
        $uid =
          LJ::create_account(
            { caps => $opts->{caps}, user => $extuser, name => $extuser } );
        last if $uid;
        select undef, undef, undef, .10;  # lets not thrash over this.
    }
    return undef unless $uid;

    # add extuser mapping.
    my $sql = "INSERT INTO extuser SET userid=?, siteid=?";
    my @bind = ($uid, $LJ::EXTERNAL_NAMESPACE{$type}->{id});

    if ($opts->{extuser}) {
        $sql .= ", extuser=?";
        push @bind, $opts->{extuser};
    }

    if ($opts->{extuserid}) {
        $sql .= ", extuserid=? ";
        push @bind, $opts->{extuserid}+0;
    }

    $dbh->do($sql, undef, @bind) or return undef;
    return $uid;
}

# given an extuserid or extuser, return the LJ uid.
# return undef if there is no mapping.
sub get_extuser_uid
{
    my ($type, $opts, $force) = @_;
    return undef unless $type && $LJ::EXTERNAL_NAMESPACE{$type}->{id};
    return undef unless ref $opts &&
        ($opts->{extuser} || defined $opts->{extuserid});

    my $dbh = $force ? LJ::get_db_writer() : LJ::get_db_reader();
    return undef unless $dbh;

    my $sql = "SELECT userid FROM extuser WHERE siteid=?";
    my @bind = ($LJ::EXTERNAL_NAMESPACE{$type}->{id});

    if ($opts->{extuser}) {
        $sql .= " AND extuser=?";
        push @bind, $opts->{extuser};
    }

    if ($opts->{extuserid}) {
        $sql .= $opts->{extuser} ? ' OR ' : ' AND ';
        $sql .= "extuserid=?";
        push @bind, $opts->{extuserid}+0;
    }

    return $dbh->selectrow_array($sql, undef, @bind);
}

# given a LJ userid/u, return a hashref of:
# type, extuser, extuserid
# returns undef if user isn't an externally mapped account.
sub get_extuser_map
{
    my $uid = LJ::want_userid(shift);
    return undef unless $uid;

    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    my $sql = "SELECT * FROM extuser WHERE userid=?";
    my $ret = $dbr->selectrow_hashref($sql, undef, $uid);
    return undef unless $ret;

    my $type = 'unknown';
    foreach ( keys %LJ::EXTERNAL_NAMESPACE ) {
        $type = $_ if $LJ::EXTERNAL_NAMESPACE{$_}->{id} == $ret->{siteid};
    }

    $ret->{type} = $type;
    return $ret;
}

# <LJFUNC>
# name: LJ::create_account
# des: Creates a new basic account.  <strong>Note:</strong> This function is
#      not really too useful but should be extended to be useful so
#      htdocs/create.bml can use it, rather than doing the work itself.
# returns: integer of userid created, or 0 on failure.
# args: dbarg?, opts
# des-opts: hashref containing keys 'user', 'name', 'password', 'email', 'caps', 'journaltype'.
# </LJFUNC>
sub create_account {
    &nodb;
    my $opts = shift;
    my $u = LJ::User->create(%$opts)
        or return 0;

    return $u->id;
}

# <LJFUNC>
# name: LJ::new_account_cluster
# des: Which cluster to put a new account on.  $DEFAULT_CLUSTER if it's
#      a scalar, random element from [ljconfig[default_cluster]] if it's arrayref.
#      also verifies that the database seems to be available.
# returns: clusterid where the new account should be created; 0 on error
#          (such as no clusters available).
# </LJFUNC>
sub new_account_cluster
{
    # if it's not an arrayref, put it in an array ref so we can use it below
    my $clusters = ref $LJ::DEFAULT_CLUSTER ? $LJ::DEFAULT_CLUSTER : [ $LJ::DEFAULT_CLUSTER+0 ];

    # select a random cluster from the set we've chosen in $LJ::DEFAULT_CLUSTER
    return LJ::random_cluster(@$clusters);
}

# returns the clusterid of a random cluster which is up
# -- accepts @clusters as an arg to enforce a subset, otherwise
#    uses @LJ::CLUSTERS
sub random_cluster {
    my @clusters = @_ ? @_ : @LJ::CLUSTERS;

    # iterate through the new clusters from a random point
    my $size = @clusters;
    my $start = int(rand() * $size);
    foreach (1..$size) {
        my $cid = $clusters[$start++ % $size];

        # verify that this cluster is in @LJ::CLUSTERS
        my @check = grep { $_ == $cid } @LJ::CLUSTERS;
        next unless scalar(@check) >= 1 && $check[0] == $cid;

        # try this cluster to see if we can use it, return if so
        my $dbcm = LJ::get_cluster_master($cid);
        return $cid if $dbcm;
    }

    # if we get here, we found no clusters that were up...
    return 0;
}


# <LJFUNC>
# name: LJ::make_journal
# class:
# des:
# info:
# args: dbarg, user, view, remote, opts
# des-:
# returns:
# </LJFUNC>
sub make_journal
{
    &nodb;
    my ($user, $view, $remote, $opts) = @_;

    my $geta = $opts->{'getargs'};

    if ($LJ::SERVER_DOWN) {
        if ($opts->{'vhost'} eq "customview") {
            return "<!-- LJ down for maintenance -->";
        }
        return LJ::server_down_html();
    }

    my $u = $opts->{'u'} || LJ::load_user($user);
    unless ($u) {
        $opts->{'baduser'} = 1;
        return "<h1>Error</h1>No such user <b>$user</b>";
    }
    LJ::set_active_journal($u);
    LJ::Request->notes('ljentry' => $opts->{'ljentry'}->url) if $opts->{'ljentry'};

    # S1 style hashref.  won't be loaded now necessarily,
    # only if via customview.
    my $style;

    my ($styleid);
    if ($opts->{'styleid'}) {  # s1 styleid
        $styleid = $opts->{'styleid'}+0;

        # if we have an explicit styleid, we have to load
        # it early so we can learn its type, so we can
        # know which uprops to load for its owner
        if ($LJ::ONLY_USER_VHOSTS && $opts->{vhost} eq "customview") {
            # reject this style if it's not trusted by the user, and we're showing
            # stuff on user domains
            my $ownerid = LJ::S1::get_style_userid_always($styleid);
            my $is_trusted = sub {
                return 1 if $ownerid == $u->{userid};
                return 1 if $ownerid == LJ::system_userid();
                return 1 if $LJ::S1_CUSTOMVIEW_WHITELIST{"styleid-$styleid"};
                return 1 if $LJ::S1_CUSTOMVIEW_WHITELIST{"userid-$ownerid"};
                my $trust_list = eval { $u->prop("trusted_s1") };
                return 1 if $trust_list =~ /\b$styleid\b/;
                return 0;
            };
            unless ($is_trusted->()) {
                $style = undef;
                $styleid = 0;
            }
        }
    } else {

        $view ||= "lastn";    # default view when none specified explicitly in URLs
        if ($LJ::viewinfo{$view} || $view eq "month" ||
            $view eq "entry" || $view eq "reply")  {
            $styleid = -1;    # to get past the return, then checked later for -1 and fixed, once user is loaded.
        } else {
            $opts->{'badargs'} = 1;
        }
    }
    return unless $styleid;


    $u->{'_journalbase'} = LJ::journal_base($u->{'user'}, $opts->{'vhost'});

    my $eff_view = $LJ::viewinfo{$view}->{'styleof'} || $view;
    my $s1prop = "s1_${eff_view}_style";

    my @needed_props = ("stylesys", "s2_style", "url", "urlname", "opt_nctalklinks",
                        "renamedto",  "opt_blockrobots", "opt_usesharedpic", "icbm",
                        "journaltitle", "journalsubtitle", "external_foaf_url",
                        "adult_content", "admin_content_flag");

    # S2 is more fully featured than S1, so sometimes we get here and $eff_view
    # is reply/month/entry/res and that means it *has* to be S2--S1 defaults to a
    # BML page to handle those, but we don't want to attempt to load a userprop
    # because now load_user_props dies if you try to load something invalid
    push @needed_props, $s1prop if $eff_view =~ /^(?:calendar|day|friends|lastn)$/;

    # preload props the view creation code will need later (combine two selects)
    if (ref $LJ::viewinfo{$eff_view}->{'owner_props'} eq "ARRAY") {
        push @needed_props, @{$LJ::viewinfo{$eff_view}->{'owner_props'}};
    }

    if ($eff_view eq "reply") {
        push @needed_props, "opt_logcommentips";
    }

    $u->preload_props(@needed_props);

    # FIXME: remove this after all affected accounts have been fixed
    # see http://zilla.livejournal.org/1443 for details
    if ($u->{$s1prop} =~ /^\D/) {
        $u->{$s1prop} = $LJ::USERPROP_DEF{$s1prop};
        $u->set_prop($s1prop, $u->{$s1prop});
    }

    # if the remote is the user to be viewed, make sure the $remote
    # hashref has the value of $u's opt_nctalklinks (though with
    # LJ::load_user caching, this may be assigning between the same
    # underlying hashref)
    $remote->{'opt_nctalklinks'} = $u->{'opt_nctalklinks'} if
        ($remote && $remote->{'userid'} == $u->{'userid'});

    my $stylesys = 1;
    if ($styleid == -1) {

        my $get_styleinfo = sub {

            my $get_s1_styleid = sub {
                my $id = $u->{$s1prop};
                LJ::run_hooks("s1_style_select", {
                    'styleid' => \$id,
                    'u' => $u,
                    'view' => $view,
                });
                return $id;
            };

            # forced s2 style id
            if ($geta->{'s2id'}) {

                # get the owner of the requested style
                my $style = LJ::S2::load_style( $geta->{s2id} );
                my $owner = $style && $style->{userid} ? $style->{userid} : 0;

                # remote can use s2id on this journal if:
                # owner of the style is remote or managed by remote OR
                # owner of the style has s2styles cap and remote is viewing owner's journal

                if ($u->id == $owner && $u->get_cap("s2styles")) {
                    $opts->{'style_u'} = LJ::load_userid($owner);
                    return (2, $geta->{'s2id'});
                }

                if ($remote && $remote->can_manage($owner)) {
                    # check is owned style still available: paid user possible became plus...
                    my $lay_id = $style->{layer}->{layout};
                    my $theme_id = $style->{layer}->{theme};
                    my %lay_info;
                    LJ::S2::load_layer_info(\%lay_info, [$style->{layer}->{layout}, $style->{layer}->{theme}]);

                    if (LJ::S2::can_use_layer($remote, $lay_info{$lay_id}->{redist_uniq})
                        and LJ::S2::can_use_layer($remote, $lay_info{$theme_id}->{redist_uniq})) {
                        $opts->{'style_u'} = LJ::load_userid($owner);
                        return (2, $geta->{'s2id'});
                    } # else this style not allowed by policy
                }
            }

            # style=mine passed in GET?
            if ($remote && ( $geta->{'style'} eq 'mine' ||
                             $remote->opt_stylealwaysmine ) ) {

                # get remote props and decide what style remote uses
                $remote->preload_props("stylesys", "s2_style");

                # remote using s2; make sure we pass down the $remote object as the style_u to
                # indicate that they should use $remote to load the style instead of the regular $u
                if ($remote->{'stylesys'} == 2 && $remote->{'s2_style'}) {
                    $opts->{'checkremote'} = 1;
                    $opts->{'style_u'} = $remote;
                    return (2, $remote->{'s2_style'});
                }

                # remote using s1
                return (1, $get_s1_styleid->());
            }

            # resource URLs have the styleid in it
            if ($view eq "res" && $opts->{'pathextra'} =~ m!^/(\d+)/!) {
                return (2, $1);
            }

            my $forceflag = 0;
            LJ::run_hooks("force_s1", $u, \$forceflag);

            # if none of the above match, they fall through to here
            if ( !$forceflag && $u->{'stylesys'} == 2 ) {
                return (2, $u->{'s2_style'});
            }

            # no special case and not s2, fall through to s1
            return (1, $get_s1_styleid->());
        };

        if ($LJ::JOURNALS_WITH_FIXED_STYLE{$u->user}) {
            ($stylesys, $styleid) = (2, $u->{'s2_style'}); 
        } else {
            ($stylesys, $styleid) = $get_styleinfo->();
        }
    }

    # transcode the tag filtering information into the tag getarg; this has to
    # be done above the s1shortcomings section so that we can fall through to that
    # style for lastn filtered by tags view
    if ($view eq 'lastn' && $opts->{pathextra} && $opts->{pathextra} =~ /^\/tag\/(.+)$/) {
        $opts->{getargs}->{tag} = $1;
        $opts->{pathextra} = undef;
    }

    # do the same for security filtering
    elsif ($view eq 'lastn' && $opts->{pathextra} && $opts->{pathextra} =~ /^\/security\/(.+)$/) {
        $opts->{getargs}->{security} = $1;
        $opts->{pathextra} = undef;
    }

    if (LJ::Request->is_inited) {
        LJ::Request->notes('journalid' => $u->{'userid'});
    }

    my $notice = sub {
        my $msg = shift;
        my $status = shift;

        my $url = "$LJ::SITEROOT/users/$user/";
        $opts->{'status'} = $status if $status;

        my $head;
        my $journalbase = LJ::journal_base($user);

        # Automatic Discovery of RSS/Atom
        $head .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$journalbase/data/rss" />\n};
        $head .= qq{<link rel="alternate" type="application/atom+xml" title="Atom" href="$journalbase/data/atom" />\n};
        $head .= qq{<link rel="service.feed" type="application/atom+xml" title="AtomAPI-enabled feed" href="$LJ::SITEROOT/interface/atom/feed" />\n};
        $head .= qq{<link rel="service.post" type="application/atom+xml" title="Create a new post" href="$LJ::SITEROOT/interface/atom/post" />\n};

        # OpenID Server and Yadis
        $head .= $u->openid_tags; 

        # FOAF autodiscovery
        my $foafurl = $u->{external_foaf_url} ? LJ::eurl($u->{external_foaf_url}) : "$journalbase/data/foaf";
        $head .= qq{<link rel="meta" type="application/rdf+xml" title="FOAF" href="$foafurl" />\n};

        if ($u->email_visible($remote)) {
            my $digest = Digest::SHA1::sha1_hex('mailto:' . $u->email_raw);
            $head .= qq{<meta name="foaf:maker" content="foaf:mbox_sha1sum '$digest'" />\n};
        }

        return qq{
            <html>
            <head>
            $head
            </head>
            <body>
             <h1>Notice</h1>
             <p>$msg</p>
             <p>Instead, please use <nobr><a href=\"$url\">$url</a></nobr></p>
            </body>
            </html>
        }.("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 50);
    };
    my $error = sub {
        my $msg = shift;
        my $status = shift;
        $opts->{'status'} = $status if $status;

        return qq{
            <h1>Error</h1>
            <p>$msg</p>
        }.("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 50);
    };
    if ($LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && $u->{'journaltype'} ne 'R' &&
        ! LJ::get_cap($u, "userdomain")) {
        return $notice->("URLs like <nobr><b>http://<i>username</i>.$LJ::USER_DOMAIN/" .
                         "</b></nobr> are not available for this user's account type.");
    }
    if ($opts->{'vhost'} =~ /^other:/ && ! LJ::get_cap($u, "domainmap")) {
        return $notice->("This user's account type doesn't permit domain aliasing.");
    }
    if ($opts->{'vhost'} eq "customview" && ! LJ::get_cap($u, "styles")) {
        return $notice->("This user's account type is not permitted to create and embed styles.");
    }
    if ($opts->{'vhost'} eq "community" && $u->{'journaltype'} !~ /[CR]/) {
        $opts->{'badargs'} = 1; # Output a generic 'bad URL' message if available
        return "<h1>Notice</h1><p>This account isn't a community journal.</p>";
    }
    if ($view eq "friendsfriends" && ! LJ::get_cap($u, "friendsfriendsview")) {
        my $inline;
        if ($inline .= LJ::run_hook("cprod_inline", $u, 'FriendsFriendsInline')) {
            return $inline;
        } else {
            return BML::ml('cprod.friendsfriendsinline.text.v1');
        }
    }

    # signal to LiveJournal.pm that we can't handle this
    if (($stylesys == 1 || $geta->{'format'} eq 'light') &&
        ({ entry=>1, reply=>1, month=>1, tag=>1 }->{$view} || ($view eq 'lastn' && ($geta->{tag} || $geta->{security})))) {

        # pick which fallback method (s2 or bml) we'll use by default, as configured with
        # $S1_SHORTCOMINGS
        my $fallback = $LJ::S1_SHORTCOMINGS ? "s2" : "bml";

        # but if the user specifies which they want, override the fallback we picked
        if ($geta->{'fallback'} && $geta->{'fallback'} =~ /^s2|bml$/) {
            $fallback = $geta->{'fallback'};
        }

        # if we are in this path, and they have style=mine set, it means
        # they either think they can get a S2 styled page but their account
        # type won't let them, or they really want this to fallback to bml
        if ($remote && ( $geta->{'style'} eq 'mine' ||
                         $remote->opt_stylealwaysmine ) ) {
            $fallback = 'bml';
        }

        # If they specified ?format=light, it means they want a page easy
        # to deal with text-only or on a mobile device.  For now that means
        # render it in the lynx site scheme.
        if ($geta->{'format'} eq 'light') {
            $fallback = 'bml';
            LJ::Request->notes('bml_use_scheme' => 'lynx');
        }

        # there are no BML handlers for these views, so force s2
        if ($view eq 'tag' || $view eq 'lastn') {
            $fallback = "s2";
        }

        # fall back to BML unless we're using S2
        # fallback (the "s1shortcomings/layout")
        if ($fallback eq "bml") {
            ${$opts->{'handle_with_bml_ref'}} = 1;
            return;
        }

        # S1 can't handle these views, so we fall back to a
        # system-owned S2 style (magic value "s1short") that renders
        # this content
        $stylesys = 2;
        $styleid = "s1short";
    }

    # now, if there's a GET argument for tags, split those out
    if (exists $opts->{getargs}->{tag}) {
        my $tagfilter = $opts->{getargs}->{tag};
        return $error->("You must provide tags to filter by.", "404 Not Found")
            unless $tagfilter;

        # error if disabled
        return $error->("Sorry, the tag system is currently disabled.", "404 Not Found")
            if $LJ::DISABLED{tags};

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $error->("Sorry, tag filtering is not supported within S1 styles.", "404 Not Found")
            if $stylesys == 1 && $view ne 'data' && $u->{journaltype} ne 'R';

        # overwrite any tags that exist
        $opts->{tags} = [];
        return $error->("Sorry, the tag list specified is invalid.", "404 Not Found")
            unless LJ::Tags::is_valid_tagstring($tagfilter, $opts->{tags}, { omit_underscore_check => 1 });

        # get user's tags so we know what remote can see, and setup an inverse mapping
        # from keyword to tag
        $opts->{tagids} = [];
        my $tags = LJ::Tags::get_usertags($u, { remote => $remote });
        my %kwref = ( map { $tags->{$_}->{name} => $_ } keys %{$tags || {}} );
        foreach (@{$opts->{tags}}) {
            unless ($kwref{$_}) {
                LJ::Request->pnotes ('error' => 'e404');
                LJ::Request->pnotes ('remote' => LJ::get_remote ());
                $opts->{'handler_return'} = "404 Not Found";
                return;
            }
            #return $error->("Sorry, one or more specified tags do not exist.", "404 Not Found")
            #    unless $kwref{$_};
            push @{$opts->{tagids}}, $kwref{$_};
        }

        $opts->{tagmode} = $opts->{getargs}->{mode} eq 'and' ? 'and' : 'or';
    }

    # validate the security filter
    if (exists $opts->{getargs}->{security}) {
        my $securityfilter = $opts->{getargs}->{security};
        return $error->("You must provide a security level to filter by.", "404 Not Found")
            unless $securityfilter;

        return $error->("This feature is not available for your account level.", "403 Forbidden")
            unless LJ::get_cap($remote, "security_filter") || LJ::get_cap($u, "security_filter");

        # error if disabled
        return $error->("Sorry, the security-filtering system is currently disabled.", "404 Not Found")
            unless LJ::is_enabled("security_filter");

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $error->("Sorry, security filtering is not supported within S1 styles.", "404 Not Found")
            if $stylesys == 1 && $view ne 'data' && !$u->is_redirect;

        # check the filter itself
        if ($securityfilter =~ /^(?:public|friends|private)$/i) {
            $opts->{'securityfilter'} = lc($securityfilter);

        } elsif ($securityfilter =~ /^group:(.+)$/i) {
            my $groupres = LJ::get_friend_group($u, { 'name' => $1});

            if ($groupres && (LJ::u_equals($u, $remote)
                              || LJ::get_groupmask($u, $remote) & (1 << $groupres->{groupnum}))) {
                $opts->{securityfilter} = $groupres->{groupnum};
            }
        }

        return $error->("You have specified an invalid security setting, the friends group you specified does not exist, or you are not a member of that group.", "404 Not Found")
            unless defined $opts->{securityfilter};

    }

    unless ($geta->{'viewall'} && LJ::check_priv($remote, "canview", "suspended") ||
            $opts->{'pathextra'} =~ m#/(\d+)/stylesheet$#) { # don't check style sheets
        if ($u->is_deleted){
            my $warning = LJ::Lang::get_text(LJ::Lang::get_effective_lang(), 
                                    'journal.deleted', undef, {username => $u->username})
                       || LJ::Lang::get_text($LJ::DEFAULT_LANG, 
                                    'journal.deleted', undef, {username => $u->username});
            LJ::Request->pnotes ('error' => 'deleted');
            LJ::Request->pnotes ('remote' => LJ::get_remote ());
            $opts->{'handler_return'} = "404 Not Found";
            return;
            #return $error->($warning, "404 Not Found");

        }
        if ($u->is_suspended) {
            LJ::Request->pnotes ('error' => 'suspended');
            LJ::Request->pnotes ('remote' => LJ::get_remote ());
            $opts->{'handler_return'} = "403 Forbidden";
            return;
        }
        #return $error->("This journal has been suspended.", "403 Forbidden") if ($u->is_suspended);

        my $entry = $opts->{ljentry};

        if ($entry && $entry->is_suspended_for($remote)) {
            LJ::Request->pnotes ('error' => 'suspended_post');
            LJ::Request->pnotes ('remote' => LJ::get_remote ());
            $opts->{'handler_return'} = "403 Forbidden";
            return;
        }

        return $error->("This entry has been suspended. You can visit the journal <a href='" . $u->journal_base . "/'>here</a>.", "403 Forbidden")
            if $entry && $entry->is_suspended_for($remote);
    }
    if ($u->is_expunged) {
        LJ::Request->pnotes ('error' => 'expunged');
        LJ::Request->pnotes ('remote' => LJ::get_remote ());
        $opts->{'handler_return'} = "410 Gone";
        return;
    }

    return $error->("This user has no journal here.", "404 Not here") if $u->{'journaltype'} eq "I" && $view ne "friends";

    $opts->{'view'} = $view;

    # what charset we put in the HTML
    $opts->{'saycharset'} ||= "utf-8";

    if ($view eq 'data') {
        return LJ::Feed::make_feed($u, $remote, $opts);
    }

    if ($stylesys == 2) {
        LJ::Request->notes('codepath' => "s2.$view") if LJ::Request->is_inited;

        eval { LJ::S2->can("dostuff") };  # force Class::Autouse
        my $mj = LJ::S2::make_journal($u, $styleid, $view, $remote, $opts);

        # intercept flag to handle_with_bml_ref and instead use S1 shortcomings
        # if BML is disabled
        if ($opts->{'handle_with_bml_ref'} && ${$opts->{'handle_with_bml_ref'}} &&
            ($LJ::S1_SHORTCOMINGS || $geta->{fallback} eq "s2"))
        {
            # kill the flag
            ${$opts->{'handle_with_bml_ref'}} = 0;

            # and proceed with s1shortcomings (which looks like BML) instead of BML
            $mj = LJ::S2::make_journal($u, "s1short", $view, $remote, $opts);
        }

        return $mj;
    }

    # Everything from here on down is S1.  FIXME: this should be moved to LJ::S1::make_journal
    # to be more like LJ::S2::make_journal.
    LJ::Request->notes('codepath' => "s1.$view") if LJ::Request->is_inited;
    $u->{'_s1styleid'} = $styleid + 0;

    # For embedded polls
    BML::set_language($LJ::LANGS[0] || 'en', \&LJ::Lang::get_text);

    # load the user-related S1 data  (overrides and colors)
    my $s1uc;
    my $is_s1uc_valid = sub {
        ## Storable::thaw takes valid date, undef or empty string; 
        ## dies on invalid data
        return 
            eval {
                Storable::thaw($_[0]->{'color_stor'});
                Storable::thaw($_[0]->{'override_stor'}); 
                1;
            };
    };
    my $s1uc_memkey = [$u->{'userid'}, "s1uc:$u->{'userid'}"];
    if ($u->{'useoverrides'} eq "Y" || $u->{'themeid'} == 0) {
        $s1uc = LJ::MemCache::get($s1uc_memkey);
        undef($s1uc) if $s1uc && !$is_s1uc_valid->($s1uc);

        unless ($s1uc) {
            my $db;
            my $setmem = 1;
            if (@LJ::MEMCACHE_SERVERS) {
                $db = LJ::get_cluster_def_reader($u);
            } else {
                $db = LJ::get_cluster_reader($u);
                $setmem = 0;
            }
            $s1uc = $db->selectrow_hashref("SELECT * FROM s1usercache WHERE userid=?",
                                           undef, $u->{'userid'});
            undef($s1uc) if $s1uc && !$is_s1uc_valid->($s1uc); 
            LJ::MemCache::set($s1uc_memkey, $s1uc) if $s1uc && $setmem;
        }
    }

    # we should have our cache row!  we'll update it in a second.
    my $dbcm;
    if (! $s1uc) {
        $u->do("INSERT IGNORE INTO s1usercache (userid) VALUES (?)", undef, $u->{'userid'});
        $s1uc = {};
    }

    # conditionally rebuild parts of our cache that are missing
    my %update;

    # is the overrides cache old or missing?
    my $dbh;
    if ($u->{'useoverrides'} eq "Y" && (! $s1uc->{'override_stor'} ||
                                        $s1uc->{'override_cleanver'} < $LJ::S1::CLEANER_VERSION)) {

        my $overrides = LJ::S1::get_overrides($u);
        $update{'override_stor'} = LJ::CleanHTML::clean_s1_style($overrides);
        $update{'override_cleanver'} = $LJ::S1::CLEANER_VERSION;
    }

    # is the color cache here if it's a custom user theme?
    if ($u->{'themeid'} == 0 && ! $s1uc->{'color_stor'}) {
        my $col = {};
        $dbh ||= LJ::get_db_writer();
        my $sth = $dbh->prepare("SELECT coltype, color FROM themecustom WHERE user=?");
        $sth->execute($u->{'user'});
        $col->{$_->{'coltype'}} = $_->{'color'} while $_ = $sth->fetchrow_hashref;
        $update{'color_stor'} = Storable::nfreeze($col);
    }

    # save the updates
    if (%update) {
        my $set;
        foreach my $k (keys %update) {
            $s1uc->{$k} = $update{$k};
            $set .= ", " if $set;
            $set .= "$k=" . $u->quote($update{$k});
        }
        my $rv = $u->do("UPDATE s1usercache SET $set WHERE userid=?", undef, $u->{'userid'});
        LJ::MemCache::set($s1uc_memkey, $s1uc);
    }

    # load the style
    my $viewref = $view eq "" ? \$view : undef;
    $style ||= $LJ::viewinfo{$view}->{'nostyle'} ? {} :
        LJ::S1::load_style($styleid, $viewref);

    my %vars = ();

    # apply the style
    foreach (keys %$style) {
        $vars{$_} = $style->{$_};
    }

    # apply the overrides
    if ($opts->{'nooverride'}==0 && $u->{'useoverrides'} eq "Y") {
        my $tw = Storable::thaw($s1uc->{'override_stor'});
        foreach (keys %$tw) {
            $vars{$_} = $tw->{$_};
        }
    }

    # apply the color theme
    $@ = '';
    my $cols = $u->{'themeid'} 
                ? LJ::S1::get_themeid($u->{'themeid'})
                : Storable::thaw($s1uc->{'color_stor'});
    foreach (keys %$cols) {
        $vars{"color-$_"} = $cols->{$_};
    }

    # instruct some function to make this specific view type
    return unless defined $LJ::viewinfo{$view}->{'creator'};
    my $ret = "";

    # call the view creator w/ the buffer to fill and the construction variables
    my $res = $LJ::viewinfo{$view}->{'creator'}->(\$ret, $u, \%vars, $remote, $opts);

    if ($LJ::USE_S1w2 && $LJ::USE_S1w2->($view, $u, $remote)) {
        # S1w2 is an experimental version of S1 that acts as if it were an S2 style,
        # getting all of its necessary data from the S2 data structures rather than
        # fetching the data itself and duplicating all of that logic.
        # It should ideally generate exactly the same output as traditional S1 with
        # the same input data, but until this has been tested thoroughly it's
        # disabled by default.
        
        # We render S1w2 in addition to traditional S1 so that we can see if there
        # is any difference.
        my $s1result = $ret;
        $ret = "";
        
        require "ljviews-s1-using-s2.pl"; # Load on demand
        $LJ::S1w2::viewcreator{$view}->(\$ret, $u, \%vars, $remote, $opts);
        
        if ($s1result ne $ret) {
            warn "S1w2 differed from S1 when rendering a $view page for $u->{user} with ".($remote ? $remote->{user} : "an anonymous user")." watching";

            # Optionally produce a diff between S1 and S1w2
            # NOTE: This _make_diff function hits the filesystem and forks a diff process.
            #   It's only useful/sensible on a low-load development server.
            if ($LJ::SHOW_S1w2_DIFFS) {
                $ret .= "<plaintext>".LJ::S1w2::_make_diff($s1result, $ret);
            }
        }
        
    }

    unless ($res) {
        my $errcode = $opts->{'errcode'};
        my $errmsg = {
            'nodb' => 'Database temporarily unavailable during maintenance.',
            'nosyn' => 'No syndication URL available.',
        }->{$errcode};
        return "<!-- $errmsg -->" if ($opts->{'vhost'} eq "customview");

        # If not customview, set the error response code.
        $opts->{'status'} = {
            'nodb' => '503 Maintenance',
            'nosyn' => '404 Not Found',
        }->{$errcode} || '500 Server Error';
        return $errmsg;
    }

    if ($opts->{'redir'}) {
        return undef;
    }

    # clean up attributes which we weren't able to quickly verify
    # as safe in the Storable-stored clean copy of the style.
    $ret =~ s/\%\%\[attr\[(.+?)\]\]\%\%/LJ::CleanHTML::s1_attribute_clean($1)/eg;

    # return it...
    return $ret;
}

# <LJFUNC>
# name: LJ::canonical_username
# des: normalizes username.
# info:
# args: user
# returns: the canonical username given, or blank if the username is not well-formed
# </LJFUNC>
sub canonical_username
{
    my $user = shift;
    if ($user =~ /^\s*([A-Za-z0-9_\-]{1,15})\s*$/) {
        # perl 5.8 bug:  $user = lc($1) sometimes causes corruption when $1 points into $user.
        $user = $1;
        $user = lc($user);
        $user =~ s/-/_/g;
        return $user;
    }
    return "";  # not a good username.
}

# <LJFUNC>
# name: LJ::get_userid
# des: Returns a userid given a username.
# info: Results cached in memory.  On miss, does DB call.  Not advised
#       to use this many times in a row... only once or twice perhaps
#       per request.  Tons of serialized db requests, even when small,
#       are slow.  Opposite of [func[LJ::get_username]].
# args: dbarg?, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_userid
{
    &nodb;
    my $user = shift;

    $user = LJ::canonical_username($user);

    if ($LJ::CACHE_USERID{$user}) { return $LJ::CACHE_USERID{$user}; }

    my $userid = LJ::MemCache::get("uidof:$user");
    return $LJ::CACHE_USERID{$user} = $userid if $userid;

    my $dbr = LJ::get_db_reader();
    $userid = $dbr->selectrow_array("SELECT userid FROM useridmap WHERE user=?", undef, $user);

    # implicitly create an account if we're using an external
    # auth mechanism
    if (! $userid && ref $LJ::AUTH_EXISTS eq "CODE")
    {
        $userid = LJ::create_account({ 'user' => $user,
                                       'name' => $user,
                                       'password' => '', });
    }

    if ($userid) {
        $LJ::CACHE_USERID{$user} = $userid;
        LJ::MemCache::set("uidof:$user", $userid);
    }

    return ($userid+0);
}

# <LJFUNC>
# name: LJ::want_userid
# des: Returns userid when passed either userid or the user hash. Useful to functions that
#      want to accept either. Forces its return value to be a number (for safety).
# args: userid
# des-userid: Either a userid, or a user hash with the userid in its 'userid' key.
# returns: The userid, guaranteed to be a numeric value.
# </LJFUNC>
sub want_userid
{
    my $uuserid = shift;
    return ($uuserid->{'userid'} + 0) if ref $uuserid;
    return ($uuserid + 0);
}

# <LJFUNC>
# name: LJ::want_user
# des: Returns user object when passed either userid or user object. Useful to functions that
#      want to accept either.
# args: user
# des-user: Either a userid or a user hash with the userid in its 'userid' key.
# returns: The user object represented by said userid or username.
# </LJFUNC>
sub want_user
{
    my $uuid = shift;
    return undef unless $uuid;
    return $uuid if ref $uuid;
    return LJ::load_userid($uuid) if $uuid =~ /^\d+$/;
    Carp::croak("Bogus caller of LJ::want_user with non-ref/non-numeric parameter");
}

# <LJFUNC>
# name: LJ::get_username
# des: Returns a username given a userid.
# info: Results cached in memory.  On miss, does DB call.  Not advised
#       to use this many times in a row... only once or twice perhaps
#       per request.  Tons of serialized db requests, even when small,
#       are slow.  Opposite of [func[LJ::get_userid]].
# args: dbarg?, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_username
{
    &nodb;
    my $userid = shift;
    $userid += 0;

    # Checked the cache first.
    if ($LJ::CACHE_USERNAME{$userid}) { return $LJ::CACHE_USERNAME{$userid}; }

    # if we're using memcache, it's faster to just query memcache for
    # an entire $u object and just return the username.  otherwise, we'll
    # go ahead and query useridmap
    if (@LJ::MEMCACHE_SERVERS) {
        my $u = LJ::load_userid($userid);
        return undef unless $u;

        $LJ::CACHE_USERNAME{$userid} = $u->{'user'};
        return $u->{'user'};
    }

    my $dbr = LJ::get_db_reader();
    my $user = $dbr->selectrow_array("SELECT user FROM useridmap WHERE userid=?", undef, $userid);

    # Fall back to master if it doesn't exist.
    unless (defined $user) {
        my $dbh = LJ::get_db_writer();
        $user = $dbh->selectrow_array("SELECT user FROM useridmap WHERE userid=?", undef, $userid);
    }

    return undef unless defined $user;

    $LJ::CACHE_USERNAME{$userid} = $user;
    return $user;
}

# <LJFUNC>
# name: LJ::can_manage_other
# des: Given a user and a target user, will determine if the first user is an
#      admin for the target user, but not if the two are the same.
# args: remote, u
# des-remote: user object or userid of user to try and authenticate
# des-u: user object or userid of target user
# returns: bool: true if authorized, otherwise fail
# </LJFUNC>
sub can_manage_other {
    my ($remote, $u) = @_;
    return 0 if LJ::want_userid($remote) == LJ::want_userid($u);
    $remote = LJ::want_user($remote);
    return $remote && $remote->can_manage($u);
}

sub can_delete_journal_item {
    my ($remote, $u, $itemid) = @_;
    $remote = LJ::want_user($remote);

    return 0 unless $remote;

    return 0 unless $remote->can_manage($u);
    # here admin or supermaintainer

    return 0 if $LJ::JOURNALS_WITH_PROTECTED_CONTENT{ $u->{user} } and !LJ::is_friend($u, $remote);

    return 1;
}


# <LJFUNC>
# name: LJ::get_remote
# des: authenticates the user at the remote end based on their cookies
#      and returns a hashref representing them.
# args: opts?
# des-opts: 'criterr': scalar ref to set critical error flag.  if set, caller
#           should stop processing whatever it's doing and complain
#           about an invalid login with a link to the logout page.
#           'ignore_ip': ignore IP address of remote for IP-bound sessions
# returns: hashref containing 'user' and 'userid' if valid user, else
#          undef.
# </LJFUNC>
sub get_remote {
    my $opts = ref $_[0] eq "HASH" ? shift : {};

    return $LJ::CACHE_REMOTE if $LJ::CACHED_REMOTE && ! $opts->{'ignore_ip'};

    my $no_remote = sub {
        LJ::User->set_remote(undef);
        return undef;
    };

    # can't have a remote user outside of web context
    return $no_remote->() unless LJ::Request->is_inited;

    my $get_as = LJ::Request->get_param('as');
    if ( $LJ::IS_DEV_SERVER && $get_as =~ /^\w{1,15}$/ ) {
        my $ru = LJ::load_user($get_as);

        # might be undef, to allow for "view as logged out":
        LJ::set_remote($ru);
        return $ru;
    }

    my $criterr = $opts->{criterr} || do { my $d; \$d; };
    $$criterr = 0;

    $LJ::CACHE_REMOTE_BOUNCE_URL = "";

    # set this flag if any of their ljsession cookies contained the ".FS"
    # opt to use the fast server.  if we later find they're not logged
    # in and set it, or set it with a free account, then we give them
    # the invalid cookies error.
    my $tried_fast = 0;
    my $sessobj = LJ::Session->session_from_cookies(
        tried_fast   => \$tried_fast,
        redirect_ref => \$LJ::CACHE_REMOTE_BOUNCE_URL,
        ignore_ip    => $opts->{ignore_ip},
    );

    my $u = $sessobj ? $sessobj->owner : undef;

    # inform the caller that this user is faking their fast-server cookie
    # attribute.
    if ($tried_fast && ! LJ::get_cap($u, "fastserver")) {
        $$criterr = 1;
    }

    return $no_remote->() unless $sessobj;

    # renew soon-to-expire sessions
    $sessobj->try_renew;

    # augment hash with session data;
    $u->{'_session'} = $sessobj;

    # keep track of activity for the user we just loaded from db/memcache
    # - if necessary, this code will actually run in Apache's cleanup handler
    #   so latency won't affect the user
    if (@LJ::MEMCACHE_SERVERS && ! $LJ::DISABLED{active_user_tracking}) {
        push @LJ::CLEANUP_HANDLERS, sub { $u->note_activity('A') };
    }

    LJ::User->set_remote($u);
    LJ::Request->notes("ljuser" => $u->{'user'});
    return $u;
}

# returns either $remote or the authenticated user that $remote is working with
sub get_effective_remote {
    my $authas_arg = shift || "authas";

    return undef unless LJ::is_web_context();

    my $remote = LJ::get_remote();
    return undef unless $remote;

    my $authas = $BMLCodeBlock::GET{authas} || $BMLCodeBlock::POST{authas} || $remote->user;
    return $remote if $authas eq $remote->user;

    return LJ::get_authas_user($authas);
}

# returns URL we have to bounce the remote user to in order to
# get their domain cookie
sub remote_bounce_url {
    return $LJ::CACHE_REMOTE_BOUNCE_URL;
}

sub set_remote {
    my $remote = shift;
    LJ::User->set_remote($remote);
    1;
}

sub unset_remote
{
    LJ::User->unset_remote;
    1;
}

sub get_active_journal
{
    return $LJ::ACTIVE_JOURNAL;
}

sub set_active_journal
{
    $LJ::ACTIVE_JOURNAL = shift;
}

# Checks if they are flagged as having a bad password and redirects
# to changepassword.bml.  If returl is on it returns the URL to
# redirect to vs doing the redirect itself.  Useful in non-BML context
# and for QuickReply links
sub bad_password_redirect {
    my $opts = shift;

    my $remote = LJ::get_remote();
    return undef unless $remote;

    return undef if $LJ::DISABLED{'force_pass_change'};

    return undef unless $remote->prop('badpassword');

    my $redir = "$LJ::SITEROOT/changepassword.bml";
    unless (defined $opts->{'returl'}) {
        return BML::redirect($redir);
    } else {
        return $redir;
    }
}

# Returns HTML to display user search results
# Args: %args
# des-args:
#           users    => hash ref of userid => u object like LJ::load userids
#                       returns or array ref of user objects
#           userids  => array ref of userids to include in results, ignored
#                       if users is defined
#           timesort => set to 1 to sort by last updated instead
#                       of username
#           perpage  => Enable pagination and how many users to display on
#                       each page
#           curpage  => What page of results to display
#           navbar   => Scalar reference for paging bar
#           pickwd   => userpic keyword to display instead of default if it
#                       exists for the user
#           self_link => Sub ref to generate link to use for pagination
sub user_search_display {
    my %args = @_;

    my $loaded_users;
    unless (defined $args{users}) {
        $loaded_users = LJ::load_userids(@{$args{userids}});
    } else {
        if (ref $args{users} eq 'HASH') { # Assume this is direct from LJ::load_userids
            $loaded_users = $args{users};
        } elsif (ref $args{users} eq 'ARRAY') { # They did a grep on it or something
            foreach (@{$args{users}}) {
                $loaded_users->{$_->{userid}} = $_;
            }
        } else {
            return undef;
        }
    }

    # If we're sorting by last updated, we need to load that
    # info for all users before the sort.  If sorting by
    # username we can load it for a subset of users later,
    # if paginating.
    my $updated;
    my @display;

    if ($args{timesort}) {
        $updated = LJ::get_timeupdate_multi(keys %$loaded_users);
        @display = sort { $updated->{$b->{userid}} <=> $updated->{$a->{userid}} } values %$loaded_users;
    } else {
        @display = sort { $a->{user} cmp $b->{user} } values %$loaded_users;
    }

    if (defined $args{perpage}) {
        my %items = BML::paging(\@display, $args{curpage}, $args{perpage});

        # Fancy paging bar
        my $opts;
        $opts->{self_link} = $args{self_link} if $args{self_link};
        ${$args{navbar}} = LJ::paging_bar($items{'page'}, $items{'pages'}, $opts);

        # Now pull out the set of users to display
        @display = @{$items{'items'}};
    }

    # If we aren't sorting by time updated, load last updated time for the
    # set of users we are displaying.
    $updated = LJ::get_timeupdate_multi(map { $_->{userid} } @display)
        unless $args{timesort};

    # Allow caller to specify a custom userpic to use instead
    # of the user's default all userpics
    my $get_picid = sub {
        my $u = shift;
        return $u->{'defaultpicid'} unless $args{'pickwd'};
        return LJ::get_picid_from_keyword($u, $args{'pickwd'});
    };

    my $ret;
    foreach my $u (@display) {
        # We should always have loaded user objects, but it seems
        # when the site is overloaded we don't always load the users
        # we request.
        next unless LJ::isu($u);

        $ret .= "<div style='width: 300px; height: 105px; overflow: hidden; float: left; ";
        $ret .= "border-bottom: 1px solid <?altcolor2?>; margin-bottom: 10px; padding-bottom: 5px; margin-right: 10px'>";
        $ret .= "<table style='height: 105px'><tr>";

        $ret .= "<td style='width: 100px; text-align: center;'>";
        $ret .= "<a href='/allpics.bml?user=$u->{user}'>";
        if (my $picid = $get_picid->($u)) {
            $ret .= "<img src='$LJ::USERPIC_ROOT/$picid/$u->{userid}' alt='$u->{user} userpic' style='border: 1px solid #000;' />";
        } else {
            $ret .= "<img src='$LJ::STATPREFIX/horizon/nouserpic.png' alt='no default userpic' style='border: 1px solid #000;' width='100' height='100' />";
        }
        $ret .= "</a>";

        $ret .= "</td><td style='padding-left: 5px;' valign='top'><table>";

        $ret .= "<tr><td class='searchusername' colspan='2' style='text-align: left;'>";
        $ret .= $u->ljuser_display({ head_size => $args{head_size} });
        $ret .= "</td></tr><tr>";

        if ($u->{name}) {
            $ret .= "<td width='1%' style='font-size: smaller' valign='top'>Name:</td><td style='font-size: smaller'><a href='" . $u->profile_url . "'>";
            $ret .= LJ::ehtml($u->{name});
            $ret .= "</a>";
            $ret .= "</td></tr><tr>";
        }

        if (my $jtitle = $u->prop('journaltitle')) {
            $ret .= "<td width='1%' style='font-size: smaller' valign='top'>Journal:</td><td style='font-size: smaller'><a href='" . $u->journal_base . "'>";
            $ret .= LJ::ehtml($jtitle) . "</a>";
            $ret .= "</td></tr>";
        }

        $ret .= "<tr><td colspan='2' style='text-align: left; font-size: smaller' class='lastupdated'>";

        if ($updated->{$u->{'userid'}} > 0) {
            $ret .= "Updated ";
            $ret .= LJ::TimeUtil->ago_text(time() - $updated->{$u->{'userid'}});
        } else {
            $ret .= "Never updated";
        }

        $ret .= "</td></tr>";

        $ret .= "</table>";
        $ret .= "</td></tr>";
        $ret .= "</table></div>";
    }

    return $ret;
}

# returns the country that the remote IP address comes from
# undef is returned if the country cannot be determined from the IP
sub country_of_remote_ip {
    my $ip = LJ::get_remote_ip();
    return undef unless $ip;
    
    if (LJ::GeoLocation->can('get_country_info_by_ip')) {
        ## use module LJ::GeoLocation if it's installed
        return LJ::GeoLocation->get_country_info_by_ip($ip)
    } elsif (eval "use IP::Country::Fast; 1;") {
        my $reg = IP::Country::Fast->new();
        my $country = $reg->inet_atocc($ip);

        # "**" is returned if the IP is private
        return undef if $country eq "**";
        return $country;
    }

    return undef;
}

1;
