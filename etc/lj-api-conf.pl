#!/usr/bin/perl
{
    package LJ;

    # Accounts must have their email validated before the commands indicated
    # below can be run.
    %LJ::XMLRPC_VALIDATION_METHOD = (
        checkfriends     => 0,
        consolecommand   => 1,
        editevent        => 1,
        editfriendgroups => 1,
        editfriends      => 1,
        friendof         => 0,
        getchallenge     => 0,
        getdaycounts     => 0,
        getevents        => 0,
        getfriends       => 0,
        getfriendgroups  => 0,
        getusertags      => 0,
        login            => 0,
        postevent        => 1,
        sessionexpire    => 0,
        sessiongenerate  => 0,
        syncitems        => 0,
    );

    %LJ::XMLRPC_USER_ACCESS = (
        login            => 'profile_ro',
        getfriendgroups  => 'friends_ro',
        getfriends       => 'friends_ro',
        friendof         => 'friends_ro',
        checkfriends     => 'friends_ro',
        getdaycounts     => 'journal_ro',
        postevent        => 'journal_rw',
        editevent        => 'journal_rw',
        syncitems        => 'journal_ro',
        getevents        => 'journal_ro',
        editfriends      => 'friends_rw',
        editfriendgroups => 'friends_rw',
        consolecommand   => 'console',
        getusertags      => 'profile_ro',
        getfriendspage   => ['journal_ro', 'friends_ro'],
        getinbox         => 'messages',
        sendmessage      => 'messages',
        setmessageread   => 'messages',
        addcomment       => 'journal_rw',

        getrecentcomments => 'journal_ro',
        getcomments       => 'journal_ro',
        deletecomments    => 'journal_rw',
        updatecomments    => 'journal_rw',
        editcomment       => 'journal_rw',

        getuserpics       => 'profile_ro',
        createpoll        => 'journal_rw',
        getpoll           => 'journal_ro',
        editpoll          => 'journal_rw',
        votepoll          => 'journal_rw',
        registerpush      => 'push',
        unregisterpush    => 'push',
        pushsubscriptions => 'push',
        resetpushcounter  => 'push',
        getpushlist       => 'push',

        geteventsrating   => 'ratings',
        getusersrating   => 'ratings',
    );

}

1;
