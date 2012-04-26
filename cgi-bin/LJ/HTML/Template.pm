package LJ::HTML::Template;
use strict;

# Returns a new HTML::Template object
# with some redefined default values.
sub new {
    my $class = shift;
    my $opts = (ref $_[0]) ? shift : {};

    my %common_params = (
        'lj_siteroot'   => $LJ::SITEROOT,
        'lj_sitename'   => $LJ::SITENAMESHORT,
        'lj_sslroot'    => $LJ::SSLROOT,
    );

    if ($LJ::IS_SSL) {
        %common_params = (
            %common_params,
            'lj_imgprefix'  => $LJ::SSLIMGPREFIX,
            'lj_jsprefix'   => $LJ::SSLJSPREFIX,
            'lj_statprefix' => $LJ::SSLSTATPREFIX,
        );
    } else {
        %common_params = (
            %common_params,
            'lj_imgprefix'  => $LJ::IMGPREFIX,
            'lj_jsprefix'   => $LJ::JSPREFIX,
            'lj_statprefix' => $LJ::STATPREFIX,
        );
    }

    if ($opts->{'use_expr'}) {
        require HTML::Template::Pro; # load module on demand

        HTML::Template::Pro->register_function(
            ml => sub {
                my $key = shift;
                my %opts = @_;
                return LJ::Lang::ml($key, \%opts);
            },
        );
        HTML::Template::Pro->register_function(
            ehtml => sub {
                my $string = shift;
                return LJ::ehtml($string);
            },
        );
        HTML::Template::Pro->register_function(
            eurl => sub {
                my $string = shift;
                return LJ::eurl($string);
            },
        );
        HTML::Template::Pro->register_function(
            ejs => sub {
                my $string = shift;
                return LJ::ejs($string);
            },
        );
        HTML::Template::Pro->register_function(
            ljuser => sub {
                my $username = shift;

                my %opts;
                $opts{'imgroot'} = "$LJ::SSLROOT/img" if $LJ::IS_SSL;

                return LJ::ljuser($username, \%opts);
            },
        );

        HTML::Template::Pro->register_function(
            'lj_enabled' => sub {
                my ($what) = @_;
                my $remote = LJ::get_remote();
                return LJ::is_enabled( $what, $remote );
            },
        );

        HTML::Template::Pro->register_function(
            'src2url' => sub {
                my $src = shift;
                return LJ::stat_src_to_url($src);
            },
        );

        HTML::Template::Pro->register_function(
            'userid2display' => sub {
                my ($userid, %opts) = @_;
                my $u = LJ::load_userid($userid);
                return $u->ljuser_display(\%opts);
            },
        );

        HTML::Template::Pro->register_function(
            'userid2name' => sub {
                my ($userid, %opts) = @_;
                my $u = LJ::load_userid($userid);
                return $u->{user};
            },
        );

        HTML::Template::Pro->register_function(
            'src2url' => sub {
                my $src = shift;
                return LJ::stat_src_to_url($src);
            },
        );

        HTML::Template::Pro->register_function(
            'src2url' => sub {
                my $src = shift;
                return LJ::stat_src_to_url($src);
            },
        );

        my $template = HTML::Template::Pro->new(
            global_vars => 1, # normally variables declared outside a loop are not available inside
                              # a loop.  This option makes <TMPL_VAR>s like global variables in Perl
                              # - they have unlimited scope.
                              # This option also affects <TMPL_IF> and <TMPL_UNLESS>

            die_on_bad_params => 0, # if set to 0 the module will let you call
                                    # $template->param(param_name => 'value') even
                                    # if 'param_name' doesn't exist in the template body.
                                    # Defaults to 1.
            loop_context_vars => 1, # special loop variables: __first__, __last__, __odd__, __inner__, __counter__
            path => $ENV{'LJHOME'},
            @_
        );

        $template->param(%common_params);

        return $template;
    } else {
        require HTML::Template; # load on demand
        my $template = HTML::Template->new(
            global_vars => 1, # normally variables declared outside a loop are not available inside
                              # a loop.  This option makes <TMPL_VAR>s like global variables in Perl
                              # - they have unlimited scope.
                              # This option also affects <TMPL_IF> and <TMPL_UNLESS>

            die_on_bad_params => 0, # if set to 0 the module will let you call
                                    # $template->param(param_name => 'value') even
                                    # if 'param_name' doesn't exist in the template body.
                                    # Defaults to 1.
            path => $ENV{'LJHOME'},
            @_
        );

        $template->param(%common_params);

        return $template;
    }
}


1;
