package LJ::Widget::FindFriendsInExistingUsers;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub ajax { 1 }
sub authas { 1 }

sub need_res { qw( stc/widgets/search.css stc/widgets/friendsfinder.css js/jobstatus.js) }

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

    $ret .= "<div class='mailfinder exists'>";
    $ret .= "<h4>" . $class->ml('.widget.search.existingtitle') . "</h4>\n";
    $ret .= $class->ml('widget.search.note');
    $ret .= $class->start_form( id => $class->input_prefix . "_user_search");
    $ret .= "<fieldset><label for='existuser'>" . $class->ml('.widget.search.title') . "</label>";
    $ret .= $class->html_text(name => 'q', 'class' => 'mailbox', 'size' => 30, id => 'existuser' ) . " ";
    $ret .= $class->html_select({name => 'type', selected => 'int'}, @search_opts) . " </fieldset>";    
    $ret .= "<div class='ffind'>" . $class->html_submit( button => $class->ml('.widget.search.submit'), { class => "btn" });
    $ret .= "<span id='" . $class->input_prefix . "_errors' class='find_err'></span>";
    $ret .= "</div>";
    $ret .= $class->end_form;
    $ret .= "<div id='" . $class->input_prefix . "_ajax_status'></div><br/>";
    $ret .= "</div>";

    return $ret;
}

sub js {
    my $self = shift;

    my $empty_query = $self->ml('widget.findfriendsinexistingusers.empty.query');
    my $init_text = $self->ml('widget.findfriendsinexistingusers.init_text');
    my $job_error = $self->ml('widget.findfriendsinexistingusers.job_error');
    my $validate_error = 'Неправильный номер';
    my $validate_name_error = 'Неправильное имя пользователя';

    qq [
        initWidget: function() {
            this.form = \$('Widget[FindFriendsInExistingUsers]_user_search');
            
            DOM.addEventListener(this.form, 'submit', function (e) {
                Event.stop(e);
                if (this.validate())
                    this.AskAddressBook(\$('Widget[FindFriendsInExistingUsers]_user_search'));
            }.bind(this))
        },

        AskAddressBook: function(form) {
            var type  = this.form['Widget[FindFriendsInExistingUsers]_type'].value,
                query = this.form['Widget[FindFriendsInExistingUsers]_q'].value;

            if (query == '') {
                \$('Widget[FindFriendsInExistingUsers]_errors').innerHTML = '$empty_query';
                return;
            }

            this.query = query;

            \$('Widget[FindFriendsInExistingUsers]_errors').innerHTML = '';
            \$('Widget[FindFriendsInExistingUsers]_ajax_status').innerHTML = '$init_text';

            var req = {
                        data: HTTPReq.formEncoded({q: query, type: type}),
                        method: 'POST',
                        url: LiveJournal.getAjaxUrl('multisearch'),
                        onData: this.import_handle.bind(this),
                        onError: this.import_error.bind(this)
                      }

            HTTPReq.getJSON(req);
        },

        import_error: function(msg) {
            \$('Widget[FindFriendsInExistingUsers]_ajax_status').innerHTML = '';
            \$('Widget[FindFriendsInExistingUsers]_errors').innerHTML = msg;
        },

        import_handle: function(info) {
            if (info.error) {
                return this.import_error(info.error);
            }

            if (info.status != 'success') {
                return this.import_error('$job_error');
            }

            \$('Widget[FindFriendsInExistingUsers]_ajax_status').innerHTML = info.result;
        },

        validate: function() {
            var v = this.form['Widget[FindFriendsInExistingUsers]_q'].value.trim(),
                r,
                select = this.form['Widget[FindFriendsInExistingUsers]_type'],
                error_msg = '$validate_error';

            switch (select.options[select.selectedIndex].value) {
                case 'user':
                    r = /^[0-9a-z_-]{1,15}\$/i;
                    error_msg = '$validate_name_error';
                    break;
                case 'jabber':
                case 'email':
                case 'msn':
                case 'yahoo':
                    r = /^(("[\\w-\\s]+")|([\\w-]+(?:\\.[\\w-]+)*)|("[\\w-\\s]+")([\\w-]+(?:\\.[\\w-]+)*))(@((?:[\\w-]+\\.)*\\w[\\w-]{0,66})\\.([a-z]{2,6}(?:\\.[a-z]{2})?)\$)|(@\\[?((25[0-5]\\.|2[0-4][0-9]\\.|1[0-9]{2}\\.|[0-9]{1,2}\\.))((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})\\.){2}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})\\]?\$)/i;
                    break;
                case 'skype':
                case 'lastfm':
                    r = /^[^@]+\$/;
                    break;
                case 'icq':
                    r = /^\\d+\$/;
                    break;
                case 'aolim':
                    r = /^\\w+\$/;
                    break;
                case 'gizmo':
                    r =  /^[0-9a-z_-]+\$/i;
                    break;
            }

            if (r && !r.test(v)) {
                this.import_error(error_msg);
                return false;
            }

            return true;
        },

        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
