package LJ::Widget;

use strict;
use Carp;
use LJ::ModuleLoader;
use LJ::Auth;

# FIXME: don't really need all widgets now
LJ::ModuleLoader->autouse_subclasses("LJ::Widget");

our $currentId = 1;

# can pass in "id" opt to use instead of incrementing $currentId.
# useful for when a widget will be created more than once but we want to keep its ID the same.
sub new {
    my $class = shift;
    my %opts = @_;

    my $id = $opts{id} ? $opts{id} : $currentId++;
    return bless {id => $id}, $class;
}

sub need_res {
    return ();
}

sub render_body {
    return "";
}

sub start_form {
    my $class = shift;
    my %opts = @_;

    croak "Cannot call start_form on parent widget class" if $class eq "LJ::Widget";

    my $eopts = "";
    my $ehtml = $opts{noescape} ? 0 : 1;
    foreach my $attr (grep { ! /^(noescape)$/ && ! /^(authas)$/ } keys %opts) {
        $eopts .= " $attr=\"" . ($ehtml ? LJ::ehtml($opts{$attr}) : $opts{$_}) . "\"";
    }

    my $ret = "<form method='POST'$eopts>";
    $ret .= LJ::form_auth();

    if ($class->authas) {
        my $u = $opts{authas} || $BMLCodeBlock::GET{authas} || $BMLCodeBlock::POST{authas};
        $u = LJ::load_user($u) unless LJ::isu($u);
        my $authas = $u->user if LJ::isu($u);

        if ($authas && !$LJ::REQ_GLOBAL{widget_authas_form}) {
            $ret .= $class->html_hidden({ name => "authas", value => $authas, id => "_widget_authas" });
            $LJ::REQ_GLOBAL{widget_authas_form} = 1;
        }
    }

    return $ret;
};

sub end_form {
    my $class = shift;

    croak "Cannot call end_form on parent widget class" if $class eq "LJ::Widget";

    my $ret = "</form>";
    return $ret;
}

# should this widget be rendered?
# -- not a page logic decision
sub should_render {
    my $class = shift;
    return $class->is_disabled ? 0 : 1;
}

# returns the dom id of this widget element
sub widget_ele_id {
    my $class = shift;

    my $widget_id = ref $class ? $class->{id} : $currentId++;
    return "LJWidget_$widget_id";
}

# render a widget, including its content wrapper
sub render {
    my ($class, @opts) = @_;

    my $subclass = $class->subclass;
    my $css_subclass = lc($subclass);
    my %opt_hash = @opts;

    my $widget_ele_id = $class->widget_ele_id;

    return "" unless $class->should_render;

    my $ret = "<div class='appwidget appwidget-$css_subclass' id='$widget_ele_id'>\n";

    my $rv = eval {
        my $widget = ref $class ? $class : "LJ::Widget::$subclass";

        # include any resources that this widget declares
        if (defined $opt_hash{stylesheet_override}) {
            LJ::need_res($opt_hash{stylesheet_override}) if $opt_hash{stylesheet_override};

            # include non-CSS files (we used stylesheet_override above)
            foreach my $file ($widget->need_res) {
                if ($file =~ m!^[^/]+\.(js|css)$!i) {
                    next if $1 eq 'css';
                    LJ::need_res("js/widgets/$subclass/$file");
                    next;
                }
                LJ::need_res($file) unless $file =~ /\.css$/i;
            }
        } else {
            foreach my $file ($widget->need_res) {
                if ($file =~ m!^[^/]+\.(js|css)$!i) {
                    my $prefix = $1 eq 'js' ? "js" : "stc";
                    LJ::need_res("$prefix/widgets/$subclass/$file");
                    next;
                }
                LJ::need_res($file);
            }
        }
        LJ::need_res($opt_hash{stylesheet}) if $opt_hash{stylesheet};

        return $widget->render_body(@opts);
    } or $class->handle_error($@);

    $ret .= $rv;
    $ret .= "</div><!-- end .appwidget-$css_subclass -->\n";

    return $ret;
}

