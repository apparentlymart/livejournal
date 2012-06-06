package LJ::DelayedEntry;

use strict;
use warnings;
require 'ljprotocol.pl';
use LJ::User;
use Storable;

sub create_from_url {
    my ($class, $url, $opts) = @_;
    return undef unless $url;

    if ($url =~ m!(.+)/d(\d+)\.html!) {
        my $username = $1;
        my $delayed_id = $2;
        my $u = LJ::User->new_from_url($username) or return undef;
        return LJ::DelayedEntry->get_entry_by_id($u, $delayed_id, $opts);
    }

    return undef;
}

sub valid {
    return 1;
}

sub is_delayed {
    return 1;
}

sub create {
    my ( $class, $req, $opts ) = @_;

    __assert( $opts , "no options");
    __assert( $opts->{journal}, "no journal");
    __assert( $opts->{poster}, "no poster" );
    __assert( $req, "no request" );

    my $self = bless {}, $class;

    $req->{'event'} =~ s/\r\n/\n/g;
    $req->{ext}->{flags}->{u} = undef; # it's no need to be stored

    my $journal = $opts->{journal};
    my $poster  = $opts->{poster};

    my $dbh         = LJ::get_db_writer();
    my $journalid   = $journal->userid;
    my $posterid    = $poster->userid;
    my $subject     = $req->{subject};

    my $now        = time;

    $req->{props}->{'set_to_schedule'} = $now;
    $req->{props}->{'revtime_sch'}     = $now;

    my $posttime    = __get_datetime($req);
    my $data_ser    = __serialize($req);
    my $delayedid   = LJ::alloc_user_counter( $journal,
                                              'Y',
                                              undef);
    my $security    = "public";
    my $uselogsec   = 0;

    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }

    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    my $allowmask  = $req->{'allowmask'}+0;

    my $dt = DateTime->new(   year       => $req->{year},
                              month      => $req->{mon},
                              day        => $req->{day},
                              hour       => $req->{hour},
                              minute     => $req->{min},
                              time_zone  => $req->{tz} );

    my $utime       = $dt->epoch;
    my $rlogtime    = $LJ::EndOfTime - $now;
    my $rposttime   = $LJ::EndOfTime - $utime;
    my $sticky_type = $req->{sticky} ? 1 : 0;

    my $taglist = __extract_tag_list(\$req->{props}->{taglist});

    $journal->do( "INSERT INTO delayedlog2 (journalid, delayedid, posterid, subject, " .
                  "logtime, posttime, security, allowmask, year, month, day, rlogtime, revptime, is_sticky) " .
                  "VALUES (?, ?, ?, ?, NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  undef,
                  $journalid,
                  $delayedid,
                  $posterid,
                  LJ::text_trim($req->{'subject'}, 30, 0),
                  $posttime,
                  $security,
                  $allowmask,
                  $req->{year}, $req->{mon}, $req->{day},
                  $rlogtime,
                  $rposttime,
                  $sticky_type );

    $journal->do( "INSERT INTO delayedblob2 ".
                  "VALUES (?, ?, ?)",
                  undef,
                  $journalid,
                  $delayedid,
                  $data_ser );


    my $memcache_key = "delayed_entry:$journalid:$delayedid";
    LJ::MemCache::set($memcache_key, $data_ser, 3600);

    $self->{journal}    = $opts->{journal};
    $self->{posttime}   = LJ::TimeUtil::mysql_time($now);
    $self->{poster}     = $opts->{poster};
    $self->{data}       = $req;
    $self->{taglist}    = $taglist;
    $self->{delayed_id} = $delayedid;

    $self->{default_dateformat} = $opts->{'dateformat'} || 'S2';
    $self->__set_mark($req);
    __statistics_absorber($journal, $poster);

    return $self;
}

