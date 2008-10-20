package LJ::Setting::FindByEmail;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(email search) }

sub as_html {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;
    my $ret;

    $ret .= "<label for='${key}opt_findbyemail'>" .
            $class->ml('settings.findbyemail.question',
                { sitename => $LJ::SITENAMESHORT }) . "</label><br />";
    my @options;
    push @options, { text => $class->ml('settings.option.select'), value => '' }
        unless $u->opt_findbyemail;
    push @options, { text => LJ::Lang::ml('settings.findbyemail.opt.Y'), value => "Y" };
    push @options, { text => LJ::Lang::ml('settings.findbyemail.opt.H'), value => "H" };
    push @options, { text => LJ::Lang::ml('settings.findbyemail.opt.N'), value => "N" };
    $ret .= LJ::html_select({ 'name' => "${key}opt_findbyemail",
                              'id' => "${key}opt_findbyemail",
                              'class' => "select",
                              'selected' => $u->opt_findbyemail || '' },
                              @options );
    $ret .= "<div class='helper'>" .
            $class->ml('settings.findbyemail.helper', {
                sitename => $LJ::SITENAMESHORT,
                siteabbrev => $LJ::SITENAMEABBREV }) .
            "</div>";
    $ret .= $class->errdiv($errs, "opt_findbyemail");

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $opt_findbyemail = $class->get_arg($args, "opt_findbyemail");
    $class->errors("opt_findbyemail" => $class->ml('settings.findbyemail.error.invalid')) unless $opt_findbyemail=~ /^[NHY]$/;
    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $opt_findbyemail = $class->get_arg($args, "opt_findbyemail");
    return $u->set_prop('opt_findbyemail', $opt_findbyemail);
}

sub label {
    my $class = shift;
    $class->ml('settings.findbyemail.label');
}

1;
