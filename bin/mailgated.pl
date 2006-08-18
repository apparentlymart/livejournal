#!/usr/bin/perl
#
# <LJDEP>
# lib: MIME::Parser, Mail::Address, cgi-bin/ljlib.pl, cgi-bin/supportlib.pl
# </LJDEP>

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use Getopt::Long;
use Sys::Hostname;
use MIME::Parser;
use Mail::Address;
use Proc::ProcessTable;
use Unicode::MapUTF8 ();
use File::Temp       ();
use File::Path       ();
use Danga::Daemon;

require "$ENV{LJHOME}/cgi-bin/ljconfig.pl";

# worker globals
use vars qw/ $mailspool $mailspool_new $workdir $maxloop
             $hostname $locktype $opt /;
$opt = {};
Getopt::Long::GetOptions $opt, qw/ workdir=s lock=s maxloop=s /;

# mailspool should match the MTA delivery location.
$mailspool     = $LJ::MAILSPOOL || "$ENV{'LJHOME'}/mail";
$mailspool_new = "$mailspool/new";

# setup defaults
$hostname = $1 if Sys::Hostname::hostname() =~ /^([\w-]+)/;
$locktype = $opt->{'lock'} || $LJ::MAILLOCK;
die "Invalid lock mechanism specified.  Set \$LJ::MAILLOCK or use --lock.\n"
  unless $locktype =~ /^hostname|none|ddlockd$/i;
$workdir = $opt->{'workdir'} || "$mailspool/tmp";
$maxloop = $opt->{'maxloop'} || 100;

# sanity checks
die "Invalid mailspool: $mailspool\n"        unless -d $mailspool_new;
die "Unable to read mailspool: $mailspool\n" unless -r $mailspool;

Danga::Daemon::daemonize(

    \&worker,
    {
        interval   => 5,
        shedprivs  => 'lj',

        listenport => 15000,
        listencode => \&cmd_interface,
    }

);

# main event loop for mailgated.
# examine mailspool, populate queues, and call
# process() as needed.
sub worker
{
    require "$ENV{'LJHOME'}/cgi-bin/ljemailgateway.pl";
    require "$ENV{'LJHOME'}/cgi-bin/supportlib.pl";
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
    require "$ENV{'LJHOME'}/cgi-bin/sysban.pl";
    $| = 1;

    debug("Starting loop:");
    cleanup();
    LJ::start_request();

    # Get list of files to process.
    # If a file simply exists in the mailspool, it needs attention.
    debug("\tprocess");
    opendir( MDIR, $mailspool_new )
      || die "Unable to open mailspool $mailspool_new: $!\n";
    my @all_files = readdir(MDIR);
    closedir MDIR;

    # Separate new messages from retries.
    # Hostname as part of the filename is Maildir specification -
    # use 'hostname' locking to be safe across NFS.
    my ( @new_messages, @retry_messages );
    foreach (@all_files) {
        next if /^\./;
        next if $locktype eq 'hostname' && !/\.$hostname\b/;
        if ( get_pcount($_) == 0 ) {    # new message
            push @new_messages, $_;
        }
        else {                          # message retry
            push @retry_messages, $_;
        }
    }

    # Make sure at least half of our processesing
    # queue is made up of new messages.
    # Randomize, so if we're running multiple mailgated
    # processess, they'll be more likely to be working on
    # different messages.
    rand_array( \@retry_messages, int( $maxloop / 2 ) );    # half queue max
    # fill the rest of the queue with new messages.
    rand_array( \@new_messages, $maxloop - ( scalar @retry_messages ) );

    # do the work
    foreach my $file ( @new_messages, @retry_messages ) {
        my $lock;
        if ( get_pcount($file) % 20 == 0 ) {   # only retry every 20th iteration
            if ( lc($locktype) eq 'ddlockd' ) {
                $lock = LJ::locker()->trylock("mailgated-$file");
                next unless $lock;
            }
            eval { process($file); };
            if ($@) {
                debug("\t\t$@");
                set_pcount($file);
            }
        }
        else {
            set_pcount($file);
        }
    }

    debug("\tdone\n");
    LJ::end_request();
}

