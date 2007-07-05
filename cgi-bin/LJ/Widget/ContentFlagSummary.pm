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
              js/contentflag.js
              );
}

sub ajax { 1 }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote();

    return "This feature is disabled" if LJ::conf_test($LJ::DISABLED{content_flag});

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
                      return 'Adult' if $cat eq LJ::ContentFlag::ADULT;
                      return "??";
                    },
                  status => sub {
                      my $stat = shift;
                      return 'New' if $stat eq LJ::ContentFlag::NEW;
                      return "??";
                    },
                  action => 
                  );


    my %fieldnames = (
                      instime => "Reported",
                      journalid => "User",
                      catid => "Complaint category",
                      reporterid => "Reported by",
                      status => "Status",
                      modtime => "Touched time",
                      itemid => "Item",
                      );

    my @flags = LJ::ContentFlag->load_by_status($opts{status});

    my %status = (
                  'Open' => LJ::ContentFlag::OPEN,
                  'Close' => LJ::ContentFlag::CLOSED,
                  'Resolve' => LJ::ContentFlag::RESOLVED,
                  );

    my @fields = qw (journalid itemid catid reporterid status modtime instime);
    my $fieldheaders = (join '', (map { "<th>$fieldnames{$_}</th>" } @fields));

    $ret .= qq {
        <table class="alternating-rows">
            <tr>
            $fieldheaders
            <th>Action</th>
            </tr>
    };

    my $i = 1;
    foreach my $flag (@flags) {
        my $n = $i++ % 2 + 1;
        $ret .= "<tr class='altrow$n'>";
        foreach my $field (@fields) {
            $ret .= "<td>" . $fields{$field}->($flag->{$field}, $flag) . '</td>';
        }

        my $flagid = $flag->flagid;

        # action buttons
        my $buttons = '';

        $buttons .= qq{<a lj_flagid="$flagid" lj_flagstatus="$status{$_}" class="textbutton ContentFlagStatusButton">[$_]</a> } 
            foreach keys %status;

        $ret .= "<td>$buttons</td>";

        $ret .= '</tr>';
    }

    $ret .= '</table>';

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
        #return $err->("You do not have content flagging admin privs") unless 

        my $action = $getopt->('action');
        my $flagid = $getopt->('flagid') + 0;

        my ($flag) = LJ::ContentFlag->load_by_flagid($flagid);

        if ($action eq 'change_status') {
            my $val = $getopt->('value');
            $success = $flag->set_status($val);
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
