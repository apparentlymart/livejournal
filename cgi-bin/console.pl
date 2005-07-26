#!/usr/bin/perl
#
# <LJDEP>
# lib: cgi-bin/conmoodtheme.pl
# lib: cgi-bin/conban.pl. cgi-bin/conshared.pl
# lib: cgi-bin/consuspend.pl, cgi-bin/confaq.pl
# lib: cgi-bin/console-local.pl, Text::Wrap
# </LJDEP>

package LJ::Con;
use strict;
use vars qw(%cmd);
use Text::Wrap ();

sub parse_line
{
    my $cmd = shift;
    return () unless ($cmd =~ /\S/);
    $cmd =~ s/^\s+//; 
    $cmd =~ s/\s+$//;
    $cmd =~ s/\t/ /g;
    
    my $state = 'a';  # w=whitespace, a=arg, q=quote, e=escape (next quote isn't closing)
    
    my @args;
    my $argc = 0;
    my $len = length($cmd);
    my ($lastchar, $char);
    
    for (my $i=0; $i<$len; $i++) 
    {
        $lastchar = $char;
        $char = substr($cmd, $i, 1);
        
        ### jump out of quots
        if ($state eq "q" && $char eq '"') {
            $state = "w";
            next;
        }
        
        ### keep ignoring whitespace
        if ($state eq "w" && $char eq " ") {
            next;
        }
        
        ### finish arg if space found
        if ($state eq "a" && $char eq " ") {
            $state = "w";
            next;
        }
         
        ### if non-whitespace encountered, move to next arg
        if ($state eq "w") {
            $argc++;
            if ($char eq '"') {
                $state = "q";
                next;
            } else {
                $state = "a";
            }
        }
        
        ### don't count this character if it's a quote
        if ($state eq "q" && $char eq '"') {
            $state = "w";
            next;
        }
        
        ### respect backslashing quotes inside quotes
        if ($state eq "q" && $char eq "\\") {
            $state = "e";
            next;
        }
        
        ### after an escape, next character is literal
        if ($state eq "e") {
            $state = "q";
        }
        
        $args[$argc] .= $char;
    }

    return @args;
}

sub execute
{
    my ($dbh, $remote, $args, $outlist) = @_;
    
    $args->[0] = lc $args->[0];
    my $cmd = $cmd{$args->[0]};
    unless ($cmd) {
        push @$outlist, [ "error", "Unknown command '$args->[0]'" ];
        return 0;
    }

    # No console for suspended users
    if ($remote && $remote->{'statusvis'} eq 'S') {
        push @$outlist, [ "error", "Suspended users cannot use the console." ];
        return 0;
    }

    if ($cmd->{'def'}) { require "$ENV{'LJHOME'}/cgi-bin/$cmd->{'def'}"; }

    unless (ref $cmd->{'handler'} eq "CODE") {
        push @$outlist, [ "error", "No handler found for command '$args->[0]'" ];
        return 0;
    }

    ## load the privileges (if not already loaded) that this remote user needs.
    if ($cmd->{'privs'})
    {
        foreach my $privname (@{$cmd->{'privs'}})
        {
            next if ($remote->{'privloaded'}->{$privname});
            $remote->{'privloaded'}->{$privname} = 1;

            unless ($remote->{'privarg'}->{$privname}) {
                $remote->{'privarg'}->{$privname} = {};
            }

            if (LJ::remote_has_priv($remote, $privname, $remote->{'privarg'}->{$privname})) {
                $remote->{'priv'}->{$privname} = 1;
            }
        }
    }

    my $rv = &{$cmd->{'handler'}}($dbh, $remote, $args, $outlist);
    return $rv;
}

# load the site-specific console commands, if present.
if (-e "$LJ::HOME/cgi-bin/console-local.pl") {
    do "$LJ::HOME/cgi-bin/console-local.pl";
}

# Convenience methods for returning from handlers
my $success = sub {
    my ($out, $msg) = @_;
    push @$out, [ "", $msg ];
    return 1;
};
my $fail = sub {
    my ($out, $msg) = @_;
    push @$out, [ "error", $msg ];
    return 0;
};
my $usage = sub {
    my ($out, $cmdname) = @_;
    return $fail->($out, "usage: $cmdname $cmd{$cmdname}{argsummary}");
};

$cmd{'priv'} =
   {
    des        => 'Grant or revoke user privileges.',
    privs      => [qw(admin)],
    argsummary => '<action> <privs> <usernames>',
    args       => [
                   action    => "'grant', 'revoke', or 'revoke_all' to revoke all args for a given priv",
                   privs     => "Comma-delimited list of priv names or priv:arg pairs",
                   usernames => "Comma-delimited list of usernames",
                  ],
    handler => sub {
        my ($dbh, $remote, $args, $out) = @_;

        return $fail->($out, "Not logged in.") unless $remote;

        # check usage, parse out some basic information.
        my $is_grant;           # 1 if granting, 0 if revoking
        my $is_revoke_all;      # 1 if action is revoke_all
        my @privs;              # ([privcode,arg], ...)
        my @usernames;          # (username, ...)
        {
            my $myname    = shift @$args;
            my $action    = shift @$args    or return $usage->($out, $myname);
            my $privstr   = shift @$args    or return $usage->($out, $myname);
            my $userstr   = shift @$args    or return $usage->($out, $myname);
            not @$args                      or return $usage->($out, $myname);
            $action =~ /^(grant|revoke|revoke_all)$/
                                            or return $usage->($out, $myname);

            $is_grant      = ($action eq "grant");
            $is_revoke_all = ($action eq "revoke_all");

            @privs     = map {[split /:/, $_, 2]} (split /,\s*/, $privstr);
            @usernames = split /,\s*/, $userstr;

            # To reduce likelihood that someone will do 'priv revoke foo'
            # intending to remove 'foo:*' and accidentally only remove 'foo:'
            if ($action eq "revoke" and grep {not defined $_->[1]} @privs) {
                $fail->($out, q{Empty arguments must be explicitly specified when using 'revoke'});
                $fail->($out, q{For example, use 'revoke foo:', not 'revoke foo', to revoke the 'foo' priv with empty argument.});
                return 0;
            }
            if ($action eq "revoke_all" and grep {defined $_->[1]} @privs) {
                return $fail->($out, q{Do not explicitly specify priv arguments when using revoke_all.});
            }
        }

        # get the userids, fail if any of them are invalid
        my %userids = ();       # username => userid
        foreach my $username (@usernames) {
            $userids{$username} = LJ::get_userid($username)
              or return $fail->($out, "No such username '$username'");
        }

        # get mapping of priv codes to priv ids, fail if any are invalid
        my %prlids;             # privcode => prlid
        {
            my @privcodes = map {$_->[0]} @privs;
            my $privcode_list = join ",", (map {$dbh->quote($_)} @privcodes);
            my $sql = ("SELECT privcode, prlid".
                       "  FROM priv_list".
                       " WHERE privcode IN ($privcode_list)");
            my $rows = $dbh->selectall_arrayref($sql)
              or return $fail->($out, "Couldn't load prlids?!");
            %prlids = map {@$_} @$rows;

            foreach my $privcode (@privcodes) {
                exists $prlids{$privcode}
                  or return $fail->($out, "No such priv '$privcode'");
            }
        }

        # check to make sure remote user has appropriate admin privs
        {
            my $admin = $remote->{privarg}{admin}
              or return $fail->($out, "Couldn't load admin privs?!");
            foreach my $pair (@privs) {
                my ($priv, $arg) = @$pair;
                unless ($admin->{'*'} or $admin->{$priv}
                        or ($arg and $admin->{"$priv/$arg"})) {
                    return $fail->($out,
                                   "You don't have permission to grant priv ".
                                   ($arg ? "$priv:$arg" : $priv));
                }
            }
        }

        my $result = 1;

        # revoke a priv with all args - just do it in one big DELETE
        if ($is_revoke_all) {
            my $sql = sprintf('DELETE FROM priv_map WHERE userid IN (%s) AND prlid IN (%s)',
                              join(',', values %userids),
                              join(',', values %prlids));
            if ($dbh->do($sql)) {
                $success->($out, sprintf("Denying: %s with all args to %s",
                                         join(',', keys %prlids),
                                         join(',', keys %userids)));
                foreach my $userid (values %userids) {
                    foreach my $privname (keys %prlids) {
                        LJ::statushistory_add($userid, $remote->{userid},
                                              'privdel',
                                              qq{Denying: "$privname" with all args});
                    }
                }
            } else {
                $result = $fail->($out, "DB failure");
            }
            return $result;
        }

        # the normal case: add/remove each combination of userid and privid/arg
        my $sql = ($is_grant
                   ? "INSERT INTO priv_map (userid,prlid,arg) VALUES (?,?,?)"
                   : "DELETE FROM priv_map WHERE userid=? AND prlid=? AND arg=?");
        my $sth = $dbh->prepare($sql)
          or return $fail->($out, "Couldn't prepare priv_map sth?!");

        foreach my $pair (@privs) {
            my ($privcode, $arg) = @$pair;
            my $prlid = $prlids{$privcode};
            $arg ||= "";   # since it might be undef

            foreach my $username (@usernames) {
                my $u = LJ::load_user($username);
                return $fail->($out, "Couldn't load user for $username") unless $u;
                my $has_priv = LJ::check_priv($u, $privcode, $arg);

                if ($is_grant && $has_priv) { # Dupe priv
                    $result = $fail->($out, "User $username already has $privcode with the argument $arg.");
                } elsif (!$is_grant && !$has_priv) { # Dupe priv
                    $result = $fail->($out, "User $username does not have $privcode with the argument $arg.");
                } else { # We can do it! ... All night long
                    my $desc = sprintf(qq{%s: "%s" with arg "%s"},
                                       $is_grant ? "Granting" : "Denying",
                                       $privcode, $arg);

                    if ($sth->execute($u->{'userid'}, $prlid, $arg)) {
                        $success->($out, "$desc to $username");
                        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'},
                                              $is_grant ? "privadd" : "privdel",
                                              $desc);
                    } else {
                        $result = $fail->($out, "DB failure: $desc to $username: " . $sth->errstr);
                    }
                }
            }
        }
        return $result;
    },
};

