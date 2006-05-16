package LJ::Setting::FOAFURL;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(FOAF) }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my $ret = $BML::ML{'.foafurl.title'} .
              LJ::html_text({
                  name  => "${key}external_foafurl",
                  value => $u->prop("external_foaf_url"),
                  size  => 40,
                  maxlength => '255',
              });
    $ret .= "<br />$BML::ML{'.foafurl.about'}";
    $ret .= $class->errdiv($errs, "external_foafurl");
    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;
    my $arg = $args->{external_foafurl};
    return 1 if $arg eq $u->{external_foaf_url};
    #$class->errors("external_foaf_url" => "Invalid Entry");
    return 0 unless $u->set_prop("external_foaf_url", $arg);
    return 1;
}

1;