sub update {
    my ($self, $req) = @_;
    __assert( $self->{delayed_id}, "no delayed id" );
    __assert( $self->{journal}, "no journal" );
    __assert( $self->{poster}, "no poster" );

    $req->{tz} = $req->{tz} || $self->data->{tz};
    $req->{ext}->{flags}->{u} = undef; # it's no need to be stored

    $req->{props}->{'set_to_schedule'} = $self->prop('set_to_schedule');
    $req->{props}->{'revtime_sch'} = time;

    my $journalid = $self->journal->userid;
    my $posterid  = $self->poster->userid;
    my $subject   = $req->{subject};
    my $posttime  = __get_datetime($req);
    my $delayedid = $self->{delayed_id};
    my $dbh       = LJ::get_db_writer();
    my $data_ser  = __serialize($req);

    my $security  = "public";
    my $uselogsec = 0;

    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }

    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    my $now = time();
    my $dt = DateTime->new( year       => $req->{year},
                            month      => $req->{mon},
                            day        => $req->{day},
                            hour       => $req->{hour},
                            minute     => $req->{min},
                            time_zone  => $req->{tz} );

    my $utime       = $dt->epoch;

    my $allowmask   = $req->{'allowmask'}+0;
    my $rlogtime    = $LJ::EndOfTime - $now;
    my $rposttime   = $LJ::EndOfTime - $utime;
    my $sticky_type = $req->{sticky} ? 1 : 0;

    $self->{'taglist'} = __extract_tag_list(\$req->{props}->{taglist});
    $req->{'event'}    =~ s/\r\n/\n/g; # compact new-line endings to more comfort chars count near 65535 limit

    $self->journal->do( "UPDATE delayedlog2 SET posterid=?, " .
                        "subject=?, posttime = ?, " .
                        "security=?, allowmask=?, " .
                        "year=?, month=?, day=?, " .
                        "rlogtime=?, revptime=?, is_sticky=? " .
                        "WHERE journalid=? AND delayedid=?",
                        undef,
                        $posterid, LJ::text_trim($req->{'subject'}, 30, 0),
                        $posttime, $security, $allowmask,
                        $req->{year}, $req->{mon}, $req->{day},
                        $rlogtime, $rposttime, $sticky_type, $journalid, $delayedid );

    $self->journal->do( "UPDATE delayedblob2 SET request_stor=?" .
                        "WHERE journalid=? AND delayedid=?", undef,
                        $data_ser, $journalid, $delayedid );
    $self->{data} = $req;

    $self->__set_mark($req);
    my $memcache_key = "delayed_entry:$journalid:$delayedid";
    LJ::MemCache::set($memcache_key, $data_ser, 3600);
}

sub convert {
    my ($self) = @_;
    my $req = $self->{data};

    my $flags = { 'noauth' => 1,
                  'use_custom_time' => 0,
                  'u' => $self->poster };

    my $err = 0;
    my $res = LJ::Protocol::do_request("postevent", $req, \$err, $flags);
    my $fail = !defined $res->{itemid} && $res->{message};


    if ( $err || !$fail ) {
        my $url = $res->{'url'} || '';
        $self->journal->do( "UPDATE delayedlog2 SET ".
                            "finaltime=NOW(), url=? " .
                            "WHERE delayedid = ? AND " .
                                  "journalid = ?", 
                            undef,
                            $url,
                            $self->delayedid,
                            $self->journalid ); 
    }

    return { 'delete_entry'  => (!$fail || $err < 500),
             'error_message' => $res->{message},
             'res' => $res };
}

sub convert_from_data {
    my ($self, $req) = @_;
    my $flags = { 'noauth' => 1,
                  'use_custom_time' => 0,
                  'u' => $self->poster };

    my $err = 0;
    my $res = LJ::Protocol::do_request("postevent", $req, \$err, $flags);
    my $fail = !defined $res->{itemid} && $res->{message};
    if ($fail) {
        $self->update($req);
    }

    
    if ( $err || !$fail ) {
        my $url = $res->{'url'} || '';
        $self->journal->do( "UPDATE delayedlog2 SET ".
                            "finaltime=NOW(), url=? " .
                            "WHERE delayedid = ? AND " .
                                  "journalid = ?",
                            undef,
                            $url,
                            $self->delayedid,
                            $self->journalid );
    }

    return { 'delete_entry' => (!$fail || $err < 500),
             'res' => $res };
}