$cmd{'gencodes'} = {
    des => 'Generate invite codes.',
    privs => [qw(gencodes)],
    argsummary => '<username> <quantity>',
    args => [
             username => "User to be given the codes",
	     quantity => "Number of codes to generate",
	    ],
    handler => sub {
        my ($dbh, $remote, $args, $out) = @_;

        my $myname   = shift @$args;
        my $username = shift @$args        or return $usage->($out, $myname);
        my $quantity = int(shift @$args)   or return $usage->($out, $myname);
        not @$args                         or return $usage->($out, $myname);

        $remote or return $fail->($out, "Not logged in.");
            
        $remote->{'priv'}->{'gencodes'}
            or return $fail->($out, "You don't have privileges needed to run this command.");

        my $userid = LJ::get_userid($username)
            or return $fail->($out, "Invalid user $username");
        my $generated = LJ::acct_code_generate($userid, $quantity)
            or return $fail->($out, "Failed to generate codes");

        LJ::statushistory_add($userid, $remote->{'userid'}, "gencodes", "$generated created");
        
        return $success->($out, "$quantity codes requested for $username, generated $generated.");
    },
};

$cmd{'foreach_entry'} = {
    'handler' => \&foreach_entry,
    'hidden' => 1,   # not yet done.
    'des' => 'Do one or more actions on some subset of your journal entries.',
    'argsummary' => '<condition>* "action" <action>',
    'args' => [
               'condition' => "Zero or more conditions used to match journal entries of yours.  An exclamation mark can be put right before a condition to indicate 'NOT'.  Possible conditions include:  'security=public', 'security=private', 'security=friends', 'security=custom'.  More may be made in the future.  Note that using multiple security=whatever conditions is pointless... no entry can have different security levels.  However, using multiple !security=whatever works .... entries can NOT be multiple things.",
               'action' => "When you're done listing your matching conditions, the literal string 'action' specifies that the remaining tokens are actions to be performed on the journal entries which matched all the preceeding conditions.",
               'action' => "One action to be performed on the matching journal entries.  Action can be 'list', 'delete', 'security=public', 'security=private', or 'security=friends'.  It's recommended that you run this command first with the 'list' action, to test that your conditions are matching the journal entries that you really want to delete or change.",
               ],
    };

$cmd{'moodtheme_create'} = {
    'def' => 'conmoodtheme.pl',
    'des' => 'Create a new mood icon set.  Return value from this command is the moodthemeid that you\'ll need to define pictures for this theme.',
    'argsummary' => '<name> <des>',
    'args' => [
               'name' => "Name of this theme, to appear in various places on the site",
               'des' => "Some description of the theme",
               ],
    };


$cmd{'moodtheme_public'} = {
    'def' => 'conmoodtheme.pl',
    'privs' => [qw(moodthememanager)],
    'des' => 'Make a mood theme public or not.  You have to be a moodthememanager to do this.',
    'argsummary' => '<themeid> <setting>',
    'args' => [
               'themeid' => "Mood theme ID number.",
               'setting' => "Either 'Y' or 'N' to make it public or not public, respectively.",
               ],
    };

$cmd{'moodtheme_setpic'} = {
    'def' => 'conmoodtheme.pl',
    'des' => 'Change data for a mood theme.  If picurl, width, or height is empty or zero, the data is deleted.',
    'argsummary' => '<themeid> <moodid> <picurl> <width> <height>',
    'args' => [
               'themeid' => "Mood theme ID number.",
               'moodid' => "Mood ID number.",
               'picurl' => "URL to picture to show for this moodid in this themeid.  If a public one, use /img/mood/themename/file.gif",
               'width' => "Width of picture",
               'height' => "Height of picture",
               ],
    };

$cmd{'moodtheme_list'} = {
    'def' => 'conmoodtheme.pl',
    'des' => 'List mood themes, or data about a mood theme',
    'argsummary' => '[<themeid>]',
    'args' => ['themeid' => 'Optional mood theme ID.  If given, you view the data for that theme, otherwise you see just a list of the available mood themes',
               ],
};

$cmd{'ban_set'} = {
    'def' => 'conban.pl',
    'des' => 'Ban another user from posting in your journal.  In the future, banning a user will also prevent them from text messaging you, adding you as a friend, etc... Basically, banning somebody restricts their interaction with you severely.',
    'argsummary' => '<user> [ "from" <community> ]',
    'args' => [
               'user' => "This is the user which the logged in user wants to ban.",
               'community' => "Optional, to ban a user from a community you run.",
               ],
    };

$cmd{'ban_unset'} = {
    'def' => 'conban.pl',
    'des' => 'Remove a ban on a user.',
    'argsummary' => '<user> [ "from" <community> ]',
    'args' => [
               'user' => "The user that will be unbanned by the logged in user.",
               'community' => "Optional, to unban a user from a community you run.",
               ],
    };