sub post_fields_by_widget {
    my $class = shift;
    my %opts = @_;

    my $post = $opts{post};
    my $widgets = $opts{widgets};
    my $errors = $opts{errors};

    my %per_widget = map { /^(?:LJ::Widget::)?(.+)$/; $1 => {} } @$widgets;
    my $eff_submit = undef;

    # per_widget is populated above for widgets which
    # are declared to be able to post to this page... if
    # it's not in the hashref then it's not whitelisted
    my $allowed = sub {
        my $wclass = shift;
        return 1 if $per_widget{$wclass};

        push @$errors, "Submit from disallowed class: $wclass";
        return 0;
    };

    foreach my $key (keys %$post) {
        next unless $key;

        # FIXME: this is currently unused, but might be useful
        if ($key =~ /^Widget_Submit_(.+)$/) {
            die "Multiple effective submits?  class=$1"
                if $eff_submit;

            # is this class whitelisted?
            next unless $allowed->($1);

            $eff_submit = $1;
            next;
        }

        my ($subclass, $field) = $key =~ /^Widget(?:\[([\w]+)\])?_(.+)$/;
        next unless $subclass && $field;

        $subclass =~ s/_/::/g;

        # whitelisted widget class?
        next unless $allowed->($subclass);

        $per_widget{$subclass}->{$field} = $post->{$key};
    }

    # now let's remove empty hashref placeholders from %per_widget
    while (my ($k, $v) = each %per_widget) {
        delete $per_widget{$k} unless %$v;
    }

    return \%per_widget;
}

sub post_fields_of_widget {
    my $class = shift;
    my $widget = shift;
    my $post = shift() || \%BMLCodeBlock::POST;

    my $errors = [];
    my $per_widget = LJ::Widget->post_fields_by_widget( post => $post, widgets => [ $widget ], errors => $errors );
    return $per_widget->{$widget} || {};
}

sub post_fields {
    my $class = shift;
    my $post = shift() || \%BMLCodeBlock::POST;

    my @widgets = ( $class->subclass );
    my $errors = [];
    my $per_widget = LJ::Widget->post_fields_by_widget( post => $post, widgets => \@widgets, errors => $errors );
    return $per_widget->{$class->subclass} || {};
}

sub get_args {
    my $class = shift;
    return \%BMLCodeBlock::GET;
}

sub get_effective_remote {
    my $class = shift;

    if ($class->authas) {
        return LJ::get_effective_remote();
    }

    return LJ::get_remote();
}

# call to have a widget process a form submission. this checks for formauth unless
# an ajax auth token was already verified
# returns hash returned from the last processed widget
# pushes any errors onto @BMLCodeBlock::errors
sub handle_post {
    my $class   = shift;
    my $post    = shift;
    my @widgets;
    # support for per-widget handle_post() options
    my %widget_opts = ();
    while (@_) {
        my $w = shift;
        if (@_ && ref $_[0]) {
            $widget_opts{$w} = shift(@_);
        }
        push @widgets, $w;
    }
    # no errors, return empty list
    return () unless LJ::did_post() && @widgets;

    # is this widget disabled?
    return () if $class->is_disabled;

    # require form auth for widget submissions
    my $errorsref = \@BMLCodeBlock::errors;

    unless (LJ::check_form_auth($post->{lj_form_auth}) || $LJ::WIDGET_NO_AUTH_CHECK) {
        push @$errorsref, BML::ml('error.invalidform');
    }

    my $per_widget = $class->post_fields_by_widget( post => $post, widgets => \@widgets, errors => $errorsref );

    my %res;

    while (my ($class, $fields) = each %$per_widget) {
        eval { %res = "LJ::Widget::$class"->handle_post($fields, %{$widget_opts{$class} or {}}) } or
            "LJ::Widget::$class"->handle_error($@ => $errorsref);
    }

    return %res;
}

# handles post vars for a widget, passes result of handle_post to render
sub handle_post_and_render {
    my ($class, $post, $widgetclass, %opts) = @_;

    my %post_result = LJ::Widget->handle_post($post, $widgetclass);
    my $subclass = LJ::Widget::subclass($widgetclass);

    $opts{$_} = $post_result{$_} foreach keys %post_result;
    return "LJ::Widget::$subclass"->render(%opts);
}

*error = \&handle_error;
sub handle_error {
    my ($class, $errstr, $errref) = @_;
    $errstr ||= $@;
    $errref ||= \@BMLCodeBlock::errors;
    return 0 unless $errstr;

    $errstr =~ s/\s+at\s+.+line \d+.*$//ig unless $LJ::IS_DEV_SERVER || $LJ::DEBUG{"full_widget_error"};
    push @$errref, $errstr;
    return 1;
}

sub error_list {
    my ($class, @errors) = @_;

    if (@errors) {
        $class->error($_) foreach @errors;
    }
    return @BMLCodeBlock::errors;
}

