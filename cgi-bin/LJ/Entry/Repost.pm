package LJ::Entry::Repost;

use strict;
use warnings;

require 'ljlib.pl';
require 'ljprotocol.pl';
use LJ::Lang;

use constant {  REPOST_KEYS_EXPIRING => 0,
                REPOST_USERS_LIST_LIMIT => 25,
             };


sub __get_count {
    my ($u, $jitemid) = @_;

    my $journalid = $u->userid;
    my $memcache_key = "reposted_count:$journalid:$jitemid";
    my ($count) = LJ::MemCache::get($memcache_key);
    if ($count) {
        return $count;
    }

    my $dbcr = LJ::get_cluster_master($u)
        or die "get cluster for journal failed";

    my ($count_jitemid) = $dbcr->selectrow_array( 'SELECT COUNT(reposted_jitemid) ' .
                                                  'FROM repost2 ' .
                                                  'WHERE journalid = ? AND jitemid = ?',
                                                   undef,
                                                   $u->userid,
                                                   $jitemid, );

    LJ::MemCache::set($memcache_key, $count_jitemid, REPOST_KEYS_EXPIRING);

    return $count_jitemid;
}

sub __get_repostid {
    my ($u, $jitemid, $reposterid) = @_;
    return 0 unless $u;

    my $journalid = $u->userid;
    my $memcache_key = "reposted_itemid:$journalid:$jitemid:$reposterid";
    my ($itemid) = LJ::MemCache::get($memcache_key);
    if ($itemid) {
        return $itemid;
    }

    my $dbcr = LJ::get_cluster_master($u)
        or die "get cluster for journal failed";

    my @repost_jitemid = $dbcr->selectrow_array( 'SELECT reposted_jitemid ' .
                                                  'FROM repost2 ' .
                                                  'WHERE journalid = ? AND jitemid = ? AND reposterid = ?',
                                                  undef,
                                                  $u->userid,
                                                  $jitemid,
                                                  $reposterid, );

    if (@repost_jitemid) {
        LJ::MemCache::set($memcache_key, $repost_jitemid[0], REPOST_KEYS_EXPIRING);
        return $repost_jitemid[0];
    }

    return 0;;
}

sub __create_repost_record {
    my ($u, $itemid, $repost_journalid, $repost_itemid) = @_;

    my $journalid = $u->userid;
    my $time  = time();
    my $query = 'INSERT INTO repost2(journalid,
                                    jitemid,
                                    reposterid,
                                    reposted_jitemid';
    $query .= LJ::is_enabled('repost2_with_time') ? 
                            ',repost_time) VALUES(?,?,?,?,?)' :
                            ') VALUES(?,?,?,?)'; 
                                    
    $u->do( $query,
            undef,
            $u->userid,
            $itemid,
            $repost_journalid,
            $repost_itemid,
            $time );

    my $memcache_key_count = "reposted_count:$journalid:$itemid";
    my $memcache_key_status = "reposted_itemid:$journalid:$itemid:$repost_journalid";

    __clear_reposters_list($journalid, $itemid);

    if (!LJ::MemCache::incr($memcache_key_count, 1)) {
        my $count = __get_count($u, $itemid);
        LJ::MemCache::add($memcache_key_count, int($count));
    }

    LJ::MemCache::set($memcache_key_status, $repost_itemid, REPOST_KEYS_EXPIRING);
}

sub __delete_repost_record {
    my ($u, $itemid, $reposterid) = @_;

    my $journalid = $u->userid;
    my $memcache_key = "reposted_count:$journalid:$itemid";
    my $memcache_key_status = "reposted_itemid:$journalid:$itemid:$reposterid";
    LJ::MemCache::delete($memcache_key);
    LJ::MemCache::delete($memcache_key_status);

    __clear_reposters_list($journalid, $itemid);

    $u->do('DELETE FROM repost2 WHERE journalid = ? AND jitemid = ? AND reposterid = ?',
            undef,
            $u->userid,
            $itemid,
            $reposterid,);
}

