package LJ::DelayedEntry;

use strict;
use warnings;
require 'ljprotocol.pl';
use LJ::User;
use Storable;

sub create_from_url {
    my ($class, $url, $opts) = @_;

    if ($url =~ m!(.+)/d(\d+)\.html!) {
        my $username = $1;
        my $delayed_id = $2;
        my $u = LJ::User->new_from_url($username) or return undef;
        return LJ::DelayedEntry->get_entry_by_id($u, $delayed_id, $opts);
    }

    return undef;
}
              
sub create {
    my ( $class, $req, $opts ) = @_;

    __assert( $opts , "no options");
    __assert( $opts->{journal}, "no journal");
    __assert( $opts->{poster}, "no poster" );
    __assert( $req, "no request" );

    my $self = bless {}, $class;

    my $journal = $opts->{journal};
    my $poster = $opts->{poster};
    $req->{'event'} =~ s/\r\n/\n/g;

    my $journalid = $journal->userid;
    my $posterid = $poster->userid;
    my $subject = $req->{subject};
    my $posttime = __get_datetime($req);
    my $dbh = LJ::get_db_writer();
    my $data_ser = __serialize($req);
    my $qdata_ser = $dbh->quote($data_ser);
    
    my $delayedid = LJ::alloc_user_counter( $journal, 
                                            'Y',
                                            undef);

    my $security = "public";
    my $uselogsec = 0;

    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }

    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    my ($now)       = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()");

    my $qsecurity   = $dbh->quote($security);
    my $qallowmask  = $req->{'allowmask'}+0;
    my $qposttime   = $dbh->quote($posttime);
    my ($utime)     = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP($qposttime)");

    my $rlogtime    = $LJ::EndOfTime - $now;
    my $rposttime   = $LJ::EndOfTime - $utime;

    my $taglist = __extract_tag_list(\$req->{props}->{taglist});

    $journal->do( "INSERT INTO delayedlog2 (journalid, delayedid, posterid, subject, " .
                  "logtime, posttime, security, allowmask, year, month, day, rlogtime, revptime) " .
                  "VALUES ($journalid, $delayedid, $posterid, ?, NOW(), $qposttime, ".
                  "$qsecurity, $qallowmask, ?, ?, ?, $rlogtime,  $rposttime)",
                  undef,  LJ::text_trim($req->{'subject'}, 30, 0), 
                  $req->{year}, $req->{mon}, $req->{day} );
    
    $journal->do( "INSERT INTO delayedblob2 ".
                  "VALUES ($journalid, $delayedid, $qdata_ser)" );

    my $memcache_key = "delayed_entry:$journalid:$delayedid";
    my $timelife = $rposttime - $rlogtime;
    LJ::MemCache::set($memcache_key, $data_ser, $timelife);

    $self->{journal} = $opts->{journal};    
    $self->{posttime} = $opts->{posttime};
    $self->{posttime} = LJ::TimeUtil::mysql_time($now);
    $self->{poster} = $opts->{poster};
    $self->{data} = $req;
    $self->{taglist} = $taglist;
    $self->{delayed_id} = $delayedid;
    $self->{default_dateformat} = $opts->{'dateformat'} || 'S2';
    return $self;
}

sub valid {
    return 1;
}

sub delayedid {
    my ($self) = @_;
    return $self->{delayed_id};
}

sub data {
    my ($self) = @_;
    return $self->{data};
}

sub subject {
    my ($self) = @_;
    return $self->{data}->{subject};
}

sub event {
    my ($self) = @_;
    return $self->{data}->{event};
}

sub poster {
    my ($self) = @_;
    return $self->{poster};
}

sub posterid {
    my ($self) = @_;
    return $self->poster->userid;
}

sub journal {
    my ($self) = @_;
    return $self->{journal};
}

sub journalid {
    my ($self) = @_;
    return $self->journal->userid;
}

sub timezone {
    my ($self) = @_;
    return $self->data->{'tz'}
}

sub logtime {
    my ($self) = @_;
    return $self->{logtime};
}

sub system_posttime {
    my ($self) = @_;
    return $self->{posttime};
}

sub posttime_as_unixtime {
    my ($self) = @_;
    my $dbh = LJ::get_db_writer();
    my $qposttime = $self->system_posttime;
    return LJ::TimeUtil::->mysqldate_to_time($qposttime, 0);
}


sub posttime {
    my ($self, $u) = @_;
    my $posttime = $self->system_posttime;
    my $timezone = $self->timezone;
    if (!$timezone) {
        return $posttime;
    }
    my $epoch = $self->posttime_as_unixtime;
    my $dt = DateTime->from_epoch( 'epoch' => $epoch );
    $dt->set_time_zone( $timezone );

    # make the proper date format
    return sprintf("%04d-%02d-%02d %02d:%02d", $dt->year,
                                               $dt->month,
                                               $dt->day,
                                               $dt->hour,
                                               $dt->minute );
}

sub alldatepart {
    my ($self, $style) = @_;
    my $mysql_time = $self->posttime;
    if ( ($style && $style eq 'S1') || $self->{default_dateformat} eq 'S1') {
        return LJ::TimeUtil::->alldatepart_s1($mysql_time);
    }

    return LJ::TimeUtil::->alldatepart_s2($mysql_time);
}

sub system_alldatepart { 
    my ($self, $style) = @_;
    my $mysql_time = $self->system_posttime;
    if ( ($style && $style eq 'S1') || $self->{default_dateformat} eq 'S1' ) {
        return LJ::TimeUtil::->alldatepart_s1($mysql_time);
    }
    return LJ::TimeUtil::->alldatepart_s2($mysql_time);
}

