#!/usr/bin/perl
#
# <LJDEP>
# lib: MIME::Parser, Mail::Address, cgi-bin/ljlib.pl, cgi-bin/supportlib.pl
# </LJDEP>

use strict;
use vars qw($opt $mailspool $pidfile $workdir
            $pid $hostname $busy $stop $lock);

use Getopt::Long;
use Sys::Hostname;
use MIME::Parser;
use Mail::Address;
use Unicode::MapUTF8 ();
use File::Temp ();
use File::Path ();
use POSIX 'setsid';
require "$ENV{'LJHOME'}/cgi-bin/ljemailgateway.pl";
require "$ENV{'LJHOME'}/cgi-bin/supportlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/sysban.pl";

# mailspool should match the MTA delivery location.
$mailspool = $LJ::MAILSPOOL || "$ENV{'LJHOME'}/mail";

$hostname = $1 if hostname() =~ /^(\w+)/;
$SIG{$_} = \&stop_daemon foreach qw/INT TERM/;
$| = 1;

$opt = {};
GetOptions $opt, qw/stop foreground workdir pidfile lock=s/;

# setup defaults
$lock    = $opt->{'lock'}    || "hostname";
die "Invalid lock mechanism specified."
    unless $lock =~ /hostname|none|ddlockd/i;
$workdir = $opt->{'workdir'} || "$mailspool/tmp";
$pidfile = $opt->{'pidfile'} || "/var/run/mailgated.pid";

# Maildir expected.
die "Invalid mailspool: $mailspool\n" unless -d "$mailspool/new";
$mailspool .= '/new';

# shutdown existing daemon?
if ($opt->{'stop'}) {
    if (-e $pidfile) {
        open (PID, $pidfile);
        chomp ($pid = <PID>);
        close PID;
    }
    if (kill 15, $pid) {
        print "Shutting down mailgated.";
    } else {
        print "Mailgated not running?\n";
        exit 0;
    }

    # display something while we're waiting for a 
    # busy mailgate to shutdown
    while (kill 0, $pid) { sleep 1 && print '.'; }
    print "\n";
    exit 0;
}

# daemonize.
if (!$opt->{'foreground'}) {
    fork && exit 0;
    POSIX::setsid() || die "Unable to become session leader: $!\n";

    $pid = fork;
    die "Couldn't fork.\n" unless defined $pid;
    umask 0;
    chdir('/');

    if ($pid != 0) {  # we are the parent
        unless (open (PID, ">$pidfile")) {
            kill 15, $pid;
            die "Couldn't write PID file.  Exiting.\n";
        }
        print PID $pid, "\n";
        close PID;
        print "mailgate started with pid: $pid\n";
        exit 0;
    }

    # we're the child from here on out.
    close STDIN  && open STDIN, "</dev/null";
    close STDOUT && open STDOUT, "+>&STDIN";
    close STDERR && open STDERR, "+>&STDIN";
}

while (1) {
    debug("Starting loop:");
    
    $busy = 1;
    cleanup();

    # Get list of files to process.
    # If a file simply exists in the mailspool, it needs processing.
    # Only process files with a matching hostname, to
    # allow for multiple mailgates working in the
    # same mailspool across NFS.
    # Non NFS spools will process all messages as normal.
    # (hostname as part of the message filename is
    #  part of the Maildir specification) 
    debug("\tprocess");
    opendir(MDIR, $mailspool) || die "Unable to open mailspool $mailspool: $!\n";
    my $count = 0;
    my $MAX_LOOP = 50;
    foreach (readdir(MDIR)) {
        next if /^\./;
        next if $lock eq 'hostname' && ! /\.$hostname\b/;
        process($_);
	exit 0 if $stop;
	last if ++$count == $MAX_LOOP;
    }
    closedir MDIR;

    $busy = 0;
    debug("\tdone\n");

    # sleep for a bit if we finished reading the directory
    sleep ($opt->{'foreground'} ? 3 : 10) unless $count == $MAX_LOOP;
}

