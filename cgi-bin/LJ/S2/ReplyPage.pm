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
        $p->{'head_content'} .= "<meta name=\"robots\" content=\"noindex,nofollow\" />\n";
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
        my $dbcs = LJ::get_cluster_set($u);
        my $sql = "SELECT t.posterid, t.state, t.datepost FROM talk2 ".
            "WHERE t.journalid=$u->{'userid'} AND t.jtalkid=$re_talkid ".
            "AND nodetype='L' AND nodeid=$re_talkid";
        $parpost = LJ::dbs_selectrow_hashref($dbcs, $sql);
        unless ($parpost) {
            $opts->{'handler_return'} = 404;
            return;
        }

        my $tt = LJ::get_talktext2($u, $replyto);
        $parpost->{'subject'} = $tt->{$replyto}->[0];
        $parpost->{'body'} = $tt->{$replyto}->[1];
        $parpost->{'props'} = {};

        LJ::load_talk_props2($dbcs, $u->{'userid'}, [ $re_talkid ], { $re_talkid => $parpost->{'props'} }); 
        if($LJ::UNICODE && $parpost->{'props'}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$parpost->{'subject'}, \$parpost->{'body'}, {});
        }

        $parpost->{'subject'} = LJ::ehtml($parpost->{'subject'});
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
            'subject' => $parpost->{'subject'},
            'text' => $parpost->{'body'},
            'userpic' => $comment_userpic,
            'poster' => $s2poster,
            'journal' => $s2entry->{'journal'},
            'metadata' => {},
            'permalink_url' => $u->{'_journalbase'} . "/$ditemid?view=dtalkid#t#dtalkid",
            'depth' => 1,
        };
    }

    $p->{'replyto'} = $replyto;

    $p->{'form'} = {
        '_type' => "ReplyForm",
        '_remote' => $remote,
        '_u' => $u,
        '_ditemid' => $ditemid,
    };

    return $p;
}

package S2::Builtin::LJ;