sub is_sticky {
    my ($self) = @_;
    return 0 unless  $self->data->{sticky};
    return $self->data->{sticky};
}

sub allowmask {
    my ($self) = @_;
    return $self->data->{allowmask};
}

sub security {
    my ($self) = @_;
    return $self->data->{security};
}

sub mood {
    my ($self) = @_;
    #warn "TODO: add mood";
    return 0;
}

sub props {
    my ($self) = @_;
    return $self->data->{props};
}

sub is_future_date {
    my ($req) = @_;
    my $now = __get_now();
    my $request_time = __get_datetime($req);

    return $request_time ge $now;
}

sub visible_to {
    my ($self, $remote, $opts) = @_;
    return 0 unless $self->valid;

    # can see anything with viewall
    return 1 if $opts->{'viewall'};
        
    # can't see anything unless the journal is visible
    # unless you have viewsome. then, other restrictions apply
    if (!$opts->{'viewsome'}) {
        return 0 if $self->journal->{statusvis} =~ m/[DSX]/;
        
        # can't see anything by suspended users
        my $poster = $self->poster;
        return 0 if $poster->{statusvis} eq 'S';
        
        # if poster choosed to delete jouranl and all external content, 
        # then don't show his/her entries, except in some protected journals like 'lj_core'
        if ($poster->{statusvis} eq 'D') {
            my ($purge_comments, $purge_community_entries) = split /:/, $poster->prop("purge_external_content");
            if ($purge_community_entries) {
                my $journal_name = $self->journal->{user};
                if (!$LJ::JOURNALS_WITH_PROTECTED_CONTENT{$journal_name}) {
                    return 0;
                }
            }
        }
        
        # can't see suspended entries
        return 0 if $self->is_suspended_for($remote);
    }   
            
    # public is okay
    return 1 if $self->security eq "public";
    
    # must be logged in otherwise
    return 0 unless $remote;
        
    my $userid   = int($self->journalid);
    my $remoteid = int($remote->userid);

    # owners can always see their own.
    return 1 if $userid == $remoteid;

    # author in community can always see their post
    return 1 if $remoteid == $self->posterid and not $LJ::JOURNALS_WITH_PROTECTED_CONTENT{ $self->journal->{user} };

    # other people can't read private
    return 0 if $self->security eq "private";

    # should be 'usemask' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless $self->security eq "usemask";

    # if it's usemask, we have to refuse non-personal journals,
    # so we have to load the user
    return 0 unless $remote->is_person() || $remote->is_identity();

    my $gmask = LJ::get_groupmask($userid, $remoteid);
    my $allowed = (int($gmask) & int($self->allowmask));
    return $allowed ? 1 : 0;  # no need to return matching mask
}

# defined by the entry poster
sub adult_content {
    my ($self) = @_;
    return $self->prop('adult_content');
}

# defined by an admin
sub admin_content_flag {
    my ($self) = @_;
    return $self->prop('admin_content_flag') || {};
}

# uses both poster- and admin-defined props to figure out the adult content level
sub adult_content_calculated {
    my ($self) = @_;

    return "explicit" if $self->admin_content_flag eq "explicit_adult";
    return $self->adult_content;
}

sub prop {
    my ( $self, $prop_name ) = @_;
    return $self->props->{$prop_name};
}

sub url {
    my ($self) = @_;
    my $journal = $self->journal;
    my $url = $journal->journal_base . "/d" . $self->delayedid . ".html";
    return $url;
}

sub statusvis {
    my ($self) = @_;
    my $statusvis = $self->prop("statusvis") || '';
    return $statusvis eq "S" ? "S" : "V";
}

sub is_visible {
    my ($self) = @_;
    return $self->statusvis eq "V" ? 1 : 0;
}

sub is_suspended {
    my ($self) = @_;
    return $self->statusvis eq "S" ? 1 : 0;
}

# same as is_suspended, except that it returns 0 if the given user can see the suspended entry
sub is_suspended_for {
    my ( $self, $u ) = @_;

    return 0 unless $self->is_suspended;
    return 0 if LJ::check_priv($u, 'canview', 'suspended');
    return 0 if LJ::isu($u) && $u->equals($self->poster);
    return 1;
}

sub get_suspended_mark {
    return 0;
} 

sub should_show_suspend_msg_to {
    my ( $self, $u ) = @_;
    return $self->is_suspended && !$self->is_suspended_for($u) ? 1 : 0;
}

sub is_delayed {
    return 1;
}

# no anum for delayed entries
sub correct_anum {
    my ($self) = @_;
    return 0;
}

sub anum {
    my ($self) = @_;
    return 0;
}

# no ditemid
sub ditemid {
    my ($self) = @_;
    return 0;
}

# no jitemid
sub jitemid {
    my ($self) = @_;
    return 0;
}

sub group_names {
    return undef;
}

# returns a LJ::Userpic object for this post, or undef
# currently this is for the permalink view, not for the friends view
# context.  TODO: add a context option for friends page, and perhaps
# respect $remote's userpic viewing preferences (community shows poster
# vs community's picture)
sub userpic {
    my ($self) = @_;

    my $up = $self->poster;

    # try their entry-defined userpic keyword, then their custom
    # mood, then their standard mood
    my $key = $self->prop('picture_keyword') ||
    $self->prop('current_mood') ||
    LJ::mood_name($self->prop('current_moodid'));

    # return the picture from keyword, if defined
    my $picid = LJ::get_picid_from_keyword($up, $key);
    return LJ::Userpic->new($up, $picid) if $picid;

    # else return poster's default userpic
    return $up->userpic;
}