# additional command line options
sub cmd_interface
{
    my ( $line, $s, $c, $codeloop, $codeopts ) = @_;

        if ($line =~ /help/i) {
            foreach (sort qw/ ping pids reload stop queuesize status /) {
                print $c "\t$_\n";
            }
            print $c ".\nOK\n";
            return 1;
        }

        if ($line =~ /queuesize/) {
            if (! opendir(MDIR, $mailspool_new)) {
                print $c "Unable to open mailspool $mailspool_new: $!\n";
            } else {
                my $count = 0;
                foreach (readdir(MDIR)) {
                    next if /^\./;
                    $count++;
                }
                closedir MDIR;
                print $c "$count\n";
            }
            return 1;
        }

        if ($line =~ /status/) {
            my $pid = $Danga::Daemon::pid;
            my $t = new Proc::ProcessTable;
            my $state;

            foreach my $p ( @{$t->table} ){
                $state = $p->state if $p->pid == $pid;
            }

            print $c "mailgate ";
            print $c ($state ne 'defunct' && kill 0, $pid) ? "running" : "down";
            print $c "\n";
            return 1;
        }

    return;
}

# Remove prior run workdirs.
# File::Temp's CLEANUP only works upon program exit.
sub cleanup
{
    debug("\tcleanup");
    my $now = time();
    unless ( opendir( TMP, $workdir ) ) {
        debug("\t\tCan't open workdir $workdir: $!");
        return;
    }
    my $limit = 0;
    while ( my $dirent = readdir(TMP) ) {
        next unless $dirent =~ /^ljmailgate_/;
        last if $limit >= 200;
        my $modtime = ( stat("$workdir/$dirent") )[9];
        if ( $now - $modtime > 300 ) {
            # rmtree croaks if it disappears from under itself, and if
            # this is running on multiple hosts all mounting the same
            # NFS, then it can.  (and does, often)
            eval {
                File::Path::rmtree("$workdir/$dirent");
                debug("\t\tdeleted: $workdir/$dirent");
                $limit++;
            };
            if ($@) {
                debug("\t\talready deleted: $workdir/$dirent");
            }
        }
    }
    closedir TMP;
    return 0;
}

# takes an array ref - truncates to max size and shuffles it.
sub rand_array
{
    my ( $array, $max ) = @_;

    my ( @tmp, $c );
    while (@$array) {
        push( @tmp, splice( @$array, rand(@$array), 1 ) );
        last if ++$c == $max;
    }
    @$array = @tmp;
    return;
}

sub set_pcount
{
    my ( $file, $resetattempt ) = @_;
    my $attempt = get_pcount($file);
    $attempt++;
    $attempt = 0 if $resetattempt;

    my $name = $file;
    $name =~ s/:\d+$//;
    $name = $name . ":" . $attempt;
    rename "$mailspool_new/$file", "$mailspool_new/$name";
    return 0;
}

# return the number of times we've seen this
# message in the queue
sub get_pcount
{
    return 0 unless shift() =~ /:(\d+)$/;
    return $1;
}

# Either an unrecoverable error, or a total success.  ;)
# Regardless, we're done with this message.
# Remove it so it isn't processed again.
our $last_file;
our $last_tempdir;

sub dequeue
{
    my $msg = shift;
    debug("\t\t dequeued: $msg") if $msg;
    unlink("$mailspool_new/$last_file")
      || debug("\t\t Can't unlink $last_file!");
    File::Path::rmtree($last_tempdir);
    return 0;
}

# cleanup mime tempdirs, update attempt number,
# but don't delete the message.
sub retry
{
    my $msg = shift;
    debug("\t\t retrying: $msg") if $msg;
    set_pcount($last_file);
    File::Path::rmtree($last_tempdir);
    return 0;
}