sub __create_post {
    my ($u, $timezone, $url, $error) = @_;

    my $err = 0;
    my $flags = { 'noauth'             => 1,
                  'use_custom_time'    => 0,
                  'u'                  => $u,
                  'entryrepost'        => 1, };

    my $event_text_stub = LJ::Lang::ml('entry.reference.event_text', { 'url' =>  $url}) | 
                          "Entry reposted from $url";

    my %req = ( 'username'    => $u->user,
                'event'       => $event_text_stub,
                'subject'     => '',
                'tz'          => $timezone,
              );

    # move to LJ::API
    my $res = LJ::Protocol::do_request("postevent", \%req, \$err, $flags);

    $flags->{u} = undef;
    my $fail = !defined $res->{itemid} && $res->{message};
    if ($fail) {
         warn "repost_create: 1, request " . LJ::compact_dumper(%req);
              " flags: " . LJ::compact_dumper($flags) .
              " result: " . LJ::compact_dumper($res) .
              " error: $err" if $err;

         $$error = LJ::API::Error->make_error( $res->{message},($err || -10000) );
         return;
    }

    if ($err) {    
        warn "repost_create: 2, request " . LJ::compact_dumper(%req) .
            " flags: " . LJ::compact_dumper($flags) .
            " result: " . LJ::compact_dumper($res) .
            " error: $err";

        $$error = LJ::API::Error->get_error('create_entry_failed');
        return;
    }

    return LJ::Entry->new($u, jitemid => $res->{'itemid'} );
}

sub __create_repost {
    my ($opts) = @_;

    my $u         = $opts->{'u'};
    my $entry_obj = $opts->{'entry_obj'}; 
    my $timezone  = $opts->{'timezone'};
    my $error     = $opts->{'error'};

    if (!$entry_obj->visible_to($u)) {
        $$error = LJ::API::Error->make_error( LJ::Lang::ml('repost.access_denied'), -9002);
        return;
    }

    my $post_obj = __create_post($u, $timezone, $entry_obj->url, $error);
    if (!$post_obj) {
        return;
    }

    my $mark = $entry_obj->journalid . ":" . $entry_obj->jitemid;
    $post_obj->convert_to_repost($mark);
    $post_obj->set_prop( 'repost' => 'e' );

    # create record
    my $repost_jitemid = $post_obj->jitemid;
    
    my $journalid = $entry_obj->journalid;
    my $jitemid   = $entry_obj->jitemid;

    __create_repost_record($entry_obj->journal,
                           $jitemid,
                           $u->userid,
                           $repost_jitemid);

    return $post_obj;
}

sub get_status {
    my ($class, $entry_obj, $u) = @_;

    my $reposted = 0;
    if ($u) {
        $reposted = __get_repostid( $entry_obj->journal, 
                                    $entry_obj->jitemid, 
                                    $u->userid );
    }

    return  { 'count'    =>  __get_count($entry_obj->journal, $entry_obj->jitemid), 
              'reposted' => (!!$reposted) || 0,
            };
}

sub __reposters {
    my ($dbcr, $journalid, $jitemid) = @_;

    my $reposted = $dbcr->selectcol_arrayref( 'SELECT reposterid ' .
                                              'FROM repost2 ' .
                                              'WHERE journalid = ? AND jitemid = ? LIMIT 1000',
                                              undef,
                                              $journalid,
                                              $jitemid, );

    return undef unless scalar @$reposted;
    return $reposted;
}

sub __clear_reposters_list {
    my ($journalid, $jitemid) = @_;

    my $subkey = "$journalid:$jitemid";
    my $memcached_key_list = "reposters_keys_list:$subkey";

    my ($keys_list) = LJ::MemCache::get($memcached_key_list) ;
    if (defined $keys_list) {
        my @keys = split(/:/, $keys_list);
        foreach my $key (@keys) {
            my $memcache_key = "reposters_list_chunk:$subkey:$key";
            LJ::MemCache::delete($memcache_key);
        }
    }
    LJ::MemCache::delete($memcached_key_list);
}