$cmd{'ban_list'} = {
    'def' => 'conban.pl',
    'des' => 'List banned users.',
    'argsummary' => '[ "from" <user> ]',
    'args' => [
               'user' => "Optional; list bans in a community you maintain, or any user if you have the 'finduser' priv.",
               ],
    };

$cmd{'friend'} = {
    'handler' => \&friend,
    'des' => 'List your friends, add a friend, or remove a friend.  Optionally, add friends to friend groups.',
    'argsummary' => '<command> [<username>] [<group>] [<fgcolor>] [<bgcolor>]',
    'args' => [
               'command' => "Either 'list' to list friend, 'add' to add a friend, or 'remove' to remove a friend.",
               'username' => "The username of the person to add or remove when using the add or remove command.",
               'group' => "When using command 'add', this optional parameter can list the name of a friend group to add the friend to.  The group must already exist.",
               'fgcolor' => "When using command 'add', this optional parameter specifies the foreground color associated with this friend. The parameter must have the form \"fgcolor=#num\" where 'num' is a 6-digit hexadecimal number.",
               'bgcolor' => "When using command 'add', this optional parameter specifies the background color associated with this friend. The parameter must have the form \"bgcolor=#num\" where 'num' is a 6-digit hexadecimal number.",
               ],
    };

$cmd{'shared'} = {
    'def' => 'conshared.pl',
    'privs' => [qw(sharedjournal)],
    'des' => 'Add or remove access for a user to post in a shared journal.',
    'argsummary' => '<sharedjournal> <action> <user>',
    'args' => [
               'sharedjournal' => "The username of the shared journal.",
               'action' => 'Either <b>add</b> or <b>remove</b>.',
               'user' => "The user you want to add or remove from posting in the shared journal.",
               ],
    };

$cmd{'change_community_admin'} = {
    'def' => 'conshared.pl',
    'privs' => [qw(communityxfer)],
    'des' => 'Change the ownership of a community.',
    'argsummary' => '<community> <new_owner>',
    'args' => [
               'community' => "The username of the community.",
               'new_owner' => "The username of the new owner of the community.",
               ],

};

$cmd{'community'} = {
    'def' => 'conshared.pl',
    'privs' => [qw(sharedjournal)],
    'des' => 'Add or remove a member from a community.',
    'argsummary' => '<community> <action> <user>',
    'args' => [
               'community' => "The username of the community.",
               'action' => 'Only <b>remove</b> is supported right now.',
               'user' => "The user you want to remove from the community.",
               ],
    };

$cmd{'suspend'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(suspend)],
    'des' => 'Suspend a user\'s account.',
    'argsummary' => '<username or email address> <reason>',
    'args' => [
               'username or email address' => "The username of the person to suspend, or an email address to suspend all accounts at that address.",
               'reason' => "Why you're suspending the account.",
               ],
    };

$cmd{'unsuspend'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(suspend)],
    'des' => 'Unsuspend a user\'s account.',
    'argsummary' => '<username or email address> <reason>',
    'args' => [
               'username or email address' => "The username of the person to unsuspend, or an email address to unsuspend all accounts at that address.",
               'reason' => "Why you're unsuspending the account.",
               ],
    };

$cmd{'expunge_userpic'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(siteadmin)],
    'des' => 'Expunge a user picture icon from the site.',
    'argsummary' => '<user> <picid>',
    'args' => [
               'user' => 'The username of the picture owner.',
               'picid' => 'The id of the picture to expunge.',
               ],
    };

$cmd{'getemail'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(suspend)],
    'des' => "Get a user's email address. (for emailing them about TOS violations)",
    'argsummary' => '<user>',
    'args' => [
               'user' => "The username of the person whose email address you'd like to see.",
               ],
    };

$cmd{'get_maintainer'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(finduser)],
    'des' => "Finds out the current maintainer(s) of a community or the communities that a user maintains.  If you pass a community as the argument, the maintainer(s) will be listed.  Otherwise, if you pass a user account, the account(s) they maintain will be listed.",
    'argsummary' => '<community or user name>',
    'args' => [
               'community or user name' => "The username of the account you want to lookup.",
               ],
    };

$cmd{'get_moderator'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(finduser)],
    'des' => "Finds out the current moderator(s) of a community or the communities that a user moderates.  If you pass a community as the argument, the moderator(s) will be listed.  Otherwise, if you pass a user account, the account(s) they moderate will be listed.",
    'argsummary' => '<community or user name>',
    'args' => [
               'community or user name' => "The username of the account you want to lookup.",
               ],
    };

$cmd{'set_underage'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(siteadmin)],
    'des' => "Change a journal's underage flag.",
    'argsummary' => '<journal> <on/off> <note>',
    'args' => [
               'journal' => "The username of the journal that type is changing.",
               'on/off' => "Either 'on' or 'off' which is whether to turn it on or off.",
               'note' => "Required information about why you are setting this status.",
               ],

    };
    
$cmd{'change_journal_type'} = {
    'privs' => [qw(changejournaltype)],
    'handler' => \&change_journal_type,
    'des' => "Change a journal's type.",
    'argsummary' => '<journal> <type> [owner]',
    'args' => [
               'journal' => "The username of the journal that type is changing.",
               'type' => "Either 'person', 'shared', or 'community'.",
               'owner' => "If converting from a person to a community, specify the person to be made maintainer in owner.  If going the other way from community/shared to a person, specify the account to adopt the email address and password of.",
               ],
    };

$cmd{'finduser'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(finduser)],
    'des' => "Find a user by a criteria.",
    'argsummary' => '<criteria> <data>',
    'args' => [
               'criteria' => "Currently the only known criterias are 'email', 'userid', or 'user'",
               'data' => "The thing you know about the user, either their username, userid, or their email address.",
               ],
    };

$cmd{'print'} = {
    'def' => '',
    'des' => "This is a debugging function.  Given an arbitrary number of meaningless arguments, it'll print each one back to you.  If an argument begins with a bang (!) then it'll be printed to the error stream instead.",
    'argsummary' => '...',
    'handler' => sub {
        my ($dbh, $remote, $args, $out) = @_;
        push @{$out}, [ "info", "welcome to 'print', $remote->{'user'}" ];
        shift @$args;
        foreach (@$args) {
            if (/^\!/) {
                push @{$out}, [ "error", $_ ];
            } else {
                push @{$out}, [ "", $_ ];
            }
        }
        return 1;
    },
};

$cmd{'deletetalk'} = {
    'handler' => \&delete_talk,
    'privs' => [qw(deletetalk)],
    'des' => "Delete a comment.",
    'argsummary' => '<user> <itemid> <talkid>',
    'args' => [
               'user' => "The username of the journal comment is in.",
               'itemid' => "The itemid of the post to have a comment deleted from it.",
               # note: the ditemid, actually, but that's too internals-ish?
               'talkid' => "The talkid of the comment to be deleted.",
               ],
    };

$cmd{'faqcat'} = {
    'def' => 'confaq.pl',
    'privs' => [qw(faqcat)],
    'des' => 'Tool for managing FAQ categories.',
    'argsummary' => '<command> <commandargs>',
    'args' => [
               'command' => <<DES,
One of: list, delete, add, move.  'list' shows all the defined FAQ
categories, including their catkey, name, and sortorder.  Also, it
shows all the distinct catkeys that are in use by FAQ.  'add' creates
or modifies a FAQ category.  'delete' removes a FAQ category (but not
the questions that are in it). 'move' moves a FAQ category up or down
in the list.
DES
               'commandargs' => <<DES,
'add' takes 3 arguments: a catkey, a catname, and a sort order field.
'delete' takes one argument: the catkey value.  'move' takes two
arguments: the catkey and either the word "up" or "down".
DES
               ],
    };