sub stop_daemon
{ 
    # signal safe since it's not run when in daemon mode:
    debug("Shutting down...\n");  

    exit 0 unless $busy;
    $stop = 1;
}

sub debug
{
    return unless $opt->{'foreground'};
    print STDERR (shift) . "\n";
}

# the filename of a mail message - Maildir++ style.
# (time.pid.hostname:flags)
sub set_status
{
    my ($file, $reason, $resetattempt) = @_;
    my ($name, $flags) = ($1, $2) if $file =~ /^(.+?)(?::(.+))?$/;
    my ($oldreason, $attempt) = ($1, $2) if $flags =~ /^(\w)(\d+)$/;
    $reason ||= $oldreason;
    $attempt = 0 if $resetattempt;

    my $newname = $name . ":" . $reason . $attempt++;
    return 0; # todo.  rename() didn't work in a quick test.
}

# return the status code and attempt number
# of a mail message.
sub get_status
{
    my $file = shift;
    return ($1, $2) if $file =~ /:(\w)(\d+)$/;
}

# Either an unrecoverable error, or a total success.  ;)
# Regardless, we're done with this message.
# Remove it so it isn't processed again.
sub dequeue
{
    my ($file, $msg) = @_;
    debug("\t\t dequeued: $msg") if $msg;
    unlink("$mailspool/$file") || debug("\t\t Can't unlink $file!");
    return 0;
}