sub __put_reposters_list {
    my ($journalid, $jitemid, $data, $lastrequest) = @_;

    my $subkey = "$journalid:$jitemid";
    my $memcache_key = "reposters_list_chunk:$subkey:$lastrequest";
    my $memcache_keys_list = "reposters_keys_list:$subkey";

    if ($lastrequest) {
        LJ::MemCache::append($memcache_keys_list,":$lastrequest");
    } else {
        LJ::MemCache::set($memcache_keys_list, "$lastrequest", REPOST_KEYS_EXPIRING);
    }
    
    my $serialized = LJ::JSON->to_json( $data );
    LJ::MemCache::set( $memcache_key, $serialized, REPOST_KEYS_EXPIRING );
}

sub __get_reposters_list {
    my ($journalid, $jitemid, $lastrequest) = @_;

    my $memcache_key = "reposters_list_chunk:$journalid:$jitemid:$lastrequest";

    my $data;
    my $reposters = LJ::MemCache::get($memcache_key);

    if ($reposters) {
        eval {
            $data = LJ::JSON->from_json($reposters);
        };
        if ($@) {
            warn $@;
        }
    }
    return $data;
}

sub __get_reposters {
    my ($u, $jitemid, $lastrequest) = @_;
    return [] unless $u;

    my $dbcr = LJ::get_cluster_master($u)
        or die "get cluster for journal failed";

    my $final_limit = REPOST_USERS_LIST_LIMIT + 1;
    my $query_reposters = 'SELECT reposterid ' .
                          'FROM repost2 ' .
                          'WHERE journalid = ? AND jitemid = ? ';

    $query_reposters .=  LJ::is_enabled('repost2_with_time') ? 'ORDER BY repost_time ' :  '';
    $query_reposters .= "LIMIT $lastrequest, $final_limit";

    my $reposters = $dbcr->selectcol_arrayref( $query_reposters,
                                               undef,
                                               $u->userid,
                                               $jitemid,);

    return $reposters;
}

sub is_repost {
    my ($class, $u, $itemid) = @_;
    my $jitemid = int($itemid / 256);
    
    my $props = {};
    LJ::load_log_props2($u, [ $jitemid ], $props);
    my $item_props = $props->{ $jitemid};

    return !!$item_props->{'repost_link'};
}

sub get_list {
    my ($class, $entry, $lastrequest) = @_;

    my $journalid = $entry->journalid;
    my $jitemid   = $entry->jitemid;

    if (!$lastrequest || $lastrequest < 0) {
        $lastrequest = 0;
    }

    my $cached_reposters = __get_reposters_list($journalid, 
                                                $jitemid, 
                                                $lastrequest);
    if ($cached_reposters) {
        return $cached_reposters;
    }

    my $repostersids = __get_reposters( $entry->journal,
                                        $jitemid,
                                        $lastrequest );

    my $reposters_info = { users => [] };
    my $users = $reposters_info->{'users'};

    my $reposters_count = scalar @$repostersids;
    $reposters_info->{'last'}   = $lastrequest + 1;
    if ($reposters_count < REPOST_USERS_LIST_LIMIT + 1) {
        $reposters_info->{'nomore'} = 1;
    } else {
        pop @$repostersids;
    }

    foreach my $reposter (@$repostersids) {
        my $u = LJ::want_user($reposter);
        push @$users, { user => $u->user,  'url' => $u->journal_base, };
    }  
 
    $reposters_info->{'last'}   = $lastrequest + 1;
    $reposters_info->{'count'}  = __get_count($entry->journal, 
                                              $entry->jitemid);

    __put_reposters_list( $journalid,
                          $jitemid,
                          $reposters_info, 
                          $lastrequest );

    
    return $reposters_info; 
}

sub delete_all_reposts_records {
    my ($class, $journalid, $jitemid) = @_;

    my $memcache_key = "reposted_count:$journalid:$jitemid";
    LJ::MemCache::delete($memcache_key);

    my $u = LJ::want_user($journalid);
    my $dbcr = LJ::get_cluster_master($u)
        or die "get cluster for journal failed";

    while (my $reposted = __reposters($dbcr, $journalid, $jitemid)) {
        foreach my $reposterid (@$reposted) {
            my $memcache_key_status = "reposted_itemid:$journalid:$jitemid:$reposterid";
            LJ::MemCache::delete($memcache_key_status);
        }

        my $reposters = join(',', @$reposted);

        $u->do("DELETE FROM repost2 WHERE journalid = ? AND jitemid = ? AND reposterid IN ($reposters)",
                undef,
                $u->userid,
                $jitemid,);
    }
}

