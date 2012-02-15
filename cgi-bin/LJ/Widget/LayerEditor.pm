package LJ::Widget::LayerEditor;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
sub ajax { 1 }
sub authas { 1 }
sub need_res { qw( js/jquery/jquery.storage.js
                    js/jquery/jquery.hotkeys.js
                    js/jquery/jquery.lj.s2editSearchBox.js
                    js/ace/ace.js
                    js/ace/theme-textmate.js
                    js/ace/mode-perl.js
                    js/ace/mode-s2.js
                    stc/s2edit.css
                    stc/widgets/layereditor.css
                    js/s2edit/xlib.js
                    js/s2edit/s2edit.js
                    js/s2edit/s2gui.js
                    js/s2edit/s2parser.js
                    js/s2edit/s2sense.js
                    js/s2edit/s2library.js
                    ) }

=head2 template_filename
# path to template file,
# subclass may skip overriding this method
=cut
sub template_filename { 
    my $class = shift;
    my $lc_class = lc $class->subclass;
    $lc_class =~ s|::|/|g;
    return "$ENV{'LJHOME'}/templates/Widgets/${lc_class}.tmpl";
}

=head2 render_body
=cut
# fully ready 'render_body' method, subclass have no need to override this method
sub render_body {
    my $class = shift;
    my %opts = @_;

    # opts: GET parameters, and from_post - from previous post, parameters 

    my $filename = $class->template_filename();
    my $template = LJ::HTML::Template->new(
        { use_expr => 1 }, # force HTML::Template::Pro with Expr support
        filename => $filename,
        die_on_bad_params => 0,
        strict => 0,
    ) or die "Can't open template '$filename': $!";

    # template object already contains 'lj_siteroot' and several same parameters, look LJ/HTML/Template.pm
    # also it contains 'ml', 'ljuser', ... functions

    my %params = ( );
    $class->prepare_template_params(\%params, %opts);

    if($opts{parameters}) {
        $opts{parameters}->{$_} = $params{$_} foreach keys %params;
    }
    $template->param(%params);

    return if LJ::Request->redirected;

    return $template->output;
}

=head2 prepare_template_params

=cut
sub prepare_template_params {
    my ($class, $params, %opts) = @_;

    # we need a valid id
    my $id = $opts{'id'} if $opts{'id'} =~ /^\d+$/;
    die("You have not specified a layer to edit.")
        unless $id;

    # authenticate user;
    my $remote = LJ::get_remote();
    die("You must be logged in to edit layers.")
        unless $remote;
        
    my $no_layer_edit = LJ::run_hook("no_theme_or_layer_edit", $remote);
    die(BML::ml('/customize/advanced/index.bml.error.advanced.editing.denied'))
        if $no_layer_edit;

    # load layer
    my $lay = LJ::S2::load_layer($id);
    die("The specified layer does not exist.")
        unless $lay;

    # if the b2lid of this layer has been remapped to a new layerid
    # then update the b2lid mapping for this layer
    my $b2lid = $lay->{b2lid};
    if ($b2lid && $LJ::S2LID_REMAP{$b2lid}) {
        LJ::S2::b2lid_remap($remote, $id, $b2lid);
        $lay->{b2lid} = $LJ::S2LID_REMAP{$b2lid};
    }

    # is authorized admin for this layer?
    die('You are not authorized to edit this layer.')
        unless $remote && $remote->can_manage($lay->{'userid'});

    # get u of user they are acting as
    my $u = $lay->{'userid'} == $remote->{'userid'} ? $remote : LJ::load_userid($lay->{'userid'});

    # check priv and ownership
    croak("You are not authorized to edit styles.")
        unless LJ::get_cap($u, "s2styles");

    # at this point, they are authorized, allow viewing & editing
    # get s2 code from db - use writer so we know it's up-to-date
    my $dbh = LJ::get_db_writer();
    my $s2code = $opts{'s2code'} || LJ::S2::load_layer_source($lay->{s2lid});

    # load layer info
    my $layinf = {};
    LJ::S2::load_layer_info($layinf, [ $id ]);

    # find a title to display on this page
    my $type = $layinf->{$id}->{'type'};
    my $name = $layinf->{$id}->{'name'};

    # find name of parent layer if this is a child layer
    if (! $name && $type =~ /^(user|theme|i18n)$/) {
        my $par = $lay->{'b2lid'} + 0;
        LJ::S2::load_layer_info($layinf, [$par]);
        $name =  $layinf->{$par}->{'name'};
    }

    # Only use the layer name if there is one and it's more than just whitespace
    my $title = "[$type] ";
    $title .= $name && $name =~ /[^\s]/ ? "$name [\#$id]" : "Layer \#$id";

    # add template variables
    $params->{prefix} = $class->input_prefix,
    $params->{id} = $id;
    $params->{type} = $type;
    $params->{name} = $name;
    $params->{title} = $title;
    $params->{s2code} = LJ::ehtml($s2code);
    $params->{s2doc} = "$LJ::SITEROOT/doc/s2",
    $params->{build} = (exists $opts{build} ? $opts{build} : "Loaded layer $id.");

    $params->{is_remote_sup} = LJ::SUP->is_remote_sup ? 1 : 0;
    $params->{errors} = [ $class->error_list ];
    $params->{form_auth} = LJ::form_auth();

    return 1;
}
=head2 handle_post
    Check parameters passed.
    Compile layer, return compile status
