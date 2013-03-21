#!/usr/bin/perl

##
## This script dumps all poll data (questions, answers, results, etc) 
## to file <poll_id>.xml
## Usage:  dump-poll.pl <poll_id>
##

use strict;
use warnings;
use XML::Simple qw/XMLin/;
use Data::Dumper;
use Encode();
use lib "$ENV{'LJHOME'}/cgi-bin";
use LJ;
use LJ::Poll;
use Getopt::Long;

my $usage = <<"USAGE";
$0 - script to dump polls in XML or text formats
Usage:
    $0 [options] <poll_id> 
Options:
    --text  Dump in text (tab-separated) format for Excel
            Also prints user data (gender and birthday)
    --help  Show this help and exit
Example:
    $0 --text 1499317 >1499317.txt
USAGE

my ($text_format, $need_help);
GetOptions(
    "text"  =>  \$text_format,
    "help"  =>  \$need_help,
) or die $usage;
die $usage if $need_help;
my $pollid = $ARGV[0] or die $usage;

my $poll = LJ::Poll->new($pollid) 
    or die "No such poll: $pollid";

if ($text_format) {
    
    my $data;
    {
        my $tmp;
        open FILE, ">", \$tmp;
        $poll->dump_poll(\*FILE);
        close FILE;
        $data = XMLin($tmp);

        ## remote wide (Unicode) characters from strings
        my %attrs_to_encode = (pollquestion2 => 'qtext', pollitem2 => 'item');
        while (my ($t, $attr) = each %attrs_to_encode) {
            foreach my $item (@{ $data->{$t} }) {
                $item->{$attr} = Encode::encode_utf8($item->{$attr});
            }
        }
    }

    my @questions = 
        sort { $a->{sortorder} <=> $b->{sortorder} } 
        @{ $data->{pollquestion2} }; 
        
    ## $answers{question_id} = [ answer1, answer2, ...]
    ## $answers_hash{question_id}->{answer_id} = answer1;
    my (%answers, %answers_hash);
    foreach my $a (@{ $data->{pollitem2} }) {
        $answers{ $a->{pollqid} } ||= [];
        push @{ $answers{ $a->{pollqid} } }, $a;
        $answers_hash{ $a->{pollqid} }->{ $a->{pollitid} } = $a;
    }
    foreach my $pollqid (keys %answers) {
        $answers{$pollqid} = [
            sort { $a->{sortorder} <=> $b->{sortorder} }
            @{ $answers{$pollqid} }
        ];
    }

    ## $user{userid}->{question_id} = $answer_hasref;
    my %users;
    foreach my $r (@{ $data->{pollresult2} }) {
        $users{ $r->{userid} }->{ $r->{pollqid} } = $r;
    }


    ## print header (3 lines):
    ## poll ID
    ## userid, username, gender, birthday, city, question1, question1, question2, question2
    ## -     , -       , -     , -       , -   , answer11,  answer12,  answer21,  answer22...
    print "Pollid = $pollid\n";
    print "Userid\tusername\tgender\tbirthday\tcity\t";
    foreach my $q (@questions) {
        if ($q->{type} eq 'radio') {
            ## one answer only
            print "$q->{qtext}\t";
        } elsif ($q->{type} eq 'check') {
            ## many answers
            print "$q->{qtext}\t" x (scalar @{ $answers{ $q->{pollqid} } });
        } else {
            die $q->{type};
        }
    }
    print "\n";
    print "\t\t\t\t\t";
    foreach my $q (@questions) {
        if ($q->{type} eq 'radio') {
            ## one answer only
            print "\t";
        } elsif ($q->{type} eq 'check') {
            ## many answers
            foreach my $a (@{ $answers{ $q->{pollqid} } }) {
                print $a->{item}, "\t";
            }
        } else {
            die $q->{type};
        }
    }
    print "\n";

    ## print data for each user
    foreach my $userid (sort {$a <=> $b} keys %users) {
        my $u = LJ::load_userid($userid);
        print "$userid\t";
        print "$u->{user}\t";
        print $u->prop('gender')||'', "\t";
        print $u->{'bdate'}||'', "\t";
        print $u->prop('city')||'', "\t";
        foreach my $q (@questions) {
            my $r = $users{$userid}->{ $q->{pollqid} };
            if ($q->{type} eq 'radio') {
                ## one answer only
                my $text = ($r) ? 
                    $answers_hash{ $q->{pollqid} }->{ $r->{value} }->{item} :
                    '';
                print "$text\t";
            } elsif ($q->{type} eq 'check') {
                ## many answers
                my %checked_answers = ($r) ?
                    map { $_ => 1 } split /,/, $r->{value} : 
                    ();
                foreach my $a (@{ $answers{ $q->{pollqid} } }) {
                    my $text = ($checked_answers{ $a->{pollitid} }) ? 'x' : ' '; 
                    print "$text\t";
                }
            } else {
                die $q->{type};
            }
        }
        print "\n";
    }
} else {
    ## xml format
    $poll->dump_poll();
}


