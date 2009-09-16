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
}

1;
