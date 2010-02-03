package LJ::ML;
use strict;
use DB_File;
my $debug = 1;
sub debug (@){ warn "ML sync: " . shift if $debug; }

my $X;
my %BDB;
sub open_db {

    # http://search.cpan.org/~pmqs/DB_File-1.820/DB_File.pm#The_untie()_Gotcha
    untie %BDB;
    undef $X;
    undef %BDB;
    
    # open/reopen or create BerkeleyDB
    my $filename = "/home/lj/ml/ml.bdb";
    $X = tie %BDB, "DB_File", $filename, O_RDWR|O_CREAT, 0666, $DB_BTREE
               or die "Cannot open $filename: $!\n";
    return;
}

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
#warn "key: $key" if $code eq 'web.controlstrip.links.post2';
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

    debug "Update local storage. caller: " . caller;

    open_db();

    # do we have an actual local replica?
    my $sys_revid = _get_system_revid();
    debug "local revid $BDB{revid}    vs global revid $sys_revid";
    return if $BDB{revid} eq $sys_revid; # yes.

    # fetch changes
    my $dbh = LJ::get_db_writer();
    unless (LJ::get_lock($dbh, 'global', 'mlsync', 180)){
        debug "CANT GET LOCK to SYNC";
        return 0;
    }
    debug "get lock";


    # check revid again. it could be updated during we were waiting the lock.
    {
        my $sys_revid = _get_system_revid();

        # reopen db
        open_db();

        debug "REPEAT: local revid $BDB{revid}    vs global revid $sys_revid";
        return if $BDB{revid} eq $sys_revid; # yes.
    }



    my $new_revid = _load_updates($BDB{revid});
    debug "new revid=$new_revid,   sys_revid=$sys_revid";
    $BDB{revid} = $sys_revid;

    debug "check revid after updating it: revid=$BDB{revid}  (should be $sys_revid)";
    debug "release lock";
    
    # flush chages on disk
    $X->sync();
    debug "bdb buffers are synced to disc";

    LJ::release_lock($dbh, 'global', 'mlsync');

    return $sys_revid;
}

sub _get_system_revid {
    # check memcached
    my $counter = "ml_latest_updates_counter";
    my $mem = LJ::MemCache::get($counter);
    debug "  revid from MemCache: $mem";
    return $mem if defined $mem;

    # check db
    my $val = LJ::global_coounter_value($counter);
    debug "  revid from DB: $val";
    LJ::MemCache::set($counter, $val);
    return $val;

}


sub _load_updates {
    my $revid = int (+shift);

    #
    my $dbr = LJ::get_db_reader();
    debug "start fetching ml... revid=$revid\n";

    # get updated ml_latest
    # get codes for them
    # get texts

    my $max_revid = $revid;
    # get updated ml_latest records
    my $sign = $revid eq '0' 
                ? '>=' # initial import
                : '>';
    my $sth = $dbr->prepare("
        SELECT dmid, lnid, itid, txtid, revid
        FROM   ml_latest
        WHERE  revid $sign ?
        ");
    $sth->execute($revid) or die $dbr->errstr;
    debug "executed loading from rev $sign $revid ...";
    
    my @updated = ();
    while (my $h = $sth->fetchrow_hashref){
        push @updated => {
            dmid  => $h->{dmid},
            lnid  => $h->{lnid},
            itid  => $h->{itid},
            txtid => $h->{txtid}
            };
        $max_revid = $h->{revid} if $max_revid < $h->{revid};
    }
    debug "got " . scalar(@updated) . " updates";
    return $revid unless @updated;

    my %items = ();
    my @updated_loop1 = @updated;
    debug "  \@updated_loop1 copied";
    my $items_n = 0;
    while (my $els = @updated_loop1){
        my $splice = ($els > 5000 ? -5000 : (-1)*$els);
        my @upds = splice @updated_loop1, $splice, $splice*(-1);
        debug "    loop 1  items_n: $items_n  els after splice " . scalar(@updated_loop1);
        
        my %domains = ();
        foreach my $upd (@upds){
            push @{ $domains{$upd->{dmid}} } => $upd;
        }

        foreach my $domain (keys %domains){
            #warn "domain: $domain";
            my $statement = eval { "
                SELECT dmid, itid, itcode
                FROM
                    ml_items
                WHERE
                    dmid = $domain AND
                    itid IN (" . (join "," => (map { $_->{itid} } @{ $domains{ $domain } } )) . ")"
                    };
            
            $sth = $dbr->prepare($statement) 
                or die $statement;
            $sth->execute() or die $dbr->errstr;
            while (my $h = $sth->fetchrow_hashref){
                $items{ "$h->{dmid}:$h->{itid}" } = $h->{itcode};
                $items_n++;
            }
        }
    }

    debug "got $items_n items";
    
    my %texts = ();
    my $texts_n = 0;
    my @updated_loop2 = @updated;
    while (my $els = @updated_loop2){
        my $splice = ($els > 5000 ? -5000 : (-1)*$els);
        my @upds = splice @updated_loop2, $splice, (-1)*$splice;
        debug "    loop 2  texts_n: $texts_n    els after splice " . scalar(@updated_loop2);
        $sth = $dbr->prepare("
            SELECT txtid, text
            FROM   ml_text
            WHERE 
                txtid IN (" . ( 
                    join (", " =>
                        map { $_->{txtid} }
                        @upds
                        )
                    ) . ")" 
            );

        $sth->execute() or die $dbr->errstr;
        while (my $h = $sth->fetchrow_hashref){
            $texts{ $h->{txtid} } = $h->{text};
            $texts_n++;
        }
    }
    
    debug("got $texts_n texts");
    #
    my $n = 0;
    foreach my $upd (@updated){
        my $itcode = $items{"$upd->{dmid}:$upd->{itid}"};
        my $dbkey  = "$upd->{dmid}:$upd->{lnid}:$itcode";
warn "$dbkey = $texts{$upd->{txtid}}" if $itcode eq 'web.controlstrip.links.post2';
        $BDB{$dbkey} = $texts{$upd->{txtid}};
        $n++;
    }
    debug("do $n updates in BDB");
    debug("new max revid = $max_revid");

    undef %items;
    undef %texts;
    undef @updated;

    return $max_revid;
}    



1;

