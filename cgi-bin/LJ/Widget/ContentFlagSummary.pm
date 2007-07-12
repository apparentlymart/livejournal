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
              );
}

sub ajax { 1 }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote();

    return "This feature is disabled" if LJ::conf_test($LJ::DISABLED{content_flag});

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
                      LJ::ljuser(LJ::load_userid(shift()));
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
                      return 'New' if $stat eq LJ::ContentFlag::NEW;
                      return "??";
                    },
                  action => sub {
                      my (undef, $flag) = @_;
                      my $flagid = $flag->flagid;
                      my $actions = $class->html_select(name => "action_" . $flag->flagid, list => [@actions]);
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
                      instime => 'Reported',
                      journalid => 'User',
                      catid => 'Abuse type',
                      reporterid => 'Last submitted by',
                      status => 'Status',
                      modtime => 'Touched time',
                      itemid => 'Report type',
                      action => 'Resolve',
                      _count => 'Freq',
                      priority => 'Queue',
                      );

    my $sort = $opts{sort} || 'count';
    $sort =~ s/\W//g;
    my @flags = LJ::ContentFlag->load(status => $opts{status}, group => 1, sort => $sort);

    my @fields = qw (catid _count itemid journalid reporterid);
    my @cols = (@fields, qw(action priority));
    my $fieldheaders = (join '', (map { "<th>$fieldnames{$_}</th>" } @cols));

    $ret .= qq {
        <table class="alternating-rows">
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

    return $ret;
}

sub handle_post {
    my ($class, $opts) = @_;

    my $err = sub {
        my $msg = shift;
        print "err: $msg";
        die $msg;

        return JSON::objToJson({
            error => "Error: $msg",
        });
    };

    return $err->("This feature is disabled") if LJ::conf_test($LJ::DISABLED{content_flag});

    # get user
    my $remote = LJ::get_remote()
        or return $err->("Sorry, you must be logged in to use this feature.");

    # check auth token
    #return $err->("Invalid auth token") unless LJ::Auth->check_ajax_auth_token($remote, '/__rpc_changerelation', %POST);

    my $getopt = sub {
        my $field = shift;
        my $val = $opts->{$field} or return $err->("Required field $field missing");
        return $val;
    };

    my $mode = $getopt->('mode');
    my $action = $getopt->('action');

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

        my $action = $getopt->('action');
        my $flagid = $getopt->('flagid') + 0;

        my ($flag) = LJ::ContentFlag->load_by_flagid($flagid);

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
            # eh?

        } elsif ($action eq LJ::ContentFlag::CLOSED) {
            $_->close foreach @flags;

        } else {
            return $err->("Unknown action $action");
        }
    } else {
        return $err->("Unknown mode $mode");
    }

    sleep 1 if $LJ::IS_DEV_SERVER;

    return JSON::objToJson({
        success   => $success,
        %ret,
    });
}

sub js {
    q[
     initWidget: function () {
         LiveJournal.addClickHandlerToElementsWithClassName(this.statusBtnClicked.bindEventListener(this), "ContentFlagStatusButton");
         LiveJournal.addClickHandlerToElementsWithClassName(this.contentFlagItemClicked.bindEventListener(this), "ctflag_item");
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
     statusBtnClicked: function (e) {
         var target = e.target;
         if (! target) return;

         var flagid = target.getAttribute('lj_flagid');
         var flagstatus = target.getAttribute('lj_flagstatus');

         if (! flagid || ! flagstatus) return;

         this.doPostAndUpdateContent({
           mode: "admin",
           action: "change_status",
           flagid: flagid,
           value: flagstatus
         });
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
