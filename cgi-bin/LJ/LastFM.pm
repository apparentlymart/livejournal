#!/usr/bin/perl

# LastFM - API to LastFM
package LJ::LastFM;

use strict;

use LWP::UserAgent;
use HTML::Entities;
use XML::Parser;
use Encode;

# Get current track
sub current {
    my $username = LJ::eurl(shift);

    return { error => "Missing last.fm credentials" }
        unless $LJ::LAST_FM_API_KEY && $LJ::LAST_FM_BASE_URL;

    my $ua = LJ::get_useragent( role=>'last_fm', timeout=>$LJ::LAST_FM_TIMEOUT );
    my $url = "$LJ::LAST_FM_BASE_URL&api_key=$LJ::LAST_FM_API_KEY&user=$username";
    my $response = $ua->get($url);
    unless ($response->is_success) {
        warn "Can't get data from last.fm: " . $response->status_line;
        return { error => "Can't retrieve data from last.fm" };
    }
    
    my $content = $response->content();

    # process xml
    my $in_current_play_tag = 0;    # if we are inside track tag with nowplaying attribute
    my $current_tag = '';           # a name of a current tag

    # error
    my $error_code  = 0;
    my $error_message = '';

    # now plaing song attributes
    my $artist = '';
    my $name = '';

    # Handlers.
    # on tag start:
    my $handler_start = sub {
        my $expat = shift;
        my $element = shift;
        my %attr = @_;

        # catch tag 'track' with 'nowplaying=true'
        if ($element eq "track"
            && exists($attr{'nowplaying'}) && $attr{'nowplaying'} eq "true") {
            $in_current_play_tag = 1;
            return;
        }

        $error_code = $attr{'code'}
            if ($element eq "error" && exists($attr{'code'}));

        # for all other tags just remember name
        $current_tag = $element;
    };

    # on tag end:
    my $handler_end = sub {
        my $expat = shift;
        my $element = shift;
        my %attr = @_;

        # if we leave 'track' tag
        if ($element eq "track") {
            $in_current_play_tag = 0;
        }

        # forget a name of a current tag
        $current_tag = '';
    };

    # inside a tag:
    my $handler_char = sub {
        my $expat = shift;
        my $string = shift;

        # 'error'
        if ($current_tag eq 'error') {
            $error_message = $string;
            return;
        }

        # pay attention only on current playing tracks
        return unless($in_current_play_tag);

        # remember song attributes
        if ($current_tag eq "artist") {
            $artist = $string;
            return;
        }

        if ($current_tag eq "name") {
            $name = $string;
            return;
        }
    };

    my $parser = new XML::Parser(Handlers => {
            Start => $handler_start,
            End   => $handler_end,
            Char  => $handler_char,
        });
    eval { $parser->parse($content); };
    if ($@) { # invalid xml
        return { error => "Can't retrieve data from last.fm: wrong response from server" };
    }

    if ($error_message) {
        return { error => "Can't retrieve data from last.fm: $error_message" };
    }

    # This prevents worker from die when it catch unicode characters in last.fm title.
    # (turn off UTF-8 flags from text strings)
    ($artist, $name) = map { Encode::is_utf8($_) ? Encode::encode("utf8", $_) : $_ } ($artist, $name);

    if ($artist || $name) {
        my $track = HTML::Entities::decode(($artist ? "$artist - $name" : $name) . ' | Scrobbled by Last.fm');
        return { data => $track };
    } else {
        return { error => 'No "now listening" track in last.fm data' };
    }
}

1;
