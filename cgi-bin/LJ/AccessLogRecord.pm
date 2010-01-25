package LJ::AccessLogRecord;
use strict;

sub new {
    my $class = shift;

    my $now = time();
    my @now = gmtime($now);

    my $remote = eval { LJ::load_user(LJ::Request->notes('ljuser')) };
    my $remotecaps = $remote ? $remote->{caps} : undef;
    my $remoteid   = $remote ? $remote->{userid} : 0;
    my $ju = eval { LJ::load_userid(LJ::Request->notes('journalid')) };
    my $ctype = LJ::Request->content_type;
    $ctype =~ s/;.*//;  # strip charset

    my $self = bless {
        '_now' => $now,
        '_r'   => LJ::Request->r,
        'whn' => sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, @now[3, 2, 1, 0]),
        'whnunix' => $now,
        'server' => $LJ::SERVER_NAME,
        'addr' => LJ::Request->remote_ip,
        'ljuser' => LJ::Request->notes('ljuser'),
        'remotecaps' => $remotecaps,
        'remoteid'   => $remoteid,
        'journalid' => LJ::Request->notes('journalid'),
        'journaltype' => ($ju ? $ju->{journaltype} : ""),
        'journalcaps' => ($ju ? $ju->{caps} : undef),
        'codepath' => LJ::Request->notes('codepath'),
        'anonsess' => LJ::Request->notes('anonsess'),
        'langpref' => LJ::Request->notes('langpref'),
        'clientver' => LJ::Request->notes('clientver'),
        'uniq' => LJ::Request->notes('uniq'),
        'method' => LJ::Request->method,
        'uri' => LJ::Request->uri,
        'args' => scalar LJ::Request->args,
        'status' => LJ::Request->status,
        'ctype' => $ctype,
        'bytes' => LJ::Request->bytes_sent,
        'browser' => LJ::Request->header_in("User-Agent"),
        'secs' => $now - LJ::Request->request_time(),
        'ref' => LJ::Request->header_in("Referer"),
        'host' => LJ::Request->header_in("Host"),
    }, $class;
    $self->populate_gtop_info();
    return $self;
}

sub keys {
    my $self = shift;
    return grep { $_ !~ /^_/ } keys %$self;
}

sub populate_gtop_info {
    my $self = shift;

    # If the configuration says to log statistics and GTop is available, then
    # add those data to the log
    # The GTop object is only created once per child:
    #   Benchmark: timing 10000 iterations of Cached GTop, New Every Time...
    #   Cached GTop: 2.06161 wallclock secs ( 1.06 usr +  0.97 sys =  2.03 CPU) @ 4926.11/s (n=10000)
    #   New Every Time: 2.17439 wallclock secs ( 1.18 usr +  0.94 sys =  2.12 CPU) @ 4716.98/s (n=10000)
    my $GTop = LJ::gtop() or return;

    my $startcpu = LJ::Request->pnotes( 'gtop_cpu' ) or return;
    my $endcpu = $GTop->cpu                 or return;
    my $startmem = LJ::Request->pnotes( 'gtop_mem' ) or return;
    my $endmem = $GTop->proc_mem( $$ )      or return;
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