sub is_disabled {
    my $class = shift;

    my $subclass = $class->subclass;
    return $LJ::WIDGET_DISABLED{$subclass} ? 1 : 0;
}

# returns the widget subclass name
sub subclass {
    my $class = shift;
    $class = ref $class if ref $class;
    return $class unless $class =~ /::/;
    return ($class =~ /LJ::Widget::([\w:]+)$/)[0];
}

# wrapper around BML... for now
sub decl_params {
    my $class = shift;
    return BML::decl_params(@_);
}

sub form_auth {
    my $class = shift;
    return LJ::form_auth(@_);
}

# override in subclasses with a string of JS to extend the widget subclass with
sub js { '' }

# override to return a true value if this widget accept AJAX posts
sub ajax { 0 }

# override if this widget can perform an AJAX request via GET instead of post
sub can_fake_ajax_post { 0 }

# override in subclasses that support authas authentication
sub authas { 0 }

# instance method to return javascript for this widget
# "page_js_obj" opt:
#     The JS object that is defined by the page the widget is in.
#     Used to create a variable "<page_js_obj>.<widgetclass>" which holds
#     this widget's JS object.  Then the page can call functions that are
#     on specific widgets.
sub wrapped_js {
    my $self = shift;
    my %opts = @_;

    croak "wrapped_js is an instance method" unless ref $self;

    my $widgetid = $self->widget_ele_id or return '';
    my $widgetclass = $self->subclass;
    my $js = $self->js or return '';

    my $authtoken = LJ::Auth->ajax_auth_token(LJ::get_remote(), "/_widget");
    $authtoken = LJ::ejs($authtoken);

    LJ::need_res(qw(js/ljwidget.js));

    my $widgetvar = "LJWidget.widgets[\"$widgetid\"]";
    my $widget_js_obj = $opts{page_js_obj} ? "$opts{page_js_obj}.$widgetclass = $widgetvar;" : "";

    return qq {
        <script>
            $widgetvar = new LJWidget("$widgetid", "$widgetclass", "$authtoken");
            $widget_js_obj
            $widgetvar.extend({$js});
            LiveJournal.register_hook("page_load", function () { $widgetvar.initWidget() });
        </script>
    };
}

package LJ::Error::WidgetError;

use strict;
use base qw(LJ::Error);

sub fields { qw(errstr) }

sub new {
    my $class = shift;
    my ($errstr, %opts) = @_;

    my $self = { errstr => $errstr };

    return bless $self, $class;
}

sub as_html {
    my $self = shift;

    return $self->{errstr};
}

##################################################
# htmlcontrols-like utility methods

package LJ::Widget;
use strict;

# most of these are flat wrappers, but swapping in a valid 'name'
sub _html_star {
    my $class = shift;
    my $func  = shift;
    my %opts = @_;

    croak "Cannot call htmlcontrols-like utility method on parent widget class" if $class eq "LJ::Widget";

    my $prefix = $class->input_prefix;
    $opts{name} = "${prefix}_$opts{name}";
    return $func->(\%opts);
}

sub _html_star_list {
    my $class  = shift;
    my $func   = shift;
    my @params = @_;

    croak "Cannot call htmlcontrols-like utility method on parent widget class" if $class eq "LJ::Widget";

    # If there's only one (non-ref) element in @params, then there
    # is no name for the field and nothing should be changed.
    unless (@params == 1 && !ref $params[0]) {
        my $prefix = $class->input_prefix;

        my $is_name = 1; # if true, the next element we'll check is a name (not a value)
        foreach my $el (@params) {
            if (ref $el) {
                $el->{name} = "${prefix}_$el->{name}" if $el->{name};
                $is_name = 1;
                next;
            }
            if ($is_name) {
                $el = "${prefix}_$el";
                $is_name = 0;
            } else {
                $is_name = 1;
            }
        }
    }

    return $func->(@params);
}

sub html_text {
    my $class = shift;
    return $class->_html_star(\&LJ::html_text, @_);
}

sub html_check {
    my $class = shift;
    return $class->_html_star(\&LJ::html_check, @_);
}

sub html_textarea {
    my $class = shift;
    return $class->_html_star(\&LJ::html_textarea, @_);
}

sub html_color {
    my $class = shift;
    return $class->_html_star(\&LJ::html_color, @_);
}

sub input_prefix {
    my $class = shift;
    my $subclass = $class->subclass;
    $subclass =~ s/::/_/g;
    return 'Widget[' . $subclass . ']';
}

