#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub ReplyPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts);
    $p->{'_type'} = "ReplyPage";
    $p->{'view'} = "reply";

    my $get = $opts->{'getargs'};

    my ($entry, $s2entry) = EntryPage_entry($u, $remote, $opts);
    return if $opts->{'handler_return'};
    my $ditemid = $entry->{'itemid'}*256 + $entry->{'anum'};

    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    $p->{'entry'} = $s2entry;

    # setup the replying item
    my $replyto = $s2entry;
    my $parpost;
    if ($get->{'replyto'}) {
        my $re_talkid = int($get->{'replyto'} >> 8);
        my $re_anum = $get->{'replyto'} % 256;
        unless ($re_anum == $entry->{'anum'}) {
            $opts->{'handler_return'} = 404;
            return;
        }

        my $sql = "SELECT jtalkid, posterid, state, datepost FROM talk2 ".
            "WHERE journalid=$u->{'userid'} AND jtalkid=$re_talkid ".
            "AND nodetype='L' AND nodeid=$entry->{'jitemid'}";
        foreach my $pass (1, 2) {
            my $db = $pass == 1 ? LJ::get_cluster_reader($u) : LJ::get_cluster_master($u);
            $parpost = $db->selectrow_hashref($sql);
            last if $parpost;
        }
        unless ($parpost) {
            $opts->{'handler_return'} = 404;
            return;
        }

        my $tt = LJ::get_talktext2($u, $re_talkid);
        $parpost->{'subject'} = $tt->{$re_talkid}->[0];
        $parpost->{'body'} = $tt->{$re_talkid}->[1];
        $parpost->{'props'} =
            LJ::load_talk_props2($u, [ $re_talkid ])->{$re_talkid} || {};

        if($LJ::UNICODE && $parpost->{'props'}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$parpost->{'subject'}, \$parpost->{'body'}, {});
        }

        LJ::CleanHTML::clean_comment(\$parpost->{'body'}, 
                                     $parpost->{'props'}->{'opt_preformatted'});        
        
        my $datetime = DateTime_unix(LJ::mysqldate_to_time($parpost->{'datepost'}));

        my ($s2poster, $pu);
        my $comment_userpic;
        if ($parpost->{'posterid'}) {
            $pu = LJ::load_userid($parpost->{'posterid'});
            $s2poster = UserLite($pu);

            # FIXME: this is a little heavy:
            $comment_userpic = Image_userpic($pu, 0, $parpost->{'props'}->{'picture_keyword'});
        }
        
        my $dtalkid = $re_talkid * 256 + $entry->{'anum'};
        $replyto = {
            '_type' => 'EntryLite',
            'subject' => LJ::ehtml($parpost->{'subject'}),
            'text' => $parpost->{'body'},
            'userpic' => $comment_userpic,
            'poster' => $s2poster,
            'journal' => $s2entry->{'journal'},
            'metadata' => {},
            'permalink_url' => $u->{'_journalbase'} . "/$ditemid.html?view=$dtalkid#t$dtalkid",
            'depth' => 1,
            'time' => $datetime,
        };
    }

    $p->{'replyto'} = $replyto;

    $p->{'form'} = {
        '_type' => "ReplyForm",
        '_remote' => $remote,
        '_u' => $u,
        '_ditemid' => $ditemid,
        '_parpost' => $parpost,
    };

    return $p;
}

package S2::Builtin::LJ;

sub ReplyForm__print
{
    my ($ctx, $form) = @_;
    my $remote = $form->{'_remote'};
    my $u = $form->{'_u'};
    my $parpost = $form->{'_parpost'};
    my $parent = $parpost ? $parpost->{'jtalkid'} : 0;

    $S2::pout->(LJ::Talk::talkform($remote, $u, $parpost, $parent, $form->{'_ditemid'}, $form->{'prop_picture_keyword'}));
}

1;