=cut
sub handle_post {
    my ($class, $post, %opts) = @_;
    my $u = $class->get_effective_remote();
    my $build;
    if ($post->{'action'} eq "compile") {
        # we need a valid id
        my $id = $post->{'id'} if $post->{'id'} =~ /^\d+$/;

        die("You have not specified a layer to edit.") unless $id;

        # load layer
        my $lay = LJ::S2::load_layer($id);
        die("The specified layer does not exist.") unless $lay;

        $build = "<b>S2 Compiler Output</b> <em>at " . scalar(localtime) . "</em><br />\n";

        my $error;
        $post->{'s2code'} =~ tr/\r//d;  # just in case
        unless (LJ::S2::layer_compile($lay, \$error, { 's2ref' => \$post->{'s2code'} })) {

            $error =~ s/LJ::S2,.+//s;
            $error =~ s!, .+?(src/s2|cgi-bin)/!, !g;

            $build .= "Error compiling layer:\n<pre style=\"border-left: 1px red solid\">$error</pre>";

            # display error with helpful context
            if ($error =~ /^compile error: line (\d+)/i) {
                my $errline = $1;
                my $kill = $errline - 5 < 0 ? 0 : $errline - 5;
                my $prehilite = $errline - 1 > 4 ? 4: $errline - 1;
                my $snippet = $post->{'s2code'};

                # make sure there's a newlilne at the end
                chomp $snippet;
                $snippet .= "\n";

                # and now, fun with regular expressions
                my $ct = 0;
                $snippet =~ s!(.*?)\n!sprintf("%3d", ++$ct) . ": " .
                    $1 . "\n"!ge;                      # add line breaks and numbering
                $snippet = LJ::ehtml($snippet);
                $snippet =~ s!^((?:.*?\n){$kill,$kill})           # kill before relevant lines
                               ((?:.*?\n){$prehilite,$prehilite}) # capture context before error
                               (.*?\n){0,1}                       # capture error
                               ((?:.*?\n){0,4})                   # capture context after error
                               .*                                 # kill after relevant lines
                             !$2<em class='error'>$3</em>$4!sx;

                $build .= "<b>Context</b><br /><pre>$snippet</pre>\n";
            }

        } else {
            $build .= "Compiled with no errors.\n";
        }
    }
    return ( build => $build, s2code => $post->{'s2code'} );
}

sub js {
    q [
        initWidget: function () {
            s2edit.init(this);
        },

        saveContent: function(text) {
            var form = jQuery('#s2').get(0);
            this.doPost({
                s2code: text,
                action: 'compile',
                id: form["Widget[LayerEditor]_id"].value
            });
        }
    ];


}
1;