# for delayed entry always false
sub comments_shown {
    my ($self) = @_;
    return 0;
}

sub posting_comments_allowed {
    my ($self) = @_;
    return 0;
}

sub everyone_can_comment {
    my ($self) = @_;
    return 0;
}

sub registered_can_comment {
    my ($self) = @_;
    return 0;
}

sub friends_can_comment {
    my ($self) = @_;
    return 0;
}

sub tag_map {
    my ($self) = @_;
    return {};
}

sub subject_html {
    my ($self) = @_;
    my $subject = $self->subject;
    LJ::CleanHTML::clean_subject( \$subject ) if $subject;
    return $subject;
}

sub subject_text {
    my ($self) = @_;
    my $subject = $self->subject;
    LJ::CleanHTML::clean_subject_all( \$subject ) if $subject;
    return $subject;
}

# instance method.  returns HTML-cleaned/formatted version of the event
# optional $opt may be:
#    undef:   loads the opt_preformatted key and uses that for formatting options
#    1:       treats entry as preformatted (no breaks applied)
#    0:       treats entry as normal (newlines convert to HTML breaks)
#    hashref: passed to LJ::CleanHTML::clean_event verbatim
sub event_html
{
    my ($self, $opts) = @_;

    if (! defined $opts) {
        $opts = {};
    } elsif (! ref $opts) {
        $opts = { preformatted => $opts };
    }

    unless ( exists $opts->{'preformatted'} ) {
        $opts->{'preformatted'} = $self->prop('opt_preformatted');
    }

    my $remote = LJ::get_remote();
    my $suspend_msg = $self->should_show_suspend_msg_to($remote) ? 1 : 0;
    $opts->{suspend_msg} = $suspend_msg;
    $opts->{unsuspend_supportid} = $suspend_msg ? $self->prop("unsuspend_supportid") : 0;

    if($opts->{no_cut_expand}) {
        $opts->{expand_cut} = 0;
        $opts->{cuturl} = $self->prop('reposted_from') || $self->url . '?page=' . $opts->{page} . '&cut_expand=1';
    } elsif (!$opts->{cuturl}) {
        $opts->{expand_cut} = 1;
        $opts->{cuturl}     = $self->prop('reposted_from') || $self->url;
    }

    $opts->{journalid} = $self->journalid;
    $opts->{posterid} = $self->posterid;
    $opts->{entry_url} = $self->prop('reposted_from') || $self->url;

    my $event = $self->event;
    LJ::CleanHTML::clean_event(\$event, $opts);

    #LJ::expand_embedded($self->journal, $self->ditemid, LJ::User->remote, \$event);
    return $event;
}

sub verticals_list {
    my ($self) = @_;

    my $verticals_list = $self->prop("verticals_list");
    return () unless $verticals_list;

    my @verticals = split(/\s*,\s*/, $verticals_list);
    return @verticals ? @verticals : ();
}

sub eventtime_mysql {
    my ($self) = @_;
    return $self->posttime;
}

sub logtime_mysql {
    my ($self) = @_;
    return $self->system_posttime;
}

sub verticals_list_for_ad {
    my ($self) = @_;

    my @verticals = $self->verticals_list;
    my @verticals_for_ad;
    if (@verticals) {
        foreach my $vertname (@verticals) {
            my $vertical = LJ::Vertical->load_by_name($vertname);
            next unless $vertical;

            push @verticals_for_ad, $vertical->ad_name;
        }
    }

    # remove parent verticals if any of their subverticals are in the list
    my %vertical_in_list = map { $_ => 1 } @verticals_for_ad;
    foreach my $vertname (@verticals_for_ad) {
        my $vertical = LJ::Vertical->load_by_name($vertname);
        next unless $vertical;

        foreach my $child ($vertical->children) {
            if ($vertical_in_list{$child->ad_name}) {
                delete $vertical_in_list{$vertical->ad_name};
            }
        }
    }
    @verticals_for_ad = keys %vertical_in_list;

    return @verticals_for_ad ? @verticals_for_ad : ();
}

sub tags {
    my ($self) = @_;
    return @{$self->{taglist}};
}

sub get_tags {
    my ($self) = @_;
    my $i = 1;
    my $result;
    foreach my $tag (@{$self->{taglist}}) {
        $result->{$self->delayedid}->{$i} = $tag;
        $i++;
    }

    return $result;
}

# raw utf8 text, with no HTML cleaning
sub subject_raw {
    my ($self) = @_;
    return $self->subject;
}

sub event_raw {
    my ($self) = @_;
    return $self->event;
}

sub is_public {
    my ($self) = @_;
    return 0;
}

sub delete {
    my ($self) = @_;
    __assert( $self->{delayed_id}, "no delayed id" );
    __assert( $self->{journal}, "no journal" );

    my $journal = $self->{journal};
    my $journalid = $journal->userid;
    my $delayed_id = $self->{delayed_id};

    $journal->do("DELETE FROM delayedlog2 " .
                  "WHERE delayedid = $delayed_id AND " .
                  "journalid = " . $journalid);

    $journal->do("DELETE FROM delayedblob2 " .
                 "WHERE delayedid = $delayed_id AND " .
                 "journalid = " . $journalid);

    $self->{delayed_id} = undef;
    $self->{journal} = undef;
    $self->{poster} = undef;
    $self->{data} = undef;
    
    my $memcache_key = "delayed_entry:$journalid:$delayed_id";
    LJ::MemCache::delete($memcache_key);
}