# examine message contents and decide what to do
# with it.
sub process
{
    my $file = shift;
    debug("\t\t$file");
    my $tmpdir =
      File::Temp::tempdir( "ljmailgate_" . 'X' x 20, DIR => $workdir );
    my $parser = new MIME::Parser;

    # for dequeue sub:
    $last_file    = $file;
    $last_tempdir = $tmpdir;

    $parser->output_dir($tmpdir);

    # Close the message as quickly as possible, in case
    # we need to change status mid process.
    open( MESSAGE, "$mailspool_new/$file" )
      || debug("\t\t Can't open file: $!") && return;
    my $entity;
    eval { $entity = $parser->parse( \*MESSAGE ) };
    close MESSAGE;
    return dequeue("Can't parse MIME") if $@;

    my $head = $entity->head;
    $head->unfold;

    if ($head->get("Return-Path") =~ /^\s*<>\s*$/) {
        return dequeue("Bounce");
    }

    my $subject = $head->get('Subject');
    chomp $subject;

    # ignore spam/vacation/auto-reply messages
    if (   $subject =~ /auto.?(response|reply)/i
        || $subject =~
/^(Undelive|Mail System Error - |ScanMail Message: |\+\s*SPAM|Norton AntiVirus)/i
        || $subject =~ /^(Mail Delivery Problem|Mail delivery failed)/i
        || $subject =~ /^failure notice$/i
        || $subject =~ /\[BOUNCED SPAM\]/i
        || $subject =~ /^Symantec AVF /i
        || $subject =~ /Attachment block message/i
        || $subject =~ /Use this patch immediately/i
        || $subject =~ /^YOUR PAYPAL\.COM ACCOUNT EXPIRES/i
        || $subject =~ /^don\'t be late! ([\w\-]{1,15})$/i
        || $subject =~ /^your account ([\w\-]{1,15})$/i
        || $subject =~ /Message Undeliverable/i )
    {
        return dequeue("Spam");
    }

    # quick and dirty (and effective) scan for viruses
    return dequeue("Virus found") if virus_check($entity);

    # see if it's a post-by-email
    my @to = Mail::Address->parse( $head->get('To') );
    if ( scalar @to > 0 ) {
        foreach my $dest ( @to ) {
            next unless $dest->address =~ /^(\S+?)\@\Q$LJ::EMAIL_POST_DOMAIN\E$/i;

            my $user = $1;

            # FIXME: verify auth (extra from $user/$subject/$body), require ljprotocol.pl, do post.
            # unresolved:  where to temporarily store messages before they're approved?
            # perhaps the modblob table?  perhaps a column it can be used to determine
            # whether it's a moderated community post vs. an un-acked phone post.
            my $post_rv;
            my $post_msg = LJ::Emailpost::process( $entity, $user, \$post_rv );

            return $post_rv ? dequeue($post_msg) : retry($post_msg);
        }
    }

    # stop more spam, based on body text checks
    my $tent = LJ::Emailpost::get_entity($entity);
    $tent = LJ::Emailpost::get_entity( $entity, 'html' ) unless $tent;
    return dequeue("Can't find text or html entity") unless $tent;
    my $body = $tent->bodyhandle->as_string;
    $body = LJ::trim($body);

    ### spam
    if (   $body =~ /I send you this file in order to have your advice/i
        || $body =~ /^Content-Type: application\/octet-stream/i
        || $body =~ /^(Please see|See) the attached file for details\.?$/i
        || $body =~ /^I apologize for this automatic reply to your email/i )
    {
        return dequeue("Spam");
    }


    # From this point on we know it's a support request of some type,
    my $email2cat = LJ::Support::load_email_to_cat_map();

    my $to;
    my $toarg;
    foreach my $a ( @to, Mail::Address->parse( $head->get('Cc') ) ) {
        my $address = $a->address;
        my $arg;
        if ( $address =~ /^(.+)\+(.*)\@(.+)$/ ) {
            ( $address, $arg ) = ( "$1\@$3", $2 );
        }
        if ( defined $LJ::ALIAS_TO_SUPPORTCAT{$address} ) {
            $address = $LJ::ALIAS_TO_SUPPORTCAT{$address};
        }
        if ( defined $email2cat->{$address} ) {
            $to    = $address;
            $toarg = $arg;
        }
    }

    return dequeue("Not deliverable to support system (no match To:)")
      unless $to;

    my $adf = ( Mail::Address->parse( $head->get('From') ) )[0];
    return dequeue("Bogus From: header") unless $adf;

    my $name = $adf->name;
    my $from = $adf->address;
    $subject ||= "(No Subject)";

    # is this a reply to another post?
    if ( $toarg =~ /^(\d+)z(.+)$/ ) {
        my $spid     = $1;
        my $miniauth = $2;
        my $sp       = LJ::Support::load_request($spid);

        LJ::Support::mini_auth($sp) eq $miniauth
          or die "Invalid authentication?";

        if ( LJ::sysban_check( 'support_email', $from ) ) {
            my $msg = "Support request blocked based on email.";
            LJ::sysban_block( 0, $msg, { 'email' => $from } );
            return dequeue($msg);
        }

        # make sure it's not locked
        return dequeue("Request is locked, can't append comment.")
          if LJ::Support::is_locked($sp);

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
        my $splid = LJ::Support::append_request(
            $sp,
            {
                'type' => 'comment',
                'body' => $body,
            }
          )
          or return dequeue("Error appending request?");

        LJ::Support::touch_request($spid);

        return dequeue("Support reply success");
    }

    # Now see if we want to ignore this particular email and bounce it back with
    # the contents from a file.  Check $LJ::DENY_REQUEST_FROM_EMAIL first.  Note
    # that this will only bounce initial emails; if a user replies to an email
    # from a request that's open, it'll be accepted above.
    my ( $content_file, $content );
    if ( %LJ::DENY_REQUEST_FROM_EMAIL && $LJ::DENY_REQUEST_FROM_EMAIL{$to} ) {
        $content_file = $LJ::DENY_REQUEST_FROM_EMAIL{$to};
        $content      = LJ::load_include($content_file);
    }
    if ( $content_file && $content ) {

        # construct mail to send to user
        my $email = <<EMAIL_END;
$content

Your original message:

$body
EMAIL_END

        # send the message
        LJ::send_mail(
            {
                'to'      => $from,
                'from'    => $LJ::BOGUS_EMAIL,
                'subject' => "Your Email to $to",
                'body'    => $email,
                'wrap'    => 1,
            }
        );

        # all done
        return dequeue("Support request bounced to origin");
    }

    # make a new post.
    my @errors;

    # convert email body to utf-8
    my $content_type = $head->get('Content-type:');
    my $charset      = $1
      if $content_type =~ /\bcharset=[\'\"]?(\S+?)[\'\"]?[\s\;]/i;
    if (   defined($charset)
        && $charset !~ /^UTF-?8$/i
        && Unicode::MapUTF8::utf8_supported_charset($charset) )
    {
        $body =
          Unicode::MapUTF8::to_utf8(
            { -string => $body, -charset => $charset } );
    }

    my $spid = LJ::Support::file_request(
        \@errors,
        {
            'spcatid'  => $email2cat->{$to}->{'spcatid'},
            'subject'  => $subject,
            'reqtype'  => 'email',
            'reqname'  => $name,
            'reqemail' => $from,
            'body'     => $body,
        }
    );

    if (@errors) {
        # FIXME: detect trasient vs. permanent errors (changes to
        # file_request above, probably) and either dequeue or try
        # later
        return dequeue("Support errors: @errors");
    }
    else {
        return dequeue("Support request success");
    }
}

# returns true on found virus
sub virus_check
{
    my $entity = shift;
    return unless $entity;

    my @exe = LJ::Emailpost::get_entity( $entity, 'all' );
    return unless scalar @exe;

    # If an attachment's encoding begins with one of these strings,
    # we want to completely drop the message.
    # (Other 'clean' attachments are silently ignored, and the
    # message is allowed.)
    my @virus_sigs =
      qw(
      TVqQAAMAA TVpQAAIAA TVpAALQAc TVpyAXkAX TVrmAU4AA
      TVrhARwAk TVoFAQUAA TVoAAAQAA TVoIARMAA TVouARsAA
      TVrQAT8AA UEsDBBQAA UEsDBAoAAA
      R0lGODlhaAA7APcAAP///+rp6puSp6GZrDUjUUc6Zn53mFJMdbGvvVtXh2xre8bF1x8cU4yLprOy
    );

    # get the length of the longest virus signature
    my $maxlength =
      length( ( sort { length $b <=> length $a } @virus_sigs )[0] );
    $maxlength = 1024 if $maxlength >= 1024;    # capped at 1k

    foreach my $part (@exe) {
        my $contents = $part->stringify_body;
        $contents = substr $contents, 0, $maxlength;

        foreach (@virus_sigs) {
            return 1 if index( $contents, $_ ) == 0;
        }
    }

    return;
}

