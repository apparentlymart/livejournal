#!/usr/bin/perl
#

use strict;
 
unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

use vars qw(%caps_general %caps_local);

my $LJHOME = $ENV{'LJHOME'};

require "$LJHOME/doc/raw/build/docbooklib.pl";

if (-e "$LJHOME/doc/raw/build/caps/cap-local.pl") {
    require "$LJHOME/doc/raw/build/caps/cap-local.pl";
}

$caps_general{'checkfriends'} = {
    type => 'boolean',
    desc => 'User can use checkfriends.',
};
$caps_general{'checkfriends_interval'} = {
    type => 'integer',
    desc => 'Time before clients can call "checkfriends" (use min).',
};
$caps_general{'synd_create'} = {
    type => 'boolean',
    desc => 'User can create syndicated accounts.',
};
$caps_general{'findsim'} = {
    type => 'boolean',
    desc => 'User is able to use the similar interests matching feature',
};
$caps_general{'friendsfriendsview'} = {
    type => 'boolean',
    desc => 'User\'s "friends of friends" /friendsfriends view is enabled',
};
$caps_general{'friendsviewupdate'} = {
    type => 'integer',
    desc => 'After how many seconds user see new friends view items.',
};
$caps_general{'makepoll'} = {
    type => 'boolean',
    desc => 'User can user make a poll',
};
$caps_general{'maxfriends'} = {
    type => 'integer',
    desc => 'Maximum number of friends that are allowed per account',
};
$caps_general{'moodthemecreate'} = {
    type => 'boolean',
    desc => 'User can create new mood themes.',
};
$caps_general{'readonly'} = {
    type => 'boolean',
    desc => 'No writes to the database for this journal are permitted. '.
            '(this is used by cluster management tool:  a journal is readonly '.
            'while it is being moved to another cluster)',
};
$caps_general{'styles'} = {
    type => 'boolean',
    desc => 'User can create &amp; use their own styles.',
};
$caps_general{'textmessage'} = {
    type => 'boolean',
    desc => 'User can use text messaging.',
};
$caps_general{'todomax'} = {
    type => 'integer',
    desc => 'Maximum number of todo items allowed',
};
$caps_general{'todosec'} = {
    type => 'boolean',
    desc => 'Can user make non-public todo items?',
};
$caps_general{'userdomain'} = {
    type => 'boolean',
    desc => 'Can view journal at http://user.$LJ::DOMAIN/',
};
$caps_general{'useremail'} = {
    type => 'boolean',
    desc => 'User has email address @$LJ::USER_DOMAIN',
};
$caps_general{'userpics'} = {
    type => 'integer',
    desc => 'Maximum number of user pictures allowed.',
};
$caps_general{'hide_email_after'} = {
    type => 'integer',
    desc => "Hide an account's email address who has not used the site in a time period longer than the given setting.  ".
            "If 0, the email is never hidden.  The time period is in days.",
};
$caps_general{'weblogscom'} = {
    type => 'boolean',
    desc => "Allow the account to ping weblogs.com with new updates",
};
$caps_general{'full_rss'} = {
    type => 'boolean',
    desc => "Show the full text in the RSS view",
};
$caps_general{'get_comments'} = {
    type => 'boolean',
    desc => "Can receive comments",
};
$caps_general{'leave_comments'} = {
    type => 'boolean',
    desc => "Can leave comments on other accounts",
};
$caps_general{'can_post'} = {
    type => 'boolean',
    desc => "Can post new entries",
};
$caps_general{'rateperiod-failed_login'} = {
    type => 'integer',
    desc => "The period of time an account can try to repeat logging in for",
};
$caps_general{'rateallowed-failed_login'} = {
    type => 'integer',
    desc => "How many times a period an account can try to log in for", 
};
$caps_general{'s2everything'} = {
    type => 'boolean',
    desc => "Can use all properties of S2 layouts",
};
$caps_general{'friendspopwithfriends'} = {
    type => 'boolean',
    desc => "Can use <quote>Popular with Friends</quote> tool",
};
$caps_general{'emailpost'} = {
    type => 'boolean',
    desc => "User has ability to post via an email gateway.",
};
$caps_general{'disable_can_post'} = {
    type => "boolean",
    desc => "Posting new journal entries is disabled for this account, presumably because a trial period of some sort has expired.",
};
$caps_general{'disable_get_comments'} = {
    type => "boolean",
    desc => "Getting new comments in this journal is disabled, presumably because a trial period of some sort has expired.",
};
$caps_general{'disable_leave_comments'} = {
    type => "boolean",
    desc => "This account can no longer leave comments, presumably because a trial period of some sort has expired.",
};


sub dump_caps
{
    my $title = shift;
    my $caps = shift;
    print "<variablelist>\n  <title>$title Capabilities</title>\n";
    foreach my $cap (sort keys %$caps)
    {
        print "  <varlistentry>\n";
        print "    <term><literal role=\"cap.class\">$cap</literal></term>\n";
        print "    <listitem><para>\n";
        print "      (<emphasis>$caps->{$cap}->{'type'}</emphasis>) - $caps->{$cap}->{'desc'}\n";
        print "    </para></listitem>\n";
        print "  </varlistentry>\n";
    }
    print "</variablelist>\n";
}

dump_caps("General", \%caps_general);
if (%caps_local) { dump_caps("Local", \%caps_local); }
