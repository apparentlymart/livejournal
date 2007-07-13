package LJ::Widget::ContentFlagSummary;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::ContentFlag;

sub need_res {
    return qw(
              js/ippu.js
              js/lj_ippu.js
              js/httpreq.js
              stc/contentflag.css
              js/ljwidget_ippu.js
              js/widget_ippu/contentflagreporters.js
              );
}

sub ajax { 1 }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote();

    return "This feature is disabled" if LJ::conf_test($LJ::DISABLED{content_flag});
    return "You are not authorized to use this" unless $remote && $remote->can_admin_content_flagging;

    $ret .= $class->start_form;
    $ret .= "<div>";

    my @actions = (
                   '', 'Choose...',
                   LJ::ContentFlag::CLOSED => 'No Action (close)',
                   '', '',
                   LJ::ContentFlag::ABUSE           => 'Abuse',
                   LJ::ContentFlag::ABUSE_WARN      => 'Abuse > Warning',
                   LJ::ContentFlag::ABUSE_DELETE    => 'Abuse > Delete',
                   LJ::ContentFlag::ABUSE_SUSPEND   => 'Abuse > Suspend',
                   LJ::ContentFlag::ABUSE_TERMINATE => 'Abuse > Terminate',
                   '', '',
                   LJ::ContentFlag::REPORTER_BANNED => 'Ban Submitter',
                   LJ::ContentFlag::PERM_OK         => 'Permanently OK',
                  );

    # format fields for display
    my %fields = (
                  instime => sub {
                      LJ::ago_text(time() - shift());
                    },
                  modtime => sub {
                      my $time = shift;
                      return $time ? LJ::ago_text(time() - $time) : "Never";
                    },
                  journalid => sub {
                      LJ::ljuser(LJ::load_userid(shift()));
                    },
                  itemid => sub {
                      my ($id, $flag) = @_;
                      my $typeid = $flag->{typeid};

                      my ($ret, $popup, $url, $text);
                      $ret = '';

                      if ($typeid == LJ::ContentFlag::ENTRY) {
                          my $entry = $flag->item;
                          $url = $entry->url;
                          $text = "Entry [" . ($entry->subject_text || 'no subject') . "]"; 
                          $popup = $entry->visible_to($remote) ? $entry->event_text : "[Private entry]";
                      }

                      if ($typeid == LJ::ContentFlag::COMMENT) {
                          my $cmt = $flag->item;
                          $url = $cmt->url;
                          $text = "Comment [" . ($cmt->subject_text || 'no subject') . "]"; 
                          $popup = $cmt->visible_to($remote) ? $cmt->body_text : "[Private comment]";
                      }

                      my $e_popup = LJ::ehtml($popup);

                      return qq {
                          <div class="standout-border standout-background ctflag_item" style="cursor: pointer;"
                            lj_itemid="$id" lj_itemtext="$e_popup">
                                <a href="$url"><img src="$LJ::IMGPREFIX/link.png" /></a>
                                $text
                          </div>
                      };
                  },
                  reporterid => sub {
                      my ($reporter, $flag) = @_;

                      my $journalid = $flag->journalid;
                      my $typeid = $flag->typeid;
                      my $itemid = $flag->itemid;

                      return "<div class='standout-border standout-background ctflag_reporterlist' " . 
                          "lj_itemid='$itemid' lj_journalid='$journalid' lj_typeid='$typeid'>click</div>";
                    },
                  catid => sub {
                      my $cat = shift;
                      return 'Child Porn' if $cat eq LJ::ContentFlag::CHILD_PORN;
                      return 'Illegal Act.' if $cat eq LJ::ContentFlag::ILLEGAL_ACTIVITY;
                      return 'Illegal Cont.' if $cat eq LJ::ContentFlag::ILLEGAL_CONTENT;
                      return "??";
                    },
                  status => sub {
                      my $stat = shift;
                      my %cats = (
                                  LJ::ContentFlag::NEW             => 'New',
                                  LJ::ContentFlag::ABUSE           => 'Moved to abuse',
                                  LJ::ContentFlag::ABUSE_DELETE    => 'Moved to abuse (delete)',
                                  LJ::ContentFlag::ABUSE_SUSPEND   => 'Moved to abuse (suspend)',
                                  LJ::ContentFlag::ABUSE_WARN      => 'Moved to abuse (warn)',
                                  LJ::ContentFlag::ABUSE_TERMINATE => 'Moved to abuse (terminate)',
                                  LJ::ContentFlag::PERM_OK         => 'Permanently OK',
                                  );

                      return $cats{$stat} || "??";
                    },
                  action => sub {
                      my (undef, $flag) = @_;
                      my $flagid = $flag->flagid;
                      my $actions = $class->html_select(name => "action_$flagid", list => [@actions]);
                      return $actions;
                  },
                  priority => sub {
                      my (undef, $flag) = @_;
                      return "checkbox";
                  },
                  _count => sub {
                      my (undef, $flag) = @_;
                      return $flag->count;
                  },
                  );


    my %fieldnames = (
                      instime    => 'Reported',
                      journalid  => 'Reported user',
                      catid      => 'Abuse type',
                      reporterid => 'Reporters',
                      status     => 'Status',
                      modtime    => 'Touched time',
                      itemid     => 'Report type',
                      action     => 'Resolve',
                      _count     => 'Freq',
                      priority   => 'Queue',
                      );

    my $sort = $opts{sort} || 'count';
    $sort =~ s/\W//g;
    my @flags = LJ::ContentFlag->load(status => $opts{status}, group => 1, sort => $sort);

    my @fields = qw (catid _count itemid journalid reporterid);
    my @cols = (@fields, qw(action priority));
    my $fieldheaders = (join '', (map { "<th>$fieldnames{$_}</th>" } @cols));

    $ret .= qq {
        <table class="alternating-rows ctflag">
            <tr>
            $fieldheaders
            </tr>
    };

    my $i = 1;
    foreach my $flag (@flags) {
        my $n = $i++ % 2 + 1;
        $ret .= "<tr class='altrow$n'>";
        foreach my $field (@cols) {
            my $field_val = (grep { $_ eq $field } @fields) ? $flag->{$field} : '';
            $ret .= "<td>" . $fields{$field}->($field_val, $flag) . '</td>';
        }

        $ret .= '</tr>';
    }

    $ret .= '</table>';
    $ret .= '</div>';

    $ret .= $class->html_hidden('flagids', join(',', map { $_->flagid } @flags));
    $ret .= $class->html_hidden('mode', 'admin');
    $ret .= '<?standout ' . $class->html_submit('Submit Tickets') . ' standout?>';
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    die "This feature is disabled" if LJ::conf_test($LJ::DISABLED{content_flag});

    # get user
    my $remote = LJ::get_remote()
        or die "Sorry, you must be logged in to use this feature.";

    # check auth token
    #return $err->("Invalid auth token") unless LJ::Auth->check_ajax_auth_token($remote, '/__rpc_changerelation', %POST);

    my $getopt = sub {
        my $field = shift;
        my $val = $post->{$field} or die "Required field $field missing";
        return $val;
    };

    my $mode = $getopt->('mode');

    my $success = 0;
    my %ret = ();

    if ($mode eq 'flag') {
        my @fields = qw (itemid type cat journalid);
        my %opts;
        foreach my $field (@fields) {
            my $val = $getopt->($field);
        }

        $opts{reporter} = $remote;
        my $flag = LJ::ContentFlag->create(%opts);

        $success = $flag ? 1 : 0;
    } elsif ($mode eq 'admin') {
        #return $err->("You do not have content flagging admin privs") unless privz
        my $flagids = $getopt->('flagids');
        my @flagids = split(',', $flagids);

        foreach my $flagid (@flagids) {
            die "invalid flagid" unless $flagid+0;

            my $action = $post->{"action_$flagid"} or next;

            my ($flag) = LJ::ContentFlag->load_by_flagid($flagid)
                or die "Could not load flag $flagid";

            # get the other flags for this item
            my (@flags) = $flag->find_similar_flags;

            if ($action eq LJ::ContentFlag::ABUSE) {
                # move to abuse placeholder

            } elsif ($action eq LJ::ContentFlag::ABUSE_WARN) {
                # placeholder

            } elsif ($action eq LJ::ContentFlag::ABUSE_DELETE) {
                # placeholder

            } elsif ($action eq LJ::ContentFlag::ABUSE_SUSPEND) {
                # placeholder

            } elsif ($action eq LJ::ContentFlag::ABUSE_TERMINATE) {
                # placeholder

            } elsif ($action eq LJ::ContentFlag::PERM_OK) {
                # set prop on journal?

            } elsif ($action eq LJ::ContentFlag::REPORTER_BANNED) {
                # eh? which reporter?

            } elsif ($action eq LJ::ContentFlag::CLOSED) {
                $_->close foreach @flags;

            } else {
                die "Unknown action $action";
            }
        }
    } else {
        die "Unknown mode $mode";
    }
}