sub delete {
    my ($self) = @_;

    __assert( $self->{delayed_id}, "no delayed id" );
    __assert( $self->{journal}, "no journal" );

    my $journal = $self->{journal};
    my $journalid = $journal->userid;
    my $delayed_id = $self->{delayed_id};

    $journal->do( "DELETE FROM delayedlog2 " .
                  "WHERE delayedid = $delayed_id AND " .
                  "journalid = " . $journalid);

    $journal->do( "DELETE FROM delayedblob2 " .
                  "WHERE delayedid = $delayed_id AND " .
                  "journalid = " . $journalid);

    $self->{delayed_id} = undef;
    $self->{journal}    = undef;
    $self->{poster}     = undef;
    $self->{data}       = undef;

    my $memcache_key    = "delayed_entry:$journalid:$delayed_id";
    LJ::MemCache::delete($memcache_key);
}

sub original_post {
    return;
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
    return $self->data->{subject};
}

sub event {
    my ($self) = @_;
    return $self->data->{event};
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
    my $remote = LJ::get_remote();
    if (!$remote) {
        return 0;
    }

    return $remote->prop("timezone");
}

sub post_timezone {
    my ($self) = @_;
    return $self->data->{'tz'};
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
    my $req = $self->data;
    my $dt = DateTime->new( year       => $req->{year},
                            month      => $req->{mon},
                            day        => $req->{day},
                            hour       => $req->{hour},
                            minute     => $req->{min},
                            time_zone  => $req->{tz} );
    return $dt->epoch;
}

