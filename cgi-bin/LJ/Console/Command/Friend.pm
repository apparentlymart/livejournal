package LJ::Console::Command::Friend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);
use LJ::FriendsTags;

sub cmd { "friend" }

sub desc { "List your friends or add/remove a user from your friends list." }

sub args_desc { [
                 'command' => "Either 'list' to list friend, 'list_tags' to view friends page filter tags, 'add' to add a friend, or 'remove' to remove a friend.",
                 'user' => "The username of the person to add or remove when using the add or remove command.",
                 'group' => "Optional; when using 'add', adds the user to this friend group. It must already exist.",
                 'fgcolor' => "Optional; when using 'add', specifies the foreground color. Must be of form 'fgcolor=#hex'",
                 'bgcolor' => "Optional; when using 'add', specifies the background color. Must be of form 'bgcolor=#hex'",
                 ] }

sub usage { '<command> <user> [ <group> ] [ <fgcolor> ] [ <bgcolor> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, 'siteadmin') ||
           LJ::check_priv($remote, 'supporthelp') ||
           LJ::check_priv($remote, 'betatest', 'omega') ||
           $LJ::IS_DEV_SERVER;
}

sub execute {
    my ($self, $command, $user, @args) = @_;

    return $self->error("This command takes at least one argument, and no more than five. Consult the reference.")
        unless $command && scalar(@args) <= 3;

    return $self->error("Invalid command. Must be one of: 'list', 'add', or 'remove'.")
        unless $command =~ /^(?:list|list_tags|add|remove)$/;

    my $remote = LJ::get_remote();

    if ($command eq 'list' || $command eq 'list_tags') {

        my $fu = LJ::load_user($user);
        return $self->error("Invalid username: $user")
            unless $fu;

        unless (LJ::check_priv($remote, 'canview', 'friends')) {
            return $self->error("You are not allowed to view other's friends")
                if $fu->id != $remote->id;
        }

        my $friends = $fu->friends();

        if ($command eq 'list') {
            $self->info(sprintf("%-15s S T  Name", "User"));
            $self->info("-" x 58);

            foreach my $u (values %$friends) {
                my $type = $u->journaltype eq "P" ? "" : $u->journaltype;
                my $statusvis = $u->statusvis eq "V" ? "" : $u->statusvis;
                $self->info(sprintf("%-15s %1s %1s  %s", $u->username, $statusvis, $type, $u->name));
            }
        }
        elsif ($command eq 'list_tags') {
            my $tags_by_friendid = LJ::FriendsTags->load_tags($fu);

            my $get_tags_str = sub {
                my $tags_data = shift;

                my $tags_str = '';
                return '' unless $tags_data && ref($tags_data) eq 'ARRAY';
                my ($mode, $tags_list) = @$tags_data;
                $mode ||= 'A';
                $tags_list = [] unless $tags_list && ref($tags_list) eq 'ARRAY';
                return ($mode eq 'D' ? '- ' : '+ ') . join(', ', @$tags_list);
            };

            $self->info(sprintf("%-15s S T  Tags", "User"));
            $self->info("-" x 58);

            foreach my $u (values %$friends) {
                my $type = $u->journaltype eq "P" ? "" : $u->journaltype;
                my $userid = $u->id;
                my $statusvis = $u->statusvis eq "V" ? "" : $u->statusvis;

                $self->info(sprintf("%-15s %1s %1s  %s", $u->username, $statusvis, $type,
                                    $get_tags_str->($tags_by_friendid->{$userid})));

                delete $tags_by_friendid->{$userid};
            }

            if (keys %$tags_by_friendid) {
                $self->info("");
                $self->info("--- Not Friends " . "-" x 42);
                while (my ($friendid, $tags_data) = each %$tags_by_friendid) {
                    my $u = LJ::load_userid($friendid);
                    my $username = $u ? $u->user : "userid=$friendid";
                    $self->info(sprintf("%-15s      %s", $username, $get_tags_str->($tags_data)));
                }
            }
        }

        return 1;
    }

    # at this point we're doing an add or a remove
    my $fu = LJ::load_user($user);
    return $self->error("Invalid username: $user")
        unless $fu;

    if ($command eq "remove") {
        return $self->error("$user is not on your friends list")
            unless $remote->has_friend($fu);

        if ($remote->remove_friend($fu)) {
            return $self->print("$user removed from friends list.");
        } else {
            return $self->error("Error removing $user from friends list.")
        }
    }

    if ($command eq "add") {
        unless (LJ::is_enabled('new_friends_and_subscriptions')) {
            my $errmsg;
            return $self->error($errmsg)
                unless $remote->can_add_friends(\$errmsg, {friend => $fu});
        }

        return $self->error("You cannot add inactive journals to your Friends list.")
            unless $fu->is_visible;

        my ($group, $fg, $bg);
        foreach (@args) {
            last unless $_;
            $fg = $1 and next if m!fgcolor=(.*)!;
            $bg = $1 and next if m!bgcolor=(.*)!;
            $group = $_;
        }

        my $gmask = 0;
        if ($group ne "") {
            my $grp = LJ::get_friend_group($remote->id, { name => $group });
            my $num = $grp ? $grp->{groupnum}+0 : 0;
            if ($num) {
                $gmask = 1 | 1 << $num; # friends-only bit, group bit
            } else {
                $self->error("You don't have a group called '$group'.");
            }
        } else {
            $gmask = LJ::get_groupmask($remote, $fu);
        }

        my $opts = {};
        $opts->{'groupmask'} = $gmask if $gmask;
        $opts->{'fgcolor'} = $fg if $fg;
        $opts->{'bgcolor'} = $bg if $bg;

        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            unless ($remote->to_offer_friendship($fu)) {
                return $self->error("Error invite sending $user.");
            }
        } else {
            if ($remote->add_friend($fu, $opts)) {
                return $self->print("$user added as a friend.");
            } else {
                return $self->error("Error adding $user to friends list.");
            }
        }
    }
}

1;
