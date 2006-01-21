#!/usr/bin/perl

use strict;
package LJ::Captcha;
use GD;
use File::Temp;
use Cwd ();
use Digest::MD5 ();
use LJ::Blob qw{};
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";


# stolen from Authen::Captcha.  code was small enough that duplicating
# was easier than requiring that module, and removing all its automatic
# database tracking stuff and replacing it with ours.  maybe we'll move
# to using it in the future, but for now this works.  (both their code
# and ours is GPL)
sub generate_visual
{
    my ($code) = @_;
    
    my $im_width = 25;
    my $im_height = 35;
    my $length = length($code);

    my $img = $LJ::CAPTCHA_IMAGE_RAW;

    # create a new image and color
    my $im = new GD::Image(($im_width * $length),$im_height);
    my $black = $im->colorAllocate(0,0,0);
    
    # copy the character images into the code graphic
    for(my $i=0; $i < $length; $i++)
    {
        my $letter = substr($code,$i,1);
        my $letter_png = "$img/$letter.png";
        my $source = new GD::Image($letter_png);
        $im->copy($source,($i*($im_width),0,0,0,$im_width,$im_height));
        my $a = int(rand (int(($im_width)/14)))+0;
        my $b = int(rand (int(($im_height)/12)))+0;
        my $c = int(rand (int(($im_width)/3)))-(int(($im_width)/5));
        my $d = int(rand (int(($im_height)/3)))-(int(($im_height)/5));
        $im->copyResized($source,($i*($im_width))+$a,$b,0,0,($im_width)+$c,($im_height)+$d,$im_width,$im_height);
    }
    
    # distort the code graphic
    for(my $i=0; $i<($length*$im_width*$im_height/14+150); $i++)
    {
        my $a = int(rand($length*$im_width));
        my $b = int(rand($im_height));
        my $c = int(rand($length*$im_width));
        my $d = int(rand($im_height));
        my $index = $im->getPixel($a,$b);
        if ($i < (($length*($im_width)*($im_height)/14+200)/100))
        {
            $im->line($a,$b,$c,$d,$index);
        } elsif ($i < (($length*($im_width)*($im_height)/14+200)/2)) {
            $im->setPixel($c,$d,$index);
        } else {
            $im->setPixel($c,$d,$black);
        }
    }
    
    # generate a background
    my $a = int(rand 5)+1;
    my $background_img = "$img/background$a.png";
    my $source = new GD::Image($background_img);
    my ($background_width, $background_height) = $source->getBounds();
    my $b = int(rand (int($background_width/13)))+0;
    my $c = int(rand (int($background_height/7)))+0;
    my $d = int(rand (int($background_width/13)))+0;
    my $e = int(rand (int($background_height/7)))+0;
    my $source2 = new GD::Image(($length*($im_width)),$im_height);
    $source2->copyResized($source,0,0,$b,$c,$length*$im_width,$im_height,$background_width-$b-$d,$background_height-$c-$e);
    
    # merge the background onto the image
    $im->copyMerge($source2,0,0,0,0,($length*($im_width)),$im_height,40);
    
    # add a border
    $im->rectangle(0, 0, $length*$im_width-1, $im_height-1, $black);
    
    return $im->png;
    
}


### get_visual_id() -> ( $capid, $anum )
sub get_visual_id { get_id('image') }
sub get_audio_id { get_id('audio') }


### get_id( $type ) -> ( $capid, $anum )
sub get_id
{
    my ( $type ) = @_;
    my (
        $dbh,                   # Database handle (writer)
        $sql,                   # SQL statement
        $row,                   # Row arrayref
        $capid,                 # Captcha id
        $anum,                  # Unseries-ifier number
        $issuedate,             # unixtime of issue
       );

    # Fetch database handle and lock the captcha table
    $dbh = LJ::get_db_writer()
		or return LJ::error( "Couldn't fetch a db writer." );
    $dbh->selectrow_array("SELECT GET_LOCK('get_captcha', 10)")
                or return LJ::error( "Failed lock on getting a captcha." );

    # Fetch the first unassigned row
    $sql = q{
        SELECT capid, anum
        FROM captchas
        WHERE
            issuetime = 0
            AND type = ?
        LIMIT 1
    };
    $row = $dbh->selectrow_arrayref( $sql, undef, $type )
        or $dbh->do("DO RELEASE_LOCK('get_captcha')") && die "No $type captchas available";
    die "selectrow_arrayref: $sql: ", $dbh->errstr if $dbh->err;
    ( $capid, $anum ) = @$row;

    # Mark the captcha as issued
    $issuedate = time();
    $sql = qq{
        UPDATE captchas
        SET issuetime = $issuedate
        WHERE capid = $capid
    };
    $dbh->do( $sql ) or die "do: $sql: ", $dbh->errstr;
    $dbh->do("DO RELEASE_LOCK('get_captcha')");

    return ( $capid, $anum );
}


