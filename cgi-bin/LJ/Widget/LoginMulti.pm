package LJ::Widget::LoginMulti;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Request;
use URI;

sub need_res { return 'stc/widgets/login.css' }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;
    my @errors = ();

    ## Page with widget
    my $thispage = $opts{thispage} || "$LJ::SITEROOT/identity/login.bml";
    $thispage =~ m|^http://| 
        or die "'thispage' param should be absolute uri";

    ## Handle auth params
    if (LJ::Request->did_post) {
        do_login($thispage, \@errors);
        ## where to go on success?
        return if LJ::Request->redirected;
    }

    ## Draw widget
    my $template = LJ::HTML::Template->new(
        { use_expr => 1 }, # force HTML::Template::Pro with Expr support
        filename => "$ENV{'LJHOME'}/templates/Identity/Login.tmpl",
        die_on_bad_params => 0,
        strict => 0,
    ) or die "Can't open template: $!";

    my $current_type = LJ::Request->post_param('type') ||
                       LJ::Request->get_param('type')  ||
                       $LJ::IDENTITY_TYPES[0];

    ## to lj.com authorization we need to send data to https endpoint of this page
    my $action_uri = URI->new($thispage);
    $action_uri->scheme("https");
    $action_uri->fragment(undef);
    $action_uri->query(undef);

    ## Auth types.
    ## User type (LJ.com) is always enabled.
    my @types = ({ type => 'user', 
                   ml_tab_heading => LJ::Lang::ml("/identity/login.bml.tab.user"),
                   action => $action_uri->as_string . "?ret=" . LJ::eurl($thispage),
                   });
    ## external auth
    foreach my $type (@LJ::IDENTITY_TYPES) {
        my $idclass = LJ::Identity->find_class($type);
        next unless $idclass->enabled;

        my $type_display = {
            'type' => $type,
            'ml_tab_heading' => LJ::Lang::ml("/identity/login.bml.tab.$type"),
        };

        if ($type eq $current_type) {
            $type_display->{'errors'} = [ map { { 'error' => $_ } } @errors ];
        }
        push @types, $type_display;
    }

    $template->param(
        'types' => \@types,
        'current_type' => $current_type,
    );
    
    ## well cooked widget is here
    return $template->output;
}

sub do_login {
    my $thispage = shift;
    my $errors = shift;
    my $idtype = LJ::Request->post_param('type');

    ## Special case: perform LJ.com login.
    if ($idtype eq 'user'){
        ## Determine user
        my $username = LJ::Request->post_param('user');
        unless ($username){
            push @$errors => LJ::Lang::ml("/htdocs/talkpost_do.bml.error.nousername");
            return;
        }
        ##
        my $u = LJ::load_user($username);
        unless ($u){
            push @$errors => LJ::Lang::ml("/htdocs/talkpost_do.bml.error.badusername2", {
                                'sitename' => $LJ::SITENAMESHORT,
                                'aopts'    => "href='$LJ::SITEROOT/lostinfo.bml'",
                                });
            return;
        }
        ##
        unless ($u->is_person and $u->is_visible){
            push @$errors => LJ::Lang::ml("/identity/login.bml.user.denylogin");
            return;
        }


        ## Verify
        my $ok = LJ::auth_okay($u, LJ::Request->post_param('password'));
        unless ($ok){
            push @$errors => LJ::Lang::ml("/htdocs/talkpost_do.bml.error.badpassword2", {
                                            'aopts' => "href='$LJ::SITEROOT/lostinfo.bml'",
                                            });
            return;
        }

        ## Init Session
        my $exptype = (LJ::Request->post_param('remember_me') ? 'long' : 'short');
        my $ipfixed = 0;
        $u->make_login_session($exptype, $ipfixed);

        ## Where to go?
        my $returnto = LJ::Request->post_param("returnto") || $thispage;
        $returnto = "https://www.livejournal.com/login.bml"
            unless $returnto =~ m!^https?://\Q$LJ::DOMAIN_WEB\E/!;
        LJ::Request->redirect($returnto);

        return 1;

    } else {
        my $idclass = LJ::Identity->find_class($idtype);
        if ($idclass && $idclass->enabled) {
            $idclass->attempt_login($errors,
                'returl_fail' => "$thispage?type=$idtype",
                'forwhat' => 'login',
            );

            return 1 if LJ::Request->redirected;
        } else {
            push @$errors, 'unknown identity type';
        }
    }

}

1;
