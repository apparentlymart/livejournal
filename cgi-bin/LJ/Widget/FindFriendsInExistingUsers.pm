package LJ::Widget::FindFriendsInExistingUsers;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub ajax { 1 }
sub authas { 1 }

sub need_res { qw( stc/widgets/search.css js/jobstatus.js) }

sub handle_post { }

sub render_body {
    my $class = shift;
    my $ret;

    my @search_opts = (
        'user' => $class->ml('.widget.search.username'),
        'email' => $class->ml('.widget.search.email'),
        'aolim' => $class->ml('.widget.search.aim'),
        'icq' => $class->ml('.widget.search.icq'),
        'jabber' => $class->ml('.widget.search.jabber'),
        'msn' => $class->ml('.widget.search.msn'),
        'yahoo' => $class->ml('.widget.search.yahoo'),
    );

    $ret .= "<h2>" . $class->ml('.widget.search.title') . "</h2>\n";
    $ret .= $class->start_form( id => $class->input_prefix . "_user_search" );
    $ret .= $class->html_select({name => 'type', selected => 'int', class => 'select'}, @search_opts) . " ";
    $ret .= $class->html_text(name => 'q', 'class' => 'text', 'size' => 30) . " ";
    $ret .= $class->html_submit( button => $class->ml('.widget.search.submit'));
    $ret .= "<div id='" . $class->input_prefix . "_ajax_status'></div><br/>";
    $ret .= $class->end_form;
    $ret .= "<div id='" . $class->input_prefix . "_errors' style='color: #ff0000'></div>";

    return $ret;
}

sub js {
    my $self = shift;

    my $empty_query = $self->ml('widget.findfriendsinexistingusers.empty.query');
    my $init_text = $self->ml('widget.findfriendsinexistingusers.init_text');
    my $job_error = $self->ml('widget.findfriendsinexistingusers.job_error');

    qq [
        initWidget: function () {
            var self = this;

            DOM.addEventListener(\$("Widget[FindFriendsInExistingUsers]_user_search"), "submit", function (evt) { 
                self.AskAddressBook(evt, \$("Widget[FindFriendsInExistingUsers]_user_search")) 
            });
        },
        AskAddressBook: function (evt, form) {
            var type  = form["Widget[FindFriendsInExistingUsers]_type"].value + "";
            var query = form["Widget[FindFriendsInExistingUsers]_q"].value + "";

            if (query == '') {
                \$("Widget[FindFriendsInExistingUsers]_errors").innerHTML = "$empty_query";
                Event.stop(evt);
                return;
            }

            this.query = query;

            \$("Widget[FindFriendsInExistingUsers]_errors").innerHTML = "";
            \$("Widget[FindFriendsInExistingUsers]_ajax_status").innerHTML = "$init_text";

            var req = { method : "POST",
                        data : HTTPReq.formEncoded({ "q" : query, "type" : type }),
                        url : LiveJournal.getAjaxUrl("multisearch"),
                        onData : this.import_handle.bind(this),
                        onError : this.import_error.bind(this)
                      };

            HTTPReq.getJSON(req);
            Event.stop(evt);
        },

        import_error: function(msg) {
            \$("Widget[FindFriendsInExistingUsers]_ajax_status").innerHTML = "";
            \$("Widget[FindFriendsInExistingUsers]_errors").innerHTML = msg;
        },

        import_handle: function(info) {
            if (info.error) {
                return this.import_error(info.error);
            }

            if (info.status != "success") {
                this.import_error("$job_error");
                return;
            }

            \$("Widget[FindFriendsInExistingUsers]_ajax_status").innerHTML = info.result;
        },

        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