sub posttime {
    my ($self, $use_original_timezone) = @_;
    my $posttime = $self->system_posttime;
    my $timezone = $self->timezone;

    if ($use_original_timezone) {
        $timezone = $self->post_timezone;
    }
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

sub eventtime_mysql {
    my ($self) = @_;
    return $self->posttime;
}

sub logtime_mysql {
    my ($self) = @_;
    return $self->system_posttime;
}

sub alldatepart {
    my ($self, $style, $use_original_timezone) = @_;

    my $mysql_time = $self->posttime($use_original_timezone);
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
    return $self->data->{security} || '';
}

sub props {
    my ($self) = @_;
    return $self->data->{props};
}

sub visible_to {
    my ($self, $remote, $opts) = @_;

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

sub should_show_suspend_msg_to {
    my ( $self, $u ) = @_;
    return $self->is_suspended && !$self->is_suspended_for($u) ? 1 : 0;
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

sub update_tags {
    my ($self, $tags) = @_;
    $self->props->{taglist} = $tags;
    $self->{taglist} = __extract_tag_list(\$self->prop("taglist"));
    $self->update($self->data);
    return 1;
}

sub get_log2_row {
    my ($self, $opts) = @_;

    my $db = LJ::get_cluster_master($self->journal);
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
    __assert($opts->{journalid},  "no journal id");
    __assert($opts->{delayed_id}, "no delayed id");
    __assert($opts->{posterid},   "no poster id");

    my $journalid = $opts->{journalid};
    my $delayedid = $opts->{delayed_id};

    my ($data_ser)= $dbcr->selectrow_array( "SELECT request_stor " .
                                            "FROM delayedblob2 " .
                                            "WHERE journalid=$journalid AND " .
                                            "delayedid = $delayedid" );

    my $self = bless {}, $class;
    $self->{delayed_id} = $delayedid;
    $self->{journal}    = LJ::want_user($opts->{journalid});
    $self->{poster}     = LJ::want_user($opts->{posterid});
    $self->{data}       = __deserialize($data_ser);
    $self->{posttime}   = __get_datetime($self->{data});

    return $self;
}

sub get_entry_by_id {
    my ($class, $journal, $delayedid, $options) = @_;
    __assert($journal, "no journal");
    return undef unless $delayedid;

    my $journalid = $journal->userid;
    my $userid    = $options->{userid} || 0;
    my $user      = LJ::get_remote() || LJ::want_user($userid);
    if ($LJ::IS_DEV_SERVER) {
        __assert($user, "no user");
    }
    return undef unless $user;

    # can view entry (with content)
    my $viewall  = $options->{'viewall'} || 0;

    # can view entry (with content)
    my $viewsome  = $options->{'viewsome'} || 0;

    # delayed entries visibility
    my $can_see  = __delayed_entry_can_see( $journal, $user );

    my $sql_poster = '';

    if ( !($can_see || $viewsome || $viewall) ) {
        $sql_poster .= 'AND posterid = ' . $user->userid . " ";
    }

    unless ($options->{'show_posted'}) {
        $sql_poster .= " AND finaltime IS NULL ";
    }

    my $dbcr = LJ::get_cluster_master($journal)
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
        LJ::MemCache::set($memcache_key, $data_ser, 3600);
    }

    my $self = bless {}, $class;
    $self->{data}               = __deserialize($data_ser);
    $self->{journal}            = $journal;
    $self->{poster}             = LJ::want_user($opts->[2]);
    $self->{delayed_id}         = $delayedid;
    $self->{posttime}           = __get_datetime($self->{data});
    $self->{logtime}            = $opts->[4];
    $self->{taglist}            = __extract_tag_list( \$self->prop("taglist") );
    $self->{default_dateformat} = $options->{'dateformat'} || 'S2';

    # is entry visible to user
    my $visible = $self->visible_to($user, $options);

    # Does conent need to be hidden?
    my $hide_content = !($can_see || $viewall) && !$visible;

    if ($hide_content) {
        $self->data->{'subject'} = "*private content: subject*";
        $self->data->{'event'}   = "*private content: event*";
    }

    __assert( $self->{poster},  "no poster" );
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
    my $dbcr = LJ::get_cluster_master($journal)
        or die "get cluster for journal failed";

    my ($delayeds) =  $dbcr->selectcol_arrayref("SELECT delayedid " .
                                                "FROM delayedlog2 WHERE journalid=$journalid AND posterid = $userid ".
                                                "AND finaltime IS NULL " .
                                                "LIMIT 1");
    return @$delayeds;
}

sub get_usersids_with_delated_entry {
    my ($journalu) = @_;

    __assert($journalu);

    my $journalid = $journalu->userid;
    my $dbcr = LJ::get_cluster_master($journalu)
        or die "get cluster for journal failed";

    return $dbcr->selectcol_arrayref(  "SELECT posterid " .
                                       "FROM delayedlog2 ".
                                       "WHERE journalid = $journalid AND finaltime IS NULL GROUP BY posterid" );
}

sub get_entries_count {
    my ( $class, $journal, $skip, $elements_to_show, $userid ) = @_;
    __assert($journal, "no journal");
    my $journalid = $journal->userid;
    my $dbcr = LJ::get_cluster_master($journal)
        or die "get cluster for journal failed";

    unless ($userid) {
        my $remote = LJ::get_remote();
        return undef unless $remote;
        $userid = $remote->userid;

        return undef unless __delayed_entry_can_see( $journal,
                                                     $remote );
    } else {
        my $u = LJ::want_user($userid);
        return undef unless __delayed_entry_can_see( $journal,
                                                      $u );
    }

    return $dbcr->selectrow_array(  "SELECT count(delayedid) " .
                                    "FROM delayedlog2 ".
                                    "WHERE journalid=$journalid AND finaltime IS NULL" );
}

sub get_entries_by_journal {
    my ( $class, $journal, $opts ) = @_;
    return [] unless $journal;

    my $skip          = $opts->{'skip'} || 0;
    my $show          = $opts->{'show'} || 0;
    my $userid        = $opts->{'userid'};
    my $only_my       = $opts->{'only_my'};
    my $sticky_on_top = $opts->{'sticky_on_top'};

    # can view entry (with content)
    my $viewall  = $opts->{'viewall'} || 0;

    # can view entry (with content)
    my $viewsome = $opts->{'viewsome'} || 0;

    my $dbcr = LJ::get_cluster_master($journal);
    if (!$dbcr) {
        return [];
    }

    my $u;

    unless ($userid) {
        $u = LJ::get_remote();
    } else {
        $u = LJ::want_user($userid);
    }

    return [] unless $u;
    $userid = $u->userid;

    my $sql_poster = '';
    if ( !__delayed_entry_can_see( $journal, $u ) || $only_my ) {
        if ( !($viewall || $viewsome) || $only_my) {
            $sql_poster = 'AND posterid = ' . $u->userid . " ";
        }
    }

    my $sql_limit = '';
    if ($skip || $show) {
        $sql_limit = "LIMIT $skip, $show";
    }

    my $sticky_sql = $sticky_on_top ? 'is_sticky ASC, ' : '';
    my $journalid = $journal->userid;

    return $dbcr->selectcol_arrayref("SELECT delayedid " .
                                     "FROM delayedlog2 WHERE journalid=$journalid $sql_poster ".
                                     "AND finaltime IS NULL " .
                                     "ORDER BY $sticky_sql revptime DESC $sql_limit");
}

sub get_first_entry {
    my ( $journal, $userid ) = @_;
    __assert($journal, "no journal");

    my $dbcr = LJ::get_cluster_master($journal)
        or die "get cluster for journal failed";

    my $u;
    my $sql_poster = '';

    unless ($userid) {
        $u = LJ::get_remote();
    } else {
        $u = LJ::want_user($userid);
    }

    return 0 unless $u;
    if (!__delayed_entry_can_see( $journal, $u ) ){
        $sql_poster = 'AND posterid = ' . $u->userid . " ";
    }

    my ($id) = $dbcr->selectrow_array("SELECT delayedid " .
                                      "FROM delayedlog2 WHERE journalid=?  $sql_poster".
                                      "AND finaltime IS NULL " .
                                      "ORDER BY is_sticky ASC, revptime DESC LIMIT 1", undef, $journal->userid);
    return $id || 0;
}

sub get_last_entry {
    my ( $journal, $userid ) = @_;
    __assert($journal, "no journal");

    my $dbcr = LJ::get_cluster_master($journal)
        or die "get cluster for journal failed";

    my $u;
    my $sql_poster = '';
    unless ($userid) {
        $u = LJ::get_remote();
    } else {
        $u = LJ::want_user($userid);
    }

    return 0 unless $u;
    if (!__delayed_entry_can_see( $journal, $u ) ){
        $sql_poster = 'AND posterid = ' . $u->userid . " ";
    }

    my ($id) = $dbcr->selectrow_array("SELECT delayedid " .
                                      "FROM delayedlog2 WHERE journalid=?  $sql_poster".
                                      "AND finaltime IS NULL " .
                                      "ORDER BY is_sticky DESC, revptime ASC LIMIT 1", undef, $journal->userid);
    return $id || 0;
}

sub get_itemid_after2  {
    return get_itemid_near2(@_, "after");
}

sub get_itemid_before2 {
    return get_itemid_near2(@_, "before");
}

sub get_itemid_near2 {
    my ($u, $delayedid, $after_before) = @_;

    my $jid    = $u->userid;
    my $remote = LJ::get_remote();
    return 0 unless $remote;

    my ($order, $order_sticky, $cmp1, $cmp2, $cmp3, $cmp4);
    if ($after_before eq "after") {
        ($order, $order_sticky, $cmp1, $cmp2, $cmp3, $cmp4) = ("DESC", "ASC", "<=", ">", sub {$a->[0] <=> $b->[0]}, sub {$b->[1] <=> $a->[1]} );
    } elsif ($after_before eq "before") {
        ($order, $order_sticky, $cmp1, $cmp2, $cmp3, $cmp4) = ("ASC", "DESC",">=", "<", sub {$b->[0] <=> $a->[0]}, sub {$a->[1] <=> $b->[1]} );
    } else {
        return 0;
    }

    my $dbr = LJ::get_cluster_reader($u);
    unless ($dbr) {
        warn "Can't connect to cluster reader. Cluster: " . $u->clusterid;
        return 0;
    }

    my ($stime, $is_current_sticky) = $dbr->selectrow_array( "SELECT revptime, is_sticky FROM delayedlog2 WHERE ".
                                        "journalid=$jid AND delayedid=$delayedid");
    return 0 unless $stime;

    my $sql_poster = '';
    if (!__delayed_entry_can_see( $u, $remote ) ){
        $sql_poster = 'AND posterid = ' . $remote->userid . " ";
    }

    my $sql_item_rule = '';
    if ($after_before eq "after") {
        $sql_item_rule =  $is_current_sticky ? "(revptime $cmp1 ? AND is_sticky = 1 )" :
                                               "(revptime $cmp1 ? OR is_sticky = 1 )";
    } else {
        if ($is_current_sticky) {
            my ($new_stime) = $dbr->selectrow_array("SELECT revptime " .
                                                    "FROM delayedlog2 WHERE journalid=? $sql_poster AND is_sticky = 0 ".
                                                    "AND finaltime IS NULL " .
                                                    "ORDER BY revptime LIMIT 1", undef, $jid);
            if ($new_stime < $stime) {
                $stime = $new_stime;
            }

            $sql_item_rule = "(revptime $cmp1 ? )";
        } else {
            $sql_item_rule = "(revptime $cmp1 ? AND is_sticky = 0 )";
        }
    }

    my $result_ref = $dbr->selectcol_arrayref(  "SELECT delayedid FROM delayedlog2 use index (rlogtime,revptime) ".
                                                "WHERE journalid=? AND $sql_item_rule AND delayedid <> ? ".
                                                $sql_poster. " ".
                                                "AND finaltime IS NULL " .
                                                "ORDER BY is_sticky $order_sticky, revptime $order LIMIT 2",
                                                undef, $jid, $stime, $delayedid);
    return 0 unless $result_ref;
    return $result_ref->[0];
}

sub can_delete_delayed_item {
    my ($class, $u, $usejournal_u) = @_;
    return LJ::can_delete_journal_item($u, $usejournal_u);
}

sub can_post_to {
    my ($uowner, $poster, $req) = @_;

    my $uownerid = $uowner->userid;
    my $posterid = $poster->userid;

    my $can_manage = $poster->can_manage($uowner) || 0;
    my $moderated = $uowner->prop('moderated') || '';
    my $need_moderated = ( $moderated =~ /^[1A]$/ ) ? 1 : 0;
    if ( $req && $uowner->{'moderated'} && $uowner->{'moderated'} eq 'F' ) {
        ## Scan post for spam
        LJ::run_hook('spam_community_detector', $uowner, $req, \$need_moderated);
    }

    if ( LJ::is_banned($posterid, $uownerid) ) {
        return 0;
    }

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

sub dupsig_check {
    my ($class, $journal, $posterid, $req) = @_;

    my $signature = __get_mark($journal->userid, $posterid);
    return unless $signature;

    my @parts = split(/:/, $signature);
    my $current_signature = __signature($req);

    if ($current_signature eq $parts[0]) {
        my $delayedid = $parts[1];
        return LJ::DelayedEntry->get_entry_by_id( $journal, 
                                                  $delayedid );
    }
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
    my $url = $u->journal_base . "/d" . $delayedid . ".html";
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

sub __statistics_absorber {
    my ($journal, $poster) = @_;

    my $journalid  = $journal->userid;
    my $posterid   = $poster->userid;
    my $state_date = POSIX::strftime("%Y-%m-%d", gmtime);

    # all posts
    my $key = "stat:delayed_all:$state_date";

    LJ::MemCache::incr($key, 1) ||
            (LJ::MemCache::add($key, 0),  LJ::MemCache::incr($key, 1));

    # common journal/community entries count
    my $stat_key;

    # current user mark
    my $poster_key;

    # unique users
    my $poster_unique_key;

    # user posted to communityi
    my $posted_community_key = "stat:delayed_entry_posted_community:$posterid:$state_date";

    # user posted to journal
    my $posted_journal_key   = "stat:delayed_entry_posted_journal:$posterid:$state_date";

    if (!(LJ::MemCache::get($posted_community_key) || LJ::MemCache::get($posted_journal_key))) {
        my $unique_users = "stat:delayed_all_unique:$state_date";
        LJ::MemCache::incr($unique_users, 1) ||
            (LJ::MemCache::add($unique_users, 0),  LJ::MemCache::incr($unique_users, 1));
    }

    if (!$journal->is_community) {
        $poster_key         = $posted_journal_key;
        $poster_unique_key  = "stat:delayed_entry_posted_journal:$state_date";
        $stat_key           = "stat:delayed_entry_journal:$state_date";
    } else {
        $poster_key         = $posted_community_key;
        $poster_unique_key  = "stat:delayed_entry_posted_community:$state_date";
        $stat_key           = "stat:delayed_entry_community:$state_date";

        my $stat_comm_key        = "stat:delayed_entry_community_id:$journalid:$state_date";
        my $stat_comm_unique_key = "stat:delayed_entnry_community_unic:$state_date";

        my $current_counter_state = LJ::MemCache::get($stat_comm_key);
        if (!$current_counter_state) {
            LJ::MemCache::incr($stat_comm_unique_key, 1) ||
                (LJ::MemCache::add($stat_comm_unique_key, 0),  LJ::MemCache::incr($stat_comm_unique_key, 1));
        }

        LJ::MemCache::incr($stat_comm_key, 1) ||
            (LJ::MemCache::add($stat_comm_key, 0),  LJ::MemCache::incr($stat_comm_key, 1));
    }

    my $current_counter_state = LJ::MemCache::get($poster_key);
    if (!$current_counter_state) {
        LJ::MemCache::incr($poster_unique_key, 1) ||
            (LJ::MemCache::add($poster_unique_key, 0),  LJ::MemCache::incr($poster_unique_key, 1));
    }

    LJ::MemCache::incr($poster_key, 1) ||
        (LJ::MemCache::add($poster_key, 0),  LJ::MemCache::incr($poster_key, 1));

    LJ::MemCache::incr($stat_key, 1) ||
        (LJ::MemCache::add($stat_key, 0),  LJ::MemCache::incr($stat_key, 1));
}


sub __get_mark {
    my ($journalid, $posterid, $req) = @_;

    my $memcache_key = "delayed_entry_dup:$journalid:$posterid";
    my ($postsig) = LJ::MemCache::get($memcache_key);

    return $postsig;
}

sub __set_mark {
    my ($self, $req) = @_; 
    my $signature = __signature($req) . ":" . $self->delayedid;

    my $journalid = $self->journalid;
    my $posterid  = $self->posterid;

    my $memcache_key = "delayed_entry_dup:$journalid:$posterid";
    LJ::MemCache::set($memcache_key, $signature, 35);
}

sub __signature {
    my ($req) = @_;
    my $dupsig = Digest::MD5::md5_hex(join('', map { $req->{$_} }
                                           qw(subject event usejournal security allowmask)));
    return $dupsig;
}

sub __serialize {
    my ($req) = @_;
    __assert($req, "no request");
    $req->{'event'} =~ s/\r\n/\n/g; # compact new-line endings to more comfort chars count near 65535 limit

   my $ext   = $req->{'ext'};
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

sub __get_now {
    my $dt = DateTime->now->set_time_zone('UTC');

    # make the proper date format
    return sprintf("%04d-%02d-%02d %02d:%02d",  $dt->year,
                                                $dt->month,
                                                $dt->day,
                                                $dt->hour,
                                                $dt->minute );
}

sub is_future_date {
    my ($req) = @_;
    my $now = __get_now();
    my $request_time = __get_datetime($req);

    return $request_time ge $now;
}

sub __assert {
    my ($statement, $error) = @_;
    $error ||= '';
    unless ($statement) {
        die "assertion failed! $error";
    }
}

1;