sub process
{
    my $file = shift;
    debug("\t\t$file");
    my $tmpdir = File::Temp::tempdir("ljmailgate_" . 'X' x 20, DIR=>$workdir);
    my $parser = new MIME::Parser;
    $parser->output_dir($tmpdir);

    # Close the message as quickly as possible, in case
    # we need to change status mid process.
    open(MESSAGE, "$mailspool/$file") || debug("\t\t Can't open file: $!") && return;
    my $entity;
    eval { $entity = $parser->parse(\*MESSAGE) };
    close MESSAGE;
    return dequeue($file, "Can't parse MIME") if $@;

    my $head = $entity->head;
    $head->unfold;

    my $subject = $head->get('Subject');
    chomp $subject;

    # ignore spam/vacation/auto-reply messages
    if ($subject =~ /auto.?(response|reply)/i ||
            $subject =~ /^(Undelive|Mail System Error - |ScanMail Message: |\+\s*SPAM|Norton AntiVirus)/i ||
            $subject =~ /^(Mail Delivery Problem|Mail delivery failed)/i ||
            $subject =~ /^failure notice$/i ||
            $subject =~ /\[BOUNCED SPAM\]/i ||
            $subject =~ /^Symantec AVF /i ||
            $subject =~ /Attachment block message/i ||
            $subject =~ /Use this patch immediately/i ||
            $subject =~ /^YOUR PAYPAL\.COM ACCOUNT EXPIRES/i ||
            $subject =~ /^don't be late! ([\w\-]{1,15})$/i || 
            $subject =~ /^your account ([\w\-]{1,15})$/i) 
    {
        return dequeue($file, "Spam");
    }

    # quick and dirty (and effective) scan for viruses
    return dequeue($file, "Virus found") if virus_check($entity);

    # stop more spam, based on body text checks
    my $tent = LJ::Emailpost::get_entity($entity);
    return dequeue($file, "Can't find text entity") unless $tent;
    my $body = $tent->bodyhandle->as_string;
    $body = LJ::trim($body);

    ### spam
    if ($body =~ /I send you this file in order to have your advice/i ||
            $body =~ /^Content-Type: application\/octet-stream/i||
            $body =~ /^(Please see|See) the attached file for details\.?$/i)
    {
        return dequeue($file, "Spam");
    }

    # see if it's a post-by-email
    my @to = Mail::Address->parse($head->get('To'));
    if (@to == 1 && $to[0]->address =~ /^(\S+?)\@\Q$LJ::EMAIL_POST_DOMAIN\E$/i) {
        my $user = $1;
        # FIXME: verify auth (extra from $user/$subject/$body), require ljprotocol.pl, do post.
        # unresolved:  where to temporarily store messages before they're approved?
        # perhaps the modblob table?  perhaps a column it can be used to determine
        # whether it's a moderated community post vs. an un-acked phone post.
        my $post_rv;
        my $post_msg = LJ::Emailpost::process($entity, $user, \$post_rv);

        if (! $post_rv) {  # don't dequeue
            debug("\t\t keeping for retry: $post_msg");
            # FIXME:  set_status() of mail message?
            return;
        } else {           # dequeue
            return dequeue($file, $post_msg);
        }

    }

    # From this point on we know it's a support request of some type,
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

    return dequeue($file, "Not deliverable to support system (no match To:)") unless $to;

    my $adf = (Mail::Address->parse($head->get('From')))[0];
    my $name = $adf->name;
    my $from = $adf->address;
    $subject ||= "(No Subject)";

    # is this a reply to another post?
    if ($toarg =~ /^(\d+)z(.+)$/)
    {
        my $spid = $1;
        my $miniauth = $2;
        my $sp = LJ::Support::load_request($spid);

        LJ::Support::mini_auth($sp) eq $miniauth
            or die "Invalid authentication?";

        if (LJ::sysban_check('support_email', $from)) {
            my $msg = "Support request blocked based on email.";
            LJ::sysban_block(0, $msg, { 'email' => $from });
            return dequeue($msg);
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
                }) or return dequeue($file, "Error appending request?");

        LJ::Support::touch_request($spid);

        return dequeue($file, "Support reply success");
    }

    # Now see if we want to ignore this particular email and bounce it back with
    # the contents from a file.  Check $LJ::DENY_REQUEST_FROM_EMAIL first.  Note
    # that this will only bounce initial emails; if a user replies to an email
    # from a request that's open, it'll be accepted above.
    my ($content_file, $content);
    if (%LJ::DENY_REQUEST_FROM_EMAIL && $LJ::DENY_REQUEST_FROM_EMAIL{$to}) {
        $content_file = $LJ::DENY_REQUEST_FROM_EMAIL{$to};
        $content = LJ::load_include($content_file);
    }
    if ($content_file && $content) {
        # construct mail to send to user
        my $email = <<EMAIL_END;
$content

Your original message:

$body
EMAIL_END

        # send the message
        LJ::send_mail({
            'to' => $from,
            'from' => $LJ::BOGUS_EMAIL,
            'subject' => "Your Email to $to",
            'body' => $email,
            'wrap' => 1,
        });

        # all done
        return dequeue($file, "Support request bounced to origin");
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
        return dequeue($file, "Support errors: @errors");
    } else {
        return dequeue($file, "Support request success");
    }
}

# returns true on found virus
sub virus_check
{
    my $entity = shift;
    return unless $entity;

    my @exe = LJ::Emailpost::get_entity($entity, { type => 'all' });
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

    foreach my $part (@exe) {
        my $contents = $part->stringify_body;
        $contents =~ s/\n.*//s;
        return 1 if grep { $contents =~ /^$_/; } @virus_sigs;
    }

    return;
}

# Remove prior run workdirs.
# File::Temp's CLEANUP only works upon program exit.
sub cleanup
{
    debug("\tcleanup");
    my $now = time();
    unless (opendir(TMP, $workdir)) {
        debug("\t\tCan't open workdir $workdir: $!");
        return;
    }
    my $limit = 0;
    foreach (readdir(TMP)) {
        next unless /^ljmailgate_/;
        last if $limit >= 50;
        $limit++;
        my $modtime = (stat("$workdir/$_"))[9];
        if ($now - $modtime > 300) {
            File::Path::rmtree("$workdir/$_");
            debug("\t\t$workdir/$_");
        }
    }
    closedir TMP;
    return 0;
}