sub comments_manageable_by {
    my ($self, $remote) = @_;
    return 0 unless $remote;

    my $u = $self->{journal};

    return
        $remote->userid == $u->userid ||
        $remote->userid == $self->posterid ||
        $remote->can_manage($u) ||
        $remote->can_sweep($u);
}

sub should_block_robots {
    my ($self) = @_;
    return 1 if $self->journal->prop('opt_blockrobots');
    return 0 unless LJ::is_enabled("content_flag");

    my $adult_content = $self->adult_content_calculated;
    my $admin_flag = $self->admin_content_flag;

    return 1 if $LJ::CONTENT_FLAGS{$adult_content} && $LJ::CONTENT_FLAGS{$adult_content}->{block_robots};
    return 1 if $LJ::CONTENT_FLAGS{$admin_flag} && $LJ::CONTENT_FLAGS{$admin_flag}->{block_robots};
    return 0;
}

sub update {
    my ($self, $req) = @_;
    __assert( $self->{delayed_id}, "no delayed id" );
    __assert( $self->{journal}, "no journal" );
    __assert( $self->{poster}, "no poster" );

    $req->{tz} = $req->{tz} || $self->data->{tz};

    my $journalid = $self->journal->userid;
    my $posterid  = $self->poster->userid;
    my $subject   = $req->{subject};
    my $posttime  = __get_datetime($req);
    my $delayedid = $self->{delayed_id};
    my $dbh       = LJ::get_db_writer();
    my $data_ser  = __serialize($req);
    my $qdata_ser = $dbh->quote($data_ser);

    my $security  = "public";
    my $uselogsec = 0;

    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }

    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    my ($now)       = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()");

    my $qsecurity   = $dbh->quote($security);
    my $qallowmask  = $req->{'allowmask'}+0;
    my $qposttime   = $dbh->quote($posttime);
    my ($utime)     = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP($qposttime)");

    my $rlogtime    = $LJ::EndOfTime - $now;
    my $rposttime   = $LJ::EndOfTime - $utime;
    $self->{taglist} = __extract_tag_list(\$req->{props}->{taglist});
    $req->{'event'} =~ s/\r\n/\n/g; # compact new-line endings to more comfort chars count near 65535 limit

    $self->journal->do( "UPDATE delayedlog2 SET posterid=$posterid, " .
                        "subject=?, posttime=$qposttime, " . 
                        "security=$qsecurity, allowmask=$qallowmask, " .    
                        "year=?, month=?, day=?, " .
                        "rlogtime=$rlogtime, revptime=$rposttime " .
                        "WHERE journalid=$journalid AND delayedid=$delayedid",
                        undef,  LJ::text_trim($req->{'subject'}, 30, 0), 
                        $req->{year}, $req->{mon}, $req->{day} );

    $self->journal->do( "UPDATE delayedblob2 SET request_stor=$qdata_ser" . 
                        "WHERE journalid=$journalid AND delayedid=$delayedid" );
    $self->{data} = $req;

    my $memcache_key = 'delayed_entry:$journalid:$delayedid';
    my $timelife = $rposttime - $rlogtime;
    LJ::MemCache::set($memcache_key, $data_ser, $timelife);
}   

sub update_tags {
    my ($self, $tags) = @_;
    $self->props->{taglist} = $tags;
    $self->{taglist} = __extract_tag_list(\$self->prop("taglist"));
    $self->update($self->data);
    return 1;
}

sub get_log2_row {
    my ($self, $opts) = @_;

    my $db = LJ::get_cluster_def_reader($self->journal);
    return undef unless $db;

    my $sql = "SELECT posterid, posttime, logtime, security, allowmask " .
              "FROM delayedlog2 WHERE journalid=? AND delayedid=?";
    
    my $item = $db->selectrow_hashref($sql, undef, $self->journal->userid, $self->delayedid);
    return undef unless $item;
    $item->{'journalid'} = $self->journal->userid;
    $item->{'delayedid'} = $self->delayedid;

    return $item;
}

sub load_data {
    my ($class, $dbcr, $opts) = @_;
    __assert($opts->{journalid}, "no journal id");
    __assert($opts->{delayed_id}, "no delayed id");
    __assert($opts->{posterid}, "no poster id");

    my $journalid = $opts->{journalid};
    my $delayedid = $opts->{delayed_id};

    my ($data_ser)= $dbcr->selectrow_array( "SELECT request_stor " .
                                            "FROM delayedblob2 " .
                                            "WHERE journalid=$journalid AND " .
                                            "delayedid = $delayedid" );

    my $self = bless {}, $class; 
    $self->{journal} = LJ::want_user($opts->{journalid});
    $self->{data} = __deserialize($data_ser);
    $self->{poster} = LJ::want_user($opts->{posterid});
    $self->{delayed_id} = $delayedid;
    $self->{posttime} = __get_datetime($self->{data});

    return $self;
}

