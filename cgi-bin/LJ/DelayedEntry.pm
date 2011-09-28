package LJ::DelayedEntry;

use strict;
use warnings;
require 'ljprotocol.pl';
use LJ::User;
use Storable;
                
sub create {
    my ( $class, $req, $opts ) = @_;

    __assert( $opts );
    __assert( $opts->{journal} );
    __assert( $opts->{poster}  );
    __assert( $req );

    my $self = bless {}, $class;

    my $journal = $opts->{journal};
    my $poster = $opts->{poster};
    $req->{'event'} =~ s/\r\n/\n/g;

    my $data_ser = __serialize($journal, $req);

    my $journalid = $journal->userid;
    my $posterid = $poster->userid;
    my $subject = $req->{subject};
    my $posttime = __get_datatime($req);
    my $dbh = LJ::get_db_writer();
    
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

    my $now         = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()");

    my $qsecurity   = $dbh->quote($security);
    my $qallowmask  = $req->{'allowmask'}+0;
    my $qposttime   = $dbh->quote($posttime);
    my $utime       = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP($qposttime)");

    my $rlogtime    = $LJ::EndOfTime - $now;
    my $rposttime   = $LJ::EndOfTime - $utime;

    my $taglist = __extract_tag_list(\$req->{props}->{taglist});

    $journal->do("INSERT INTO delayedlog2 (journalid, delayedid, posterid, subject, " .
                  "logtime, posttime, security, allowmask, year, month, day, rlogtime, revptime) " .
                  "VALUES ($journalid, $delayedid, $posterid, ?, NOW(), $qposttime, ".
                  "$qsecurity, $qallowmask, ?, ?, ?, $rlogtime,  $rposttime)",
                  undef,  LJ::text_trim($req->{'subject'}, 30, 0), 
                  $req->{year}, $req->{mon}, $req->{day} );
    
    $journal->do("INSERT INTO delayedblob2 ".
                "VALUES ($journalid, $delayedid, $data_ser)");

    $self->{journal} = $opts->{journal};    
    $self->{posttime} = $opts->{posttime};
    $self->{posttime} = $dbh->selectrow_array("SELECT NOW()");
    $self->{poster} = $opts->{poster};
    $self->{data} = $req;
    $self->{taglist} = $taglist;
    $self->{delayed_id} = $delayedid;
    return $self;
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

sub logtime {
    my ($self) = @_;
    return $self->{logtime};
}

sub posttime {
    my ($self) = @_;
    return $self->{posttime};
}

sub posttime_as_unixtime {
    my ($self) = @_;
    my $dbh = LJ::get_db_writer();
    my $qposttime = $self->posttime;
    return $dbh->selectrow_array("SELECT UNIX_TIMESTAMP($qposttime)");
} 

sub alldatepart {
    my ($self) = @_;
    return $self->{alldatepart};
}

sub system_alldatepart { 
    my ($self) = @_;
    return $self->{system_alldatepart};
}

sub is_sticky {
    my ($self) = @_;
    return 0 unless  $self->data->{type};
    return $self->data->{type} eq 'sticky';
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
    my $request_time = __get_datatime($req);

    return $request_time ge $now;
}

sub visible_to {
    my ($self, $remote, $opts) = @_;
    return __delayed_entry_can_see($self->journal, $remote);
}

# defined by the entry poster
sub adult_content {
    my ($self) = @_;
    return $self->prop('adult_content');
}

# defined by an admin
sub admin_content_flag {
    my ($self) = @_;
    return $self->prop('admin_content_flag');
}

# uses both poster- and admin-defined props to figure out the adult content level
sub adult_content_calculated {
    my ($self) = @_;

    return "explicit" if $self->admin_content_flag eq "explicit_adult";
    return $self->adult_content;
}

sub prop {
    my ( $self, $prop_name ) = @_;
    return $self->props->{$prop_name} || '';
}

sub url {
    my ($self) = @_;
    my $journal = $self->journal;
    my $url = $journal->journal_base . "/d" . $self->delayedid . ".html";
    return $url;
}

sub statusvis {
    my ($self) = @_;
    return $self->prop("statusvis") eq "S" ? "S" : "V";
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
    return $self->{alldatepart};
}

sub logtime_mysql {
    my ($self) = @_;
    return $self->{system_alldatepart};
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
    __assert( $self->{delayed_id} );
    __assert( $self->{journal} );

    my $journal = $self->{journal};
    my $delayed_id = $self->{delayed_id};

    $journal->do("DELETE FROM delayedlog2 " .
                  "WHERE delayedid = $delayed_id AND " .
                  "journalid = " . $journal->userid);

    $journal->do("DELETE FROM delayedblob2 " .
                 "WHERE delayedid = $delayed_id AND " .
                 "journalid = " . $journal->userid);

    $self->{delayed_id} = undef;
    $self->{journal} = undef;
    $self->{poster} = undef;
    $self->{data} = undef;
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
    __assert( $self->{delayed_id} );
    __assert( $self->{journal} );
    __assert( $self->{poster} );

    $req->{tz} = $req->{tz} || $self->data->{tz};

    my $journalid = $self->journal->userid;
    my $posterid  = $self->poster->userid;
    my $subject   = $req->{subject};
    my $posttime  = __get_datatime($req);
    my $data_ser  = __serialize($self->journal, $req);
    my $delayedid = $self->{delayed_id};
    my $dbh       = LJ::get_db_writer();

    my $security  = "public";
    my $uselogsec = 0;

    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }

    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    my $now         = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()");

    my $qsecurity   = $dbh->quote($security);
    my $qallowmask  = $req->{'allowmask'}+0;
    my $qposttime   = $dbh->quote($posttime);
    my $utime       = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP($qposttime)");

    my $rlogtime    = $LJ::EndOfTime -= $now;
    my $rposttime   = $LJ::EndOfTime - $utime;
    $self->{taglist} = __extract_tag_list(\$req->{props}->{taglist});
    $req->{'event'} =~ s/\r\n/\n/g; # compact new-line endings to more comfort chars count near 65535 limit

    $self->journal->do("UPDATE delayedlog2 SET posterid=$posterid, " .
                         "subject=?, posttime=$qposttime, " . 
                         "security=$qsecurity, allowmask=$qallowmask, " .    
                         "year=?, month=?, day=?, " .
                         "rlogtime=$rlogtime, revptime=$rposttime " .
                         "WHERE journalid=$journalid AND delayedid=$delayedid",
        undef,  LJ::text_trim($req->{'subject'}, 30, 0), 
        $req->{year}, $req->{mon}, $req->{day} );

    $self->journal->do( "UPDATE delayedblob2 SET request_stor=$data_ser" . 
                        "WHERE journalid=$journalid AND delayedid=$delayedid");
}   

