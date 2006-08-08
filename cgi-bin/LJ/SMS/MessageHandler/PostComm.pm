package LJ::SMS::MessageHandler::PostComm;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $text = $msg->body_text;

    my ($commname, $sec, $subject, $body) = $text =~ /
        ^\s*
        p(?:ost)?c(?:omm)?        # post full or short

        (?:\.[^\.]+)              # community username

        (?:\.                     # optional security setting
         (
          (?:\"|\').+?(?:\"|\')   # single or double quoted security
          |
          \S+)                    # single word security
         )?

         \s+

         (?:                      # optional subject
          (?:\[|\()(.+)(?:\]|\))  # [...] or (...) subject
          )?

         \s*

         (.+)                     # teh paylod!

         \s*$/ix; 

    # for quoted strings, the 'sec' segment will still have single or double quotes
    $sec =~ s/^(?:\"|\')//;
    $sec =~ s/(?:\"|\')$//;

    my $u = $msg->from_u;
    my $secmask = 0;

    if ($sec) {
        if ($sec =~ /^pu/) {
            $sec = 'public';
        } elsif ($sec =~ /^fr/) {
            $sec = 'usemask';
            $secmask = 1;
        } elsif ($sec =~ /^pr/) {
            $sec = 'private';
        } else {
            warn "u: $u->{user}";
            my $groups = LJ::get_friend_group($u);
            while (my ($bit, $grp) = each %$groups) {
                next unless $grp->{groupname} =~ /^$sec$/i;

                # found the security group the user is asking for
                $sec = 'usemask';
                $secmask = 1 << $bit;

                last;
            }
        }
    }

    # initiate a protocol request to post this message
    my $err;
    my $res = LJ::Protocol::do_request
        ("postevent",
         { 
             ver         => 1,
             username    => $u->{user},
             usejournal  => $commname,
             lineendings => 'unix',
             subject     => $subject || "Posted using LJMobile...",
             event       => $body,
             props       => { sms_msgid => $msg->id },
             security    => $sec,
             allowmask   => $secmask,
             tz          => 'guess' 
         },
         \$err, { 'noauth' => 1 }
         );

    # try to load the community object so that we can add the
    # postcomm_journalid prop below if it was actually a valid
    # community... otherwise the prop will not be set and 
    # we'll error with whatever the protocol returned.
    my $commu = LJ::load_user($commname);

    # set metadata on this sms message indicating the 
    # type of handler used and the jitemid of the resultant
    # journal post
    $msg->meta
        ( postcomm_journalid => ($commu ? $commu->id : undef),
          postcomm_jitemid   => $res->{itemid},
          postcomm_error     => $err,
          );

    $msg->status($err ? 
                 ('error' => "Error posting to community: $err") : 'success');

    return 1;
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*p(?:ost)?c/i ? 1 : 0;
}

1;
