package LJ::Console::Command::ChangeJournalType;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_journal_type" }

sub desc { "Change a journal's type." }

sub args_desc { [
                 'journal' => "The username of the journal that type is changing.",
                 'type' => "Either 'person', 'shared', or 'community'.",
                 'owner' => "This is required when converting a personal journal to a community or shared journal, or the reverse. If converting to a community/shared journal, 'owner' will become the maintainer. Otherwise, the account will adopt the email address and password of the 'owner'. Only users with the 'changejournaltype' priv can specify an owner for an account.",
                 ] }

sub usage { '<journal> <type> [ <owner> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, $user, $type, $owner, @args) = @_;
    my $remote = LJ::get_remote();

    return $self->error("This command takes either two or three arguments. Consult the reference.")
        unless $user && $type && scalar(@args) == 0;

    return $self->error("Type argument must be 'person', 'shared', 'community', or 'news'.")
        unless $type =~ /^(?:person|shared|community|news)$/;

    my $u = LJ::load_user($user);
    return $self->error("Invalid user: $user")
        unless $u;

    return $self->error("Account cannot be converted while not active.")
        unless $u->is_visible;

    return $self->error("Account is not a community or personal, shared, or news journal.")
        unless $u->journaltype =~ /[PCSN]/;

    return $self->error("You cannot convert your own account.")
        if LJ::u_equals($remote, $u);

    return $self->error("This account is already a $type account")
        if $type =~ /^$u->journaltype/i;

    # get any owner specified
    my $ou = $owner ? LJ::load_user($owner) : undef;
    return $self->error("Invalid username '$owner' specified as owner.")
        if $owner && !$ou;
    return $self->error("Owner must be a personal journal.")
        if $ou && $ou->journaltype ne 'P';
    return $self->error("Owner must be an active account.")
        if $ou && !$ou->is_visible;

    if ($ou) {
        return $self->error("You cannot specify a new owner for an account")
            unless LJ::check_priv($remote, "changejournaltype");
    } else {
        return $self->error("You must specify an owner in order to change a journal type.")
            unless LJ::check_priv($remote, "changejournaltype") && !LJ::can_manage($remote, $u);

        return $self->error("You must be a maintainer of $user in order to convert it.")
            unless LJ::can_manage();

        return $self->error("You can only convert communities or shared journals.")
            if $u->journaltype =~ /^[CS]/;

        return $self->error("You can only convert to a community or shared journal.")
            if $type =~ /^(?:community|shared)$/;

        # since we use this later for setting some account settings
        $ou = $remote;
    }
    # at this point, we have verified that we can complete the action the user requested,
    # so we do not need any more authorization checks.

    # set up actions hashref with subs to do things.  this doesn't do anything yet.  it is called by
    # the various transformations down below.
    my $dbh = LJ::get_db_writer();
    my %actions = (
       # must not have entries by other users in the account
       other_entry_check => sub {
           my $dbcr = LJ::get_cluster_def_reader($u);
           my $count = $dbcr->selectrow_array('SELECT COUNT(*) FROM log2 WHERE journalid = ? AND posterid <> journalid',
                                               undef, $u->id);
           return $self->error("Account contains $count entries posted by other users and cannot be converted.")
               if $count;
       },

       # no entries by this user in the account
       self_entry_check => sub {
           my $dbcr = LJ::get_cluster_def_reader($u);
           my $count = $dbcr->selectrow_array('SELECT COUNT(*) FROM log2 WHERE journalid = ? AND posterid = journalid',
                                              undef, $u->id);
           return $self->error("Account contains $count entries posted by the account itself and so cannot be converted.")
               if $count;
       },

       # clear out or set relations
       update_rels => sub {
           if (scalar(@_) > 0 && ref $_[0]) {
               # user passed edges to set
               LJ::set_rel_multi(@_);
           } else {
               # clear, they passed a scalar of some sort
               # clear unmoderated, moderator, admin, and posting access edges
               LJ::clear_rel($u, '*', $_) foreach qw(N M A P);
           }
       },

       # update/delete community row
       update_commrow => sub {
           my $arg = shift(@_)+0;
           if ($arg) {
               $dbh->do("INSERT INTO community VALUES (?, 'open', 'members')", undef, $u->id);
           } else {
               $dbh->do("DELETE FROM community WHERE userid = ?", undef, $u->id);
           }
       },

       # delete all friendships from other people TO this account
       clear_friends => sub {
           # if we're changing a non-person account to a person account,
           # we need to ditch all its friend-ofs so that old users befriending
           # that account (in order to watch it), don't give the account maintainer
           # access to read the old reader's friends-only posts.  (which they'd now
           # be able to do, since journaltype=='P'.)

           # TAG:FR:console:change_journal_type:getfriendofs
           my $ids = $dbh->selectcol_arrayref("SELECT userid FROM friends WHERE friendid=?",
                                              undef, $u->id);
           # TAG:FR:console:change_journal_type:deletefriendofs
           $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $u->id);
           LJ::memcache_kill($_, "friends") foreach @$ids;
       },

       # change some basic user info
       update_user => sub {
           my ($journaltype, $password, $adoptemail) = @_;
           return $self->error('Invalid journaltype sent to update_user.')
               unless $journaltype =~ /[PCSN]/;
           $password = '' unless defined $password;
           $adoptemail += 0;
           my %extra = ();

           if ($adoptemail) {
               return $self->error("Owner's email address is not validated.")
                   unless $ou->email_status eq 'A';

               $extra{'email'} = $ou->email_raw;
               $extra{status} = 'A';

               # clear old email address from their infohistory to prevent account hijacking and such
               $dbh->do("UPDATE infohistory SET what='emailreset' WHERE userid=? AND what='email'", undef, $u->id)
                   or $self->error("Error updating infohistory for emailreset: " . $dbh->errstr);
               LJ::infohistory_add($u, 'emailreset', $u->email_raw, $u->email_status)
                   unless $ou->email_raw eq $u->email_raw; # record only if it changed
           }

           # password changed too?
           LJ::infohistory_add($u, 'password', Digest::MD5::md5_hex($u->password . 'change'))
               if $password ne $u->password;

           # now update the user table and kill memcache
           LJ::update_user($u, { journaltype => $journaltype,
                                 password => $password,
                                 %extra });
       },
    );


    # these are the actual transformations that define the logic behind changing journal types.
    # want to go TO a community
    my @todo;
    if ($type eq 'community') {
        # what are they coming FROM?
        return unless $actions{self_entry_check}->();
        if ($u->{journaltype} eq 'P' || $u->{journaltype} eq 'N') {
            # setup actions to be taken
            @todo = ([ 'update_commrow', 1 ],
                     [ 'update_rels',
                       [ $u->{userid}, $ou->{userid}, 'A' ],
                       [ $u->{userid}, $ou->{userid}, 'P' ], # make $ou a maintainer of $u, and have posting access
                     ],
                     [ 'clear_friends' ],
                     [ 'update_user', 'C', '', 1 ]);

        } elsif ($u->{journaltype} eq 'S') {
            # shared -> comm, allowed by anybody
            @todo = ([ 'update_commrow', 1 ],
                     [ 'update_user', 'C', '', LJ::u_equals($remote, $ou) ? 0 : 1 ]);
        }

    # or to a shared journal
    } elsif ($type eq 'shared') {
        # from?
        if ($u->{journaltype} eq 'P' || $u->{journaltype} eq 'N') {
            # actions to take
            @todo = ([ 'update_rels',
                       [ $u->{userid}, $ou->{userid}, 'A' ],
                       [ $u->{userid}, $ou->{userid}, 'P' ], # make $ou a maintainer of $u, and have posting access
                     ],
                     [ 'clear_friends' ],
                     [ 'update_user', 'S', $ou->password, 1 ]);

        } elsif ($u->{journaltype} eq 'C') {
            # comm -> shared, anybody can do
            @todo = ([ 'update_commrow', 0 ],
                     [ 'update_user', 'S', $ou->password, LJ::u_equals($remote, $ou) ? 0 : 1 ]);
        }

    # perhaps to a person
    } elsif ($type eq 'person') {
        return unless $actions{other_entry_check}->();

        # doesn't matter what they're coming from, as long as they're coming from something valid
        if ($u->{journaltype} =~ /[CSN]/) {
            @todo = ([ 'update_rels', 0 ],
                     [ 'clear_friends' ],
                     [ 'update_commrow', 0 ],
                     [ 'update_user', 'P', $ou->password, 1 ]);
        }

    # convert personal journal to news
    } elsif ($type eq 'news') {
        # can't have entries before conversion to news
        return unless $actions{self_entry_check};

        @todo = (
                 [ 'update_rels', [ $u->{userid}, $ou->{userid}, 'A' ] ],
                 [ 'update_commrow', 0 ],
                 [ 'update_user', 'N', $ou->password, 1 ],
                 );
    }

    # register this action in statushistory
    LJ::statushistory_add($u, $remote, "change_journal_type", "account '" . $u->user . "' converted to $type"
                          . LJ::u_equals($remote, $ou) ? "" : " (owner/parent is '$ou->{user}')");

    # now run the requested actions
    foreach my $row (@todo) {
        my $which = ref $row ? shift(@{$row || []}) : $row;
        if (ref $actions{$which} eq 'CODE') {
            # call subref, passing arguments left in $row
            $actions{$which}->(@{$row || []});
        }
    }

    return $self->print("User: " . $u->user . " converted to a $type account.");
}

1;
