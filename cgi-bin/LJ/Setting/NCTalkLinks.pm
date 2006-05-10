package LJ::Setting::NCTalkLinks;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(nctalklinks comment_links) }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my $ret = LJ::html_check({ 'type' => 'check', 'name' => "${key}opt_nctalklinks",
                               'id' => 'opt_nctalklinks',
                               'selected' => $u->prop("opt_nctalklinks") });
    $ret .= $class->errdiv($errs, "opt_nctalklinks");
    $ret .= " <label for='opt_nctalklinks'>$BML::ML{'.numcomments.header'}</label><br />";
    $ret .= "$BML::ML{'.numcomments.about'}";
    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;
    my $nct = $args->{opt_nctalklinks} ? 1 : 0;
    warn LJ::D($args);
    return 1 if $nct == $u->prop('opt_nctalklinks');
    $class->errors("opt_nctalklinks" => "Invalid option")  unless $nct =~ /^[01]$/;
    $u->set_prop("opt_nctalklinks", $nct);
}

1;



