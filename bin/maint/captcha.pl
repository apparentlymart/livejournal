#!/usr/bin/perl

use strict;
use vars qw(%maint %maintinfo);

use LJ::Captcha qw{};
use LJ::Blob    qw{};
use File::Temp  qw{tempdir};
use File::Path  qw{rmtree};
use File::Spec  qw{};

our ( $FakeUserId, $ClusterId, $Digits, $DigitCount,
      $ExpireThresUser, $ExpireThresNoUser );

# Data for code-generation
$Digits = "abcdefghkmnpqrstuvwzyz23456789";
$DigitCount = length( $Digits );

# Maximum age of answered captchas.  this is just
# for double-click protection.
$ExpireThresUser   = 2 * 60;   # two minutes

# 24 hours for captchas which were given out but not answered.
# (they might leave their browser window open or something)
$ExpireThresNoUser = 24 * 3600;  # 1 day


#####################################################################
### F U N C T I O N S
#####################################################################

### Read a file in as a scalar and return it
sub readfile ($) {
    my ( $filename ) = @_;
    open my $fh, "<$filename" or die "open: $filename: $!";
    local $/ = undef;
    my $data = <$fh>;

    return $data;
}

### Generate an n-character challenge code
sub gencode ($) {
    my ( $digits ) = @_;
    my $code = '';
    for ( 1..$digits ) {
        $code .= substr( $Digits, int(rand($DigitCount)), 1 );
    }

    return $code;
}


#####################################################################
### M A I N T E N A N C E   T A S K S
#####################################################################
$maintinfo{gen_audio_captchas}{opts}{locking} = "per_host";
$maint{gen_audio_captchas} = sub {
    my (
        $u,                     # Fake user record for Blob::put
        $sql,                   # SQL queries
        $dbh,                   # Database handle (writer)
        $sth,                   # Statement handle
        $count,                 # Count of currently-extant audio challenges
        $need,                  # How many we need to still create
        $make,                  # how many we're actually going to create this round
        $tmpdir,                # Temporary working directory
        $code,                  # The generated challenge code
        $wav,                   # Wav file
        $data,                  # Wav file data
        $err,                   # Error-message ref for Blob::put calls
        $capid,                 # Captcha row id
        $anum,                  # Deseries-ifier value
       );

    print "-I- Generating new audio captchas...\n";

    $dbh = LJ::get_dbh({raw=>1}, "master") or die "Failed to get_db_writer()";
    $dbh->do("SET wait_timeout=28800");

    # Count how many challenges there are currently
    $sql = q{
        SELECT COUNT(*)
        FROM captchas
        WHERE
            type = 'audio'
            AND issuetime = 0
    };

    $count = $dbh->selectrow_array( $sql );

    my $MaxItems = $LJ::CAPTCHA_AUDIO_PREGEN || 500;

    # If there are enough, don't generate any more
    print "Current count is $count of $MaxItems...";
    if ( $count >= $MaxItems ) {
        print "already have enough.\n";
        return;
    } else {
        $make = $need = $MaxItems - $count;
        $make = $LJ::CAPTCHA_AUDIO_MAKE 
            if defined $LJ::CAPTCHA_AUDIO_MAKE && $make > $LJ::CAPTCHA_AUDIO_MAKE;
        print "generating $make new audio challenges.\n";
    }

    # Clean up any old audio directories lying about from failed generations
    # before. In theory, File::Temp::tempdir() is supposed to clean them up
    # itself, but it doesn't appear to be doing so.
    foreach my $olddir ( glob "audio_captchas_*" ) {

        # If it's been more than an hour since it's been changed from the
        # starting time of the script, kill it
        if ( (-M $olddir) * 24 > 1 ) {
            print "cleaning up old working temp directory ($olddir).\n";
            rmtree( $olddir ) or die "rmtree: $olddir: $!";
        }
    }

    # Load the system user for Blob::put() and create an auto-cleaning temp
    # directory for audio generation
    $u = LJ::load_user( "system" )
        or die "Couldn't load the system user.";
    $tmpdir = tempdir( "audio_captchas_XXXXXX", CLEANUP => 0 );

    # Prepare insert statement
    $sql = q{
        INSERT INTO captchas( type, answer, anum )
        VALUES ( 'audio', ?, ? )
    };
    $sth = $dbh->prepare( $sql ) or die "prepare: $sql: ", $dbh->errstr;

    # Generate the challenges
    for ( my $i = 0; $i < $make; $i++ ) {
        print "Generating audio $i...";        
        ( $wav, $code ) = LJ::Captcha::generate_audio( $tmpdir );
        $data = readfile( $wav );
        unlink $wav or die "unlink: $wav: $!";

        # Insert the captcha into the DB
        print "inserting (code = $code)...";
        $anum = int( rand 65_535 );
        $sth->execute( $code, $anum )
            or die "insert: $sql ($code, $anum): ", $sth->errstr;
        $capid = $dbh->{mysql_insertid};

        # Insert the blob
        print "uploading (capid = $capid, anum = $anum)...";
        LJ::Blob::put( $u, 'captcha_audio', 'wav', $capid, $data, \$err )
              or die "Error uploading to media server: $err";
        print "done.\n";
    }

    print "cleaning up working temporary directory ($tmpdir).\n";
    rmtree( $tmpdir ) or die "Failed directory cleanup: $!";

    print "done. Created $make new audio captchas.\n";
    return 1;
};

