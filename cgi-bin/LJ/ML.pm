package LJ::ML;
use strict;
use DB_File;
my $debug = 0;
sub debug (@){ warn @_ if $debug; }

    # open or create BerkeleyDB
    my $filename = "/home/lj/ml/ml.bdb";
    my $X = tie my %BDB, "DB_File", $filename, O_RDWR|O_CREAT, 0666, $DB_BTREE
               or die "Cannot open $filename: $!\n";


## @spec: LJ::ML->get_text("en", 1, "code") -> "localized string"
## @doc: convert text code to local string using Berkeley DB stored on the local disk.
##       To keep local copy in actual status call "LJ::ML->update_local_storage"
sub get_text {
    my $class = shift;
    my ($lang, $dmid, $code) = @_;

    $lang ||= $LJ::DEFAULT_LANG;
    $dmid = int $dmid || 1;

    # convert $lang to lnid
    my $l = LJ::Lang::get_lang($lang);
    my $lnid = $l->{lnid};

    my $key = "$dmid:$lnid:$code";
    return $BDB{$key};
}

## @spec: LJ::ML->get_text("en", 1, ["code", ..., "codeN"]) -> {code => "string", ..., codeN => "string N"}
sub get_text_multi {
    my $class = shift;
    my ($lang, $dmid, $codes) = @_;

    $lang ||= $LJ::DEFAULT_LANG;
    $dmid = int $dmid || 1;

    # convert $lang to lnid
    my $l = get_lang($lang);
    my $lnid = $l->{lnid};

    my %strings = ();
    foreach my $code (@$codes){
        my $key = "$dmid:$lnid:$code";
        $strings{$code} = $BDB{$key};
    }

    return \%strings;
}


## @spec: LJ::ML->update_local_storage -> new update id
## @doc:  if local storage become outdated, it fetches updated and newly created ML records and store them in local db.
sub update_local_storage {

    # do we have an actual local replica?
    my $sys_updid = _get_system_updid();
    return if $BDB{updid} eq $sys_updid; # yes.

    # fetch changes
    my $new_updid = _load_updates($BDB{updid});
    debug "new updid=$new_updid,   sys_updi=$sys_updid";
    $BDB{updid} = $sys_updid;
    return $sys_updid;
}

sub _get_system_updid {
    # check memcached
    my $counter = "ml_latest_updates_counter";
    my $mem = LJ::MemCache::get($counter);
    debug "  updid from MemCache: $mem";
    return $mem if defined $mem;

    # check db
    my $val = LJ::global_coounter_value($counter);
    debug "  updid from DB: $mem";
    LJ::MemCache::set($counter, $val);
    return $val;

}


sub _load_updates {
    my $updid = int (+shift);
    
    #
    my $dbr = LJ::get_db_reader();
    debug "start fetching ml... \n";

    # get updated ml_latest
    # get codes for them
    # get texts

    my $max_updid = $updid;
    # get updated ml_latest records
    my $sth = $dbr->prepare("
        SELECT dmid, lnid, itid, txtid, updid
        FROM   ml_latest
        WHERE  updid > ?
        ");
    $sth->execute($updid) or die $dbr->errstr;
    my @updated = ();
    while (my $h = $sth->fetchrow_hashref){
        push @updated => {
            dmid  => $h->{dmid},
            lnid  => $h->{lnid},
            itid  => $h->{itid},
            txtid => $h->{txtid}
            };
        $max_updid = $h->{updid} if $max_updid < $h->{updid};
    }
    debug "Got " . scalar(@updated) . " updates";
    return $updid unless @updated;

    my %items = ();
    $sth = $dbr->prepare("
        SELECT dmid, itid, itcode
        FROM   ml_items
        WHERE 
            " . ( 
                join (" OR " =>
                    map { "(dmid = $_->{dmid} AND itid = $_->{itid})" }
                    @updated
                    )
                ) 
        );
    $sth->execute() or die $dbr->errstr;
    while (my $h = $sth->fetchrow_hashref){
        $items{ "$h->{dmid}:$h->{itid}" } = $h->{itcode};
    }

    debug "Get " . scalar(keys %items) . " items";
    
    my %texts = ();
    $sth = $dbr->prepare("
        SELECT txtid, text
        FROM   ml_text
        WHERE 
            txtid IN (" . ( 
                join (", " =>
                    map { $_->{txtid} }
                    @updated
                    )
                ) . ")" 
        );
    $sth->execute() or die $dbr->errstr;
    while (my $h = $sth->fetchrow_hashref){
        $texts{ $h->{txtid} } = $h->{text};
    }
    debug("Got " . scalar(keys(%texts)) . " texts");
    #
    my $n = 0;
    foreach my $upd (@updated){
        my $itcode = $items{"$upd->{dmid}:$upd->{itid}"};
        my $dbkey  = "$upd->{dmid}:$upd->{lnid}:$itcode";
        $BDB{$dbkey} = $texts{$upd->{txtid}};
        $n++;
    }
    debug("Do $n updates in BDB");
    debug("new max updid = $max_updid");
    return $max_updid;
}    