sub delete {
    my ($class, $u, $entry_obj) = @_;
    my $repost_itemid = __get_repostid( $entry_obj->journal, $entry_obj->jitemid, $u->userid );

    if ($repost_itemid) {
        LJ::set_remote($u);
        my $result = LJ::API::Event->delete({ itemid => $repost_itemid, journalid => $u->userid} ); 
        if ($result->{'error'}) { 
            return $result;
        }
        __delete_repost_record($entry_obj->journal, $entry_obj->jitemid, $u->userid);
    
        return  { 'delete' => 'OK' };
    }

    return LJ::API::Error->get_error('entry_not_found');
}

sub render_delete_js {
    my ($class, $url) = @_;
    return
        qq{<script type="text/javascript">jQuery('a:last').click(function(ev) {
        ev.preventDefault(); LiveJournal.run_hook('repost.requestRemove', this, "$url"); });</script>};
}

sub create {
    my ($class, $u, $entry_obj, $timezone) = @_;
    my $result = {};
   
    if ($entry_obj->original_post) {
        $entry_obj = $entry_obj->original_post;
    }

    if ($u->equals($entry_obj->journal)) {
        return LJ::API::Error->get_error('same_user'); 
    }

    my $journalid = $entry_obj->journalid;
    my $jitemid   = $entry_obj->jitemid;

    my $repost_itemid = __get_repostid( $entry_obj->journal, $jitemid, $u->userid );

    my $error;
    if ($repost_itemid) {
        $error = LJ::API::Error->make_error( LJ::Lang::ml('entry.reference.repost.already_exist'), 
                                             -9000 );
    } else {
        my $reposted_obj = __create_repost( {'u'          => $u,
                                             'entry_obj'  => $entry_obj,
                                             'timezone'   => $timezone,
                                             'error'      => \$error } );
        if ($reposted_obj) {
            my $count = __get_count($entry_obj->journal, $entry_obj->jitemid);
            $result->{'result'} = { 'count' => $count };
        } 
    }

    if ($error && !$error->{'error'}) {
        $result = LJ::API::Error->make_error( LJ::Lang::ml('api.error.unknown_error'), -9000 );
    } elsif ($error) {
        $result = $error;
    }

    return $result;
}