sub get_entry_by_id {
    my ($class, $journal, $delayedid, $options) = @_;
    __assert($journal, "no journal");    
    return undef unless $delayedid;

    my $journalid = $journal->userid;
    my $userid = $options->{userid} || 0;
    my $user = LJ::get_remote() || LJ::want_user($userid);
    return undef unless $user;

    my $delayed_visibility = $options->{'delayed_visibility'} || 0;

    my $sql_poster = '';
    if ( !$delayed_visibility && !__delayed_entry_can_see( $journal, $user ) ) {
        $sql_poster = 'AND posterid = ' . $user->userid . " "; 
    }

    my $dbcr = LJ::get_cluster_def_reader($journal)
        or die "get cluster for journal failed";

    my $opts = $dbcr->selectrow_arrayref( "SELECT journalid, delayedid, posterid, posttime, logtime " .
                                          "FROM delayedlog2 ".
                                          "WHERE journalid=$journalid AND ".
                                          "delayedid = $delayedid $sql_poster");
    return undef unless $opts;

    my $req = undef;
   
    my $memcache_key = "delayed_entry:$journalid:$delayedid";
    my ($data_ser) = LJ::MemCache::get($memcache_key);
    if (!$data_ser) {
        ($data_ser) = $dbcr->selectrow_array( "SELECT request_stor " .
                                              "FROM delayedblob2 ".
                                              "WHERE journalid=$journalid AND ".
                                              "delayedid = $delayedid");
        return undef unless $data_ser;
        my $timelife = LJ::TimeUtil::->mysqldate_to_time($opts->[3]) - time();
        LJ::MemCache::set($memcache_key, $data_ser, $timelife);
    }

    my $self = bless {}, $class; 
    $self->{data}               = __deserialize($data_ser);
    $self->{journal}            = $journal;
    $self->{poster}             = LJ::want_user($opts->[2]);
    $self->{delayed_id}         = $delayedid;
    $self->{posttime}           = __get_datetime($self->{data});
    $self->{logtime}            = $opts->[4];
    $self->{taglist}            = __extract_tag_list( \$self->prop("taglist") );
    $self->{default_dateformat}      = $options->{'dateformat'} || 'S2';

    __assert( $self->{poster}, "no poster" );
    __assert( $self->{journal}, "no journal" );
    return $self;
}

# returns a hashref: { title => '', description => '', image => $url }
sub extract_metadata {
    my ($self) = @_;
    my %meta;

    $meta{'title'} = LJ::Text->drop_html( $self->subject_raw );

    $meta{'description'} = eval {
        my $text = $self->event_raw;
        $text = LJ::Text->drop_html($text);
        $text = LJ::Text->truncate_to_word_with_ellipsis( 'str' => $text, 'bytes' => 300 );
        return $text;
    };
    die "cannot get entry description: $@" unless defined $meta{'description'};

    $meta{'image'} = eval {
        my $text = $self->event_raw;
        my $images = LJ::html_get_img_urls( \$text, 'exclude_site_imgs' => 1 );
        return $images->[0] if $images && @$images;
        
        my $userpic = $self->userpic;
        return $userpic->url if $userpic;
        
        my $journal = $self->journal;
        my ($userhead_url) = $journal->userhead;
        
        # for now, LJ::User::userhead may return a relative path,
        # so let's fix this
        unless ( $userhead_url =~ /^https?:\/\// ) {
            $userhead_url = $LJ::IMGPREFIX . '/' . $userhead_url . "?v=3";
        }
        return $userhead_url;
    };
    die "cannot get entry image: $@" unless defined $meta{'image'};

    return \%meta;
}

sub entries_exists {
  my ( $journal, $user ) = @_;
    __assert($journal, "no journal");
    my $journalid = $journal->userid;
    my $userid = $user->userid ;
    my $dbcr = LJ::get_cluster_def_reader($journal)
        or die "get cluster for journal failed";

    return $dbcr->selectcol_arrayref("SELECT delayedid " .
                                     "FROM delayedlog2 WHERE journalid=$journalid AND posterid = $userid ".
                                     "LIMIT 1");    
}

sub get_entries_count {
    my ( $class, $journal, $skip, $elements_to_show, $userid ) = @_;
    __assert($journal, "no journal");
    my $journalid = $journal->userid;

    my $dbcr = LJ::get_cluster_def_reader($journal) 
        or die "get cluster for journal failed";

    unless ($userid) {
        my $remote = LJ::get_remote();
        return undef unless $remote;
        $userid = $remote->userid ;

        return undef unless __delayed_entry_can_see( $journal,
                                                     $remote );
    } else {
        my $u = LJ::want_user($userid);
        return undef unless __delayed_entry_can_see( $journal,
                                                      $u );
    }

    return $dbcr->selectrow_array(  "SELECT count(delayedid) " .
                                    "FROM delayedlog2 ".
                                    "WHERE journalid=$journalid" );
}

sub get_entries_by_journal {
    my ( $class, $journal, $skip, $elements_to_show, $userid ) = @_;
    __assert($journal, "no journal");
    my $journalid = $journal->userid;

    my $dbcr = LJ::get_cluster_def_reader($journal) 
        or die "get cluster for journal failed";

    $elements_to_show += 1 if $skip > 0;

    my $sql_limit = '';
    if ($skip || $elements_to_show) {
        $sql_limit = "LIMIT $skip, $elements_to_show";
    }

    my $sql_poster = '';
    unless ($userid) {
        my $remote = LJ::get_remote();
        return undef unless $remote;
        $userid = $remote->userid ;

        if (!__delayed_entry_can_see( $journal, $remote ) ) {
            $sql_poster = 'AND posterid = ' . $remote->userid . " ";
         }
    } else {
        my $u = LJ::want_user($userid);
        if (!__delayed_entry_can_see( $journal, $u ) ){
            $sql_poster = 'AND posterid = ' . $u->userid . " ";
        }
    }

    #my $secwhere = __delayed_entry_secwhere( $journal,
    #                                         $journal->userid,
    #                                         $userid );

    return $dbcr->selectcol_arrayref("SELECT delayedid " .
                                     "FROM delayedlog2 WHERE journalid=$journalid  $sql_poster".
                                     "ORDER BY revptime $sql_limit");
}

