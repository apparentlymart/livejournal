#!/usr/bin/perl
#
# Check if any Writer's Block question had a start time in the last number of
# hours and if so, post them to the writersblock community.
# If writersblock was recently updated don't post, this is to help
# avoid duplicate posts even if this script is rerun or posts are
# inserted manually.

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';
require 'ljfeed.pl';

my %comms = (
    'writersblock'      => { country => 'US', },
    'writersblock_ru'   => { country => 'RU', },
);

my $u = LJ::want_user(LJ::get_userid('lj_bot'));

my $now = time();

# Get information from entries in communities
# Check for all errors, then print all error messages.
{
    my @errors;
    foreach my $comm (keys %comms) {
        if (LJ::isu($comms{$comm}->{object} = LJ::want_user(LJ::get_userid($comm)))) {

                # get last 50 entries (getevents request)
                my $req = {
                    'usejournal' => $comm,
                    'ver' => $LJ::PROTOCOL_VER,
                    'username' => $comm,
                    'selecttype' => 'lastn',
                    'howmany' => 50,
                    'noprop' => 1,
                };

                my $err;
                my $evts = LJ::Protocol::do_request("getevents", $req, \$err, { 'noauth' => 1 });
                if ($err) {
                    push @errors, "getevents from community '$comm' returns error $err";
                    next;
                }

                # get qids from it
                # 'event' => '<lj-template name="qotd" id="42" />',

                if (@{$evts->{events}}) {
                    $comms{$comm}->{qids} = {
                        map { $_ => $_ }
                        map { $_->{event} =~ m#<lj-template name="qotd" id="(\d+)" />#; $1 }
                            @{$evts->{events}}
                    };
                }
        } else {
            push @errors, "community '$comm' doesn't exist";
        }
    }

    push @errors, "user 'lj_bot' doesn't exist" unless LJ::isu($u);

    die
        "There was an error(s):\n" .
        join(";\n", map {'  - ' . $_} @errors) . ".\n" .
        "Execution cancelled\n"
            if @errors;
}

# Find QotDs
my @rows = ();
{
    my $dbh = LJ::get_db_reader() or die "Error: no database";

    my $sth = $dbh->prepare("SELECT * FROM qotd WHERE active='Y' " .
            "AND time_start < ? AND time_end > ? ORDER BY time_start");
    $sth->execute($now, $now);
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
}

# Combine information, filter it and post to communities
{
    foreach my $row (@rows) {
        foreach my $comm (keys %comms) {

            # filter by country
            my $country = $comms{$comm}->{country}; # Community's country
            if ($country) {
                my $qotd_countries = $row->{countries}; # QotD's countries
                $qotd_countries =~ s/^ *//; $qotd_countries =~ s/ *$//;
                next if $qotd_countries && ($qotd_countries !~ m/$country/i);
            }

            # filter already posted
            next if $comms{$comm}->{qids}->{$row->{qid}};

            print "Posting [$row->{qid}] $row->{subject} to $comm\n";

            my %req = (
                mode => 'postevent',
                ver => $LJ::PROTOCOL_VER,
                user => $u->user,
                usejournal => $comms{$comm}->{object}->user(),
                tz => 'guess',
                subject => $row->{subject},
                event => '<lj-template name="qotd" id="' . $row->{qid} . '" />',
                prop_taglist => $row->{tags},
                prop_opt_noemail => 1,
                prop_qotdid => $row->{qid},
            );

            my %res;
            my $flags = { noauth => 1, u => $u };

            LJ::do_request(\%req, \%res, $flags);
        }
    }
}

print "ALL DONE\n";

