#!/usr/bin/perl

use LJ::Captcha qw{};
use LJ::Blob    qw{};
use File::Temp  qw{tempdir};

our ( $MaxItems, $FakeUserId, $ClusterId, $Digits, $DigitCount, $ExpireThreshold );

# Max # of items that can be in the DB. Will create no more than this number -
# <count of items in the DB>
$MaxItems = 500;

# Data for code-generation
$Digits = "abcdefghkmnpqrstuvwzyz23456789";
$DigitCount = length( $Digits );

# Maximum age of an issued captcha, in seconds.
$ExpireThreshold = ( 24 * 3600 ); # 24 hours


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
$maint{gen_audio_captchas} = sub {
    my (
        $u,                     # Fake user record for Blob::put
        $sql,                   # SQL queries
        $dbr,                   # Database handle (reader)
        $dbh,                   # Database handle (writer)
        $sth,                   # Statement handle
        $count,                 # Count of currently-extant audio challenges
        $need,                  # How many we need to still create
        $tmpdir,                # Temporary working directory
        $code,                  # The generated challenge code
        $wav,                   # Wav file
        $data,                  # Wav file data
        $err,                   # Error-message ref for Blob::put calls
        $capid,                 # Captcha row id
        $anum,                  # Deseries-ifier value
       );

    # :FIXME: Is this correct? I don't know what '-I-' means, but lots of other
    # scripts use it...
    print "-I- Generating new audio captchas...\n";

    # Count how many challenges there are currently
    $sql = q{
        SELECT COUNT(*)
        FROM captchas
        WHERE
            type = 'audio'
            AND issuetime = 0
    };

    $dbr = LJ::get_db_reader() or die "Failed to get_db_reader()";
    ( $count ) = $dbr->selectrow_array( $sql );

    # If there are enough, don't generate any more
    print "Current count is $count of $MaxItems...";
    if ( $count >= $MaxItems ) {
        print "already have enough.\n";
        return;
    } else {
        $need = $MaxItems - $count;
        print "generating $need new audio challenges.\n";
    }

    # Load the system user for Blob::put() and create an auto-cleaning temp
    # directory for audio generation
    $u = LJ::load_user( "system" )
        or die "Couldn't load the system user.";
    $tmpdir = tempdir( "audio_captchas_XXXXXX", CLEANUP => 1 );

    # Prepare insert statement
    $sql = q{
        INSERT INTO captchas( type, answer, anum )
        VALUES ( 'audio', ?, ? )
    };
    $dbh = LJ::get_db_writer() or die "Failed to get_db_writer()";
    $sth = $dbh->prepare( $sql ) or die "prepare: $sql: ", $dbh->errstr;

    # Generate the challenges
    for ( my $i = 0; $i <= $need; $i++ ) {
        ( $wav, $code ) = LJ::Captcha::generate_audio( $tmpdir );
        $data = readfile( $wav );
        unlink $wav or die "unlink: $wav: $!";

        # Insert the captcha into the DB
        $anum = int( rand 65_535 );
        $sth->execute( $code, $anum )
            or die "insert: $sql ($code, $anum): ", $sth->errstr;
        $capid = $dbh->{mysql_insertid};

        # Insert the blob
        LJ::Blob::put( $u, 'captcha_audio', 'wav', $capid, $data, \$err )
              or die "Error uploading to media server: $err";
    }

    print "done. Created $need new audio captchas.\n";
    return 1;
};


$maint{gen_image_captchas} = sub {
    my (
        $u,                     # Fake user record for Blob::put
        $sql,                   # SQL queries
        $dbr,                   # Database handle (reader)
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

    # :FIXME: Is this correct? I don't know what '-I-' means, but lots of other
    # scripts use it...
    print "-I- Generating new image captchas...\n";

    # Count how many challenges there are currently
    $sql = q{
        SELECT COUNT(*)
        FROM captchas
        WHERE
            type = 'image'
            AND issuetime = 0
    };

    $dbr = LJ::get_db_reader() or die "Failed to get_db_reader()";
    ( $count ) = $dbr->selectrow_array( $sql );

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

    # Prepare insert cursor
    $sql = q{
        INSERT INTO captchas( type, answer, anum )
        VALUES ( 'image', ?, ? )
    };
    $dbh = LJ::get_db_writer() or die "Failed to get_db_writer()";
    $sth = $dbh->prepare( $sql ) or die "prepare: $sql: ", $dbh->errstr;

    # Generate the challenges
    for ( my $i = 0; $i <= $need; $i++ ) {
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
        $expiredate,            # unixtime of oldest-issued captcha to keep
        $expired,               # arrayref of arrayrefs of expired captchas
        $dbh,                   # Database handle (writer)
        $dbr,                   # Database handle (reader)
        $sql,                   # SQL statement
        $sth,                   # Statement handle
        $count,                 # Deletion count
        $err,                   # Error message reference for Blob::delete calls
       );

    $expiredate = time() - $ExpireThreshold;

    # :FIXME: Is this correct? I don't know what '-I-' means, but lots of other
    # scripts use it...
    print "-I- Cleaning captchas that have been used or were issued before ",
        scalar localtime($expiredate), "...\n";

    # Find captchas to delete
    $sql = q{
        SELECT
            capid, type
        FROM captchas
        WHERE
            used = 1
            OR ( issuetime <> 0 AND issuetime < ? )
    };
    $dbr = LJ::get_db_reader();
    $expired = $dbr->selectall_arrayref( $sql, undef, $expiredate );
    die "selectall_arrayref: $sql: ", $dbr->errstr if $dbr->err;

    if ( @$expired ) {
        print "found ", scalar @$expired, " captchas to delete...\n";
    } else {
        print "Done: No captchas to delete.\n";
        return;
    }

    # Prepare deletion cursor
    $sql = q{ DELETE FROM captchas WHERE capid = ? };
    $dbh = LJ::get_db_writer();
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

