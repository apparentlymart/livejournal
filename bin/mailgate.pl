#!/usr/bin/perl
#
# <LJDEP>
# lib: MIME::Parser, Mail::Address, cgi-bin/ljlib.pl, cgi-bin/supportlib.pl
# </LJDEP>

use strict;
use MIME::Parser;
use Mail::Address;
use Unicode::MapUTF8 ();

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

# ignore spam/vacation/auto-reply messages
if ($subject =~ /auto.?(response|reply)/i ||
    $subject =~ /^(Undelive|Mail System Error - |ScanMail Message: |\+\s*SPAM|Norton AntiVirus)/ ||
    $subject =~ /\[BOUNCED SPAM\]/ ||
    $subject =~ /^Symantec AVF / ||
    $subject =~ /Attachment block message/ ||
    $subject =~ /Use this patch immediately/) 
{
    $parser->filer->purge;
    exit 0;
}

# stop more spam, based on body text checks
my $tent = get_text_entity($entity);
unless ($tent) {
    $parser->filer->purge;
    die "Can't find text entity";
}
my $body = $tent->bodyhandle->as_string;
$body =~ s/^\s+//;
$body =~ s/\s+$//;

### spam
if ($body =~ /I send you this file in order to have your advice/ ||
    $body =~ /^Content-Type: application\/octet-stream/ ||
    $body =~ /^(Please see|See) the attached file for details\.?$/ ||
    ($subject eq "failure notice" && $body =~ /\.(scr|pif)\"/) ||
    ($subject =~ /^Mail delivery failed/ && $body =~ /\.(scr|pif)\"/))
{
    $parser->filer->purge;
    exit 0;
}

# at this point we need ljlib (we delayed this so spam/junk is quicker to process)
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

# see if it's a post-by-email
my @to = Mail::Address->parse($head->get('To'));
if (@to == 1 && $to[0]->address =~ /^(\S+?)\@\Q$LJ::EMAIL_POST_DOMAIN\E$/i) {
    my $user = $1;
    # FIXME: verify auth (extra from $user/$subject/$body), require ljprotocol.pl, do post.
    # unresolved:  where to temporarily store messages before they're approved?
    # perhaps the modblob table?  perhaps a column it can be used to determine
    # whethere it's a moderated community post vs. an un-acked phone post.
    require "$ENV{LJHOME}/cgi-bin/ljemailgateway.pl";
    LJ::Emailpost::process($entity, $user);

    $parser->filer->purge;
    exit 0;
}

# From this point on we know it's a support request of some type,
# so load the support library.
require "$ENV{'LJHOME'}/cgi-bin/supportlib.pl";

my $email2cat = LJ::Support::load_email_to_cat_map();

my $to;
my $toarg;
my $ignore = 0;
foreach my $a (@to,
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
    $ignore = 1 if $address eq $LJ::IGNORE_EMAIL;
    $ignore = 1 if $address eq $LJ::BOGUS_EMAIL;
}

unless ($to) {
    $parser->filer->purge;
    exit 0 if $ignore;
    die "Not deliverable to support system (no match To:)\n";
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
    my $sp = LJ::Support::load_request($spid);

    LJ::Support::mini_auth($sp) eq $miniauth
        or die "Invalid authentication?";

    if (LJ::sysban_check('support_email', $from)) {
        LJ::sysban_block(0, "Support request blocked based on email", { 'email' => $from });
        exit 0;
    }

    # valid.  need to strip out stuff now with authcodes:
    $body =~ s!http://.+/support/act\.bml\S+![snipped]!g;
    $body =~ s!\+(\d)+z\w{1,10}\@!\@!g;
    $body =~ s!&auth=\S+!!g;

    ## try to get rid of reply stuff.
    # Outlook Express:
    $body =~ s!(\S+.*?)-{4,10} Original Message -{4,10}.+!$1!s;
    # Pine/Netscape
    $body =~ s!(\S+.*?)\bOn [^\n]+ wrote:\n.+!$1!s;

    # append the comment, re-open the request if necessary
    my $splid = LJ::Support::append_request($sp, {
        'type' => 'comment',
        'body' => $body,
    }) or die "Error appending request?";

    LJ::Support::touch_request($spid);

    exit 0;
}


# make a new post.
my @errors;

# convert email body to utf-8
my $content_type = $head->get('Content-type:');
my $charset = $1 if $content_type =~ /\bcharset=['"]?(\S+?)['"]?[\s\;]/i;
if (defined($charset) && $charset !~ /^UTF-?8$/i &&
        Unicode::MapUTF8::utf8_supported_charset($charset)) {
    $body = Unicode::MapUTF8::to_utf8({ -string=>$body, -charset=>$charset });
}

my $spid = LJ::Support::file_request(\@errors, {
    'spcatid' => $email2cat->{$to}->{'spcatid'},
    'subject' => $subject,
    'reqtype' => 'email',
    'reqname' => $name,
    'reqemail' => $from,
    'body' => $body,
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
        $mime_type eq "multipart/mixed" ||
        $mime_type eq "multipart/signed") {
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

