##
## This is a Apache2 handler that implements SHOUTcast/Icecast protocol
##  
## See also: 
##      - http://search.cpan.org/perldoc?Apache::MP3 
##          ("streams" 1 file only, no support for endless streams with "icy-metaint") blocks)
##      - "Programming Erlang" by Joe Armstrong, 
##          chapter 14.7 "A SHOUTcast Server"
##      - http://forums.radiotoolbox.com/viewtopic.php?t=74
##          description of the protocol
##      - http://freshmeat.net/projects/mod_mp3/
##          mod_mp3 for the Apache1
##
## Sample Apache2 config file: 
##      Timeout 60
##      KeepAlive Off
##      SendBufferSize 16384
##      <Perl>
##          use lib '/home/lj/cgi-bin';
##      </Perl>
##      SetHandler perl-script
##      PerlHandler LJ::Radio
##      DocumentRoot /home/lj/var/www/radio/data
##
##      ## Optional config vars:
##      ##  PerlSetVar LJRadioBlockSize 4096
##      ##  PerlSetVar LJRadioVerbose 1      
##
##

package LJ::Radio;

use strict;
use warnings;
use Apache2::RequestRec();
use Apache2::RequestIO();
use Apache2::RequestUtil;
use Apache2::Connection();
use Apache2::Const qw(OK DECLINED SERVER_ERROR);
use APR::Table;

use MP3::Info qw(get_mp3info);
use IO::Dir;
use Fcntl qw(SEEK_SET);
use Data::Dumper qw/Dumper/;

use constant { LOG_INFO => 2, LOG_WARN => 1, LOG_ERROR => 0 };

sub handler {
    my $r = shift;
    
    return DECLINED
        unless $r->method eq 'GET' && -d $r->filename;

    my $block_size  = $r->dir_config("LJRadioBlockSize")    || 8192;
    my $verbose     = $r->dir_config("LJRadioVerbose")      || 0;

    my $self = bless {
        r           => $r,
        block_size  => $block_size,
        verbose     => $verbose,
    };

    if ($self->is_streaming_request) {
        return $self->serve_streaming_request;
    } else {
        return $self->serve_browser_request;
    }
}

sub is_streaming_request {
    my $self = shift;

    my $r = $self->{'r'};
    my $h = $r->headers_in;
    return  $h->get('icy-metadata') 
            || $h->get('User-Agent') =~ /NSPlayer/ ## Microsoft Windows Media player 
            || $r->args('stream');
}

## implementation of SHOUTcast protocol
sub serve_streaming_request {
    my $self = shift;

    my $r = $self->{'r'};
    $self->log(LOG_WARN, "New connection");

    ## print headers
    $r->assbackwards(1); ## notify Apache that we will print all headers ourselves
    $r->print("ICY 200 OK\r\n");
    $r->print("icy-name:LiveJournal Voice Posts\r\n");
    $r->print("icy-genre:voice\r\n");
    $r->print("icy-br:128\r\n");
    $r->print("icy-metaint:$self->{block_size}\r\n");
    $r->print("\r\n");
    $self->log(LOG_WARN, "Headers are printed");

    my $buffer = '';
    my $block_size = $self->{'block_size'};
    my $file_iterator = LJ::Radio::FileIterator->new($self);
  
    SEND_FILE:
    while (!$r->connection->aborted) {
        ## get a file to send to client
        my $file = $file_iterator->get_next_file;
        if (!$file) {
            $r->log(LOG_ERROR, "No more mp3 files found!");
            return SERVER_ERROR;    
        }
        $self->log(LOG_WARN, "File is $file");

        ## get info and open the file, skip ID3 section
        my $info = get_mp3info($file);
        $self->log(LOG_INFO, Dumper($info));
        my $fh;
        unless (open($fh, $file)) {
            $r->log(LOG_ERROR, "Can't read from $file: $!");
            next SEND_FILE;
        }
        unless (seek($fh, $info->{'OFFSET'}, SEEK_SET)) {
            $r->log(LOG_ERROR, "Invalid file $file: can't seek to $info->{'OFFSET'}");
            next SEND_FILE;
        }
       
        ## create a SHOUTcast separator/stream info header
        my $stream_info;
        { 
            my $current_journal = ($file =~ /^\d+-(\w+)-/) ? $1 : '';
            my $h = "StreamTitle=$current_journal";
            my $l = length($h);
            my $k = int( ($l+15)/16 );
            $stream_info = pack("C", $k) . $h . "\0" x ($k*16 - $l);
        }
        
        ## send the file content (actually, data stream section of the file)
        my $l = length($buffer);
        while (my $rv = read($fh, $buffer, $block_size-$l, $l)) {
            die if length($buffer)>$block_size;
            $self->log(LOG_INFO, "Read $rv bytes from $file");
            if (length($buffer)==$block_size) {
                $self->log(LOG_INFO, "Going to print buffer");
                ## $r->print may cause exception for connections aborted by users:
                ## Apache2::RequestIO::print: (103) Software caused connection abort
                eval { $r->print($buffer); }
                    or last SEND_FILE;  
                $self->log(LOG_INFO, "Buffer is printed");
                $buffer = '';

                $r->print($stream_info);
            }
        }
        close $fh;
    }
    $self->log(LOG_WARN, "Connection is closed");
    return OK;
}