sub js {
    q[
    initWidget: function () {
         LiveJournal.addClickHandlerToElementsWithClassName(this.contentFlagItemClicked.bindEventListener(this), "ctflag_item");
         LiveJournal.addClickHandlerToElementsWithClassName(this.reporterListClicked.bindEventListener(this), "ctflag_reporterlist");
     },
    reporterListClicked: function (evt) {
        var target = evt.target;
        if (! target) return true;
        var item = target;

        var itemid = item.getAttribute("lj_itemid");
        var journalid = item.getAttribute("lj_journalid");
        var typeid = item.getAttribute("lj_typeid");

        if (! itemid || ! journalid || ! typeid) return true;

        var reporterList = new LJWidgetIPPU_ContentFlagReporters({
          title: "Reporters",
          nearElement: target,
        }, {
          journalid: journalid,
          typeid: typeid,
          itemid: itemid
        });
    },
    contentFlagItemClicked: function (evt) {
         var target = evt.target;
         if (! target) return true;

         if (target.tagName.toLowerCase() == "img") return true; // don't capture events on the link img '

         var item = target;
         var itemid = item.getAttribute("lj_itemid");
         if (! itemid) return true;

         LJ_IPPU.showNote("<div class='ctflag_popup'><p><b>Preview:</b></p><p>" + item.getAttribute("lj_itemtext") + "</p></div>", item)

         Event.stop(evt);
         return false;
     },
     onData: function (data) {

     },
     onError: function (err) {

     },
     onRefresh: function (data) {
         this.initWidget();
     }
    ];
}

1;
