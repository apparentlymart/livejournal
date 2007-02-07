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

sub render {
    my ($class, @opts) = @_;
    croak "render must be called as a class method"
        unless $class =~ /^LJ::Widget/;

    my $subclass = $class->subclass;
    my $css_subclass = $subclass;

    my $ret = "<div class='Widget Widget-$css_subclass'>";

    my $rv = eval {
        my $widget = "LJ::Widget::$subclass";

        # include any resources that this widget declares
        foreach my $file ($widget->need_res) {
            if ($file =~ m!^[^/]+\.(js|css)$!i) {
                my $prefix = $1 eq 'js' ? "js" : "stc";
                LJ::need_res("$prefix/widgets/$subclass/$file");
                next;
            }
            LJ::need_res($file);
        }

        return $widget->render_body(@opts);
    } or $class->handle_error($@);

    $ret .= $rv;
    $ret .= "</div>";

    return $ret;
}

sub handle_post {
    my $class   = shift;
    my $post    = shift;
    my @widgets = @_;

    # no errors, return empty list
    return () unless LJ::did_post() && @widgets;

    # require form auth for widget submissions
    my @errors = ();
    unless (LJ::check_form_auth($post->{lj_form_auth})) {
        push @errors, BML::ml('error.invalidform');
    }

    my %per_widget = map { /^(?:LJ::Widget::)?(.+)$/; $1 => {} } @widgets;
    my $eff_submit = undef;

    # per_widget is populated above for widgets which
    # are declared to be able to post to this page... if
    # it's not in the hashref then it's not whitelisted
    my $allowed = sub {
        my $wclass = shift;
        return 1 if $per_widget{$wclass};

        push @errors, "Submit from disallowed class: $wclass";
        return 0;
    };

    foreach my $key (keys %$post) {
        next unless $key;

        # FIXME: this is currently unused, but might be useful
        if ($key =~ /^Widget_Submit_(\w+)$/) {
            die "Multiple effective submits?  class=$1"
                if $eff_submit;

            # is this class whitelisted?
            next unless $allowed->($1);

            $eff_submit = $1;
            next;
        }

        my ($class, $field) = $key =~ /^Widget_(\w+?)_(\w+)$/;
        next unless $class && $field;

        # whitelisted widget class?
        next unless $allowed->($class);

        $per_widget{$class}->{$field} = $post->{$key};
    }

    while (my ($class, $fields) = each %per_widget) {
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

    $errstr =~ s/\s+at\s+.+line \d+.*$//ig;
    push @$errref, LJ::errobj('WidgetError' => $errstr);
    return 1;
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
# FIXME: util shit

package LJ::Widget;
use strict;

# most of these are flat wrappers, but swapping in a valid 'name'
sub _html_star {
    my $class = shift;
    my $func  = shift;
    my %opts = @_;
    
    my $prefix = "Widget_" . $class->subclass;
    $opts{name} = "${prefix}_$opts{name}";
    return $func->(\%opts);
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

sub html_select {
    my $class = shift;
    return $class->_html_star(\&LJ::html_select, @_);
}

sub html_datetime {
    my $class = shift;
    return $class->_html_star(\&LJ::html_datetime, @_);
}

sub html_hidden { 
    my $class = shift;
    return LJ::html_hidden(@_);
}

sub html_submit {
    my $class = shift;
    return LJ::html_submit(@_);
}

1;
