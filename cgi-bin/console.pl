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
                my $userid = $userids{$username};
                my $desc = sprintf(qq{%s: "%s" with arg "%s"},
                                   $is_grant ? "Granting" : "Denying",
                                   $privcode, $arg);

                if ($sth->execute($userid, $prlid, $arg)) {
                    $success->($out, "$desc to $username");
                    LJ::statushistory_add($userid, $remote->{userid},
                                          $is_grant ? "privadd" : "privdel",
                                          $desc);
                } else {
                    $result = $fail->($out, "DB failure: $desc to $username: " . $sth->errstr);
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
               'action' => 'Either <b>add</b> or <b>remove</b>.',
               'user' => "The user you want to add or remove from the community.",
               ],
    };

$cmd{'suspend'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(suspend)],
    'des' => 'Suspend a user\'s account.',
    'argsummary' => '<user> <reason>',
    'args' => [
               'user' => "The username of the person to suspend.",
               'reason' => "Why you're suspending the account.",
               ],
    };

$cmd{'unsuspend'} = {
    'def' => 'consuspend.pl',
    'privs' => [qw(suspend)],
    'des' => 'Unsuspend a user\'s account.',
    'argsummary' => '<user> <reason>',
    'args' => [
               'user' => "The username of the person to unsuspend.",
               'reason' => "Why you're unsuspending the account.",
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
    'des' => "Finds out the current maintainer(s) of a community",
    'argsummary' => '<community name>',
    'args' => [
               'community name' => "The username of the community you want to lookup.",
               ],
    };
    
$cmd{'change_journal_type'} = {
    'privs' => [qw(changejournaltype)],
    'handler' => \&change_journal_type,
    'des' => "Change a journal's type from community to either person (regular), or a shared journal.",
    'argsummary' => '<journal> <type>',
    'args' => [
               'journal' => "The username of the journal that type is changing.",
               'type' => "Either 'person' or 'shared'",
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

    my $dbcm = LJ::get_cluster_master($u);
    return $err->("DB unavailable") unless $dbcm;

    my $rid = int($qitemid / 256);  # real post ID
    my $rtid = int($qtalkid / 256); # realk talk ID
    my $state = $dbcm->selectrow_array("SELECT state FROM talk2 WHERE ".
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

    return $err->("Type argument must be 'person' or 'shared'")
        unless $type eq "person" || $type eq "shared";

    my $u = LJ::load_user($user);
    return $err->("User doesn't exist.")
        unless $u;

    return $err->("$remote->{'user'}, you are not authorized to use this command.")
        unless $remote->{'priv'}->{'changejournaltype'} ||
               LJ::can_manage($remote, $u);

    return $err->("$u->{'user'} is not a community, so can't change type.")
        unless $u->{'journaltype'} eq "C";

    $dbh->do("DELETE FROM community WHERE userid=?", undef, $u->{'userid'});

    # if we're changing a non-person account to a person account,
    # we need to ditch all its friend-ofs so that old users befriending
    # that account (in order to watch it), don't give the account maintainer
    # access to read the old reader's friends-only posts.  (which they'd now
    # be able to do, since journaltype=='P'.
    $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $u->{'userid'});
    
    if ($type eq "person") {
        LJ::update_user($u, { journaltype => 'P' });
        LJ::clear_rel($u->{'userid'}, '*', 'P'); # post
        LJ::clear_rel($u->{'userid'}, '*', 'A'); # admin
        LJ::clear_rel($u->{'userid'}, '*', 'M'); # moderate

    } elsif ($type eq "shared") {
        LJ::update_user($u, { journaltype => 'S' });
    }

    return $inf->("User: $u->{'user'} converted.");
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
        my $sth = $dbh->prepare("SELECT u.user, u.name, u.statusvis, u.journaltype FROM user u, friends f WHERE u.userid=f.friendid AND f.userid=$quserid ORDER BY u.user");
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
                my $qgroup = $dbh->quote($group);
                my $num = $dbh->selectrow_array("SELECT groupnum FROM friendgroup ".
						"WHERE userid=$quserid AND groupname=$qgroup");
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
            unless LJ::check_rel($u, $remote, 'A');
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
    my $userid = LJ::get_userid($user);

    return $err->("Invalid user $user") unless ($userid);

    my $email = $args->[2];
    my $aa = LJ::register_authaction($userid, "validateemail", $email);

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

    $dbh->do("UPDATE syndicated SET synurl=? WHERE userid=?", undef,
             $newurl, $u->{'userid'});
    if ($dbh->err)
    {
        push @$out, [ 'error', "URL for account $user not changed - Duplicate Entry" ];
    } else {
        push @$out, [ '', "URL for account $user changed to $newurl ." ];
    }
    return 1;
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
    my $oldpass = $dbh->quote(Digest::MD5::md5_hex($u->{'password'} . "change"));
    $dbh->do("INSERT INTO infohistory (userid, what, oldvalue, timechange) VALUES ($u->{'userid'}, 'passwordreset', $oldpass, NOW())");
    return $err->("Failed to insert old password into information history table") if $dbh->err;

    LJ::update_user($u, { password => $newpass, })
        or return $err->("Failed to update user table");

    LJ::kill_all_sessions($u);

    my $body = "The password for your $LJ::SITENAME account '$u->{'user'}' has been reset to:\n\n";
    $body .= "     $newpass\n\n";
    $body .= "Please change it immediately by going to:\n$LJ::SITEROOT/changepassword.bml\n\n";
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

1;
