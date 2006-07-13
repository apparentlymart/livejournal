#!/usr/bin/perl

{
    use strict;
    use Test::More 'no_plan';

    use lib "./lib";
    use DSMS::Message;

    my $msg;
    
    # invalid parameters
    $msg = eval { DSMS::Message->new( foo => "bar" ) };
    like($@, qr/invalid parameters/, "invalid parameters");

    # invalid recipients cases
    $msg = eval { DSMS::Message->new; };
    like($@, qr/no recipient/, "no arguments");

    $msg = eval { DSMS::Message->new( to => undef ) };
    like($@, qr/no recipient/, "undef recipients");

    $msg = eval { DSMS::Message->new( to => 'foo' ) };
    like($@, qr/invalid recipient/, "invalid single recipient");

    $msg = eval { DSMS::Message->new( to => [ 'foo' ] ) };
    like($@, qr/invalid recipient/, "invalid single recipient in array");

    $msg = eval { DSMS::Message->new( to => [ ] ) };
    like($@, qr/empty recipient/, "empty recipient list");

    $msg = eval { DSMS::Message->new( to => [ '+1234567890', '123', '+1234567890' ] ) };
    like($@, qr/invalid recipient:\s+123/, "invalid recipient in list");

    # invalid body
    $msg = eval { DSMS::Message->new( to => '+1234567890' ) };
    like($@, qr/no body text/, "no body text specified");

    $msg = eval { DSMS::Message->new( to => '+1234567890', body_text => '' ) };
    like($@, qr/no body text/, "empty body text specified");

    # valid case
    $msg = eval { DSMS::Message->new( to        => '+1234567890', 
                                      body_text => 'TestMsg' ) };
    ok($msg && ! $@, "single number and body");

    $msg = eval { DSMS::Message->new( to        => '+1234567890', 
                                      subject   => 'TestSubj',
                                      body_text => 'TestMsg' ) };
    ok($msg && ! $@, "single number, subject and body");
}
