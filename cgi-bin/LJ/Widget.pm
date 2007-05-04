package LJ::Widget;

use strict;
use Carp;
use LJ::ModuleLoader;

# FIXME: don't really need all widgets now
LJ::ModuleLoader->autouse_subclasses("LJ::Widget");

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub need_res {
    return ();
}

sub render_body {
    return "";
}

sub start_form {
    my $ret = "<form method='POST'>";
    $ret .= LJ::form_auth();
    return $ret;
};

sub end_form {
    my $ret = "</form>";
    return $ret;
}

# should this widget be rendered?
# -- not a page logic decision
sub should_render {
    my $class = shift;
    return $class->is_disabled ? 0 : 1;
}

sub render {
    my ($class, @opts) = @_;
    croak "render must be called as a class method"
        unless $class =~ /^LJ::Widget/;

    my $subclass = $class->subclass;
    my $css_subclass = lc($subclass);
    my %opt_hash = @opts;
    
    return "" unless $class->should_render;

    my $ret = "<div class='appwidget appwidget-$css_subclass'>\n";

    my $rv = eval {
        my $widget = "LJ::Widget::$subclass";

        # include any resources that this widget declares
        if ($opt_hash{stylesheet_override}) {
            LJ::need_res($opt_hash{stylesheet_override});
        } else {
            foreach my $file ($widget->need_res) {
                if ($file =~ m!^[^/]+\.(js|css)$!i) {
                    my $prefix = $1 eq 'js' ? "js" : "stc";
                    LJ::need_res("$prefix/widgets/$subclass/$file");
                    next;
                }
                LJ::need_res($file);
            }
            LJ::need_res($opt_hash{stylesheet}) if $opt_hash{stylesheet};
        }

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

        my ($class, $field) = $key =~ /^Widget_(\w+?)_(.+)$/;
        next unless $class && $field;

        # whitelisted widget class?
        next unless $allowed->($class);

        $per_widget{$class}->{$field} = $post->{$key};
    }

    return \%per_widget;
}

sub post_fields {
    my $class = shift;
    my $post = shift;

    my @widgets = ( $class->subclass );
    my $errors = [];
    my $per_widget = LJ::Widget->post_fields_by_widget( post => $post, widgets => \@widgets, errors => $errors );
    return $per_widget->{$class->subclass} || {};
}

sub handle_post {
    my $class   = shift;
    my $post    = shift;
    my @widgets = @_;

    # no errors, return empty list
    return () unless LJ::did_post() && @widgets;
    
    # is this widget disabled?
    return () if $class->is_disabled;

    # require form auth for widget submissions
    my @errors = ();
    unless (LJ::check_form_auth($post->{lj_form_auth})) {
        push @errors, BML::ml('error.invalidform');
    }

    my $per_widget = $class->post_fields_by_widget( post => $post, widgets => \@widgets, errors => \@errors );

    while (my ($class, $fields) = each %$per_widget) {
        eval { "LJ::Widget::$class"->handle_post($fields) } or
            "LJ::Widget::$class"->handle_error($@ => \@errors);
    }

    return @errors;
}

sub handle_error {
    my ($class, $errstr, $errref) = @_;
    $errstr ||= $@;
    $errref ||= \@BMLCodeBlock::errors;
    return 0 unless $errstr;

    $errstr =~ s/\s+at\s+.+line \d+.*$//ig unless $LJ::IS_DEV_SERVER;
    push @$errref, LJ::errobj('WidgetError' => $errstr);
    return 1;
}

sub is_disabled {
    my $class = shift;
    
    my $subclass = $class->subclass;
    return $LJ::WIDGET_DISABLED{$subclass} ? 1 : 0;
}

sub subclass {
    my $class = shift;
    return ($class =~ /::(\w+)$/)[0];
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
    
    my $prefix = $class->input_prefix;
    $opts{name} = "${prefix}_$opts{name}";
    return $func->(\%opts);
}

sub _html_star_list {
    my $class  = shift;
    my $func   = shift;
    my @params = @_;

    # If there's only one element in @params, then there is
    # no name for the field and nothing should be changed.
    unless (@params == 1) {
        my $prefix = $class->input_prefix;

        my $is_name = 1;
        foreach my $el (@params) {
            if (ref $el) {
                $el->{name} = "${prefix}_$el->{name}";
                $is_name = 1;
                next;
            }
            if ($is_name) {
                $el = "${prefix}_$el";
                $is_name = 0;
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
    return "Widget_" . $class->subclass;
}

sub html_select {
    my $class = shift;

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