sub get_daycount_query {
    my ($class, $journal, $list, $secwhere) = @_;
    my $dbcr = LJ::get_cluster_def_reader($journal);

    my $remote = LJ::get_remote();
    return undef unless $remote;
    my $sql_poster = '';
    if (! __delayed_entry_can_see( $journal, $remote ) ) {
        $sql_poster = 'AND posterid = ' . $remote->userid . " ";
    }

    my $sth = $dbcr->prepare("SELECT year, month, day, COUNT(*) " .
                             "FROM delayedlog2 WHERE journalid=? $sql_poster $secwhere GROUP BY 1, 2, 3");
    $sth->execute($journal->userid);
    while (my ($y, $m, $d, $c) = $sth->fetchrow_array) {
        push @$list, [ int($y), int($m), int($d), int($c) ];
    }
}

sub get_entries_for_day_row {
    my ( $class, $journal, $year, $month, $day ) = @_;
    my $entries = [];

    my $remote = LJ::get_remote();
    return undef unless $remote;
    return undef unless __delayed_entry_can_see( $journal,
                                                 $remote );

    my $secwhere = __delayed_entry_secwhere( $journal,
                                             $journal->userid,
                                             $remote->userid );

    my $dbcr = LJ::get_cluster_def_reader($journal) 
        or die "get cluster for journal failed";

    my $jouralid = $journal->userid;
    return $dbcr->selectcol_arrayref("SELECT delayedid ".
                            "FROM delayedlog2 ".
                            "WHERE journalid=$jouralid " .
                            "AND year=$year AND month=$month AND day=$day ".
                            "$secwhere LIMIT 2000");
}

sub get_entries_for_day {
    my ($class, $journal, $year, $month, $day, $dateformat) = @_;
    my $entries = [];

    my $remote = LJ::get_remote();
    return undef unless $remote;
    return undef unless __delayed_entry_can_see( $journal,
                                                 $remote );

    my $secwhere = __delayed_entry_secwhere( $journal,
                                             $journal->userid,
                                             $remote->userid );

    my $dbcr = LJ::get_cluster_def_reader($journal) 
        or die "get cluster for journal failed";

    $dbcr = $dbcr->prepare("SELECT l.delayedid, l.posterid, l.day, ".
                            "DATE_FORMAT(l.posttime, '$dateformat') AS 'alldatepart', ".
                            "l.security, l.allowmask ".
                            "FROM delayedlog2 l ".
                            "WHERE l.journalid=? AND l.year=? AND l.month=? AND day=?".
                            "$secwhere LIMIT 2000");
    $dbcr->execute($journal->userid, $year, $month, $day);

    my @items;
    push @items, $_ while $_ = $dbcr->fetchrow_hashref;
    return @items;
}

sub getevents {
    my ( $self, $req, $flags, $err, $res ) = @_;

    return 0 if $req->{itemid};
    $flags->{allow_anonymous} = 1;
    return 0 unless LJ::Protocol::authenticate($req, $err, $flags);

    $flags->{'ignorecanuse'} = 1; # later we will check security levels, so allow some access to communities
    return 0 unless LJ::Protocol::check_altusage($req, $err, $flags);

    my $u = $flags->{'u'};
    my $uowner = $flags->{'u_owner'} || $u;

    ### shared-journal support
    my $userid = ($u ? $u->{'userid'} : 0);
    my $ownerid = $flags->{'ownerid'};
    if( $req->{journalid} ){
        $ownerid = $req->{journalid};
        $uowner = LJ::load_userid( $req->{journalid} );
    }

    my $limit = $req->{howmany} || 0;
    my $skip = $req->{'skip'} || 0;
    if ($skip > 500) { $skip = 500; }
    
    my $dbcr = LJ::get_cluster_def_reader($uowner) 
        or die "get cluster for journal failed";

    my $sql_limit = '';
    if ($skip || $limit) {
        $sql_limit = "LIMIT $skip, $limit";
    }

    my $date_limit = '';
    if ($req->{year}) {
        $date_limit .= "AND year = " . $req->{year} . " ";
    }

    if ($req->{month}) {
        $date_limit .= "AND month = " . $req->{month} . " ";
    }

    if ($req->{day}) {
        $date_limit .= "AND day = " . $req->{day} . " ";
    }

    return undef unless __delayed_entry_can_see( $uowner,
                                                 $u );

    my $secwhere = __delayed_entry_secwhere( $uowner,
                                             $ownerid,
                                             $userid );

    my $entriesids =  $dbcr->selectcol_arrayref("SELECT delayedid " .
                                                "FROM delayedlog2 WHERE journalid=$ownerid $secwhere $date_limit ".
                                                "ORDER BY revptime $sql_limit");

    my $i = 0;
    my @results = [];
    foreach my $delayedid (@$entriesids) {
        my $entry_obj = LJ::DelayedEntry->get_entry_by_id(  $u,
                                                            $delayedid,
                                                            { userid => $userid } );
        next unless $entry_obj;
        ++$i;
        $res->{"events_${i}_itemid"} = 0;
        $res->{"events_${i}_delayedid"} = $delayedid;
        $res->{"events_${i}_poster"} = $entry_obj->poster;
        $res->{"events_${i}_subject"} = $entry_obj->subject;
        $res->{"events_${i}_event"} = $entry_obj->event;
        $res->{"events_${i}_allowmask"} = $entry_obj->allowmask;
        $res->{"events_${i}_security"} = $entry_obj->security;
        $res->{"events_${i}_eventtime"} = $entry_obj->posttime;
        $res->{"events_${i}_itemid"} = $entry_obj->jitemid;
        $res->{"events_${i}_anum"} = $entry_obj->correct_anum;
        $res->{"events_${i}_sticky"} = $entry_obj->is_sticky;
    }

    $res->{'events_count'}  = $i;
    $res->{'success'} = 'OK';

    return $i;
}

