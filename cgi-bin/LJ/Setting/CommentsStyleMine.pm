package LJ::Setting::CommentsStyleMine;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;
    return 0 unless $u;
    return 0 unless LJ::is_enabled('comments_style_mine');
    return 0 unless $u->is_personal;

    my $get_styleinfo = sub {
        my $journal = shift;

        my @needed_props = ("stylesys", "s2_style");
        LJ::load_user_props($journal, @needed_props);

        my $forceflag = 0;
        LJ::run_hooks("force_s1", $journal, \$forceflag);
        if ( !$forceflag && $journal->{'stylesys'} == 2 ) {
            return (2, $journal->{'s2_style'});
        }

        return (1, 0);
    };

    my ($stylesys, $styleid) = $get_styleinfo->($u);

    my $use_s1 = 1;
    my $ctx = undef;
    if ($stylesys == 2) {
        $ctx = LJ::S2::s2_context('UNUSED', $styleid);
        $LJ::S2::CURR_CTX = $ctx;

        $use_s1 = 0 if !$ctx->[S2::PROPS]->{'view_entry_disabled'} &&
                       LJ::get_cap($u, "s2viewentry");
    }

    return $use_s1? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.commentsstylemine.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $stylealwaysmine = $class->get_arg($args, "stylealwaysmine") || $u->opt_stylealwaysmine;
    my $commentsstylemine = $class->get_arg($args, "commentsstylemine") || $u->opt_commentsstylemine;
    my $can_use_commentsstylemine = $u->can_use_commentsstylemine? 1 : 0;

    $can_use_commentsstylemine = 0 if $stylealwaysmine;

    my $ret = LJ::html_check({
        name => "${key}commentsstylemine",
        id => "${key}commentsstylemine",
        value => 1,
        selected => $commentsstylemine && $can_use_commentsstylemine? 1 : 0,
        disabled => $can_use_commentsstylemine? 0 : 1,
    });

    $ret .= " <label for='${key}commentsstylemine'>" . $class->ml('setting.commentsstylemine.option') . "</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "commentsstylemine") ? "Y" : "N";
    $u->set_prop( opt_commentsstylemine => $val );

    return 1;
}

1;
