#!/usr/bin/perl

package LJ::Emailpost;
use strict;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljconfig.pl";
    if ($LJ::USE_PGP) {
        eval 'use GnuPG::Interface';
        die "Could not load GnuPG::Interface." if $@;
        eval 'use Mail::GnuPG';
        die "Could not load Mail::GnuPG." if $@;
    }
}

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
require "$ENV{LJHOME}/cgi-bin/ljprotocol.pl";
use MIME::Words ();
use IO::Handle;

sub process {
    my ($entity, $to) = @_;
    my $head = $entity->head;
    my ($subject, $body);
    $head->unfold;

    my $err = sub {
        my ($msg, $who) = @_;

        # FIXME: Need to log last 10 errors to DB / memcache
        # and create a page to watch this stuff.

        return 0 unless $who;
        my $errbody;
        $errbody .= "There was an error during your email posting:\n\n";
        $errbody .= $msg;
        if ($body) {
            $errbody .= "\n\n\nOriginal posting follows:\n\n";
            $errbody .= $body;
        }

        # Rate limit email to 1/5min/address
        if (LJ::MemCache::add("rate_eperr:$who", 5, 300)) {
            LJ::send_mail({ 
                    'to' => $who,
                    'from' => $LJ::BOGUS_EMAIL,
                    'fromname' => "$LJ::SITENAME Error",
                    'subject' => "$LJ::SITENAME posting error: $subject",
                    'body' => $errbody  
                    });
        }
    };

    # Get various email parts.
    my @froms = Mail::Address->parse($head->get('From:'));
    my $from = $froms[0]->address;
    my $content_type = $head->get('Content-type:');
    my $tent = get_entity($entity, 'text');
    return $err->("Unable to find any text content in your mail") unless $tent;
    $subject = $head->get('Subject:');
    $body = $tent->bodyhandle->as_string;
    $body =~ s/^\s+//;
    $body =~ s/\s+$//;

    # Parse email for lj specific info                                                                                
    my ($user, $journal, $pin);
    ($user, $pin) = split(/\+/, $to);
    ($user, $journal) = split(/\./, $user) if $user =~ /\./;
    my $u = LJ::load_user($user);
    return 0 unless $u;
    LJ::load_user_props($u, 'emailpost_pin') unless (lc($pin) eq 'pgp' && $LJ::USE_PGP);

    # Pick what address to send potential errors to.
    my $addrlist = LJ::Emailpost::get_allowed_senders($u);
    my $err_addr;
    foreach (keys %$addrlist) {
        if (lc($from) eq lc &&
                $addrlist->{$_}->{'get_errors'}) {
            $err_addr = $from;
            last;
        }
    }
    $err_addr ||= $u->{email};

    # Strip (and maybe use) pin data from viewable areas
    if ($subject =~ s/^\s*\+([a-z0-9]+)\s+//i) {
        $pin = $1 unless defined $pin;
    }
    if ($body =~ s/^\s*\+([a-z0-9]+)\s+//i) {
        $pin = $1 unless defined $pin;
    }

    # Validity checks.  We only care about these if they aren't using PGP.
    unless (lc($pin) eq 'pgp' && $LJ::USE_PGP) {
        return $err->("No allowed senders have been saved for your account.") unless ref $addrlist;
        my $ok = 0;
        foreach (keys %$addrlist) {
            if (lc($from) eq lc) {
                $ok = 1;
                last;
            }
        }
        return $err->("Unauthorized sender address: $from") unless $ok; # don't mail user due to bounce spam
        return $err->("Unable to locate your PIN.", $err_addr) unless $pin;
        return $err->("Invalid PIN.", $err_addr) unless lc($pin) eq lc($u->{emailpost_pin});
    }
    return $err->("Email gateway access denied for your account type.", $err_addr)
        unless LJ::get_cap($u, "emailpost");

    # Snag charset and do utf-8 conversion
    my ($charset, $format);
    $charset = $1 if $content_type =~ /\bcharset=['"]?(\S+?)['"]?[\s\;]/i;
    $format = $1 if $content_type =~ /\bformat=['"]?(\S+?)['"]?[\s\;]/i;
    if (defined($charset) && $charset !~ /^UTF-?8$/i) { # no charset? assume us-ascii
        return $err->("Unknown charset encoding type.", $err_addr)
            unless Unicode::MapUTF8::utf8_supported_charset($charset);
        $body = Unicode::MapUTF8::to_utf8({-string=>$body, -charset=>$charset});
        # check subject for rfc-1521 junk 
        if ($subject =~ /^=\?(utf-8)?/i) {
            my @subj_data;
            @subj_data = MIME::Words::decode_mimewords($subject);
            if (scalar(@subj_data)) {
                if (! $1) {
                    $subject = Unicode::MapUTF8::to_utf8({-string=>$subj_data[0][0], -charset=>$subj_data[0][1]});
                } else {
                    $subject = $subj_data[0][0];
                }
            }
        }
    }

    # PGP signed mail?  We'll see about that.
    if (lc($pin) eq 'pgp' && $LJ::USE_PGP) {
        my %gpg_errcodes = ( # temp mapping until translation
                'bad' => "PGP signature found to be invalid.",
                'no_key' => "You don't have a PGP key uploaded.",
                'bad_tmpdir' => "Problem generating tempdir: Please try again.",
                'invalid_key' => "Your PGP key is invalid.  Please upload a proper key.",
                'not_signed' => "You specified PGP verification, but your message isn't PGP signed!");
        my $gpgcode = LJ::Emailpost::check_sig($u, $entity);
        return $err->($gpg_errcodes{$gpgcode}, $err_addr) unless $gpgcode eq 'good';
    }

    $body =~ s/^(?:\- )?[\-_]{2,}\s*\r?\n.*//ms; # trim sigs
    $body =~ s/ \n/ /g if lc($format) eq 'flowed'; # respect flowed text

    # Strip pgp clearsigning
    $body =~ s/^\s*-----BEGIN PGP SIGNED MESSAGE-----.+?\n\n//s;
    $body =~ s/-----BEGIN PGP SIGNATURE-----.+//s;

    # Find and set entry props.
    my $props = {};
    my (%lj_headers,$amask);
    if ($body =~ s/^(lj-.+?)\n\n//is) {
        my @headers = split(/\n/, $1);
        foreach (@headers) {
            $lj_headers{lc($1)} = $2 if /^lj-(\w+):\s*(.+?)\s*$/i;
        }
    }
    $props->{picture_keyword} = $lj_headers{userpic};
    $props->{current_mood} = $lj_headers{mood};
    $props->{current_music} = $lj_headers{music};
    $props->{opt_nocomments} = 1 if $lj_headers{comments} =~ /off/i;
    $props->{opt_noemail} = 1 if $lj_headers{comments} =~ /noemail/i;

    $lj_headers{security} = lc($lj_headers{security});
    if ($lj_headers{security} =~ /^(public|private|friends)$/) {
        if ($1 eq 'friends') {
            $lj_headers{security} = 'usemask';
            $amask = 1;
        }
    } elsif ($lj_headers{security}) { # Assume a friendgroup if unknown security mode.
        # Get the mask for the requested friends group, or default to private.
        my $group = LJ::get_friend_group($u, { 'name'=>$lj_headers{security} });
        if ($group) {
            $amask = (1 << $group->{groupnum});
            $lj_headers{security} = 'usemask';
        } else {
            $err->("Friendgroup \"$lj_headers{security}\" not found.  Your journal entry was posted privately.", $err_addr);
            $lj_headers{security} = 'private';
        }
    }

    # FIXME: Pict posting integration should fit in here.
    # my $ient = get_entity($entity, 'image');
    # if ($ient) {
      # my $img = $ient->bodyhandle;

    my $req = {
        'usejournal' => $journal,
        'ver' => 1,
        'username' => $user,
        'event' => $body,
        'subject' => $subject,
        'security' => $lj_headers{security},
        'allowmask' => $amask,
        'props' => $props,
        'tz'    => 'guess',
    };

    my $post_error;
    LJ::Protocol::do_request("postevent", $req, \$post_error, { noauth=>1 });
    return $err->(LJ::Protocol::error_message($post_error)) if $post_error;

    return 1; 
}

# Retreives an allowed email addr list for a given user object.
# Returns a hashref with addresses / flags.
sub get_allowed_senders {
    my $u = shift;
    my (%addr, @address);

    LJ::load_user_props($u, 'emailpost_allowfrom');
    @address = split(/\s*,\s*/, $u->{emailpost_allowfrom});
    return undef unless scalar(@address) > 0;
    
    my %flag_english = ( 'E' => 'get_errors' );

    foreach my $add (@address) {
        my $flags;
        $flags = $1 if $add =~ s/\((.+)\)$//;
        $addr{$add} = {};
        if ($flags) {
            $addr{$add}->{$flag_english{$_}} = 1 foreach split(//, $flags);
        }
    }

    return \%addr;
}

# Inserts email addresses into the database.
# Adds flags if needed.
sub set_allowed_senders {
    my ($u, $addr) = @_;
    my %flag_letters = ( 'get_errors' => 'E' );

    my @addresses;
    foreach (keys %$addr) {
        my $email = $_;
        my $flags = $addr->{$_};
        if (%$flags) {
            $email .= '(';
            foreach my $flag (keys %$flags) {
                $email .= $flag_letters{$flag};
            }
            $email .= ')';
        }
        push(@addresses, $email);
    }
    close T;
    LJ::set_userprop($u, "emailpost_allowfrom", join(", ", @addresses));
}

sub get_entity
{
    my ($entity,$etype) = @_;
    $etype ||= 'text';

    my $head = $entity->head;
    my $mime_type = $head->mime_type;
    if ($mime_type eq "text/plain" && $etype eq 'text') {
        return $entity;
    }

    my $partcount = $entity->parts;
    if ($mime_type eq "multipart/alternative" ||
        $mime_type eq "multipart/signed" ||
        $mime_type eq "multipart/mixed") {
        for (my $i=0; $i<$partcount; $i++) {
            my $alte = $entity->parts($i);
            return $alte if $alte->mime_type eq "text/plain" &&
                            $etype eq 'text';
            return $alte if $alte->mime_type =~ /image\// &&
                            $etype eq 'image';
        }
        return undef;
    }

    if ($mime_type eq "multipart/related" && $etype eq 'text') {
        if ($partcount) {
            return get_entity($entity->parts(0), 'text');
        }
        return undef;
    }

    $entity->dump_skeleton(\*STDERR);
    return undef;
}


# Verifies an email pgp signature as being valid.
# Returns codes so we can use the pre-existing err subref, 
# without passing everything all over the place.
sub check_sig {
    my ($u, $entity) = @_;

    LJ::load_user_props($u, 'public_key');
    my $key = $u->{public_key};
    return 'no_key' unless $key;

    # Create work directory.
    my $tmpdir = File::Temp::tempdir("ljmailgate_" . 'X' x 20, DIR=>'/tmp', CLEANUP=>1 );
    return 'bad_tmpdir' unless chdir($tmpdir);

    # Pull in user's key, add to keyring.
    my ($in, $out, $err, $gpg_handles, $gpg, $gpg_pid);
    $_ = IO::Handle->new() foreach $in, $out, $err;
    $gpg_handles = GnuPG::Handles->new( stdin=>$in, stdout=>$out, stderr=>$err );
    $gpg = GnuPG::Interface->new();
    $gpg->options->hash_init( armor=>1, homedir=>$tmpdir );
    $gpg_pid = $gpg->import_keys( handles=>$gpg_handles );
    print $in $key;
    close $in; close $out;
    waitpid $gpg_pid, 0;
    return 'invalid_key' if int($? / 256);  # invalid pgp key

    # Don't need this stuff anymore.
    undef foreach $gpg, $gpg_handles;

    my ($gpg_email, $ret);
    $gpg_email = new Mail::GnuPG( keydir=>$tmpdir );
    eval { $ret = $gpg_email->verify($entity); };
    if (defined($ret)) {
        $ret == 0 ? return 'good' : return 'bad';
    } else {
        return 'not_signed';
    }
}