$maintinfo{gen_image_captchas}{opts}{locking} = "per_host";
$maint{gen_image_captchas} = sub {
    my (
        $u,                     # Fake user record for Blob::put
        $sql,                   # SQL queries
        $dbh,                   # Database handle (writer)
        $sth,                   # Statement handle
        $count,                 # Count of currently-extant audio challenges
        $need,                  # How many we need to still create
        $code,                  # The generated challenge code
        $png,                   # PNG data
        $err,                   # Error-message ref for Blob::put calls
        $capid,                 # Captcha row id
        $anum,                  # Deseries-ifier value
       );

    print "-I- Generating new image captchas...\n";

    $dbh = LJ::get_dbh({raw=>1}, "master") or die "Failed to get_db_writer()";
    $dbh->do("SET wait_timeout=28800");

    # Count how many challenges there are currently
    $sql = q{
        SELECT COUNT(*)
        FROM captchas
        WHERE
            type = 'image'
            AND issuetime = 0
    };

    $count = $dbh->selectrow_array( $sql );

    my $MaxItems = $LJ::CAPTCHA_IMAGE_PREGEN || 1000;

    # If there are enough, don't generate any more
    print "Current count is $count of $MaxItems...";
    if ( $count >= $MaxItems ) {
        print "already have enough.\n";
        return;
    } else {
        $need = $MaxItems - $count;
        print "generating $need new image challenges.\n";
    }

    # Load system user for Blob::put()
    $u = LJ::load_user( "system" )
        or die "Couldn't load the system user.";

    # Prepare insert statement
    $sql = q{
        INSERT INTO captchas( type, answer, anum )
        VALUES ( 'image', ?, ? )
    };
    $dbh = LJ::get_db_writer() or die "Failed to get_db_writer()";
    $sth = $dbh->prepare( $sql ) or die "prepare: $sql: ", $dbh->errstr;

    # Generate the challenges
    for ( my $i = 0; $i < $need; $i++ ) {
        print "Generating image $i...";
        $code = gencode( 7 );
        ( $png ) = LJ::Captcha::generate_visual( $code );

        # Insert the captcha into the DB
        print "inserting (code = $code)...";
        $anum = int( rand 65_535 );
        $sth->execute( $code, $anum )
            or die "insert: $sql ($code, $anum): ", $sth->errstr;
        $capid = $dbh->{mysql_insertid};

        # Insert the blob
        print "uploading (capid = $capid, anum = $anum)...";
        LJ::Blob::put( $u, 'captcha_image', 'png', $capid, $png, \$err )
              or die "Error uploading to media server: $err";
        print "done.\n";
    }

    print "done. Created $need new image captchas.\n";
    return 1;
};

$maint{clean_captchas} = sub {
    my (
        $u,                     # System user
        $expired,               # arrayref of arrayrefs of expired captchas
        $dbh,                   # Database handle (writer)
        $sql,                   # SQL statement
        $sth,                   # Statement handle
        $count,                 # Deletion count
        $err,                   # Error message reference for Blob::delete calls
       );

    print "-I- Cleaning captchas.\n";

    # Find captchas to delete
    $sql = q{
        SELECT
            capid, type
        FROM captchas
        WHERE
	    ( issuetime <> 0 AND issuetime < ? )
	    OR
            ( userid > 0
	      AND ( issuetime <> 0 AND issuetime < ? )
	      )
        LIMIT 2500
    };
    $dbh = LJ::get_db_writer();
    $expired = $dbh->selectall_arrayref( $sql, undef,
					 time() - $ExpireThresNoUser,
					 time() - $ExpireThresUser );
    die "selectall_arrayref: $sql: ", $dbh->errstr if $dbh->err;

    if ( @$expired ) {
        print "found ", scalar @$expired, " captchas to delete...\n";
    } else {
        print "Done: No captchas to delete.\n";
        return;
    }

    # Prepare deletion statement
    $sql = q{ DELETE FROM captchas WHERE capid = ? };
    $sth = $dbh->prepare( $sql );

    # Fetch system user
    $u = LJ::load_user( "system" )
        or die "Couldn't load the system user.";

    # Now delete each one from the DB and the media server
    foreach my $captcha ( @$expired ) {
        my ( $capid, $type ) = @$captcha;
        print "Deleting captcha $capid ($type)\n";
        my $ext = $type eq 'audio' ? 'wav' : 'png';

        LJ::Blob::delete( $u, "captcha_$type", $ext, $capid, \$err )
              or die "Failed to delete $type file from media server for ".
                  "capid = $capid: $err";
        $sth->execute( $capid )
            or die "execute: $sql ($capid): ", $sth->errstr;
        $count++;
    }

    print "Done: deleted $count expired captchas.\n";
    return 1;
};