sub ReplyForm__print
{
    my ($ctx, $form) = @_;
    my $remote = $form->{'_remote'};
    my $u = $form->{'_u'};

    my $dbs = LJ::get_dbs();
    my $ret;
    $ret .= "<form method='post' action='$LJ::SITEROOT/talkpost_do.bml' id='postform'>\n";

    my $txt_from = "From:";
    my $txt_anon = "Anonymous";
    my $txt_msg = "Message:";
    my $txt_submit = "Post Comment";
    my $txt_preview = "Preview";
    my $txt_noanon = "- this user has disabled anonymous posting.";
    my $txt_spell = "Spell check entry before posting";
    my $txt_willscreen = "(will be screened)";
    my $txt_allowedhtml = "Allowed HTML:";
    my %ML;

    my $pics = LJ::Talk::get_subjecticons();

    # hidden values
    my $parent = 0;  # FIXME: need parentid (or 0 if top-level)
    my $par_subject = "";
    $ret .= "<input type='hidden' name='parenttalkid' value='$parent' />\n";
    $ret .= "<input type='hidden' name='itemid' value='$form->{'_ditemid'}' />\n";
    $ret .= "<input type='hidden' name='journal' value='$u->{'user'}' />\n";

    # from registered user or anonymous?
    $ret .= "<table>\n";
    if ($u->{'opt_whocanreply'} eq "all") {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>$txt_from</td>";
        $ret .= "<td align='middle'><input type='radio' name='usertype' value='anonymous' id='talkpostfromanon'></td>";
        $ret .= "<td align='left'><b><label for='talkpostfromanon'>$txt_anon</label></b>";
        if ($u->{'opt_whoscreened'} eq 'A' ||
            $u->{'opt_whoscreened'} eq 'R' ||
            $u->{'opt_whoscreened'} eq 'F') {
            $ret .= " " . "(will be screened)";
        }
        $ret .= "</td></tr>\n";
    } elsif ($u->{'opt_whocanreply'} eq "reg") {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>$txt_from</td><td align='middle'>(  )</td>";
        $ret .= "<td align='left' colspan='3'><font color='#c0c0c0'><b>$txt_anon</b></font>$ML{'.opt.noanonpost'}</td>";
        $ret .= "</tr>\n";
    } else {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>$txt_from</td>";
        $ret .= "<td align='middle'>(  )</td>";
        $ret .= "<td align='left' colspan='3'><font color='#c0c0c0'><b>$txt_anon</b></font>" .
            BML::ml(".opt.friendsonly", {'username'=>"<b>$u->{'user'}</b>"}) 
            . "</td>";
        $ret .= "</tr>\n";
    }

    my $checked = "checked='checked'";
    if ($remote) {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>&nbsp;</td>";
        if (LJ::is_banned($dbs, $remote, $u)) {
            $ret .= "<td align='middle'>( )</td>";
            $ret .= "<td align='left'><font color='#c0c0c0'>" . BML::ml(".opt.loggedin", {'username'=>"<i>$remote->{'user'}</i>"}) . "</font>" . BML::ml(".opt.bannedfrom", {'journal'=>$u->{'user'}}) . "</td>";
        } else {
            $ret .= "<td align='middle'><input type='radio' name='usertype' value='cookieuser' id='talkpostfromremote' $checked /></td>";
            $ret .= "<td align='left'><label for='talkpostfromremote'>" . BML::ml(".opt.loggedin", {'username'=>"<i>$remote->{'user'}</i>"}) . "</label>\n";
            $ret .= "<input type='hidden' name='cookieuser' value='$remote->{'user'}' id='cookieuser' />\n";
            if ($u->{'opt_whoscreened'} eq 'A' ||
                ($u->{'opt_whoscreened'} eq 'F' &&
                 !LJ::is_friend($dbs, $u, $remote))) {
                $ret .= " $txt_willscreen";
            }
            $ret .= "</td>";
            $checked = "";
        }
        $ret .= "</tr>\n";
    }

    # ( ) LiveJournal user:
    $ret .= "<tr valign='middle'>";
    $ret .= "<td>&nbsp;</td>";
    $ret .= "<td align=middle><input type='radio' name='usertype' value='user' id='talkpostfromlj' $checked />";
    $ret .= "</td><td align='left'><b><label for='talkpostfromlj'>$ML{'.opt.ljuser'}</label></b> ";
    $ret .= $ML{'.opt.willscreenfriend'} if $u->{'opt_whoscreened'} eq 'F';
    $ret .= $ML{'.opt.willscreen'} if $u->{'opt_whoscreened'} eq 'A';
    $ret .= "</tr>\n";

    # Username: [    ] Password: [    ]  Login? [ ]
    $ret .= "<tr valign='middle' align='left'><td colspan='2'></td><td>";
    $ret .= "$ML{'Username'}:&nbsp;<input class='textbox' name='userpost' size='13' maxlength='15' id='username' /> ";
    $ret .= "$ML{'Password'}:&nbsp;<input class='textbox' name='password' type='password' maxlength='30' size='13' id='password' /> <label for='logincheck'>$ML{'.loginq'}&nbsp;</label><input type='checkbox' name='do_login' id='logincheck' /></td></tr>\n";
    
    # subject
    $ret .= "<tr valign='top'><td align='right'>$ML{'.opt.subject'}</td><td colspan='4'><input class='textbox' type='text' size='50' maxlength='100' name='subject' value=\"" . LJ::ehtml($par_subject) . "\" /><br /><?de $ML{'.nosubjecthtml'} de?></td></tr>\n";

    unless ($u->{'opt_notalkicons'})
    {
        # spit out a pretty table of all the possible subjecticons
        $ret .= "<tr valign='middle'><td>&nbsp;</td><td align='left' colspan='4'>\n";
        $ret .= "<table border='0' cellspacing='3' cellpadding='0'>\n";
        
        foreach my $type (@{$pics->{'types'}}) {
            my $input = "";
            my $img = "";
            
            # go through and make radio button/icon image rows.
            foreach (@{$pics->{'lists'}->{$type}}) {
                $input .= "<td valign='middle' align='middle'><input type='radio' name='subjecticon' value='$_->{'id'}' id='talki_$_->{'id'}' /></td>\n";
                $img .= "<td valign='middle' align='middle'><label for='talki_$_->{'id'}'>" . LJ::Talk::show_image($pics, $_->{'id'}) . "</label></td>\n";
            }
            $ret .= "<tr>";
            
            # make an option if they don't want an image
            if ($type eq $pics->{'types'}->[0]) { 
                $ret .= "<td rowspan='5' valign='middle' align='middle'><input type='radio' name='subjecticon' value='none' checked='1' id='talki_none' /><br /><label for='talki_none'><i>$ML{'.opt.noimage'}</i></label></td><td rowspan='5'>&nbsp;</td>\n"; 
            }
            
            # then splice in the icon & radio button rows...
            $ret .= "$input</tr>\n";
            $ret .= "<tr>\n$img</tr>\n";
        }
        # end that table, foo!
        $ret .= "</table>\n";
        $ret .= "</td></tr>\n";
    }

    $ret .= "<tr><td align='right'>&nbsp;</td><td colspan='4'>";
    $ret .= "$ML{'.opt.noautoformat'}<input type='checkbox' value='1' name='prop_opt_preformatted' />";
    $ret .= LJ::help_icon("noautoformat", " ");
    
    my %res;
    if ($remote) {
        LJ::do_request($dbs, { "mode" => "login",
                               "ver" => ($LJ::UNICODE ? "1" : "0"),
                               "user" => $remote->{'user'},
                               "getpickws" => 1,
                           }, \%res, { "noauth" => 1, "userid" => $remote->{'userid'} });
      }
    if ($res{'pickw_count'}) {
        $ret .= BML::ml('.label.picturetouse',{'username'=>$remote->{'user'}});
        my @pics;
        for (my $i=1; $i<=$res{'pickw_count'}; $i++) {
            push @pics, $res{"pickw_$i"};
        }
        @pics = sort { lc($a) cmp lc($b) } @pics;
        $ret .= LJ::html_select({'name' => 'prop_picture_keyword', },
                                ("", $ML{'.opt.defpic'}, map { ($_, $_) } @pics));
        $ret .= LJ::help_icon("userpics", " ");
    }
    $ret .= "</td></tr>\n";

    # textarea for their message body
    $ret .= "<tr valign='top'><td align='right'>$txt_msg</td><td colspan='4'>";
    $ret .= "<textarea class='textbox' rows='10' cols='50' wrap='soft' name='body' id='commenttext' style='width: 99%'></textarea>";
    $ret .= "<br /><input type='submit' name='submitpost' value='$txt_submit' />\n";

    ## preview stuff
    $ret .= "<input type='submit' name='submitpreview' value='$txt_preview' />\n";
    if ($LJ::SPELLER) {
        $ret .= "<input type='checkbox' name='do_spellcheck' value='1' id='spellcheck' /> <label for='spellcheck'>$ML{'talk.spellcheck'}</label>";
    }

    if ($u->{'opt_logcommentips'} eq "A") {
        $ret .= "<br />$ML{'.logyourip'}";
        $ret .= LJ::help_icon("iplogging", " ");
    }
    if ($u->{'opt_logcommentips'} eq "S") {
        $ret .= "<br />$ML{'.loganonip'}";
        $ret .= LJ::help_icon("iplogging", " ");
    }


    $ret .= "<br />$ML{'.paraformat'}<br /> <span class='ljdeem'>$txt_allowedhtml ";
    foreach (sort &LJ::CleanHTML::get_okay_comment_tags()) {
        $ret .= "&lt;$_&gt; ";
    }
    $ret .= "</span>";


    $ret .= "</td></tr></table>\n";

    # Some JavaScript to help the UI out

    $ret .= "<script type='text/javascript' language='JavaScript'>\n";
    $ret .= "var usermismatchtext = \"" . LJ::ejs($ML{'.usermismatch'}) . "\";\n";
    $ret .= "</script><script type='text/javascript' language='JavaScript' src='/js/talkpost.js'></script>";
    $ret .= "</form>\n";    
    
    
    $S2::pout->($ret);
}

1;