## the HTML page that a regular browser will see
sub serve_browser_request {
    my $self = shift;
   
    my $r = $self->{'r'}; 
    my $files = join("\n", map { "<li><a href='$_'>$_</a>" } $self->get_list_of_files('recursive' => 1));
    $r->content_type("text/html");
    $r->print(<<"HTML");
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head>
    <title>Frank Radio</title>
    <meta http-equiv="X-UA-Compatible" content="IE=EmulateIE7; IE=EmulateIE9" />
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <link href="http://l-stat.livejournal.com/framework/error-pages.css" rel="stylesheet" type="text/css" />
    <!--[if lte IE 7]><link rel="stylesheet" href="http://l-stat.livejournal.com/framework/error-pages-ie.css"><![endif]-->
</head>
<body class="error-page">
<div class="header">
    <img src="http://l-stat.livejournal.com/img/error-pages/frank-200.png" width="250" height="260" alt="" class="pic" />
    <div class="desc">
        <h1>Frank Radio</h1>
        <p>Welcome! This page is best seen (well, listened) in audio player that support streams, e.g. iTunes, WinAmp or Microsoft Media Player - just enter the URL and listent to voice posts created by LJ users.</p>
        <p>If you use regular browser and see this text, you may download/play these posts individually:</p>
    </div>
</div>
<div class="content">
    <div class="article">
        <ul>
        $files
        </ul>
    </div>
    <div class="searchbar">
        <h3><a href="http://www.livejournal.com">LiveJournal</a></h3>
    </div>
</div>
</body>
</html>
HTML
    return OK;
}

##
## input:   hash of named options (dir, absolute_path, recursive)
## output:  array of filenames
##
sub get_list_of_files {
    my $self = shift;
    my %opts = @_;
    
    my $absolute_path = delete $opts{'absolute_path'};

    my $dir = $opts{'dir'} || $self->{'r'}->filename;
    $dir =~ s/\/$//;
     
    die "$dir is not directory!"
        unless -d $dir;

    my (@subdirs, @files);
    my $d = IO::Dir->new($dir)
        or die "Can't open dir '$dir': $!";
    while (my $f = $d->read) {
        next if $f =~ /^\./;
        if (-d "$dir/$f") {
            push @subdirs, $f if -r "$dir/$f";
        } elsif ($f =~ /\.mp3/i) {
            push @files, $f;
        }
    }
    close $d;

    if ($opts{'recursive'}) {
        foreach my $subdir (@subdirs) {
            push @files, map { "$subdir/$_" } $self->get_list_of_files(%opts, 'dir' => "$dir/$subdir");
        }
    }

    if ($absolute_path) {
        @files = map { "$dir/$_" } @files;  
    }

    return @files;
}

sub log {
    my $self = shift;
    my $level = shift;
    my $msg = shift;

    if ($self->{'verbose'}>=$level) {
        warn("[$$] $msg");
    }
}

package LJ::Radio::FileIterator;

sub new {
    my $class = shift;
    my $lj_radio = shift;

    return bless {
        lj_radio        => $lj_radio,
        palyed_files    => {},
    }, $class; 
}

sub get_next_file {
    my $self = shift;

    ## choose a file
    my @files = $self->{'lj_radio'}->get_list_of_files('absolute_path' => 1, 'recursive' => 1);
    return unless @files;

    my @non_played_files = grep { !$self->{'played_files'}->{$_} } @files;
    my $list = (@non_played_files) ? \@non_played_files : \@files;
    my $file = $list->[ rand(scalar @$list) ];
    $self->{'played_files'}->{$file}++;
    return $file;
}

1;

