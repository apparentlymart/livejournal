#!/usr/bin/perl

package LJ::Emailpost;
use strict;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljconfig.pl";
    if ($LJ::USE_PGP) {
        eval 'use GnuPG::Interface';
        die "Could not load GnuPG::Interface." if $@;
    }
}

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
require "$ENV{LJHOME}/cgi-bin/ljprotocol.pl";
require "$ENV{LJHOME}/cgi-bin/fbupload.pl";
use MIME::Words ();
use IO::Handle;
use Image::Size;

# $rv - scalar ref from mailgated.
# set to 1 to dequeue, 0 to leave for further processing.
sub process {
    my ($entity, $to, $rv) = @_;
    my $head = $entity->head;
    my ($subject, $body);
    $head->unfold;

    $$rv = 1;  # default dequeue

    # Parse email for lj specific info
    my ($user, $journal, $pin);
    ($user, $pin) = split(/\+/, $to);
    ($user, $journal) = split(/\./, $user) if $user =~ /\./;
    my $u = LJ::load_user($user);
    return unless $u;
    LJ::load_user_props($u, 'emailpost_pin') unless (lc($pin) eq 'pgp' && $LJ::USE_PGP);

    # Pick what address to send potential errors to.
    my @froms = Mail::Address->parse($head->get('From:'));
    return unless @froms;
    my $from = $froms[0]->address;
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

    my $err = sub {
        my ($msg, $opt) = @_;

        # FIXME: Need to log last 10 errors to DB / memcache
        # and create a page to watch this stuff.

        my $errbody;
        $errbody .= "There was an error during your email posting:\n\n";
        $errbody .= $msg;
        if ($body) {
            $errbody .= "\n\n\nOriginal posting follows:\n\n";
            $errbody .= $body;
        }

        # Rate limit email to 1/5min/address
        if ($opt->{'sendmail'} && $err_addr &&
            LJ::MemCache::add("rate_eperr:$err_addr", 5, 300)) {
            LJ::send_mail({
                    'to' => $err_addr,
                    'from' => $LJ::BOGUS_EMAIL,
                    'fromname' => "$LJ::SITENAME Error",
                    'subject' => "$LJ::SITENAME posting error: $subject",
                    'body' => $errbody
                    });
        }
        $$rv = 0 if $opt->{'retry'};
        return $msg;
    };

    # Get various email parts.
    my $content_type = $head->get('Content-type:');
    my $tent = get_entity($entity);
    return $err->("Unable to find any text content in your mail", { sendmail => 1 }) unless $tent;
    $subject = $head->get('Subject:');
    $body = $tent->bodyhandle->as_string;
    $body =~ s/^\s+//;
    $body =~ s/\s+$//;

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
        return $err->("Unable to locate your PIN.", { sendmail => 1 }) unless $pin;
        return $err->("Invalid PIN.", { sendmail => 1 }) unless lc($pin) eq lc($u->{emailpost_pin});
    }
    return $err->("Email gateway access denied for your account type.", { sendmail => 1 })
        unless LJ::get_cap($u, "emailpost");

    # Snag charset and do utf-8 conversion
    my ($charset, $format);
    $charset = $1 if $content_type =~ /\bcharset=['"]?(\S+?)['"]?[\s\;]/i;
    $format = $1 if $content_type =~ /\bformat=['"]?(\S+?)['"]?[\s\;]/i;
    if (defined($charset) && $charset !~ /^UTF-?8$/i) { # no charset? assume us-ascii
        return $err->("Unknown charset encoding type.", { sendmail => 1 })
            unless Unicode::MapUTF8::utf8_supported_charset($charset);
        $body = Unicode::MapUTF8::to_utf8({-string=>$body, -charset=>$charset});

        # check subject for rfc-1521 junk
        if ($subject =~ /^=\?/) {
            my @subj_data = MIME::Words::decode_mimewords($subject);
            if (@subj_data) {
                $subject = Unicode::MapUTF8::to_utf8({-string=>$subj_data[0][0],
                                                      -charset=>$subj_data[0][1]});
            }
        }
    }

    # Also check subjects of UTF-8 emails for encoded subject lines [support: 220926]
    elsif ($subject =~ /^=\?utf-8/i) {
        my @subj_data = MIME::Words::decode_mimewords( $subject );
        $subject = $subj_data[0][0] if @subj_data;
    }

    # PGP signed mail?  We'll see about that.
    if (lc($pin) eq 'pgp' && $LJ::USE_PGP) {
        my %gpg_errcodes = ( # temp mapping until translation
                'bad'         => "PGP signature found to be invalid.",
                'no_key'      => "You don't have a PGP key uploaded.",
                'bad_tmpdir'  => "Problem generating tempdir: Please try again.",
                'invalid_key' => "Your PGP key is invalid.  Please upload a proper key.",
                'not_signed'  => "You specified PGP verification, but your message isn't PGP signed!");
        my $gpgerr;
        my $gpgcode = LJ::Emailpost::check_sig($u, $entity, \$gpgerr);
        unless ($gpgcode eq 'good') {
            my $errstr = $gpg_errcodes{$gpgcode};
            $errstr .= "\nGnuPG error output:\n$gpgerr\n" if $gpgerr;
            return $err->($errstr, { sendmail => 1 });
        }
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
            $err->("Friendgroup \"$lj_headers{security}\" not found.  Your journal entry was posted privately.", { sendmail => 1 });
            $lj_headers{security} = 'private';
        }
    }

    # if they specified a imgsecurity header but it isn't valid, default
    # to private.  Otherwise, set to what they specified.
    if ($lj_headers{'imgsecurity'} &&
        $lj_headers{'imgsecurity'} !~ /^(private|regusers|friends|public)$/) {
        $lj_headers{'imgsecurity'} = 0;
    }
    if ($lj_headers{'imgsecurity'} =~ /^(private|regusers|friends|public)$/) {
        my %groupmap = ( private => 0, regusers => 253,
                         friends => 254, public => 255 );

        $lj_headers{'imgsecurity'} = $groupmap{$1};
    }

    $lj_headers{'imgcut'}    ||= 'totals';
    $lj_headers{'imglayout'} ||= 'vertical';

    # upload picture attachments to fotobilder.
    my $fb_upload_errstr;
    # undef return value? retry posting for later.
    my $fb_upload = upload_images($entity, $u, \$fb_upload_errstr, 
                               { imgsec  => $lj_headers{'imgsecurity'},
                                 galname => $lj_headers{'gallery'},
                               }) || return $err->($fb_upload_errstr, { retry => 1 });

    # if we found and successfully uploaded some images...
    if (ref $fb_upload eq 'HASH') {
        my $icount = scalar keys %$fb_upload;
        $body .= "\n\n";

        # set journal image display size
        my @valid_sizes = qw(100x100 320x240 640x480);
        my $size = lc($lj_headers{'imgsize'});
        $size = '320x240' unless grep { $size eq $_; } @valid_sizes;

        # insert image links into post body
        $body .= "<lj-cut text='$icount " .
                  (($icount == 1) ? 'image' : 'images') . "'>"
                  if $lj_headers{'imgcut'} eq lc('totals');
        $body .= "<span style='white-space: nowrap;'>" if $lj_headers{'imglayout'} =~ /^horiz/i;
        foreach my $img (keys %$fb_upload) {
            my $i = $fb_upload->{$img};
            $body .= "<lj-cut text='$img'>" if $lj_headers{'imgcut'} eq lc('titles');
            $body .= "<a href='$i->{'url'}/'>";
            $body .= "<img src='$i->{'url'}/s$size' alt='$img' border='0'></a>";
            $body .= ($lj_headers{'imglayout'} =~ /^horiz/i) ? '&nbsp;' : '<br />';
            $body .= "</lj-cut> " if $lj_headers{'imgcut'} eq lc('titles');
        }
        $body .= "</lj-cut>\n" if $lj_headers{'imgcut'} eq lc('totals');
        $body .= "</span>" if $lj_headers{'imglayout'} =~ /^horiz/i;
    }

    # at this point, there are either no images in the message ($fb_upload == 1)
    # or we had some error during upload that we may or may not want to retry
    # from.  $fb_upload contains the http error code.
    if ($fb_upload == 400) { 
        # bad request - don't retry, but go ahead and post the body to
        # the journal, postfixed with the remote error.
        $body .= "\n\n";
        $body .= "($fb_upload_errstr)";
    }

    # build lj entry
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

    # post!
    my $post_error;
    LJ::Protocol::do_request("postevent", $req, \$post_error, { noauth=>1 });
    return $err->(LJ::Protocol::error_message($post_error)) if $post_error;

    return "Email post success";
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

# By default, returns first plain text entity from email message.
# Specifying a type will return an array of MIME::Entity handles
# of that type. (image, application, etc)
# Specifying a type of 'all' will return all MIME::Entities,
# regardless of type.
sub get_entity
{
    my ($entity, $opts) = @_;
    return if $opts && ref $opts ne 'HASH';
    my $type = $opts->{'type'} || 'text';

    my $head = $entity->head;
    my $mime_type = $head->mime_type;

    return $entity if $type eq 'text' && $mime_type eq "text/plain";
    my @entities;

    # Only bother looking in messages that advertise attachments
    if ($mime_type =~ m#^multipart/(?:alternative|signed|mixed)$#) {
        my $partcount = $entity->parts;
        for (my $i=0; $i<$partcount; $i++) {
            my $alte = $entity->parts($i);

            return $alte if $alte->mime_type eq "text/plain" && $type eq 'text';
            push @entities, $alte if $type eq 'all';

            if ($type eq 'image' &&
                $alte->mime_type =~ m#^application/octet-stream#) {
                my $alte_head = $alte->head;
                my $filename = $alte_head->recommended_filename;
                push @entities, $alte if $filename =~ /\.(?:gif|png|tiff?|jpe?g)$/;
            }
            push @entities, $alte if $alte->mime_type =~ /^$type/ &&
                                     $type ne 'all';

            # Recursively search through nested MIME for various pieces
            if ($alte->mime_type =~ m#^multipart/(?:mixed|related)$#) {
                if ($type eq 'text') {
                    my $text_entity = get_entity($entity->parts($i));
                    return $text_entity if $text_entity;
                } else {
                    push @entities, get_entity($entity->parts($i), $opts);
                }
            }
        }
    }

    return @entities if $type ne 'text' && scalar @entities;
    return;
}


# Verifies an email pgp signature as being valid.
# Returns codes so we can use the pre-existing err subref,
# without passing everything all over the place.
sub check_sig {
    my ($u, $entity, $gpg_err) = @_;

    LJ::load_user_props($u, 'public_key');
    my $key = $u->{public_key};
    return 'no_key' unless $key;

    # Create work directory.
    my $tmpdir = File::Temp::tempdir("ljmailgate_" . 'X' x 20, DIR=>$main::workdir);
    return 'bad_tmpdir' unless -e $tmpdir;

    my ($in, $out, $err, $status,
        $gpg_handles, $gpg, $gpg_pid, $ret);

    my $check = sub {
        my %rets =
            (
             'NODATA 1'     => 1,   # no key or no signed data
             'NODATA 2'     => 2,   # no signed content
             'NODATA 3'     => 3,   # error checking sig (crc)
             'IMPORT_RES 0' => 4,   # error importing key (crc)
             'BADSIG'       => 5,   # good crc, bad sig
             'GOODSIG'      => 6,   # all is well
            );
        while (my $gline = <$status>) {
            foreach (keys %rets) {
                next unless $gline =~ /($_)/;
                return $rets{$1};
            }
        }
        return 0;
    };

    my $gpg_cleanup = sub {
        close $in;
        close $out;
        waitpid $gpg_pid, 0;
        undef foreach $gpg, $gpg_handles;
    };

    my $gpg_pipe = sub {
        $_ = IO::Handle->new() foreach $in, $out, $err, $status;
        $gpg_handles = GnuPG::Handles->new( stdin  => $in,  stdout=> $out,
                                            stderr => $err, status=> $status );
        $gpg = GnuPG::Interface->new();
        $gpg->options->hash_init( armor=>1, homedir=>$tmpdir );
        $gpg->options->meta_interactive( 0 );
    };

    # Pull in user's key, add to keyring.
    $gpg_pipe->();
    $gpg_pid = $gpg->import_keys( handles=>$gpg_handles );
    print $in $key;
    $gpg_cleanup->();
    $ret = $check->();
    if ($ret && $ret == 1 || $ret == 4) {
        $$gpg_err .= "    $_" while (<$err>);
        return 'invalid_key';
    }

    my ($txt, $txt_f, $txt_e, $sig_e);
    $txt_e = (get_entity($entity))[0];
    $txt = $txt_e->as_string() if $txt_e;
    if ($entity->effective_type() eq 'multipart/signed') {
        # attached signature
        $sig_e = (get_entity($entity, { type => 'application/pgp-signature' }))[0];
        my $txt_fh;
        ($txt_fh, $txt_f) =
            File::Temp::tempfile('plaintext_XXXXXXXX', DIR => $tmpdir);
        print $txt_fh $txt;
        close $txt_fh;
    } # otherwise, it's clearsigned

    # Validate message.
    # txt_e->bodyhandle->path() is clearsigned message in its entirety.
    # txt_f is the ascii text that was signed (in the event of sig-as-attachment),
    #     with MIME headers attached.
    $gpg_pipe->();
    $gpg_pid =
        $gpg->wrap_call( handles => $gpg_handles,
                         commands => [qw( --trust-model always --verify )],
                         command_args => $sig_e ? 
                             [$sig_e->bodyhandle->path(), $txt_f] :
                             $txt_e->bodyhandle->path()
                    );
    $gpg_cleanup->();
    $ret = $check->();
    if ($ret && $ret != 6) {
        $$gpg_err .= "    $_" while (<$err>);
        return 'bad' if $ret =~ /[35]/;
        return 'not_signed' if $ret =~ /[12]/;
    }

    return 'good' if $ret == 6;
    return undef;
}

# Upload images to a Fotobilder installation.
# Return codes:
# 1 - no images found in mime entity
# undef - failure during upload
# http_code - failure during upload w/ code
# hashref - { title => url } for each image uploaded
sub upload_images
{
    my ($entity, $u, $rv, $opts) = @_;
    return 1 unless LJ::get_cap($u, 'fb_can_upload') && $LJ::FB_SITEROOT;

    my @imgs = get_entity($entity, { type => 'image' });
    return 1 unless scalar @imgs;

    my %images;
    foreach my $img_entity (@imgs) {
        my $img     = $img_entity->bodyhandle;
        my $path    = $img->path;
        
        my ($width, $height) = Image::Size::imgsize($path);

        my ($title, $url) =
        LJ::FBUpload::do_upload($u, $rv,
                                { path    => $path,
                                  rawdata => \$img->as_string,
                                  imgsec  => $opts->{'imgsec'},
                                  galname => $opts->{'galname'},
                                });

        # error posting, we have a http_code (stored in $title)
        return $title if $title && ! $url;
        # error posting, no http_code
        return if $$rv;

        $images{$title} = {
                    'url'    => $url,
                    'width'  => $width,
                    'height' => $height
        };
    }

    return \%images if scalar keys %images;
    return;
}

1;

