package LJ::Console::Command::TagPermissions;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "tag_permissions" }

sub desc { "Set tagging permission levels for an account." }

sub args_desc { [
                 'community' => "Optional; community to change permission levels for.",
                 'add level' => "Accounts at this level can add existing tags to entries. One of 'public', 'friends', 'private', 'author_moder' or a custom friend group name.",
                 'control level' => "Accounts at this level can do everything: add, remove, and create new ones. Value is one of 'public', 'friends', 'private', or a custom friend group name.",
                 'merge level' => "Accounts at this level can merge and rename tags. Value is one of 'private' or 'owner'. Only for community.",
                 ] }

sub usage { '[ "for" <community> ] <add level> <control level> <merge level>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return $self->error("Sorry, the tag system is currently disabled.")
        if $LJ::DISABLED{tags};

    return $self->error("This command takes either three or five arguments. Consult the reference.")
        unless scalar(@args) == 3 || scalar(@args) == 5;

    my $remote = LJ::get_remote();
    my $foru = $remote;            # may be overridden later
    my ($add, $control, $merge);

    if (scalar(@args) == 4) {
        return $self->error("Invalid arguments. First argument must be 'for'")
            if $args[0] ne "for";

        $foru = LJ::load_user($args[1]);
        return $self->error("Invalid account specified in 'for' parameter.")
            unless $foru;

        return $self->error("You cannot change tag permission settings for $args[1]")
            unless $remote && $remote->can_manage($foru);

        ($add, $control, $merge) = ($args[2], $args[3], $args[4]);
    } else {
        ($add, $control, $merge) = ($args[0], $args[1], $args[2]);
    }

    my $validate_level = sub {
        my $level = shift;
        return $level if $level =~ /^(?:private|public|none|friends|author_moder|owner)$/;

        my $grp = LJ::get_friend_group($foru, { name => $level });
        return "group:$grp->{groupnum}" if $grp;

        return undef;
    };

    $add = $validate_level->($add);
    $control = $validate_level->($control);
    $merge = $validate_level->($merge);
    return $self->error("Levels must be one of: 'private', 'public', 'friends', 'author_moder', 'owner' or the name of a friends group.")
        unless $add && $control && $merge;
    return $self->error("Only <add level> can be 'author_moder'") 
        if $control eq 'author_moder' || $merge eq 'author_moder';
    return $self->error("'author_moder' level can be applied to communities only")
        if $add eq 'author_moder' && !$foru->is_community;
    return $self->error("Only <merge level> can be 'owner'") 
        if $control eq 'owner' || $add eq 'owner';
    return $self->error("'owner' level can be applied to communities only")
        if $merge eq 'owner' && !$foru->is_community;
    return $self->error("<merge level> can be 'private' or 'owner' only")
        if $merge && $merge !~ /^(private|owner)$/;

    $foru->set_prop('opt_tagpermissions', "$add,$control,$merge");

    return $self->print("Tag permissions updated for " . $foru->user);
}

1;