### get_visual_data( $capid, $anum, $want_paths )
# if want_paths is true, this function may return an arrayref containing
# one or more paths (disk or HTTP) to the resource
sub get_visual_data
{
    my ( $capid, $anum, $want_paths ) = @_;
    $capid = int($capid);

    my (
        $dbr,                   # Database handle (reader)
        $sql,                   # SQL statement
        $valid,                 # Are the capid/anum valid?
        $data,                  # The PNG data
        $u,                     # System user
        $location,              # Location of the file (mogile/blob)
       );

    $dbr = LJ::get_db_reader();
    $sql = q{
        SELECT capid, location
        FROM captchas
        WHERE
            capid = ?
            AND anum = ?
    };

    ( $valid, $location ) = $dbr->selectrow_array( $sql, undef, $capid, $anum );
    return undef unless $valid;

    if ($location eq 'mogile') {
        die "MogileFS object not loaded.\n" unless LJ::mogclient();
        if ($want_paths) {
            # return path(s) to the content if they want
            my @paths = LJ::mogclient()->get_paths("captcha:$capid");
            return \@paths;
        } else {
            $data = ${LJ::mogclient()->get_file_data("captcha:$capid")};
        }
    } else {
        $u = LJ::load_user( "system" )
            or die "Couldn't load the system user.";

        $data = LJ::Blob::get( $u, 'captcha_image', 'png', $capid )
              or die "Failed to fetch captcha_image $capid from media server";
    }
    return $data;
}


### get_audio_data( $capid, $anum, $want_paths )
# if want_paths is true, this function may return an arrayref containing
# one or more paths (disk or HTTP) to the resource
sub get_audio_data
{
    my ( $capid, $anum, $want_paths ) = @_;
    $capid = int($capid);

    my (
        $dbr,                   # Database handle (reader)
        $sql,                   # SQL statement
        $valid,                 # Are the capid/anum valid?
        $data,                  # The PNG data
        $u,                     # System user
        $location,              # Location of the file (mogile/blob)
       );

    $dbr = LJ::get_db_reader();
    $sql = q{
        SELECT capid, location
        FROM captchas
        WHERE
            capid = ?
            AND anum = ?
    };

    ( $valid, $location ) = $dbr->selectrow_array( $sql, undef, $capid, $anum );
    return undef unless $valid;

    if ($location eq 'mogile') {
        die "MogileFS object not loaded.\n" unless LJ::mogclient();
        if ($want_paths) {
            # return path(s) to the content if they want
            my @paths = LJ::mogclient()->get_paths("captcha:$capid");
            return \@paths;
        } else {
            $data = ${LJ::mogclient()->get_file_data("captcha:$capid")};
        }
    } else {
        $u = LJ::load_user( "system" )
            or die "Couldn't load the system user.";

        $data = LJ::Blob::get( $u, 'captcha_audio', 'wav', $capid )
              or die "Failed to fetch captcha_audio $capid from media server";
    }
    return $data;
}



# ($dir) -> ("$dir/speech.wav", $code)
#  Callers must:
#    -- create unique temporary directory, shared by no other process
#       calling this function
#    -- after return, do something with speech.wav (save on disk server/
#       db/etc), remove speech.wav, then rmdir $dir
#  Requires festival and sox.
sub generate_audio
{
    my ($dir) = @_;
    my $old_dir =  Cwd::getcwd();
    chdir($dir) or return 0;

    my $bin_festival = $LJ::BIN_FESTIVAL || "festival";
    my $bin_sox = $LJ::BIN_SOX || "sox";

    # make up 7 random numbers, without any numbers in a row
    my @numbers;
    my $lastnum;
    for (1..7) {
        my $num;
        do {
            $num = int(rand(9)+1);
        } while ($num == $lastnum);
        $lastnum = $num;
        push @numbers, $num;
    }
    my $numbers_speak = join("... ", @numbers);
    my $numbers_clean = join('', @numbers);

    # generate the clean speech
    open FEST, '|-', $bin_festival or die "Couldn't invoke festival";
    print FEST "(Parameter.set 'Audio_Method 'Audio_Command)\n";
    print FEST "(Parameter.set 'Audio_Required_Format 'wav)\n";
    print FEST "(Parameter.set 'Audio_Required_Rate 44100)\n";
    print FEST "(Parameter.set 'Audio_Command \"mv \$FILE speech.wav\")\n";
    print FEST "(SayText \"$numbers_speak\")\n";
    close FEST or die "Error closing festival";
    
    my $sox = sub {
        my ($effect, $filename, $inopts, $outopts) = @_;
        $effect = [] unless $effect;
        $filename = "speech.wav" unless $filename;
        $inopts = [] unless $inopts;
        $outopts = [] unless $outopts;
        command($bin_sox, @$inopts, $filename, @$outopts, "tmp.wav", @$effect);
        rename('tmp.wav', $filename)
            or die;
    };

    # distort the speech
    $sox->([qw(reverb 0.5 200 100 60 echo 1 0.7 100 0.03 400 0.15)]);
    command($bin_sox, qw(speech.wav noise.wav synth brownnoise 0 vibro 3 0.8 vol 0.1));
    $sox->([qw(fade 0.5)], 'noise.wav');
    $sox->([qw(reverse)], 'noise.wav');
    $sox->([qw(fade 0.5)], 'noise.wav');

    command("${bin_sox}mix", qw(-v 4 speech.wav noise.wav -r 16000 tmp.wav));
    rename('tmp.wav', 'speech.wav') or die;
    unlink('oldspeech.wav', 'noise.wav');
    
    chdir($old_dir) or return 0;
    return ("$dir/speech.wav", $numbers_clean);
}