sub substitute_content {
    my ($class, $entry_obj, $opts, $props) = @_;

    my $remote = LJ::get_remote();
    my $original_entry_obj = $entry_obj->original_post;

    unless ($original_entry_obj) {
        my $link = $entry_obj->prop('repost_link'); 
        if ($link) {
            my ($org_journalid, $org_jitemid) = split(/:/, $link);
            return 0 unless int($org_journalid);
            my $journal = int($org_journalid) ? LJ::want_user($org_journalid) : undef;
            
            my $fake_entry = LJ::Entry->new( $journal, jitemid => $org_jitemid);

            my $subject = LJ::Lang::ml( 'entry.reference.journal.delete.subject' );   
            my $event   = LJ::Lang::ml( 'entry.reference.journal.delete',
                                        'datetime'     => $entry_obj->eventtime_mysql, 
                                        'url'          => $fake_entry->url);

            if ($opts->{'original_post_obj'}) {
                ${$opts->{'original_post_obj'}}= $entry_obj;
            }

            if ($opts->{'removed'}) {
                ${$opts->{'removed'}} = 1;
            }
           
            if ($opts->{'repost_obj'}) {
                ${$opts->{'repost_obj'}} = $fake_entry;
            }
 
            if ($opts->{'subject_repost'}) {
                ${$opts->{'subject_repost'}} = $subject;
            }

            if ($opts->{'subject'}) {
                ${$opts->{'subject'}}  = $subject;
            }
 
            if ($opts->{'event_raw'}) {
                ${$opts->{'event_raw'}} = $event;
            }

            if ($opts->{'event'}) {
                ${$opts->{'event'}} = $event;
            }

            return 1;    
        }
        return 0;
    }

    if ($opts->{'removed'}) {
        ${$opts->{'removed'}} = 0;
    }

    if ($opts->{'anum'}) {
        ${$opts->{'anum'}} = $original_entry_obj->anum;
    }

    if ($opts->{'cluster_id'}) {
        ${$opts->{'cluster_id'}} = $original_entry_obj->journal->clusterid;
    }
    
    if ($opts->{'original_post_obj'}) {
        ${$opts->{'original_post_obj'}}= $original_entry_obj;
    }

    if ($opts->{'repost_obj'}) {
        ${$opts->{'repost_obj'}} = $entry_obj;
    }

    if ($opts->{'ditemid'}) {
        ${$opts->{'ditemid'}} = $original_entry_obj->ditemid;
    }

    if ($opts->{'itemid'}) {
        ${$opts->{'itemid'}} = $original_entry_obj->jitemid;
    }

    if ($opts->{'journalid'}) {
        ${$opts->{'journalid'}} = $original_entry_obj->journalid;
    }

    if ($opts->{'journalu'}) {
        ${$opts->{'journalu'}} = $original_entry_obj->journal;
    }

    if ($opts->{'posterid'}) {
        ${$opts->{'posterid'}} = $original_entry_obj->posterid;
    }

    if ($opts->{'allowmask'}) {
        ${$opts->{'allowmask'}} = $original_entry_obj->allowmask;
    }

    if ($opts->{'security'}) {
        ${$opts->{'security'}} = $original_entry_obj->security;
    }

    if ($opts->{'eventtime'}) {
        ${$opts->{'eventtime'}} = $entry_obj->eventtime_mysql;
    }

    if ($opts->{'event'}) {
        my $event_text = $original_entry_obj->event_raw;

        if ($props->{use_repost_signature}) { 
            my $text_var =  LJ::u_equals($remote, $entry_obj->poster) ? 'entry.reference.journal.owner' : 
                                                                        'entry.reference.journal.guest';
    
            my $event =  LJ::Lang::ml($text_var,  
                                        { 'author'       => LJ::ljuser2($original_entry_obj->poster),
                                          'reposter'     => LJ::ljuser2($entry_obj->poster),
                                          'datetime'     => $entry_obj->eventtime_mysql,
                                          'text'         => $event_text, });
            ${$opts->{'event'}} = $event;
        } else {
            ${$opts->{'event'}} = $event_text;
        }
    }

    if ($opts->{'event_friend'}) {
        my $event_text = $original_entry_obj->event_raw;

        if ($props->{use_repost_signature}) {
            my $journal = $original_entry_obj->journal;
            
            my $text_var = $journal->is_community ? 'entry.reference.friends.community' :
                                                    'entry.reference.friends.journal';

            $text_var .= LJ::u_equals($remote, $entry_obj->poster) ? '.owner' : '.guest';
    
            my $event = LJ::Lang::ml($text_var, 
                                       { 'author'           => LJ::ljuser2($original_entry_obj->poster),
                                         'communityname'    => LJ::ljuser2($original_entry_obj->journal),
                                         'reposter'         => LJ::ljuser2($entry_obj->poster),
                                         'datetime'         => $entry_obj->eventtime_mysql,
                                         'text'             => $event_text, });

            ${$opts->{'event_friend'}} = $event;
        } else {
            ${$opts->{'event_friend'}} = $event_text;
        }
    }

    if ($opts->{'subject_repost'}) {
        my $subject_text = $original_entry_obj->subject_html;
        ${$opts->{'subject_repost'}} = $subject_text;
    }

    if ($opts->{'subject'}) {
        ${$opts->{'subject'}}  = $original_entry_obj->subject_html;
    }

    if ($opts->{'reply_count'}) {    
        ${$opts->{'reply_count'}} = $original_entry_obj->reply_count;
    } 
    
    return 1;
}

1;