$cmd{'help'} = {
    'des' => 'Get help on admin console commands',
    'handler' => \&conhelp,
    'argsummary' => '[<command>]',
    'args' => [
      'command' => "The command to get help on.  If ommitted, prints a list of commands."
    ],
  };

$cmd{'infohistory'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(finduser)],
    'des' => 'Retrieve the infohistory of a given user',
    'argsummary' => '<user>',
    'args' => [
        'user' => "The user whose infohistory is being retrieved.",
    ],
};

$cmd{'set'} = {
    'des' => 'Set a userprop.',
    'handler' => \&set,
    'argsummary' => '["for" <community>] <propname> <value>',
    'args' => [
               'community' => "Community to set property for, if you're a maintainer.",
               'propname' => "Property name to set.",
               'value' => "Value to set property to.",
               ],
    };

 
$cmd{'reset_email'} = {
    'des' => 'Resets the email address for a given account',
    'privs' => [qw(reset_email)],
    'handler' => \&reset_email,
    'argsummary' => '<username> <value> <reason>',
    'args' => [
               'username' => "The account to reset the email address for.",
               'value' => "Email address to set the account to.",
               'reason' => "Reason for the reset",
               ],
    };

$cmd{'reset_password'} = {
    'des' => 'Resets the password for a given account',
    'privs' => [qw(reset_password)],
    'handler' => \&reset_password,
    'argsummary' => '<username> <reason>',
    'args' => [
               'username' => "The account to reset the email address for.",
               'reason' => "Reason for the password reset.",
               ],
    };

$cmd{'syn_editurl'} = {
    'handler' => \&syn_editurl,
    'privs' => [qw(syn_edit)],
    'des' => "Changes the syndication URL for a syndicated account.",
    'argsummary' => '<username> <newurl>',
    'args' => [
               'username' => "The username of the syndicated journal.",
               'newurl' => "The new URL to syndicate the journal from.",
               ],
    };

$cmd{'syn_merge'} = {
    'handler' => \&syn_merge,
    'privs' => [qw(syn_edit)],
    'des' => "Merge two syndicated accounts into one, keeping an optionally specified url for the final. " .
        "Sets up redirection between from_user and to_user, swapping feed urls if there will be a conflict.",
    'argsummary' => '<from_user> to <to_user> [using <url>]',
    'args' => [
               'from_user' => "Syndicated account to merge into another.",
               'to_user'   => "Syndicated account to merge 'from_user' into.",
               'url'       => "Optional.  Url to use for 'to_user' once merge is complete. If none is specified, the 'to_user' URL will be used.",
               ],
    };

$cmd{'allow_open_proxy'} = {
    'handler' => \&allow_open_proxy,
    'privs' => [qw(allowopenproxy)],
    'des' => "Marks an IP address as not being an open proxy for the next 24 hours.",
    'argsummary' => '<ip> <forever>',
    'args' => [
               'ip' => "The IP address to mark as clear.",
               'forever' => "Set to 'forever' if this proxy should be allowed forever.",
               ],
    };

$cmd{'find_user_cluster'} = {
    'handler' => \&find_user_cluster,
    'privs' => [qw(supportviewinternal supporthelp)],
    'des' => "Finds the cluster that the given user's journal is on.",
    'argsummary' => '<user>',
    'args' => [
               'user' => "The user to locate.",
               ],
    };

$cmd{'change_journal_status'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(siteadmin)],
    'des' => "Change the status of an account.",
    'argsummary' => '<account> <status>',
    'args' => [
               'account' => "The account to update.",
               'status' => "One of 'normal', 'memorial', 'locked'.  Memorial accounts allow new comments to entries, locked accounts do not allow further comments.  Entries are blocked either way.",
               ],
    };

$cmd{'tag_display'} = {
    des => 'Set tag visibility to S2.',
    argsummary => '[for <community>] <tag> <value>',
    args => [
        tag => "The tag to change the display value of.  This must be quoted if it contains any spaces.",
        value => "A boolean value: 1/on/true/yes or 0/off/false/no.",
    ],
    handler => sub {
        my ($dbh, $remote, $args, $out) = @_;

        my $err = sub { push @$out, [ "error", $_[0] ]; return 0; };
        my $ok = sub { push @$out, [ "", $_[0] ]; return 1; };

        return $err->("Sorry, the tag system is currently disabled.")
            if $LJ::DISABLED{tags};

        my $foru = $remote;
        my ($tag, $val);

        if (scalar(@$args) == 5) {
            return $err->("Invalid arguments, please see reference.")
                unless $args->[1] eq 'for';
            $foru = LJ::load_user($args->[2]);
            return $err->("Account specified in 'for' parameter invalid.")
                unless $foru;
            ($tag, $val) = @{$args}[3,4];
        } else {
            ($tag, $val) = @{$args}[1,2];
        }

        $val = { 1 => 1, 0 => 0, yes => 1, no => 0, true => 1, false => 0, on => 1, off => 0 }->{$val};

        return $err->("Invalid argument list, please see reference.")
            unless $foru && $tag && defined $val;
        return $err->("You are not allowed to edit the tags for $foru->{user}.")
            unless LJ::Tags::can_control_tags($foru, $remote);
        return $err->("Error changing tag value; please make sure the specified tag exists.")
            unless LJ::Tags::set_usertag_display($foru, name => $tag, $val);

        return $ok->("Tag display value updated.");
    },
};

$cmd{'tag_permissions'} = {
    des => 'Set permission levels for the tag system.',
    argsummary => '[for <community>] <add level> <control level>',
    args => [
        'add level' => 'Accounts at this level are allowed to assign pre-existing tags to entries.  Accounts are not allowed to define new tags or remove tags from entries.  The value can be one of "public", "private", "friends", or the name of a friend group already defined.',
        'control level' => 'Accounts at this level have full control over tags and can define new ones, delete old ones, rename, merge, and perform all other functions of the tags system.  Potential values are the same as in the add level.',
    ],
    handler => sub {
        my ($dbh, $remote, $args, $out) = @_;

        my $err = sub { push @$out, [ "error", $_[0] ]; return 0; };
        my $ok = sub { push @$out, [ "", $_[0] ]; return 1; };

        return $err->("Sorry, the tag system is currently disabled.")
            if $LJ::DISABLED{tags};

        my $foru = $remote;
        my ($add, $control);

        if (scalar(@$args) == 5) {
            return $err->("Invalid arguments, please see reference.")
                unless $args->[1] eq 'for';
            $foru = LJ::load_user($args->[2]);
            return $err->("Account specified in 'for' parameter invalid.")
                unless $foru;
            ($add, $control) = @{$args}[3,4];
        } else {
            ($add, $control) = @{$args}[1,2];
        }

        return $err->("Invalid argument list, please see reference.")
            unless $foru && $add && $control;
        return $err->("You are not allowed to edit the tags for $foru->{user}.")
            unless LJ::can_manage($remote, $foru) || # need to check this in case of 'none' control level
                   LJ::Tags::can_control_tags($foru, $remote);

        my $validate_level = sub {
            my $level = shift;
            return $level if $level =~ /^(?:private|public|none|friends)$/;

            my $grp = LJ::get_friend_group($foru, { name => $level });
            return "group:$grp->{groupnum}" if $grp;

            return undef;
        };

        $add = $validate_level->($add);
        $control = $validate_level->($control);
        return $err->("Levels must be one of: 'private', 'public', 'friends', or the name of a friend's group.")
            unless $add && $control;

        LJ::set_userprop($foru, opt_tagpermissions => "$add,$control");

        return $ok->("Tag system permissions updated.");        
    },
};