sub get_entries_for_month {
    my ($class, $journal, $year, $month, $dateformat) = @_;
    my $entries = [];
    
    my $remote = LJ::get_remote();

    return undef unless $remote;
    return undef unless __delayed_entry_can_see( $journal,
                                                 $remote );
    
    my $secwhere = __delayed_entry_secwhere( $journal,
                                             $journal->userid,
                                             $remote->userid );
    
    my $dbcr = LJ::get_cluster_def_reader($journal) 
                            or die "get cluster for journal failed";
    
    $dbcr = $dbcr->prepare("SELECT l.delayedid, l.posterid, l.day, ".
                          "DATE_FORMAT(l.posttime, '$dateformat') AS 'alldatepart', ".
                          "l.security, l.allowmask ".
                          "FROM delayedlog2 l ".
                          "WHERE l.journalid=? AND l.year=? AND l.month=? ".
                          "$secwhere LIMIT 2000");
    $dbcr->execute($journal->userid, $year, $month);

    my @items;
    push @items, $_ while $_ = $dbcr->fetchrow_hashref;
    return @items;
}

sub get_itemid_after2  {
    return get_itemid_near2(@_, "after");
}

sub get_itemid_before2 {
    return get_itemid_near2(@_, "before");
}

sub get_itemid_near2 {
    my ($self, $after_before) = @_;
    my $u = $self->journal;
    my $delayedid = $self->delayedid;

    my ($order, $cmp1, $cmp2, $cmp3, $cmp4);
    if ($after_before eq "after") {
        ($order, $cmp1, $cmp2, $cmp3, $cmp4) = ("DESC", "<=", ">", sub {$a->[0] <=> $b->[0]}, sub {$b->[1] <=> $a->[1]} );
    } elsif ($after_before eq "before") {
        ($order, $cmp1, $cmp2, $cmp3, $cmp4) = ("ASC",  ">=", "<", sub {$b->[0] <=> $a->[0]}, sub {$a->[1] <=> $b->[1]} );
    } else {
        return 0;
    }

    my $dbr = LJ::get_cluster_reader($u);
    unless ($dbr){
        warn "Can't connect to cluster reader. Cluster: " . $u->clusterid;
        return 0;
    }

    my $jid = $self->journalid;
    my $field = $u->is_person() ? "revptime" : "rlogtime";

    my ($stime) = $dbr->selectrow_array(  "SELECT $field FROM delayedlog2 WHERE ".
                                        "journalid=$jid AND delayedid=$delayedid");
    return 0 unless $stime;

    my $secwhere = "AND security='public'";
    my $remote = LJ::get_remote();

    if ($remote) {
        if ($remote->userid == $self->journalid) {
            $secwhere = "";   # see everything
        } elsif ($remote->is_person() || $remote->is_identity) {
            my $gmask = LJ::get_groupmask($u, $remote);
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
            if $gmask;
        }
    }

    ##
    ## We need a next/prev record in journal before/after a given time
    ## Since several records may have the same time (time is rounded to 1 minute),
    ## we're ordering them by jitemid. So, the SQL we need is
    ##      SELECT * FROM log2
    ##      WHERE journalid=? AND rlogtime>? AND jitmemid<?
    ##      ORDER BY rlogtime, jitemid DESC
    ##      LIMIT 1
    ## Alas, MySQL tries to do filesort for the query.
    ## So, we sort by rlogtime only and fetch all (2, 10, 50) records
    ## with the same rlogtime (we skip records if rlogtime is different from the first one).
    ## If rlogtime of all fetched records is the same, increase the LIMIT and retry.
    ## Then we sort them in Perl by jitemid and takes just one.
    ##
    my $result_ref;
    foreach my $limit (2, 10, 50, 100) {
        $result_ref = $dbr->selectall_arrayref( "SELECT delayedid, $field FROM delayedlog2 use index (rlogtime,revptime) ".
                                                "WHERE journalid=? AND $field $cmp1 ? AND delayedid <> ? ".
                                                $secwhere. " ".
                                                "ORDER BY $field $order LIMIT $limit",
                                                undef, $jid, $stime, $delayedid
        );

        my %hash_times = ();
        map {$hash_times{$_->[1]} = 1} @$result_ref;

        # If we has one the only 'time' in $limit fetched rows,
        # may be $limit cuts off our record. Increase the limit and repeat.
        if (((scalar keys %hash_times) > 1) || (scalar @$result_ref) < $limit) {
            my @result;

            # Remove results with the same time but the jitemid is too high or low
            if ($after_before eq "after") {
                @result = grep { $_->[1] != $stime || $_->[0] > $delayedid } @$result_ref;
            } elsif ($after_before eq "before") {
                @result = grep { $_->[1] != $stime || $_->[0] < $delayedid } @$result_ref;
            }

            # Sort result by jitemid and get our id from a top.
            @result =  sort $cmp3 @result;

            # Sort result by revttime
            @result =  sort $cmp4 @result;

            my $id = $result[0]->[0];
            return 0 unless $id;
            return $id;
        }
    }
    return 0;
}

sub handle_prefetched_props {
    my ($self) = @_;
    #stab
    return;
}

sub can_delete_delayed_item {
    my ($class, $u, $usejournal_u) = @_;
    return LJ::can_delete_journal_item($u, $usejournal_u);
}

