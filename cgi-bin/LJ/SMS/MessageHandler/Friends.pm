package LJ::SMS::MessageHandler::Friends;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $text = $msg->body_text;
    my $u    = $msg->from_u;

    my ($group) = $text =~ /
        ^\s*
        fr(?:iends)?              # post full or short

        (?:\.                     # optional friends group setting
         (
          (?:\"|\').+?(?:\"|\')   # single or double quoted friends group
          |
          \S+)                    # single word friends group
         )?

         \s*$/ix;

    # for quoted strings, the 'group' segment will still have single or double quotes
    if ($group) {
        $group =~ s/^(?:\"|\')//;
        $group =~ s/(?:\"|\')$//;
    }

    # if no group specified, see if they have a default friend group prop set
    $group ||= $u->prop('sms_friend_group');

    # try to find the requested friends group and construct a filter mask
    my $filter;
    if ($group) {
        my $groups = LJ::get_friend_group($u);
        while (my ($bit, $grp) = each %$groups) {
            next unless $grp->{groupname} =~ /^$group$/i;

            # found the security group the user is asking for
            $filter = 1 << $grp->{groupnum};

            last;
        }

        # if there is no match then the loop above will
        # fall through to here where filter isn't set, 
        # resulting in an unfiltered final view
    }

    my @entries = LJ::get_friend_items({
        remoteid   => $u->id,
        itemshow   => 5,
        skip       => 0,
        showtypes  => 'PYC',
        u          => $u,
        userid     => $u->id,
        filter     => $filter,
    });

    my $resp = "";

    foreach my $item (@entries) {

        # each $item is just a magical hashref.  from that we'll
        # need to construct actual LJ::Entry objects to process
        # and eventually return via SMS

        my $entry;

        # have a ditemid only?  no problem.
        if ($item->{ditemid}) {
	    $entry = LJ::Entry->new($item->{journalid},
                                    ditemid => $item->{ditemid});

        # jitemid/anum is okay too
        } elsif ($item->{jitemid} && $item->{anum}) {
	    $entry = LJ::Entry->new($item->{journalid},
                                    jitemid => $item->{jitemid},
                                    anum    => $item->{anum});
        }
        next unless $entry;

        my $seg = $entry->as_sms(maxlen => 20) . "\n\n";

        # if the length of the current string plus our segment is greater than
        # the 160 byte SMS length limit plus the length of 2 bytes of \n, then
        # we'll strip the \n off the end and transmit the final segment
        last if length($resp) + length($seg) > 162;

        # still more buffer room, append another
        $resp .= $seg;

        # optimization: length($seg) == (160 + 2)
        # -- we appended the current segment, but any other segment definitely
        #    won't fit on.
        # -- yeah we thought of checking for a threshold of 5 bytes or something
        #    but it's feasible for the user 'aa' to post 'hi' for a total of 6
        #    bytes or something.
        last if length($resp) == 162;
    }

    # trim trailing newlines
    $resp =~ s/\n+$//;

    # ... but what if there actually were no entries?
    unless ($resp) {
        $resp = "Sorry, you currently have no friends page entries";
        $resp .= " for group '$group'" if $group;
        $resp .= ")";
    }

    my $resp_msg = eval { $msg->respond($resp) };

    # FIXME: do we set error status on $resp?

    # mark the requesting (source) message as processed
    $msg->status($@ ? ('error' => $@) : 'success');

    return 1;
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*fr(?:iends)?\.?/i ? 1 : 0;
}

1;
