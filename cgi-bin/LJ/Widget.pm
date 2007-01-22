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

sub render {
    my ($class, @opts) = @_;
    croak "render must be called as a class method"
        unless $class =~ /^LJ::Widget/;

    my $subclass = $class->subclass;
    my $css_subclass = lc($subclass);

    my $ret = "<div class='appwidget appwidget-$css_subclass'>";

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
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $errorsref = $opts{errors} || [];

    unless (LJ::check_form_auth($post->{lj_form_auth})) {
        push @$errorsref, BML::ml('error.invalidform');

        # FIXME: start here!
    }
        

    my %per_widget = ();

    foreach my $key (keys %$post) {
        next unless $key;

        my ($class, $field) = $key =~ /^Widget_(\w+)_(\w+)$/;
        next unless $class && $field;

        $per_widget{$class}->{$field} = $post->{$key};
    }

    while (my ($class, $fields) = each %per_widget) {
        eval { "LJ::Widget::$class"->handle_post($fields) } or
            $class->handle_error($@ => $errorsref);
    }
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

sub html_text {
    my $class = shift;
    my %opts = @_;
    
    my $prefix = "Widget_" . $class->subclass;
    $opts{name} = "${prefix}_$opts{name}";
    return LJ::html_text(\%opts);
}

sub html_submit {
    my $class = shift;

    return LJ::html_submit(@_);
}

1;
