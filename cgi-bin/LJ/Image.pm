package LJ::Image;
use strict;
use Carp qw(croak);
#use Class::Autouse qw( Image::Size );

# given an image and some dimensions, will return the dimensions that the image
# should be if it was resized to be no greater than the given dimensions
# (keeping proportions correct).
#
# default dimensions to resize to are:
# 320x240 (for a horizontal image)
# 240x320 (for a vertical image)
# 240x240 (for a square image)
sub get_dimensions_of_resized_image {
    my $class = shift;
    my $imageref = shift;
    my %opts = @_;

    my $given_width = $opts{width} || 320;
    my $given_height = $opts{height} || 240;

    my $percentage = 1;
    require Image::Size;
    my ($width, $height) = Image::Size::imgsize($imageref);
    die "Unable to get image size." unless $width && $height;

    if ($width > $height) {
        if ($width > $given_width) {
            $percentage = $given_width / $width;
        } elsif ($height > $given_height) {
            $percentage = $given_height / $height;
        }
    } elsif ($height > $width) {
        if ($width > $given_height) {
            $percentage = $given_height / $width;
        } elsif ($height > $given_width) {
            $percentage = $given_width / $height;
        }
    } else { # $width == $height
        my $min = $given_width < $given_height ? $given_width : $given_height;
        if ($width > $min) {
            $percentage = $min / $width;
        }
    }

    $width = int($width * $percentage);
    $height = int($height * $percentage);

    return ( width => $width, height => $height );
}

sub prefetch_image_response {
    my $class = shift;
    my $img_url = shift;
    my %opts = @_;

    my $timeout = defined $opts{timeout} ? $opts{timeout} : 3;

    my $ua = LJ::get_useragent( role => 'image_prefetcher', timeout => $timeout ) or die "Unable to get user agent for image";
    $ua->agent("LJ-Image-Prefetch/1.0");

    my $req = HTTP::Request->new( GET => $img_url ) or die "Unable to make HTTP request for image";
    $req->header( Referer => "livejournal.com" );
    my $res = $ua->request($req);

    return $res;
}

# given an image URL, prefetches that image and returns a reference to it
sub prefetch_image {
    my $class = shift;
    my $img_url = shift;
    my %opts = @_;

    my $res = $class->prefetch_image_response($img_url, %opts);

    return undef unless $res->is_success;
    return \$res->content;
}

sub get_image_content {
    my $class   = shift;
    my $img_src = shift;

    ## varlamov.me request the real useragent. it set the speed to 200b/s on default 'user-agent'
    my $ua = LWPx::ParanoidAgent->new (
        agent   => 'Mozilla/5.0',
    );

    ## Allow request to local network (ic.pics.lj.com)
    $ua->whitelisted_hosts (
        qr/^172\./,
    );
    $ua->timeout (30);

    my $status_code = 0;
    my $result;
    my $iter = 2;
    while (1) {
        $result = eval { $ua->get($img_src) };
        if ($@) {
            return undef;
        }
        if ($img_src =~ /^http:\/\/ic?\.pics\.livejournal\.com/) {
            my $new_url = $result->header ('X-Mog-Pth');
            $img_src = $new_url if $new_url;
            last unless $iter--;
        } elsif (($status_code = $result->code) =~ /302|301/) {
            $img_src = $result->header ('Location');
        } else {
            last;
        }
    }

    return $result->content;
}

1;