sub update_tags {
    my ($self, $tags) = @_;
    $self->props->{taglist} = $tags;
    $self->{taglist} = __extract_tag_list(\$self->props->{taglist});
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
    __assert($opts->{journalid});
    __assert($opts->{delayed_id});
    __assert($opts->{posterid});

    my $journalid = $opts->{posterid};
    my $delayedid = $opts->{delayed_id};

    my $data_ser = $dbcr->selectrow_array( "SELECT request_stor " .
                                           "FROM delayedblob2 " .
                                           "WHERE journalid=$journalid AND " .
                                           "delayedid = $delayedid" );

    my $self = bless {}, $class; 
    $self->{journal} = LJ::want_user($opts->{journalid});
    $self->{data} = __deserialize($self->journal, $data_ser);
    $self->{poster} = LJ::want_user($opts->{posterid});
    $self->{delayed_id} = $delayedid;
    $self->{posttime} = __get_datatime($self->{data});

    return $self;
}


sub get_entry_by_id {
    my ($class, $journal, $delayedid, $options) = @_;
    __assert($journal);
    
    return undef unless $delayedid;

    my $journalid = $journal->userid;
    my $dateformat_type = $options->{'dateformat'} || '';
    my $dbcr = LJ::get_cluster_def_reader($journal) 
        or die "get cluster for journal failed";

    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    if ($dateformat_type eq "S2") {
        $dateformat = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    }

    my $userid = $options->{userid} || 0;
    my $user = LJ::get_remote() || LJ::want_user($userid);

    return undef unless $user;
    return undef unless __delayed_entry_can_see( $journal,
                                                  $user );

    #my $secwhere = __delayed_entry_can_see() __delayed_entry_secwhere( $journal,
    #                                         $journal->userid,
    #                                         $userid );

    my $opts = $dbcr->selectrow_arrayref("SELECT journalid, delayedid, posterid, " .
                                         "DATE_FORMAT(posttime, \"$dateformat\") AS 'alldatepart', " .
                                         "DATE_FORMAT(logtime, \"$dateformat\") AS 'system_alldatepart', " . 
                                         "logtime " .
                                         "FROM delayedlog2 ".
                                         "WHERE journalid=$journalid AND ".
                                         "delayedid = $delayedid");

    return undef unless $opts;

    my $data_ser = $dbcr->selectrow_array("SELECT request_stor " .
                                          "FROM delayedblob2 ".
                                          "WHERE journalid=$journalid AND ".
                                          "delayedid = $delayedid");
    my $self = bless {}, $class; 
    $self->{data}               = __deserialize($journal, $data_ser);
    $self->{journal}            = $journal;
    $self->{poster}             = LJ::want_user($opts->[2]);
    $self->{delayed_id}         = $delayedid;
    $self->{posttime}           = __get_datatime($self->{data});
    $self->{alldatepart}        = $opts->[3];
    $self->{logtime}            = $opts->[5];
    $self->{system_alldatepart} = $opts->[4];
    $self->{taglist}            = __extract_tag_list(\$self->{data}->{props}->{taglist});

    __assert( $self->{poster} );
    __assert( $self->{journal} );

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


sub get_entries_count {
    my ( $class, $journal, $skip, $elements_to_show, $userid ) = @_;
    __assert($journal);
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

    #my $secwhere = __delayed_entry_secwhere( $journal,
    #                                         $journal->userid,
    #                                         $userid );

    return $dbcr->selectrow_array(" SELECT count(delayedid) " .
                                    "FROM delayedlog2 ".
                                    "WHERE journalid=$journalid ");
}

sub get_entries_by_journal {
    my ( $class, $journal, $skip, $elements_to_show, $userid ) = @_;
    __assert($journal);
    my $journalid = $journal->userid;

    my $dbcr = LJ::get_cluster_def_reader($journal) 
        or die "get cluster for journal failed";

    $elements_to_show += 1 if $skip > 0;

    my $sql_limit = '';
    if ($skip || $elements_to_show) {
        $sql_limit = "LIMIT $skip, $elements_to_show";
    }

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

    #my $secwhere = __delayed_entry_secwhere( $journal,
    #                                         $journal->userid,
    #                                         $userid );

    return $dbcr->selectcol_arrayref("SELECT delayedid " .
                                     "FROM delayedlog2 WHERE journalid=$journalid  ".
                                     "ORDER BY revptime $sql_limit");
}

sub get_daycount_query {
    my ($class, $journal) = @_;
    my $dbcr = LJ::get_cluster_def_reader($journal);

    my $remote = LJ::get_remote();
    return undef unless $remote;
    return undef unless __delayed_entry_can_see( $journal,
                                                 $remote  );
    
    my $secwhere = __delayed_entry_secwhere( $journal,
                                             $journal->userid,
                                             $remote->userid );

    my $sth = $dbcr->prepare("SELECT year, month, day, COUNT(*) " .
                             "FROM delayedlog2 WHERE journalid=? $secwhere GROUP BY 1, 2, 3");
    $sth->execute($journal->userid);
    return $sth;
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
    my $field = $u->{'journaltype'} eq "P" ? "revptime" : "rlogtime";

    my $stime = $dbr->selectrow_array(  "SELECT $field FROM delayedlog2 WHERE ".
                                        "journalid=$jid AND delayedid=$delayedid");
    return 0 unless $stime;

    my $secwhere = "AND security='public'";
    my $remote = LJ::get_remote();

    if ($remote) {
        if ($remote->userid == $self->journalid) {
            $secwhere = "";   # see everything
        } elsif ($remote->{'journaltype'} eq 'P' || $remote->{'journaltype'} eq 'I') {
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
}

sub can_delete_delayed_item {
    my ($u, $usejournal_u) = @_;
    return LJ::can_delete_journal_item($u, $usejournal_u);
}

sub convert {
    my ($self) = @_;
    my $req = $self->{data};

    my $journal    = $self->journal;
    my $journalid  = $journal->userid;
    my $clusterid  = $journal->clusterid;

    my $poster     = $self->poster;
    my $posterid   = $poster->userid;

    my $dbh  = LJ::get_db_writer();
    my $dbcm = LJ::get_cluster_master($journal);

    my $ext = $req->{data_d_ext};

    my $flags     = $ext->{flags};
    my $event     = $req->{event};
    my $eventtime = __get_datatime($req);

    my $security  = "public";
    my $uselogsec = 0;

    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }

    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    my $qsecurity  = $dbh->quote($security);
    my $qallowmask = $req->{'allowmask'}+0;
    my $qeventtime = $dbh->quote($eventtime);
    my $now        = $dbcm->selectrow_array("SELECT UNIX_TIMESTAMP()");
    my $anum       = int(rand(256));
    my $jitemid    = LJ::alloc_user_counter($journal, "L");
    my $rlogtime   = $LJ::EndOfTime;

    # do processing of embedded polls (doesn't add to database, just
    # does validity checking)
    my @polls = ();

    if (LJ::Poll->contains_new_poll(\$event)) {
        return "Your account type doesn't permit creating polls."
            unless (LJ::get_cap($poster, "makepoll")
                    || ($journal->{'journaltype'} eq "C"
                    && LJ::get_cap($journal, "makepoll")
                    && LJ::can_manage_other($poster, $journal)));

        my $error = "";
        @polls = LJ::Poll->new_from_html(\$event, \$error, {
            'journalid' => $journalid,
            'posterid' => $posterid,
        });

        return $error if $error;
    }

    $req->{subject}    = $req->{subject} || '';
    $req->{usejournal} = $req->{usejournal} || '';
    $req->{allowmask}  = $req->{allowmask} || '';
    $req->{security}   = $req->{security} || '';

    my $dupsig = Digest::MD5::md5_hex(join('', map { $req->{$_} }
                            qw(subject event usejournal security allowmask)));

    my $lock_key = "post-$journalid";

    # release our duplicate lock
    my $release = sub {  $dbcm->do("SELECT RELEASE_LOCK(?)", undef, $lock_key); };

    # our own local version of fail that releases our lock first
    my $fail = sub { $release->(); return fail(@_); };

    my $res = {};
    my $res_done = 0;  # set true by getlock when post was duplicate, or error getting lock

    my $getlock = sub {
        my $r = $dbcm->selectrow_array("SELECT GET_LOCK(?, 2)", undef, $lock_key);

        unless ($r) {
            $res = undef;    # a failure case has an undef result
            $res_done = 1;   # tell caller to bail out

            return {
                error_message => "can't get lock",
                delete_entry  => 0,
            }; 
        }

        my @parts = split(/:/, $poster->{'dupsig_post'});

        if ($parts[0] eq $dupsig) {
            # duplicate!  let's make the client think this was just the
            # normal first response.
            $res->{'itemid'} = $parts[1];
            $res->{'anum'}   = $parts[2];
            
            my $dup_entry = LJ::Entry->new(
                $journal,
                jitemid => $res->{'itemid'},
                anum    => $res->{'anum'},
            );
            $res->{'url'} = $dup_entry->url;
            
            $res_done = 1;
            $release->();
        }
    };

    # bring in LJ::Entry with Class::Autouse
    LJ::Entry->can("dostuff");
    LJ::replycount_do($journal, $jitemid, "init");

    # remove comments and logprops on new entry ... see comment by this sub for clarification
    LJ::Protocol::new_entry_cleanup_hack($poster, $jitemid) if $LJ::NEW_ENTRY_CLEANUP_HACK;
    my $verb = $LJ::NEW_ENTRY_CLEANUP_HACK ? 'REPLACE' : 'INSERT';    

    my $dberr;
    $journal->log2_do(\$dberr,  "INSERT INTO log2 (journalid, jitemid, posterid, eventtime, logtime, security, ".
                                "allowmask, replycount, year, month, day, revttime, rlogtime, anum) ".
                                "VALUES ($journalid, $jitemid, $posterid, $qeventtime, FROM_UNIXTIME($now), $qsecurity, $qallowmask, ".
                                "0, $req->{'year'}, $req->{'mon'}, $req->{'day'}, $LJ::EndOfTime-".
                                "UNIX_TIMESTAMP($qeventtime), $rlogtime, $anum)");

    return {
        error_message => $dberr,
        delete_entry  => 0,
    } if $dberr;

    # post become 'sticky post'
    if ( $req->{type} && $req->{type} eq 'sticky' ) {
        $journal->set_sticky($jitemid);
    }

    LJ::MemCache::incr([$journalid, "log2ct:$journalid"]);
    LJ::memcache_kill($journalid, "dayct2");
    __kill_dayct2_cache();

    # set userprops.
    {
        my %set_userprop;

        # keep track of itemid/anum for later potential duplicates
        $set_userprop{"dupsig_post"} = "$dupsig:$jitemid:$anum";

        # record the eventtime of the last update (for own journals only)
        $set_userprop{"newesteventtime"} = $eventtime if $posterid == $journalid;

        $poster->set_prop(\%set_userprop);
    }

    # end duplicate locking section
    $release->();

    my $ditemid = $jitemid * 256 + $anum;

    ### finish embedding stuff now that we have the itemid
    {
        ### this should NOT return an error, and we're mildly fucked by now
        ### if it does (would have to delete the log row up there), so we're
        ### not going to check it for now.
        
        my $error = "";
        foreach my $poll (@polls) {
            $poll->save_to_db(
                journalid => $journalid,
                posterid  => $posterid,
                ditemid   => $ditemid,
                error     => \$error,
            );
            
            my $pollid = $poll->pollid;
            
            $event =~ s/<lj-poll-placeholder>/<lj-poll-$pollid>/;
        }
    }
    #### /embedding

    ### extract links for meme tracking
    unless ( $req->{'security'} eq "usemask" ||
             $req->{'security'} eq "private" )
    {
        foreach my $url (LJ::get_urls($event)) {
            LJ::record_meme($url, $posterid, $ditemid, $journalid);
        }
    }

    # record journal's disk usage
    my $bytes = length($event) + length($req->{'subject'});
    $journal->dudata_set('L', $jitemid, $bytes);

    $journal->do("$verb INTO logtext2 (journalid, jitemid, subject, event) ".
        "VALUES ($journalid, $jitemid, ?, ?)", undef, $req->{'subject'},
    LJ::text_compress($event));

    if ($journal->err) {
        my $msg = $journal->errstr;
        LJ::delete_entry($journal, $jitemid, undef, $anum);   # roll-back
         return  { error_message =>  "logsec2:$msg", delete_entry => 0 };
    }

    LJ::MemCache::set(  [$journalid, "logtext:$clusterid:$journalid:$jitemid"],
                        [ $req->{'subject'}, $event ]);

    # keep track of custom security stuff in other table.
    if ($uselogsec) {
        $journal->do("INSERT INTO logsec2 (journalid, jitemid, allowmask) ".
            "VALUES ($journalid, $jitemid, $qallowmask)");
        if ($journal->err) {
            my $msg = $journal->errstr;
            LJ::delete_entry($journal, $jitemid, undef, $anum);   # roll-back
            return  { error_message =>  "logsec2:$msg", delete_entry => 0 };
        }
    }

    # Entry tags
    if ($req->{props} && defined $req->{props}->{taglist}) {
        # slightly misnamed, the taglist is/was normally a string, but now can also be an arrayref.
        my $taginput = $req->{props}->{taglist};
        
        my $logtag_opts = {
            remote       => $poster,
            skipped_tags => [], # do all possible and report impossible
        };

        if (ref $taginput eq 'ARRAY') {
            $logtag_opts->{set} = [@$taginput];
            $req->{props}->{taglist} = join(", ", @$taginput);
        }
        else {
            $logtag_opts->{set_string} = $taginput;
        }

        my $rv = LJ::Tags::update_logtags($journal, $jitemid, $logtag_opts);
        push @{$res->{warnings} ||= []}, LJ::Lang::ml('/update.bml.tags.skipped', { 'tags' => join(', ', @{$logtag_opts->{skipped_tags}}),
            'limit' => $journal->get_cap('tags_max') } )
        if @{$logtag_opts->{skipped_tags}};
    }

    ## copyright
    if (LJ::is_enabled('default_copyright', $poster)) {
        $req->{'props'}->{'copyright'} = $poster->prop('default_copyright')
            unless defined $req->{'props'}->{'copyright'};
        $req->{'props'}->{'copyright'} = 'P' # second try
            unless defined $req->{'props'}->{'copyright'};
    }
    else {
        delete $req->{'props'}->{'copyright'};
    }

    ## give features
    if (LJ::is_enabled('give_features')) {
        $req->{'props'}->{'give_features'} = ($req->{'props'}->{'give_features'} eq 'enable') ? 1 :
        ($req->{'props'}->{'give_features'} eq 'disable') ? 0 :
        1; # LJSUP-9142: All users should be able to use give button 
    }

    # meta-data
    if (%{$req->{'props'}}) {
        my $propset = {};

        foreach my $pname (keys %{$req->{'props'}}) {
            next unless $req->{'props'}->{$pname};
            next if $pname eq "revnum" || $pname eq "revtime";
            my $p = LJ::get_prop("log", $pname);
            next unless $p;
            next unless $req->{'props'}->{$pname};
            $propset->{$pname} = $req->{'props'}->{$pname};
        }

        my %logprops;
        LJ::set_logprop($journal, $jitemid, $propset, \%logprops) if %$propset;
        
        # if set_logprop modified props above, we can set the memcache key
        # to be the hashref of modified props, since this is a new post
        LJ::MemCache::set([$journal->{'userid'}, "logprop:$journal->{'userid'}:$jitemid"],
        \%logprops) if %logprops;
    }

    $dbh->do("UPDATE userusage SET timeupdate=NOW(), lastitemid=$jitemid ".
        "WHERE userid=$journalid") unless $flags->{'notimeupdate'};
    LJ::MemCache::set([$journalid, "tu:$journalid"], pack("N", time()), 30*60);

    # argh, this is all too ugly.  need to unify more postpost stuff into async
    $poster->invalidate_directory_record;

    # note this post in recentactions table
    LJ::note_recent_action($journal, 'post');

    # if the post was public, and the user has not opted out, try to insert into the random table;
    # note we do INSERT INGORE since there will be lots of people posting every second, and that's
    # the granularity we use
    if ($security eq 'public' && LJ::u_equals($poster, $journal) && ! $poster->prop('latest_optout')) {
        $poster->do("INSERT IGNORE INTO random_user_set (posttime, userid) VALUES (UNIX_TIMESTAMP(), ?)",
            undef, $poster->{userid});
    }

    my @jobs;  # jobs to add into TheSchwartz

    # notify weblogs.com of post if necessary
    if ( !$LJ::DISABLED{'weblogs_com'} && $poster->{'opt_weblogscom'} 
         && LJ::get_cap($poster, "weblogscom") &&
         $security eq "public" ) {
            push @jobs, TheSchwartz::Job->new_from_array("LJ::Worker::Ping::WeblogsCom", {
                'user'  => $poster->{'user'},
                'title' => $poster->{'journaltitle'} || $poster->{'name'},
                'url'   => LJ::journal_base($poster) . "/",
        });
    }

    my $entry = LJ::Entry->new($journal, jitemid => $jitemid, anum => $anum);

    # run local site-specific actions
    LJ::run_hooks("postpost", {
        'itemid'    => $jitemid,
        'anum'      => $anum,
        'journal'   => $journal,
        'poster'    => $poster,
        'event'     => $event,
        'eventtime' => $eventtime,
        'subject'   => $req->{'subject'},
        'security'  => $security,
        'allowmask' => $qallowmask,
        'props'     => $req->{'props'},
        'entry'     => $entry,
        'jobs'      => \@jobs,  # for hooks to push jobs onto
        'req'       => $req,
        'res'       => $res,
    });

    # cluster tracking
    LJ::mark_user_active($poster, 'post');
    LJ::mark_user_active($journal, 'post') unless LJ::u_equals($poster, $journal);

    $res->{'itemid'} = $jitemid;  # by request of mart
    $res->{'anum'}   = $anum;
    $res->{'url'}    = $entry->url;

    push @jobs, LJ::Event::JournalNewEntry->new($entry)->fire_job;
    push @jobs, LJ::Event::UserNewEntry->new($entry)->fire_job if (!$LJ::DISABLED{'esn-userevents'} || $LJ::_T_FIRE_USERNEWENTRY);
    push @jobs, LJ::EventLogRecord::NewEntry->new($entry)->fire_job;

    # PubSubHubbub Support
    LJ::Feed::generate_hubbub_jobs($journal, \@jobs) unless $journal->is_syndicated;

    my $sclient = LJ::theschwartz();

    if ($sclient && @jobs) {
        my @handles = $sclient->insert_jobs(@jobs);
        # TODO: error on failure?  depends on the job I suppose?  property of the job?
    }

    return { delete_entry => 1, res => $res };
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
    warn "cannot see";

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
    __assert($tags);

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
    my ($journal, $req) = @_;
    __assert($journal);
    __assert($req);

    my $dbcm = LJ::get_cluster_master($journal);

    return $dbcm->quote(Storable::nfreeze($req));
    #return LJ::JSON->to_json( $data );
}

sub __deserialize {
    my ($journal, $req) = @_;
    __assert($journal);
    __assert($req);

    #return LJ::JSON->from_json( $data );
    return Storable::thaw($req);
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

sub __get_datatime {
    my ($req) = @_;
    __assert($req);
    __assert($req->{'tz'});

    my $dt = DateTime->new(
        year      => $req->{'year'}, 
        month     => $req->{'mon'},
        day       => $req->{'day'}, 
        hour      => $req->{'hour'},
        minute    => $req->{'min'},
        time_zone => $req->{tz},
    );

    #if ($dt->is_dst) {
    #    $dt->subtract( hours => 1 );
    #}

    $dt->set_time_zone( 'UTC' );

    # make the proper date format
    return sprintf("%04d-%02d-%02d %02d:%02d",  $dt->year, 
                                                $dt->month,
                                                $dt->day, 
                                                $dt->hour,
                                                $dt->minute );
}

sub __assert {
    my ($statement) = @_;

    unless ($statement) {
        die "assertion failed!";
    }
}

1;
