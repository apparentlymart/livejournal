package LJ::AccessLogRecord;
use strict;

sub new {
    my ( $class, %args ) = @_;

    my $now = $args{'time'} || time();
    my @now = gmtime($now);

    my $remote_username = $args{'remote_username'} || LJ::Request->notes('ljuser');
    my $remote = eval { LJ::load_user($remote_username) };
    my $remotecaps = $remote ? $remote->{caps} : undef;
    my $remoteid   = $remote ? $remote->{userid} : 0;
    my $journalid = $args{'journalid'} || LJ::Request->notes('journalid');
    my $ju = eval { LJ::load_userid($journalid) };
    my $ctype = $args{'content_type'} || LJ::Request->content_type;
    $ctype =~ s/;.*//;  # strip charset

    my $request_time = $args{'request_time'} || LJ::Request->request_time();

    my $self = bless {
        '_now' => $now,
        '_r'   => $args{'apreq'} || LJ::Request->r,
        'whn' => sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, @now[3, 2, 1, 0]),
        'whnunix' => $now,
        'server' => $LJ::SERVER_NAME,
        'addr' => $args{'remote_ip'} || LJ::Request->remote_ip,
        'ljuser' => $remote_username,
        'remotecaps' => $remotecaps,
        'remoteid'   => $remoteid,
        'journalid' => $journalid,
        'journaltype' => ($ju ? $ju->{journaltype} : ""),
        'journalcaps' => ($ju ? $ju->{caps} : undef),
        'codepath' => $args{'codepath'} || LJ::Request->notes('codepath'),
        'anonsess' => $args{'anonsess'} || LJ::Request->notes('anonsess'),
        'langpref' => $args{'langpref'} || LJ::Request->notes('langpref'),
        'clientver' => $args{'clientver'} || LJ::Request->notes('clientver'),
        'uniq' => $args{'uniq'} || LJ::Request->notes('uniq'),
        'method' => $args{'http_method'} || LJ::Request->method,
        'uri' => $args{'http_uri'} || LJ::Request->uri,
        'args' => $args{'http_argcount'} || scalar(LJ::Request->args),
        'status' => $args{'http_status'} || LJ::Request->status,
        'ctype' => $ctype,
        'bytes' => $args{'http_bytes_sent'} || LJ::Request->bytes_sent,
        'browser' => $args{'user_agent'} || LJ::Request->header_in("User-Agent"),
        'secs' => $now - $request_time,
        'ref' => $args{'referer'} || LJ::Request->header_in("Referer"),
        'host' => $args{'http_hostname'} || LJ::Request->header_in("Host"),
        'accept' => $args{'accept'} || LJ::Request->header_in('Accept'),
    }, $class;
    $self->populate_gtop_info(%args);
    return $self;
}

sub keys {
    my $self = shift;
    return grep { $_ !~ /^_/ } keys %$self;
}

sub populate_gtop_info {
    my ( $self, %args ) = @_;

    # If the configuration says to log statistics and GTop is available, then
    # add those data to the log
    # The GTop object is only created once per child:
    #   Benchmark: timing 10000 iterations of Cached GTop, New Every Time...
    #   Cached GTop: 2.06161 wallclock secs ( 1.06 usr +  0.97 sys =  2.03 CPU) @ 4926.11/s (n=10000)
    #   New Every Time: 2.17439 wallclock secs ( 1.18 usr +  0.94 sys =  2.12 CPU) @ 4716.98/s (n=10000)
    my $GTop = LJ::gtop() or return;

    my $startcpu = $args{'gtop_startcpu'} || LJ::Request->pnotes( 'gtop_cpu' ) or return;
    my $endcpu = $args{'gtop_endcpu'} || $GTop->cpu                 or return;
    my $startmem = $args{'gtop_startmem'} || LJ::Request->pnotes( 'gtop_mem' ) or return;
    my $endmem = $args{'gtop_endmem'} || $GTop->proc_mem( $$ )      or return;
    my $cpufreq = $endcpu->frequency        or return;

    # Map the GTop values into the corresponding fields in a slice
    @$self{qw{pid cpu_user cpu_sys cpu_total mem_vsize
              mem_share mem_rss mem_unshared}} =
        (
         $$,
         ($endcpu->user - $startcpu->user) / $cpufreq,
         ($endcpu->sys - $startcpu->sys) / $cpufreq,
         ($endcpu->total - $startcpu->total) / $cpufreq,
         $endmem->vsize - $startmem->vsize,
         $endmem->share - $startmem->share,
         $endmem->rss - $startmem->rss,
         $endmem->size - $endmem->share,
         );
}

sub ip { $_[0]{addr} }
sub r  { $_[0]{_r} }

sub table {
    my ($self, $prefix) = @_;
    my @now = gmtime($self->{_now});
    return ($prefix || "access") .
        sprintf("%04d%02d%02d%02d",
                $now[5]+1900,
                $now[4]+1,
                $now[3],
                $now[2]);
}

1;