sub conhelp 
{
    my ($dbh, $remote, $args, $out) = @_;

    $Text::Wrap::columns = 72;

    my $pr  = sub { foreach (split(/\n/,$_[0])) {
                      push @$out, [ "",      $_ ];
                    } 1; };
    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };

    my $which = $args->[1];
    return $err->("Invalid Arguments") if ($#{$args} > 1);

    unless ($which) 
    {
        # Make a command list.
        foreach my $cmdname (sort keys %LJ::Con::cmd) {
            next if ($LJ::Con::cmd{$cmdname}->{'hidden'});
            my $des = $LJ::Con::cmd{$cmdname}->{'des'};
            my $indent = length($cmdname)+2;
            my $helptext = Text::Wrap::wrap('',' 'x$indent,"$cmdname: $des");
            $pr->($helptext);
        }
        return 1;
    } 

    # Help for a specific command
    return $err->("Command '$which' does not exist here.")
        unless defined $LJ::Con::cmd{$which};
    my $cmd = $LJ::Con::cmd{$which};
    
    $pr->("$which ".$cmd->{'argsummary'});
    $pr->(Text::Wrap::wrap('  ','  ',$cmd->{'des'}));
    if ($cmd->{'args'}) {
        $pr->("  --------");
        my @des = @{$cmd->{'args'}};
        while (my ($arg, $des) = splice(@des, 0, 2)) {
            $pr->("  $arg");
            $pr->(Text::Wrap::wrap('    ','    ',$des));
        }
    }
    return 1;
}

sub delete_talk
{
    my ($dbh, $remote, $args, $out) = @_;

    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };
    my $inf = sub { push @$out, [ "info",  $_[0] ]; 1; };

    return $err->("You do not have the required privilege to use this command.")
        unless $remote->{'priv'}->{'deletetalk'};
    return $err->("This command has 3 arguments") unless @$args == 4;

    my $user = LJ::canonical_username($args->[1]);
    return $err->("First argument must be a username.")	unless $user;

    my $u = LJ::load_user($user);
    return $err->("User '$user' not found.") unless $u;

    my $qitemid = $args->[2]+0;
    return $err->("Second argument must be a positive integer (the itemid).")
        unless $qitemid;

    my $qtalkid = $args->[3]+0;
    return $err->("Third argument must be a positive integer (the talkid).")
        unless $qtalkid;

    my $dbcr = LJ::get_cluster_def_reader($u);
    return $err->("DB unavailable") unless $dbcr;

    my $rid = int($qitemid / 256);  # real post ID
    my $rtid = int($qtalkid / 256); # realk talk ID
    my $state = $dbcr->selectrow_array("SELECT state FROM talk2 WHERE ".
                                       "journalid=$u->{'userid'} AND ".
                                       "jtalkid=$rtid AND nodetype='L' ".
                                       "AND nodeid=$rid");
    return $err->("No talkid with that number found for that itemid.") 
        unless $state;
    return $inf->("Talkid $qtalkid is already deleted.") 
        if $state eq "D";
    
    return $inf->("Success.") 
        if LJ::delete_comments($u, "L", $rid, $rtid);
    return $err->("Error deleting.");
}

