#!/usr/bin/perl
#

# <WCMFUNC>
# name: html_datetime
# class: component
# des:
# info: Parse output later with [func[html_datetime_decode]].
# args:
# des-:
# returns:
# </WCMFUNC>
sub html_datetime
{
    my $opts = shift;
    my $lang = $opts->{'lang'} || "EN";
    my ($yyyy, $mm, $dd, $hh, $nn, $ss);
    my $ret;
    my $name = $opts->{'name'};
    my $disabled = $opts->{'disabled'} ? "disabled" : "";
    if ($opts->{'default'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d):(\d\d))?/) {
        ($yyyy, $mm, $dd, $hh, $nn, $ss) = ($1 > 0 ? $1 : "",
                                            $2+0,
                                            $3 > 0 ? $3+0 : "",
                                            $4 > 0 ? $4 : "",
                                            $5 > 0 ? $5 : "",
                                            $6 > 0 ? $6 : "");
    }
    $ret .= html_select({ 'name' => "${name}_mm", 'selected' => $mm, 'disabled' => $opts->{'disabled'} },
                         map { $_, Lang::month_long($lang, $_) } (0..12));
    $ret .= "<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_dd VALUE=\"$dd\" $disabled>, <INPUT SIZE=4 MAXLENGTH=4 NAME=${name}_yyyy VALUE=\"$yyyy\" $disabled>";
    unless ($opts->{'notime'}) {
        $ret.= " <INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_hh VALUE=\"$hh\" $disabled>:<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_nn VALUE=\"$nn\" $disabled>";
        if ($opts->{'seconds'}) {
            $ret .= "<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_ss VALUE=\"$ss\" $disabled>";
        }
    }

    return $ret;
}

# <WCMFUNC>
# name: html_datetime_decode
# class: component
# des:
# info: Generate the form controls with [func[html_datetime]].
# args:
# des-:
# returns:
# </WCMFUNC>
sub html_datetime_decode
{
    my $opts = shift;
    my $hash = shift;
    my $name = $opts->{'name'};
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                   $hash->{"${name}_yyyy"},
                   $hash->{"${name}_mm"},
                   $hash->{"${name}_dd"},
                   $hash->{"${name}_hh"},
                   $hash->{"${name}_nn"},
                   $hash->{"${name}_ss"});
}

# <WCMFUNC>
# name: html_select
# class: component
# des:
# info:
# args:
# des-:
# returns:
# </WCMFUNC>
sub html_select
{
    my $opts = shift;
    my @items = @_;
    my $disabled = $opts->{'disabled'} ? " disabled='1'" : "";
    my $ret;
    $ret .= "<select";
    if ($opts->{'name'}) { $ret .= " name='$opts->{'name'}'"; }
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    $ret .= "$disabled>";
    my $did_sel = 0;
    while (my ($value, $text) = splice(@items, 0, 2)) {
        my $sel = "";
        if ($value eq $opts->{'selected'} && ! $did_sel++) { $sel = " selected"; }
        $ret .= "<option value=\"$value\"$sel>$text</option>";
    }
    $ret .= "</select>";
    return $ret;
}

# <WCMFUNC>
# name: html_check
# class: component
# des:
# info:
# args:
# des-:
# returns:
# </WCMFUNC>
sub html_check
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " disabled" : "";
    my $ret;
    if ($opts->{'type'} eq "radio") {
        $ret .= "<input type=\"radio\" ";
    } else {
        $ret .= "<input type=\"checkbox\" ";
    }
    if ($opts->{'selected'}) { $ret .= " checked='checked'"; }
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    if ($opts->{'name'}) { $ret .= " name=\"$opts->{'name'}\""; }
    if (defined $opts->{'value'}) { $ret .= " value=\"$opts->{'value'}\""; }
    $ret .= "$disabled>";
    return $ret;
}

# <WCMFUNC>
# name: html_text
# class: component
# des:
# info:
# args:
# des-:
# returns:
# </WCMFUNC>
sub html_text
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " disabled" : "";
    my $ret;
    $ret .= "<input type=\"text\"";
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    if ($opts->{'size'}) { $ret .= " size=\"$opts->{'size'}\""; }
    if ($opts->{'maxlength'}) { $ret .= " maxlength=\"$opts->{'maxlength'}\""; }
    if ($opts->{'name'}) { $ret .= " name=\"" . ehtml($opts->{'name'}) . "\""; }
    if ($opts->{'value'}) { $ret .= " value=\"" . ehtml($opts->{'value'}) . "\""; }
    $ret .= "$disabled>";
    return $ret;
}

# <WCMFUNC>
# name: html_color
# class: component
# des: A text field with attached color preview and button to choose a color
# info: Depends on the client-side Color Picker
# args:
# des-:
# returns:
# </WCMFUNC>
sub html_color
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " disabled" : "";
    my $htmlname = ehtml($opts->{'name'});
    my $des = ehtml($opts->{'des'}) || "Pick a Color";
    my $ret;

    ## Output the preview box and picker button with script so that
    ## they don't appear when JavaScript is unavailable.
    $ret .= "<script language=\"JavaScript\"><!--\n".
            "document.write('<span style=\"border: 1px solid #000000; ".
            "padding-left: 2em; background-color: ".ehtml($opts->{'default'}).";\" ".
            "id=\"${htmlname}_disp\">&nbsp;</span>'); ".
            "\n--></script>\n";

    # Would have used html_text here, but need an event handler attached
    $ret .= "<input type=\"text\" size=\"8\" maxlength=\"7\"";
    $ret .= " name=\"$htmlname\" id=\"$htmlname\"";
    if ($opts->{'default'}) { $ret .= " value=\"" . ehtml($opts->{'default'}) . "\""; }
    $ret .= " onchange=\"setBGColor(findel('${htmlname}_disp'),${htmlname}.value);\"";
    $ret .= "$disabled>";

    $ret .= "<script language=\"JavaScript\"><!--\n".
            "document.write('<button ".
            "onclick=\"spawnPicker(findel(\\'${htmlname}\\'),findel(\\'${htmlname}_disp\\'),\\'$des\\'); ".
            " return false;\"$disabled>Choose...</button>'); ".
            "\n--></script>\n";

    # A little help for the non-JavaScript folks
    $ret .= "<noscript> (#<var>rr</var><var>gg</var><var>bb</var>)</noscript>";

    return $ret;
}

# <WCMFUNC>
# name: html_hidden
# class: component
# des: Makes the HTML for a hidden form element
# args: name, val
# des-name: Name of form element (will be HTML escaped)
# des-val: Value of form element (will be HTML escaped)
# returns: HTML
# </WCMFUNC>
sub html_hidden
{
    my $ret;
    while (@_) {
        my $name = shift;
        my $val = shift;
        $ret .= "<input type='hidden' name=\"" . ehtml($name) . "\" value=\"" .
            ehtml($val) . "\" />\n";
    }
    return $ret;
}

# <WCMFUNC>
# name: html_submit
# class: component
# des: Makes the HTML for a submit button
# args: name, val
# des-name: Name of form element (will be HTML escaped)
# des-val: Value of form element, and label of button (will be HTML escaped)
# returns: HTML
# </WCMFUNC>
sub html_submit
{
    my ($name, $val) = @_;
    return "<input type='submit' name=\"" . ehtml($name) . "\" value=\"" .
        ehtml($val) . "\" />";

}

1;
