#!/usr/bin/perl
use strict;
use LWP::Simple qw//;
use HTTP::Request;
use LWP::UserAgent;
    
    my $pool_file = $ARGV[0] || 'etc/pool_lj_web_servers.txt';
    print "Get uptime of servers from pool $pool_file\n";

    #
    local *FILE;
    open FILE, "<", $pool_file
        or die "Can't open file $pool_file: $!";
    my @servers = 
        grep { not /^\s*#/ and not /^\s*$/ and length }
        <FILE>;
    close FILE;
    
    #
    print "Server -> Uptime\n";
    foreach my $server (@servers){
        my $uptime = get_uptime($server);
        my $str = localtime($uptime);
        print "$server -> $uptime ($str)\n";
    }

sub get_uptime {
    my $server = shift;
    
    my $request = HTTP::Request->new('GET' => "http://$server/uptime.bml");
    $request->header(Host => 'www.livejournal.com');
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($request);
    my $content = $response->content;
    return int $content;

}