sub change_journal_type
{
    my ($dbh, $remote, $args, $out) = @_;

    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };
    my $inf = sub { push @$out, [ "info",  $_[0] ]; 1; };

    my $user = $args->[1];
    my $type = $args->[2];
    my $owner = $args->[3];

    return $err->("Type argument must be 'person', 'shared', or 'community'.")
        unless $type =~ /^(?:person|shared|community)$/;

    my $u = LJ::load_user($user);
    return $err->("User doesn't exist.")
        unless $u;

    return $err->("Account cannot be converted while not active.")
        unless $u->{statusvis} eq 'V';

    return $err->("An account must be a community, shared account, or personal journal to be eligible for conversion.")
        unless $u->{journaltype} =~ /[PCS]/;

    return $err->("This command cannot be used on an account you are logged in as.")
        if LJ::u_equals($remote, $u);

    # take advantage of the fact that we know type...
    return $err->("You cannot convert $type accounts to $type.")
        if $type =~ /^$u->{journaltype}/i;

    # get any owner specified
    my $ou = $owner ? LJ::load_user($owner) : undef;
    return $err->("Owner must be a personal journal.")
        if $ou && $ou->{journaltype} ne 'P';
    return $err->("Owner must be an active account.")
        if $ou && $ou->{statusvis} ne 'V';

    # logic for determining if action is by a manager or a site admin:
    #   byadmin: has changejournaltype priv, and they specified a new owner/parent
    #   bymanager: LJ::can_manage is true and byadmin is false
    my ($byadmin, $bymanager);
    if ($ou) {
        # specified an owner, verify priv
        $byadmin = LJ::check_priv($remote, 'changejournaltype', '');
        return $err->("You cannot specify a new owner for $u->{user} unless you have the changejournaltype privilege.")
            unless $byadmin;
    } else {
        # make sure they're a manager
        $bymanager = LJ::can_manage($remote, $u);
        return $err->("You must be a maintainer of $u->{user} to convert it.")
            unless $bymanager;

        # set $ou to $remote, because it's used in some situations when we have a manager but no admin
        # and we want to verify that the users can't reparent
        $ou = $remote;
    }

    # setup actions hashref with subs to do things.  this doesn't do anything yet.  it is called by
    # the various transformations down below.
    my %actions = (
        # must not have entries by other users in the account
        other_entry_check => sub {
            my $dbcr = LJ::get_cluster_def_reader($u);
            my $count = $dbcr->selectrow_array('SELECT COUNT(*) FROM log2 WHERE journalid = ? AND posterid <> journalid',
                                               undef, $u->{userid});
            return $err->("Account contains $count entries posted by other users and cannot be converted.")
                if $count;           
            return 1;
        },

        # no entries by this user in the account
        self_entry_check => sub {
            my $dbcr = LJ::get_cluster_def_reader($u);
            my $count = $dbcr->selectrow_array('SELECT COUNT(*) FROM log2 WHERE journalid = ? AND posterid = journalid',
                                               undef, $u->{userid});
            return $err->("Account contains $count entries posted by account itself and cannot be converted.")
                if $count;
            return 1;
        },

        # clear out or set relations
        update_rels => sub {
            if (scalar(@_) > 0 && ref $_[0]) {
                # user passed edges to set
                LJ::set_rel_multi(@_);
            } else {
                # clear, they passed a scalar of some sort
                # clear unmoderated, moderator, admin, and posting access edges
                LJ::clear_rel($u->{userid}, '*', $_) foreach qw(N M A P);
            }
        },

        # update/delete community row
        update_commrow => sub {
            my $arg = shift(@_)+0;
            if ($arg) {
                $dbh->do("INSERT INTO community VALUES (?, 'open', 'members')", undef, $u->{userid});
            } else {
                $dbh->do("DELETE FROM community WHERE userid = ?", undef, $u->{userid});
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
                                               undef, $u->{userid});
            # TAG:FR:console:change_journal_type:deletefriendofs
            $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $u->{userid});
            LJ::memcache_kill($_, "friends") foreach @$ids;
        },

        # change some basic user info
        update_user => sub {
            my ($journaltype, $password, $adoptemail) = @_;
            return $err->('Invalid journaltype sent to update_user.')
                unless $journaltype =~ /[PCS]/;
            $password = '' unless defined $password;
            $adoptemail += 0;
            my %extra = ();

            if ($adoptemail) {
                # get email address and setup a validation nag
                my $email = $ou->{email};
                my $aa = LJ::register_authaction($u->{userid}, "validateemail", $email);

                # setup extra stuff so we set it in the user table
                $extra{email} = $email;
                $extra{status} = 'T';

                # create email to send to user
                my $body = "Your email address for $LJ::SITENAME for the $u->{user} account has been reset.  To validate ";
                $body .= "the change, please go to this address:\n\n";
                $body .= "     $LJ::SITEROOT/confirm/$aa->{aaid}.$aa->{authcode}\n\n";
                $body .= "Regards,\n$LJ::SITENAME Team\n\n$LJ::SITEROOT/\n";

                # send email
                LJ::send_mail({
                    to => $email,
                    from => $LJ::ADMIN_EMAIL,
                    subject => "Email Address Reset",
                    body => $body,
                    wrap => 1,
                }) or $err->('Confirmation email could not be sent.');

                # now clear old email address from their infohistory to prevent account hijacking and such
                $dbh->do("UPDATE infohistory SET what='emailreset' WHERE userid=? AND what='email'", undef, $u->{userid})
                    or $err->("Error updating infohistory for emailreset: " . $dbh->errstr);
                LJ::infohistory_add($u, 'emailreset', $u->{email}, $u->{status})
                    unless $email eq $u->{email}; # record only if it changed
            }

            # password changed too?
            LJ::infohistory_add($u, 'password', Digest::MD5::md5_hex($u->{password} . 'change'))
                if $password ne $u->{password};
            
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
        if ($u->{journaltype} eq 'P') {
            # person -> comm, admins only
            return $err->("Not authorized.  Please verify you have the changejournaltype privilege and you specified an owner/parent.")
                unless $byadmin;

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
                     [ 'update_user', 'C', '', $byadmin ? 1 : 0 ]);
        }

    # or to a shared journal
    } elsif ($type eq 'shared') {
        # from?
        if ($u->{journaltype} eq 'P') {
            # person -> shared, admins only
            return $err->("Not authorized.  Please verify you have the changejournaltype privilege and you specified an owner/parent.")
                unless $byadmin;

            # actions to take
            @todo = ([ 'update_rels', 
                         [ $u->{userid}, $ou->{userid}, 'A' ],
                         [ $u->{userid}, $ou->{userid}, 'P' ], # make $ou a maintainer of $u, and have posting access
                     ],
                     [ 'clear_friends' ],
                     [ 'update_user', 'S', $ou->{password}, 1 ]);

        } elsif ($u->{journaltype} eq 'C') {
            # comm -> shared, anybody can do
            @todo = ([ 'update_commrow', 0 ],
                     [ 'update_user', 'S', $ou->{password}, $byadmin ? 1 : 0 ]);
        }

    # or finally perhaps to a person
    } elsif ($type eq 'person') {
        # all conversions to a person must go through these checks
        return $err->("Not authorized.  Please verify you have the changejournaltype privilege and you specified an owner/parent.")
            unless $byadmin;
        return unless $actions{other_entry_check}->();

        # doesn't matter what they're coming from, as long as they're coming from something valid
        if ($u->{journaltype} =~ /[CS]/) {
            @todo = ([ 'update_rels', 0 ],
                     [ 'clear_friends' ],
                     [ 'update_commrow', 0 ],
                     [ 'update_user', 'P', $ou->{password}, 1 ]);
        }
    }

    # register this action in statushistory
    LJ::statushistory_add($u->{userid}, $remote->{userid}, "change_journal_type", "account '$u->{user}' converted to $type" .
                                                          ($ou ? " (owner/parent is '$ou->{user}')" : '(no owner/parent)'));
    
    # now run the requested actions
    foreach my $row (@todo) {
        my $which = ref $row ? shift(@{$row || []}) : $row;
        if (ref $actions{$which} eq 'CODE') {
            # call subref, passing arguments left in $row
            $actions{$which}->(@{$row || []});
        } else {
            $err->("Requested action $which not found.  Please notify site administrators of this error.");
        }
    }
    
    # done
    return $inf->("User: $u->{user} converted to a $type account.");
}

sub foreach_entry
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;
    my $sth;

    my @conds;
    my $action;
    my $action_found;

    for (my $i=1; $i<scalar(@$args); $i++) {
        if ($args->[$i] eq "action") {
            $action_found = 1;
        } elsif (! $action_found) {
            push @conds, $args->[$i];
        } else {
            if ($action) {
                $error = 1;
                push @$out, [ "error", "Only one action is supported at a time." ];
            } else {
                $action = $args->[$i];
            }
        }
    }

    unless ($action_found && $action) {
        $error = 1;
        push @$out, [ "error", "No actions given." ];
    }

    unless ($remote) {
        $error = 1;
        push @$out, [ "error", "You're not logged in." ];
    }
    
    return 0 if ($error);

    my @itemids;
    
    # security conditions
    my $secand;
    my $seccount = 0;

    foreach my $cond (@conds) {
        if ($cond eq "security=private") { $secand .= " AND security='private'"; $seccount++; }
        if ($cond eq "security=public") { $secand .= " AND security='public'"; $seccount++; }
        if ($cond eq "security=friends") { $secand .= " AND security='usemask' AND allowmask = 1"; $seccount++; }
        if ($cond eq "security=custom") { $secand .= " AND security='usemask' AND allowmask <> 1"; $seccount++; }
        if ($cond eq "!security=private") { $secand .= " AND security<>'private'"; }
        if ($cond eq "!security=public") { $secand .= " AND security<>'public'";  }
        if ($cond eq "!security=friends") { $secand .= " AND (security<>'usemask' OR allowmask <> 1)"; }
        if ($cond eq "!security=custom") { $secand .= " AND (security<>'usemask' OR allowmask = 1)"; }
    }

    if ($seccount > 1) {
        ## TODO: bitch.  that's pointless.
    }

    $sth = $dbh->prepare("SELECT itemid FROM log WHERE ownerid=$remote->{'userid'} $secand ORDER BY itemid");
    $sth->execute;
    if ($dbh->err) { push @$out, [ "error", $dbh->errstr ] }
    push @itemids, $_ while ($_ = $sth->fetchrow_array);
    $sth->finish;

    if ($action eq "list") 
    {
        while (@itemids) {
            push @$out, [ "info", "-----" ];
            my @chunk;
            if (@itemids < 200) { @chunk = @itemids; @itemids = (); }
            else { @chunk = splice(@itemids, 0, 200); }
            my $in = join(",",@chunk);
            $sth = $dbh->prepare("SELECT l.itemid, l.eventtime, lt.subject FROM log l, logtext lt WHERE l.itemid=lt.itemid AND l.itemid IN ($in) ORDER BY l.itemid");
            $sth->execute;
            while (my ($itemid, $eventtime, $subject) = $sth->fetchrow_array) {
                push @$out, [ "", sprintf("%9d | %19s | %s", $itemid, $eventtime, $subject) ];	
            }
            $sth->finish;
        }
    } else {
        
        push @$out, [ "info", "not implemented." ];	

    }

    push @$out, [ "info", "the end.  (btw, this command isn't done yet)" ];	

    return 1;
    
}