sub command {
    system(@_) >> 8 == 0 or die "audio command failed, died";
}


### check_code( $capid, $anum, $code, $u ) -> <true value if code is correct>
sub check_code {
    my ( $capid, $anum, $code, $u ) = @_;

    my (
        $dbr,                   # Database handle (reader)
        $sql,                   # SQL query
        $answer,                # Challenge answer
        $userid,                # userid of previous answerer (or 0 if none)
       );

    $sql = q{
        SELECT answer, userid
        FROM captchas
        WHERE
            capid = ?
            AND anum = ?
    };

    # Fetch the challenge's answer based on id and anum.
    $dbr = LJ::get_db_writer();
    ( $answer, $userid ) = $dbr->selectrow_array( $sql, undef, $capid, $anum );

    # if it's already been answered, it must have been answered by the $u
    # given to this function (double-click protection)
    return 0 if $userid && ( ! $u || $u->{userid} != $userid );

    # otherwise, just check answer.
    return lc $answer eq lc $code;
}

# Verify captcha answer if using a captcha session.
# (captcha challenge, code, $u)
# Returns capid and anum if answer correct. (for expire)
sub session_check_code {
    my ($sess, $code, $u) = @_;
    return 0 unless $sess && $code;
    $sess = LJ::get_challenge_attributes($sess);

    $u = LJ::load_user('system') unless $u;

    my $dbcm = LJ::get_cluster_master($u);
    my $dbr = LJ::get_db_reader();
    
    my ($lcapid, $try) =  # clustered
        $dbcm->selectrow_array('SELECT lastcapid, trynum ' .
                               'FROM captcha_session ' .
                               'WHERE sess=?', undef, $sess);
    my ($capid, $anum) =  # global
        $dbr->selectrow_array('SELECT capid,anum ' .
                              'FROM captchas '.
                              'WHERE capid=?', undef, $lcapid);
    if (! LJ::Captcha::check_code($capid, $anum, $code, $u)) {
        # update try and lastcapid
        $u->do('UPDATE captcha_session SET lastcapid=NULL, ' .
               'trynum=trynum+1 WHERE sess=?', undef, $sess);
        return 0;
    }
    return ($capid, $anum);
}

### expire( $capid ) -> <true value if code was expired successfully>
sub expire {
    my ( $capid, $anum, $userid ) = @_;

    my (
        $dbh,                   # Database handle (writer)
        $sql,                   # SQL update query
       );

    $sql = q{
        UPDATE captchas
        SET userid = ?
        WHERE capid = ? AND anum = ? AND userid = 0
    };

    # Fetch the challenge's answer based on id and anum.
    $dbh = LJ::get_db_writer();
    $dbh->do( $sql, undef, $userid, $capid, $anum ) or return undef;

    return 1;
}

# Update/create captcha sessions, return new capid/anum pairs on success.
# challenge, type, optional journalu->{clusterid} for clustering.
# Type is either 'image' or 'audio'
sub session
{
    my ($chal, $type, $cid) = @_;
    return unless $chal && $type;

    my $chalinfo = {};
    LJ::challenge_check($chal, $chalinfo);
    return unless $chalinfo->{valid};

    my $sess = LJ::get_challenge_attributes($chal);
    my ($capid, $anum) = ($type eq 'image') ?
                         LJ::Captcha::get_visual_id() :
                         LJ::Captcha::get_audio_id();


    $cid = LJ::load_user('system')->{clusterid} unless $cid;
    my $dbcm = LJ::get_cluster_master($cid);

    # Retain try count
    my $try = $dbcm->selectrow_array('SELECT trynum FROM captcha_session ' .
                                     'WHERE sess=?', undef, $sess);
    $try ||= 0;
    # Add/update session
    $dbcm->do('REPLACE INTO captcha_session SET sess=?, sesstime=?, '.
              'lastcapid=?, trynum=?', undef, $sess, time(), $capid, $try);
    return ($capid, $anum);
}


1;
