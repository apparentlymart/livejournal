#!/usr/bin/perl
#

package Apache::LiveJournal::PalImg;

use strict;
#use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED);
use PaletteModify;

# for callers to 'ping' as a class method for Class::Autouse to lazily load
sub load { 1 }

# URLs of form /palimg/somedir/file.gif[extra]
# where extras can be:
#   /p...    - palette modify

sub handler
{
    #my $r = shift;
    my $uri = LJ::Request->uri;
    my ($base, $ext, $extra) = $uri =~ m!^/palimg/(.+)\.(\w+)(.*)$!;
    LJ::Request->notes("codepath" => "img.palimg");
    return LJ::Request::NOT_FOUND unless $base && $base !~ m!\.\.!;

    my $disk_file = "$LJ::HOME/htdocs/palimg/$base.$ext";
    return LJ::Request::NOT_FOUND unless -e $disk_file;

    my @st = stat(_);
    my $size = $st[7];
    my $modtime = $st[9];
    my $etag = "$modtime-$size";

    my $mime = {
        'gif' => 'image/gif',
        'png' => 'image/png',
    }->{$ext};

    my $palspec;
    if ($extra) {
        if ($extra =~ m!^/p(.+)$!) {
            $palspec = $1;
        } else {
            return LJ::Request::NOT_FOUND;
        }
    }

    return send_file($disk_file, {
        'mime' => $mime,
        'etag' => $etag,
        'palspec' => $palspec,
        'size' => $size,
        'modtime' => $modtime,
    });
}

sub parse_hex_color
{
    my $color = shift;
    return [ map { hex(substr($color, $_, 2)) } (0,2,4) ];
}

sub send_file
{
    my ($disk_file, $opts) = @_;

    my $etag = $opts->{'etag'};

    # palette altering
    my %pal_colors;
    if (my $pals = $opts->{'palspec'}) {
        my $hx = "[0-9a-f]";
        if ($pals =~ /^g($hx{2,2})($hx{6,6})($hx{2,2})($hx{6,6})$/) {
            # gradient from index $1, color $2, to index $3, color $4
            my $from = hex($1);
            my $to = hex($3);
            return LJ::Request::NOT_FOUND if $from == $to;
            my $fcolor = parse_hex_color($2);
            my $tcolor = parse_hex_color($4);
            if ($to < $from) {
                ($from, $to, $fcolor, $tcolor) =
                    ($to, $from, $tcolor, $fcolor);
            }
            $etag .= ":pg$pals";
            for (my $i=$from; $i<=$to; $i++) {
                $pal_colors{$i} = [ map {
                    int($fcolor->[$_] +
                        ($tcolor->[$_] - $fcolor->[$_]) *
                        ($i-$from) / ($to-$from))
                    } (0..2)  ];
            }
        } elsif ($pals =~ /^t($hx{6,6})($hx{6,6})?$/) {
            # tint everything towards color
            my ($t, $td) = ($1, $2);
            $pal_colors{'tint'} = parse_hex_color($t);
            $pal_colors{'tint_dark'} = $td ? parse_hex_color($td) : [0,0,0];
        } elsif (length($pals) > 42 || $pals =~ /[^0-9a-f]/) {
            return LJ::Request::NOT_FOUND;
        } else {
            my $len = length($pals);
            return LJ::Request::NOT_FOUND if $len % 7;  # must be multiple of 7 chars
            for (my $i = 0; $i < $len/7; $i++) {
                my $palindex = hex(substr($pals, $i*7, 1));
                $pal_colors{$palindex} = [
                                          hex(substr($pals, $i*7+1, 2)),
                                          hex(substr($pals, $i*7+3, 2)),
                                          hex(substr($pals, $i*7+5, 2)),
                                          substr($pals, $i*7+1, 6),
                                          ];
            }
            $etag .= ":p$_($pal_colors{$_}->[3])" for (sort keys %pal_colors);
        }
    }

    $etag = '"' . $etag . '"';
    my $ifnonematch = LJ::Request->header_in("If-None-Match");
    return LJ::Request::HTTP_NOT_MODIFIED if
        defined $ifnonematch && $etag eq $ifnonematch;

    # send the file
    LJ::Request->content_type($opts->{'mime'});
    LJ::Request->header_out("Content-length", $opts->{'size'});
    LJ::Request->header_out("ETag", $etag);
    if ($opts->{'modtime'}) {
        LJ::Request->update_mtime($opts->{'modtime'});
        LJ::Request->set_last_modified();
    }
    LJ::Request->send_http_header();

    # HEAD request?
    return LJ::Request::OK if LJ::Request->method eq "HEAD";

    # this is slow way of sending file.
    # but in productions this code should not be called.
    open my $fh, "<" => $disk_file
        or return LJ::Request::NOT_FOUND;
    binmode $fh;
    my $palette = undef;
    if (%pal_colors) {
        if ($opts->{'mime'} eq "image/gif") {
            $palette = PaletteModify::new_gif_palette($fh, \%pal_colors);
        } elsif ($opts->{'mime'} == "image/png") {
            $palette = PaletteModify::new_png_palette($fh, \%pal_colors);
        }
        unless ($palette) {
            return LJ::Request::NOT_FOUND;  # image isn't palette changeable?
        }
    }
    LJ::Request->print($palette) if $palette;
    while (my $readed = read($fh, my $buf, 1024*1024)){
        LJ::Request->print($buf);
    }
    close $fh;

=head
    my $fh = Apache::File->new($disk_file);
    return LJ::Request::NOT_FOUND unless $fh;
    binmode($fh);

    my $palette;
    if (%pal_colors) {
        if ($opts->{'mime'} eq "image/gif") {
            $palette = PaletteModify::new_gif_palette($fh, \%pal_colors);
        } elsif ($opts->{'mime'} == "image/png") {
            $palette = PaletteModify::new_png_palette($fh, \%pal_colors);
        }
        unless ($palette) {
            return LJ::Request::NOT_FOUND;  # image isn't palette changeable?
        }
    }

    $r->print($palette) if $palette; # when palette modified.
    $r->send_fd($fh); # sends remaining data (or all of it) quickly
    $fh->close();
=cut
    return LJ::Request::OK;
}

1;

