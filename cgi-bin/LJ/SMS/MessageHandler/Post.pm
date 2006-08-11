package LJ::SMS::MessageHandler::Post;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $text = $msg->body_text;

    my ($sec, $subject, $body) = $text =~ /
        ^\s*
        p(?:ost)?                 # post full or short

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
             ver        => 1,
             username   => $u->{user},
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

    # set metadata on this sms message indicating the 
    # type of handler used and the jitemid of the resultant
    # journal post
    $msg->meta
        ( post_jitemid => $res->{itemid},
          post_error   => $err,
          );

    $msg->status($err ? 
                 ('error' => "Error posting to journal: $err") : 'success');

    return 1;
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*p(?:ost)?[\.\s]/i ? 1 : 0;
}

1;