sub html_select {
    my $class = shift;

    croak "Cannot call htmlcontrols-like utility method on parent widget class" if $class eq "LJ::Widget";

    my $prefix = $class->input_prefix;

    # old calling method, exact wrapper around html_select
    if (ref $_[0]) {
        my $opts = shift;
        $opts->{name} = "${prefix}_$opts->{name}";
        return LJ::html_select($opts, @_);
    }

    # newer calling method, no hashref w/ list as list => [ ... ]
    my %opts = @_;
    my $list = delete $opts{list};
    $opts{name} = "${prefix}_$opts{name}";
    return LJ::html_select(\%opts, @$list);
}

sub html_datetime {
    my $class = shift;
    return $class->_html_star(\&LJ::html_datetime, @_);
}

sub html_hidden {
    my $class = shift;

    return $class->_html_star_list(\&LJ::html_hidden, @_);
}

sub html_submit {
    my $class = shift;

    return $class->_html_star_list(\&LJ::html_submit, @_);
}

##################################################
# Utility methods for getting/setting ML strings
# in the 'widget' ML domain
# -- these are usually living in a db table somewhere
#    and input by an admin who wants translateable text

sub ml_key {
    my $class = shift;
    my $key = shift;

    croak "invalid key: $key"
        unless $key;

    my $ml_class = lc $class->subclass;
    return "widget.$ml_class.$key";
}

sub ml_remove_text {
    my $class = shift;
    my $ml_key = shift;

    my $ml_dmid     = $class->ml_dmid;
    my $root_lncode = $class->ml_root_lncode;
    return LJ::Lang::remove_text($ml_dmid, $ml_key, $root_lncode);
}

sub ml_set_text {
    my $class = shift;
    my ($ml_key, $text) = @_;

    # create new translation system entry
    my $ml_dmid     = $class->ml_dmid;
    my $root_lncode = $class->ml_root_lncode;

    # call web_set_text, though there shouldn't be any
    # commits going on since this is the 'widget' dmid
    return LJ::Lang::web_set_text
        ($ml_dmid, $root_lncode, $ml_key, $text,
         { changeseverity => 1, childrenlatest => 1 });
}

sub ml_dmid {
    my $class = shift;

    my $dom = LJ::Lang::get_dom("widget");
    return $dom->{dmid};
}

sub ml_root_lncode {
    my $class = shift;

    my $ml_dom = LJ::Lang::get_dom("widget");
    my $root_lang = LJ::Lang::get_root_lang($ml_dom);
    return $root_lang->{lncode};
}

# override LJ::Lang::is_missing_string to return true
# if the string equals the class name (the fallthrough
# for LJ::Widget->ml)
sub ml_is_missing_string {
    my $class = shift;
    my $string = shift;

    $class =~ /.+::(\w+)$/;
    return $string eq $1 || LJ::Lang::is_missing_string($string);
}

# this function should be used when getting any widget ML string
# -- it's really just a wrapper around LJ::Lang::ml or BML::ml,
#    but it does nice things like falling back to global definition
# -- also allows getting of strings from the 'widget' ML domain
#    for text which was dynamically defined by an admin
sub ml {
    my ($class, $code, $vars) = @_;

    # can pass in a string and check 3 places in order:
    # 1) widget.foo.text => general .widget.foo.text (overridden by current page)
    # 2) widget.foo.text => general widget.foo.text  (defined in en(_LJ).dat)
    # 3) widget.foo.text => widget  widget.foo.text  (user-defined by a tool)

    # whether passed with or without a ".", eat that immediately
    $code =~ s/^\.//;

    # 1) try with a ., for current page override in 'general' domain
    # 2) try without a ., for global version in 'general' domain
    foreach my $curr_code (".$code", $code) {
        my $string = LJ::Lang::ml($curr_code, $vars);
        return "" if $string eq "_none";
        return $string unless LJ::Lang::is_missing_string($string);
    }

    # 3) now try with "widget" domain for user-entered translation string
    my $dmid = $class->ml_dmid;
    my $lncode = LJ::Lang::get_effective_lang();
    my $string = LJ::Lang::get_text($lncode, $code, $dmid, $vars);
    return "" if $string eq "_none";
    return $string unless LJ::Lang::is_missing_string($string);

    # return the class name if we didn't find anything
    $class =~ /.+::(\w+)$/;
    return $1;
}

1;