sub friend
{
    my ($dbh, $remote, $args, $out) = @_;

    my $command = $args->[1];
    my $quserid = $remote->{'userid'}+0;

    if ($command eq "list") 
    {
        # TAG:FR:console:friend:getfriends
        my $sth = $dbh->prepare("SELECT u.user, u.name, u.statusvis, u.journaltype FROM user u, friends f ".
                                "WHERE u.userid=f.friendid AND f.userid=$quserid ORDER BY u.user");
        $sth->execute;
        push @$out, [ "", sprintf("%-15s S T  Name", "User") ];
        push @$out, [ "", "-"x58 ];
        while (my ($user, $name, $statusvis, $type) = $sth->fetchrow_array)
        {
            push @$out, [ "", sprintf("%-15s %1s %1s  %s", 
                                      $user, 
                                      ($statusvis ne "V" ? $statusvis : ""), 
                                      ($type ne "P" ? $type : ""), 
                                      $name) ];
        }

        return 1;
    }

    if ($command eq "add" || $command eq "remove") 
    {
        my $friend = $args->[2];
        my $err;
        my $fid = LJ::get_userid($friend);
        if (! $fid) {
            push @$out, [ "error", "Unknown friend \"$friend\"" ];
            return 0;
        }
        if ($command eq "remove") {
            my $oreq = LJ::Protocol::do_request("editfriends", {
                'username' => $remote->{'user'},
                'ver'      => $LJ::PROTOCOL_VER,
                'delete'   => [$friend],
            }, \$err, {'noauth'=>1});
            if($err) {
                push @$out, [ "error", $err ];
            } else {
                push @$out, [ "", "$friend removed from friends list" ];
            }
        } elsif ($command eq "add") {
            my ($group, $fg, $bg);
            foreach(@{$args}[3..5]) {
                last unless $_;
                $fg = $1 and next if m!fgcolor=(.*)!;
                $bg = $1 and next if m!bgcolor=(.*)!;
                $group = $_;
            }
            my $gmask = 0;
            if ($group ne "") {
                my $group = LJ::get_friend_group($remote->{userid}, { name => $group });
                my $num = $group ? $group->{groupnum}+0 : 0;
                if ($num) {
                    $gmask = 1 << $num;
                } else {
                    push @$out, [ "error", "You don't have a group called \"$group\"" ];
                }
            }
    
            my $fhash = {'username' => $friend};
            $fhash->{'groupmask'} = $gmask if $gmask;
            $fhash->{'fgcolor'} = $fg if $fg;
            $fhash->{'bgcolor'} = $bg if $bg;

            my $oreq = LJ::Protocol::do_request("editfriends", {
                'username' => $remote->{'user'},
                'ver'      => $LJ::PROTOCOL_VER,
                'add'      => [$fhash],
            }, \$err, {'noauth'=>1});
            if($err) {
                push @$out, [ "error", $err ];
            } else {
                push @$out, [ "", "$friend added as a friend" ];
            }

        }
        return 1;
    }

    push @$out, [ "error", "Invalid command.  See reference." ];
    return 0;

}

sub set
{
    my ($dbh, $remote, $args, $out) = @_;
    my $err = sub { push @$out, [ "error", $_[0] ]; return 0; };
    
    return $err->("You need to be logged in to use this command.")
        unless $remote;

    my $u = $remote;

    my @args = @$args;
    shift @args;  # remove command name "set"

    if ($args[0] eq "for") {
        shift @args;
        my $comm = shift @args;
        $u = LJ::load_user($comm);
        return $err->("Community doesn't exist.") unless $u;
        return $err->("You're not an admin of this community.")
            unless LJ::can_manage_other($remote, $u);
    }
    return $err->("Wrong number of arguments") unless @args == 2;
    my ($k, $v) = @args;
    return $err->("Unknown property") unless ref $LJ::SETTER{$k} eq "CODE";

    my $errmsg;
    my $rv = $LJ::SETTER{$k}->($dbh, $u, $remote, $k, $v, \$errmsg);
    return $err->($errmsg) unless $rv;

    push @$out, [ '', "User property '$k' set to '$v'." ];
    return 1;
}

sub reset_email
{
    my ($dbh, $remote, $args, $out) = @_;
    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };
    my $inf = sub { push @$out, [ "info",  $_[0] ]; 1; };

    return $err->("This command has 3 arguments") unless @$args == 4;

    return $err->("$remote->{'user'}, you are not authorized to use this command.")
        unless ($remote->{'priv'}->{'reset_email'});

    my $user = $args->[1];
    my $u = LJ::load_user($user);
    my $userid = $u->{userid};

    return $err->("Invalid user $user") unless ($userid);

    my $email = $args->[2];
    my $aa = LJ::register_authaction($userid, "validateemail", $email);

    LJ::infohistory_add($u, 'emailreset', $u->{email}, $u->{status})
        if $u->{email} ne $email;

    LJ::update_user($userid, { email => $email, status => 'T' })
        or return $err->("A database error has occurred");

    my $body;
    $body .= "Your email address for $LJ::SITENAME has been reset.  To validate the change, please go to this address:\n\n";
    $body .= "     $LJ::SITEROOT/confirm/$aa->{'aaid'}.$aa->{'authcode'}\n\n";
    $body .= "Regards,\n$LJ::SITENAME Team\n\n$LJ::SITEROOT/\n";

    LJ::send_mail({
        'to' => $email,
        'from' => $LJ::ADMIN_EMAIL,
        'subject' => "Email Address Reset",
        'body' => $body,
    }) or $inf->("Confirmation email could not be sent.");

    $dbh->do("UPDATE infohistory SET what='emailreset' WHERE userid=? AND what='email'",
             undef, $userid) or return $err->($dbh->errstr);

    my $reason = $args->[3];
    LJ::statushistory_add($userid, $remote->{'userid'}, "reset_email", $reason);

    push @$out, [ '', "Address reset." ];
    return 1;
}

sub syn_editurl
{
    my ($dbh, $remote, $args, $out) = @_;
    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };

    return $err->("This command has 2 arguments") unless @$args == 3;

    return $err->("You are not authorized to use this command.")
        unless ($remote && $remote->{'priv'}->{'syn_edit'});

    my $user = $args->[1];
    my $newurl = $args->[2];
    my $u = LJ::load_user($user);

    return $err->("Invalid user $user") unless $u;
    return $err->("Not a syndicated account") unless $u->{'journaltype'} eq 'Y';
    return $err->("Invalid URL") unless $newurl =~ m!^http://(.+?)/!;

    my $oldurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?",
                                       undef, $u->{userid});

    $dbh->do("UPDATE syndicated SET synurl=? WHERE userid=?", undef,
             $newurl, $u->{'userid'});
    if ($dbh->err)
    {
        push @$out, [ 'error', "URL for account $user not changed - Duplicate Entry" ];
    } else {
        push @$out, [ '', "URL for account $user changed: $oldurl => $newurl ." ];

        # log to statushistory
        LJ::statushistory_add($u->{userid}, $remote->{userid}, 'synd_edit',
                              "URL changed: $oldurl => $newurl");
    }
    return 1;
}

