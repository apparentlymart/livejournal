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
##      PerlSetVar LJRadioBlockSize 4096
##      PerlSetVar LJRadioVerbose 0        
##      PerlSetVar LJRadioDataDir /home/lj/var/www/radio/data
##

package LJ::Radio;

use strict;
use warnings;
use Apache2::RequestRec();
use Apache2::RequestIO();
use Apache2::ServerUtil();
use Apache2::Connection();
use Apache2::Const qw(OK DECLINED SERVER_ERROR);
use APR::Table;

use MP3::Info;
use IO::Dir;
use Fcntl qw(SEEK_SET);
use Data::Dumper qw/Dumper/;

sub handler {
    my $r = shift;
    
    return DECLINED
        unless $r->method eq 'GET';

    if (    $r->headers_in->get('icy-metadata') ||
            $r->headers_in->get('User-Agent') =~ /NSPlayer/) ## Microsoft Windows Media player 
    {
        LJ::Radio->serve_streaming_request($r);
        return OK;
    } else {
        $r->log_reason("Got a non-streaming request");
        $r->content_type("text/plain");
        print("This stream requires a shoutcast/icecast compatible player (e.g. winamp, mpg123 or microsoft media player)");
        return OK;
    }
}

sub serve_streaming_request {
    my $class = shift;
    my $r = shift;

    my $s = Apache2::ServerUtil->server;
    my $block_size  = $s->dir_config("LJRadioBlockSize")    || 8192;
    my $data_dir    = $s->dir_config("LJRadioDataDir")      || "/var/www/radio/data";
    my $verbose     = $s->dir_config("LJRadioVerbose");
    $verbose = 1 unless defined $verbose;

    warn "BlockSize=$block_size, data_dir=$data_dir, verbose=$verbose" if $verbose;
    
    my $self = bless {
        r           => $r,
        block_size  => $block_size,
        data_dir    => $data_dir,
        verbose     => $verbose,
    }, $class;

    warn "Got streaming request" if $verbose;

    $self->print_headers();
    my (%played_files, $fh);
    my $buffer = '';
    my $current_journal = '';
    
    SEND_FILE:
    while (!$r->connection->aborted) {
        ## choose a file
        my @files = $self->get_list_of_files();
        unless (@files) {
            $r->log_reason("No files found in '$data_dir'");
            return SERVER_ERROR;    
        }
        my @non_played_files = grep { !$played_files{$_} } @files;
        my $file = (@non_played_files) 
            ? $non_played_files[ rand(scalar@non_played_files) ] 
            : $files[ rand(scalar @files) ];
        warn "File is $file" if $verbose;
        $played_files{$file}++;

        ## get info and open the file, skip ID3 section
        my $info = get_mp3info($file);
        warn(Dumper $info) if $verbose>1;
        unless (open($fh, $file)) {
            $r->log_reason("Can't read from $file: $!");
            next SEND_FILE;
        }
        unless (seek($fh, $info->{'OFFSET'}, SEEK_SET)) {
            $r->log_reason("Invalid file $file: can't seek to $info->{'OFFSET'}");
            next SEND_FILE;
        }
        $current_journal = ($file =~ /^\d+-(\w+)-/) ? $1 : '';
        
        ## send the file content (actually, stream section of the file)
        my $l = length($buffer);
        while (my $rv = read($fh, $buffer, $block_size-$l, $l)) {
            die if length($buffer)>$block_size;
            warn "Read $rv bytes from $file" if $verbose>2;
            if (length($buffer)==$block_size) {
                warn "Going to print buffer" if $verbose>2;
                ## $r->print may cause exception for connections aborted by users:
                ## Apache2::RequestIO::print: (103) Software caused connection abort
                eval { $r->print($buffer); }
                    or last SEND_FILE;  
                warn "Buffer is printed" if $verbose>2;
                $buffer = '';

                my $header = "StreamTitle=$current_journal";
                my $k = int( (length($header)+15)/16 );
                $header .= "\0" x ($k*16 - length($header));
                $r->print( pack("C", $k) . $header );
            }
        }
        close $fh; undef $fh;
    }
    close $fh if $fh; ## aborted connection case
    warn "Connection is closed" if $verbose;
}

sub print_headers {
    my $self = shift;

    my $r = $self->{'r'};
    $r->assbackwards(1); ## we will print all headers ourselves
    $r->print("ICY 200 OK\r\n");
    $r->print("icy-name:LiveJournal Voice Posts\r\n");
    $r->print("icy-genre:voice\r\n");
    $r->print("icy-br:128\r\n");
    $r->print("icy-metaint:$self->{block_size}\r\n");
    $r->print("\r\n");

    $r->log_reason("Headers are printed") 
        if $self->{'verbose'} > 1;
}

sub get_list_of_files {
    my $self = shift;
    
    my $dir = $self->{'data_dir'};    
    my $d = IO::Dir->new($dir);
    return unless $d;
    my @files = map {"$dir/$_" } grep { $_ =~ /\.mp3$/ } $d->read;
    close $d;
    return @files;
}

1;

