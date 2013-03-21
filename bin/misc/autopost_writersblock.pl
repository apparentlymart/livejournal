#!/usr/bin/perl
#
# Check if any Writer's Block question had a start time in the last number of
# hours and if so, post them to the writersblock community.

use strict;

use Getopt::Long;
use Data::Dumper;

use lib "$ENV{LJHOME}/cgi-bin";
use LJ;
require 'ljprotocol.pl';
require 'ljfeed.pl';

my %comms = (
    'writersblock'      => { country => 'US', },
    'writersblock_ru'   => { country => 'RU', },
);

my $bot_name = 'lj_bot';

my $help    = 0;
my $dry     = 0;
my $verbose = 0;

unless (GetOptions(
    'help'          => \$help,
    'dry'           => \$dry,
    'bot=s'         => \$bot_name,
    'verbose'       => \$verbose,
) && !$help) {
    print
        "-----------------------------------------------------------\n" .
        " Autopost question of the day to writers block communities.\n" .
        "-----------------------------------------------------------\n" .
        "Options are:\n".
        "   verbose     - print more information\n".
        "   dry         - dry run, do not post any information\n".
        "   bot         - lj user name for bot\n" .
        "\n";
    exit(0);
}

my $u = LJ::want_user(LJ::get_userid($bot_name));

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
                        map { $_->{event} =~ m#<lj-template\s+name=["']qotd["']\s+id=["'](\d+)["']#; $1 }
                            @{$evts->{events}}
                    };
                }
        } else {
            push @errors, "community '$comm' doesn't exist";
        }
    }

    push @errors, "user '$bot_name' doesn't exist" unless LJ::isu($u);

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

# LJSUP-5545: Post to 'ru' community entries with empty 'country' field
# only if there is no entries for cyrillic country.
# Also remove spaces from country field.
{
    my $skip_cyrillic_with_defaults = 0; # set this if we find new row(s) with 'RU' country.
    foreach my $comm (grep { 'RU' eq $comms{$_}->{country} } keys %comms) {
        foreach my $row (@rows) {

            # filter already posted
            next if $comms{$comm}->{qids}->{$row->{qid}};

            $row->{countries} =~ s/^ *//;
            $row->{countries} =~ s/ *$//;

            $skip_cyrillic_with_defaults = 1 if $row->{countries} && ($row->{countries} =~ m/RU/i);
        }
        $comms{$comm}->{'skip_with_defaults'} = $skip_cyrillic_with_defaults;
    }
}

# Combine information, filter it and post to communities
{
    foreach my $row (@rows) {

        my $qotd_countries = $row->{countries}; # QotD's countries

        foreach my $comm (keys %comms) {

            # filter by country
            my $country = $comms{$comm}->{country}; # Community's country

            # Skip if specified country does not match.
            next if $qotd_countries && ($qotd_countries !~ m/$country/i);

            # Don't post to community entries with 'default' country. 
            next if $comms{$comm}->{'skip_with_defaults'} && ! $qotd_countries;

            # filter already posted
            next if $comms{$comm}->{qids}->{$row->{qid}};

            print "Posting [$row->{qid}] $row->{subject} to $comm\n" if $verbose;

            my %req = (
                mode => 'postevent',
                ver => $LJ::PROTOCOL_VER,
                user => $u->{user},
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

            unless ($dry) {
                LJ::do_request(\%req, \%res, $flags);
                unless ('OK' eq $res{success}) {
                    print "Error in LJ::do_request call:\n",
                        "request:\n",
                        Dumper(\%req), "\n" .
                        "result:\n",
                        Dumper(\%res), "\n";
                }
            }
        }
    }
}

print "ALL DONE\n" if $verbose;