sub convert {
    my ($self) = @_;
    my $req = $self->{data};
    
    my $flags = { 'noauth' => 1, 
                  'u' => $self->poster };

    my $err = 0;
    my $res = LJ::Protocol::do_request("postevent", $req, \$err, $flags);
    my $fail = !defined $res->{itemid} && $res->{message};
    
    return { 'delete_entry' => (!$fail || $err < 500), 
             'res' => $res };
}

sub convert_from_data {
    my ($self, $req) = @_;
    my $flags = { 'noauth' => 1,
                  'u' => $self->poster };

    my $err = 0;
    my $res = LJ::Protocol::do_request("postevent", $req, \$err, $flags);
    my $fail = !defined $res->{itemid} && $res->{message};
    if ($fail) {
        $self->update($req);
    }
    return { 'delete_entry' => (!$fail || $err < 500), 
             'res' => $res };
}

sub can_post_to {
    my ($uowner, $poster) = @_;
    
    #if (__delayed_entry_can_see($uowner, $poster)) {
    #    return 1;
    #}
    
    my $uownerid = $uowner->userid;
    my $posterid = $poster->userid;

    my $can_manage = $poster->can_manage($uowner) || 0;
    my $moderated = $uowner->prop('moderated') || '';
    my $need_moderated = ( $moderated =~ /^[1A]$/ ) ? 1 : 0;
    my $can_post = ($uowner->is_community() && !$need_moderated) || $can_manage;
   
    if ($can_post) {
        return 1;
    }

    # don't moderate admins, moderators & pre-approved users
    my $dbh = LJ::get_db_writer();
    my ($relcount) = $dbh->selectrow_array( "SELECT 1 FROM reluser ".
                                            "WHERE userid=$uownerid AND targetid=$posterid ".
                                            "AND type IN ('A','M','N') LIMIT 1" );
    return $relcount ? 1 : 0;
}

sub __delayed_entry_can_see {
    my ( $uowner, $poster ) = @_;

    if (!$poster->can_post_to($uowner)) {
        return 0;
    }

    if ($poster->can_manage($uowner)) {
        return 1;
    }

    if ($poster->can_moderate($uowner)) {
        return 1;
    }

    return 0;
}

sub item_link {
    my ($u, $delayedid, @args) = @_;
    # XXX: should have an option of returning a url with escaped (&amp;)
    #      or non-escaped (&) arguments.  a new link object would be best.
    my $args = @args ? "?" . join("&amp;", @args) : "";
    return LJ::journal_base($u) . "/d$delayedid.html$args";
}

sub __delayed_entry_secwhere {
    my ( $uowner, $ownerid, $posterid ) = @_;
    my $secwhere = " AND (posterid = $posterid OR journalid = $posterid
                            OR posterid = $ownerid OR journalid = $ownerid)";
    return $secwhere;
}

sub __extract_tag_list {
    my ($tags) = @_;
    __assert($tags, "no tags");

    return [] unless $$tags;

    my @tags_array = ();
    my @pretags = split(/,/, $$tags );
    foreach my $pretag (@pretags) {
        my $trimmed = LJ::trim($pretag);
        
        my $in = grep { $_ eq $trimmed } @tags_array;
        if (!$in) {
            push @tags_array, $trimmed;
        }
    }

    $$tags = join(",", @tags_array);
    return \@tags_array;
}

sub __kill_dayct2_cache {
    my ($u) = @_;
    my $uid = LJ::want_userid($u) or return undef;

    my $memkey = [$uid, "dayct2:$uid:p"];
    LJ::MemCache::delete($memkey);

    $memkey = [$uid, "dayct2:$uid:a"];
    LJ::MemCache::delete($memkey);

    $memkey = [$uid, "dayct2:$uid:g"];
    LJ::MemCache::delete($memkey);
}

sub __serialize {
    my ($req) = @_;
    __assert($req, "no request");
    $req->{'event'} =~ s/\r\n/\n/g; # compact new-line endings to more comfort chars count near 65535 limit

   my $ext = $req->{'ext'};
   my $flags = $ext->{'flags'};
   $flags->{'u_owner'} = undef;
   $flags->{'u'} = undef;

   return LJ::JSON->to_json( $req );
}

sub __deserialize {
    my ($req) = @_;
    __assert($req, "no request");

    return LJ::JSON->from_json( $req );
}

sub __get_now {
    my $dt = DateTime->now->set_time_zone('UTC');

    # make the proper date format
    return sprintf("%04d-%02d-%02d %02d:%02d",  $dt->year, 
                                                $dt->month,
                                                $dt->day, 
                                                $dt->hour,
                                                $dt->minute );
}

sub __get_datetime {
    my ($req, $dont_use_tz) = @_;
    __assert($req, "No request");
    __assert($req->{'tz'}, "time zone is not set");

    my $dt = DateTime->new(
        year      => $req->{'year'}, 
        month     => $req->{'mon'},
        day       => $req->{'day'}, 
        hour      => $req->{'hour'},
        minute    => $req->{'min'},
        time_zone => $req->{tz},
    );

    if (!$dont_use_tz) {
        $dt->set_time_zone( 'UTC' );
    }

    # make the proper date format
    return sprintf("%04d-%02d-%02d %02d:%02d",  $dt->year, 
                                                $dt->month,
                                                $dt->day, 
                                                $dt->hour,
                                                $dt->minute );
}

sub __assert {
    my ($statement, $error) = @_;
    $error ||= '';
    unless ($statement) {
        die "assertion failed! $error";
    }
}

1;

