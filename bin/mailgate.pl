#!/usr/bin/perl
#
# <LJDEP>
# lib: MIME::Parser, Mail::Address, cgi-bin/ljlib.pl, cgi-bin/supportlib.pl
# </LJDEP>

use strict;
use MIME::Parser;
use Mail::Address;
use vars qw($dbh);

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/supportlib.pl";

$dbh = LJ::get_dbh("master");
my $email2cat = LJ::Support::load_email_to_cat_map($dbh);

my $parser = new MIME::Parser;
$parser->output_dir("/tmp");

my $entity;
eval { $entity = $parser->parse(\*STDIN) };
if ($@) {
    my $results  = $parser->results;
    $parser->filer->purge;
    die "Can't parse MIME.\n";
}

my $head = $entity->head;
$head->unfold;

my $subject = $head->get('Subject');
chomp $subject;

my $to;
my $toarg;
foreach my $a (Mail::Address->parse($head->get('To')),
             Mail::Address->parse($head->get('Cc')))
{
    my $address = $a->address;
    my $arg;
    if ($address =~ /^(.+)\+(.*)\@(.+)$/) {
        ($address, $arg) = ("$1\@$3", $2);
    }
    if (defined $email2cat->{$address}) {
        $to = $address;
        $toarg = $arg;
    }
}
unless ($to) {
    $parser->filer->purge;
    die "Not deliverable to support system (no match To:)\n";
}

# ignore vacation/auto-reply messages
if ($subject =~ /auto.?(response|reply)/i) {
    $parser->filer->purge;
    exit 0;
}

my $tent = get_text_entity($entity);
unless ($tent) {
    $parser->filer->purge;
    die "Can't find text entity";
}
my $body = $tent->bodyhandle->as_string;
$body =~ s/^\s+//;
$body =~ s/\s+$//;

### spam
if ($body =~ /I send you this file in order to have your advice/) {
    $parser->filer->purge;
    exit 0;
}

my $adf = (Mail::Address->parse($head->get('From')))[0];
my $name = $adf->name;
my $from = $adf->address;
$subject ||= "(No Subject)";

$parser->filer->purge;

# is this a reply to another post?
if ($toarg =~ /^(\d+)z(.+)$/)
{
    my $spid = $1;
    my $miniauth = $2;
    my $sp = LJ::Support::load_request($dbh, $spid);

    if (LJ::Support::mini_auth($sp) eq $miniauth) 
    {
        # valid.  need to strip out stuff now with authcodes:
        $body =~ s!http://.+/support/act\.bml\S+![snipped]!g;
        $body =~ s!\+(\d)+z\w{1,10}\@!\@!g;
        $body =~ s!&auth=\S+!!g;

        ## try to get rid of reply stuff.
        # Outlook Express:
        $body =~ s!(\S+.*?)-{4,10} Original Message -{4,10}.+!$1!s;
        # Pine/Netscape
        $body =~ s!(\S+.*?)\bOn [^\n]+ wrote:\n.+!$1!s;
        
        my $splid = LJ::Support::append_request($dbh, $sp, {
            'type' => 'comment',
            'body' => $body,
            'posterid' => 0,
        });
        if ($splid) { exit 0; }
        die "Error appending request?";
    }
}


# make a new post.
my @errors;
my $spid = LJ::Support::file_request($dbh, \@errors, {
    'supportcat' => $email2cat->{$to},
    'subject' => $subject,
    'reqtype' => 'email',
    'reqname' => $name,
    'reqemail' => $from,
    'body' => $body
    });

if (@errors) {
    die "Errors: @errors\n";
}


sub get_text_entity
{
    my $entity = shift;

    my $head = $entity->head;
    my $mime_type =  $head->mime_type;
    if ($mime_type eq "text/plain") {
        return $entity;
    }

    if ($mime_type eq "multipart/alternative" ||
        $mime_type eq "multipart/mixed") {
        my $partcount = $entity->parts;
        for (my $i=0; $i<$partcount; $i++) {
            my $alte = $entity->parts($i);
            return $alte if ($alte->mime_type eq "text/plain");
        }
        return undef;
    }

    if ($mime_type eq "multipart/related") {
        my $partcount = $entity->parts;
        if ($partcount) {
            return get_text_entity($entity->parts(0));
        }
        return undef;
    }

    $entity->dump_skeleton(\*STDERR);
    
    return undef;
}