sub syn_merge
{
    my ($dbh, $remote, $args, $out) = @_;
    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };

    return $err->("You are not authorized to use this command.")
        unless ($remote && $remote->{'priv'}->{'syn_edit'});

    return $err->("This command takes 5 arguments.")
        unless @$args == 6; # 0 is 'syn_merge'

    return $err->("Second argument must be 'to'.")
        unless $args->[2] eq 'to';

    return $err->("Fourth argument must be 'using'.")
        if $args->[4] ne 'using';

    my $from_user = LJ::canonical_username($args->[1]);
    my $from_u = LJ::load_user($from_user)
        or return $err->("Invalid user: '$from_user'.");
    my $from_userid = $from_u->{userid};

    my $to_user = LJ::canonical_username($args->[3]);
    my $to_u = LJ::load_user($to_user)
        or return $err->("Invalid user: '$to_user'.");
    my $to_userid = $to_u->{userid};

    foreach ($to_u, $from_u) {
        return $err->("Invalid user: '$_->{user}' (statusvis=$_->{statusvis}, already merged?)")
            unless $_->{statusvis} eq 'V';
    }

    my $url = LJ::CleanHTML::canonical_url($args->[5])
        or return $err->("Invalid url.");

    # 1) set up redirection for 'from_user' -> 'to_user'
    LJ::update_user($from_u, { 'journaltype' => 'R', 'statusvis' => 'R' });
    LJ::set_userprop($from_u, 'renamedto' => $to_user)
        or return $err->("Unable to set userprop.  Database unavailable?");

    # 2) update the url of the destination syndicated account
    # if the from_u's url is the same as what we're about to set the to_u's url to, then
    # we'll get a duplicate key error.  if this is the case, our behavior will be to 
    # swap the two.
    my $urls = $dbh->selectall_hashref("SELECT userid, synurl FROM syndicated " .
                                       "WHERE userid=? OR userid=?",
                                       'userid', undef, $from_userid, $to_userid);
    return $err->("Missing 'syndicated' rows: Possible corruption?")
        unless $urls && $urls->{$from_userid} && $urls->{$to_userid};

    if ($urls->{$from_userid}->{synurl} eq $url) {

        # clear the to_u's synurl, we'll update it back in a sec
        $dbh->do("UPDATE syndicated SET synurl=NULL WHERE userid=?",
                 undef, $to_userid);

        # now update from_u's url to be to_u's old url
        $dbh->do("UPDATE syndicated SET synurl=? WHERE userid=?",
                 undef, $urls->{$to_userid}->{synurl}, $from_userid);
        return $err->("Database Error: " . $dbh->errstr) if $dbh->err;
    }

    # after possibly swapping above, update the to_u's synurl
    # ... should have no errors
    $dbh->do("UPDATE syndicated SET synurl=? WHERE userid=?",
             undef, $url, $to_userid);
    return $err->("Database Error: " . $dbh->errstr) if $dbh->err;

    # 3) make users who befriend 'from_user' now befriend 'to_user'
    #    'force' so we get master db and there's no row limit
    if (my @ids = LJ::get_friendofs($from_u, { force => 1 } )) {

        # update ignore so we don't raise duplicate key errors
        $dbh->do("UPDATE IGNORE friends SET friendid=? WHERE friendid=?",
                 undef, $to_userid, $from_userid);
        return $err->("Database Error: " . $dbh->errstr) if $dbh->err;

        # in the event that some rows in the update above caused a duplicate key error,
        # we can delete the rows that weren't updated, since they don't need to be
        # processed anyway
        $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $from_userid);
        return $err->("Database Error: " . $dbh->errstr) if $dbh->err;

        # clear memcache keys
        LJ::memcache_kill($_, 'friend') foreach @ids;
    }

    # log to statushistory
    foreach ($from_userid, $to_userid) {
        LJ::statushistory_add($_, $remote->{userid}, 'synd_merge',
                              "Merged $from_user => $to_user using URL: $url");
    }

    push @$out, [ '', "Syndicated accounts merged: '$from_user' to '$to_user'" ];
}

sub reset_password
{
    my ($dbh, $remote, $args, $out) = @_;
    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };
    my $inf = sub { push @$out, [ "info",  $_[0] ]; 1; };

    return $err->("This command takes exactly 2 arguments") unless @$args == 3;

    return $err->("$remote->{'user'}, you are not authorized to use this command.")
        unless $remote->{'priv'}->{'reset_password'};

    my $user = $args->[1];
    my $u = LJ::load_user($user);

    return $err->("Invalid user $user") unless $u;

    my $newpass = LJ::rand_chars(8);
    my $oldpass = Digest::MD5::md5_hex($u->{'password'} . "change");
    my $rval = LJ::infohistory_add($u, 'passwordreset', $oldpass);
    return $err->("Failed to insert old password into information history table") unless $rval;

    LJ::update_user($u, { password => $newpass, })
        or return $err->("Failed to update user table");

    $u->kill_all_sessions;

    my $body = "The password for your $LJ::SITENAME account '$u->{'user'}' has been reset to:\n\n";
    $body .= "     $newpass\n\n";
    $body .= "Please change it immediately by going to:\n\n";
    $body .= "     $LJ::SITEROOT/changepassword.bml\n\n";
    $body .= "Regards,\n$LJ::SITENAME Team\n\n$LJ::SITEROOT/\n";

    LJ::send_mail({
        'to' => $u->{'email'},
        'from' => $LJ::ADMIN_EMAIL,
        'subject' => "Password Reset",
        'body' => $body,
    }) or $inf->("Notification email could not be sent.");

    my $reason = $args->[2];
    LJ::statushistory_add($u->{'userid'}, $remote->{'userid'}, "reset_password", $reason);

    push @$out, [ '', "Password reset." ];
    return 1;
}

sub allow_open_proxy
{
    my ($dbh, $remote, $args, $out) = @_;
    my $err = sub { push @$out, [ "error", $_[0] ]; 0; };

    return $err->('This command requires 1 or 2 arguments.') unless @$args == 2 || @$args == 3;

    return $err->('You are not authorized to use this command.')
        unless $remote && $remote->{priv}->{allowopenproxy};

    my $ip = $args->[1];
    return $err->('That is an invalid IP address.')
        unless $ip =~ /^(?:\d{1,3}\.){3}\d{1,3}$/;
    return $err->('That IP address is not an open proxy.')
        unless LJ::is_open_proxy($ip);

    my $forever = $args->[2];
    my $asof = $forever ? "'0'" : "UNIX_TIMESTAMP()";
    $dbh->do("REPLACE INTO openproxy VALUES (?, 'clear', $asof, ?)",
             undef, $ip, "Manual: $remote->{user}");
    return $err->($dbh->errstr) if $dbh->err;

    my $period = $forever ? "forever" : "for the next 24 hours";
    push @$out, [ '', "$ip cleared $period." ];
    return 1;
}

sub find_user_cluster
{
    my ($dbh, $remote, $args, $out) = @_;
    my $err = sub { push @$out, ["error", $_[0] ]; 0; };

    return $err->('This command requires an argument.') unless @$args == 2;

    return $err->('You are not authorized to use this command.')
        unless $remote && ($remote->{priv}->{supportviewinternal} || $remote->{priv}->{supporthelp}) ;

    my $u = LJ::load_user($args->[1]);
    return $err->('Unable to load given user.') unless $u;

    my $cluster = LJ::get_cluster_description($u->{clusterid}, 0);
    push @$out, [ '', "$u->{user} is on the $cluster cluster." ];

    return 1;
}

sub fb_push
{
    my $u = LJ::want_user( shift() );
    return unless $u && LJ::get_cap( $u, 'fb_account' );
    return Apache::LiveJournal::Interface::FotoBilder::push_user_info( $u->{userid} );
}

1;
