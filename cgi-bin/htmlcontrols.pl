#!/usr/bin/perl
#

package LJ;

use strict;

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
    my $disabled = $opts->{'disabled'} ? 1 : 0;

    my %extra_opts;
    foreach (grep { ! /^(name|disabled|seconds|notime|lang|default)$/ } keys %$opts) {
        $extra_opts{$_} = $opts->{$_};
    }

    if ($opts->{'default'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d):(\d\d))?/) {
        ($yyyy, $mm, $dd, $hh, $nn, $ss) = ($1 > 0 ? $1 : "",
                                            $2+0,
                                            $3 > 0 ? $3+0 : "",
                                            $4 > 0 ? $4 : "",
                                            $5 > 0 ? $5 : "",
                                            $6 > 0 ? $6 : "");
    }
    $ret .= html_select({ 'name' => "${name}_mm", 'selected' => $mm,
                          'disabled' => $disabled, %extra_opts },
                         map { $_, LJ::Lang::month_long($_) } (1..12));
    $ret .= html_text({ 'name' => "${name}_dd", 'size' => '2',
                        'maxlength' => '2', 'value' => $dd,
                        'disabled' => $disabled, %extra_opts }) . ", ";
    $ret .= html_text({ 'name' => "${name}_yyyy", 'size' => '4',
                        'maxlength' => '4', 'value' => $yyyy,
                        'disabled' => $disabled, %extra_opts });
    unless ($opts->{'notime'}) {
        $ret .= ' ';
        $ret .= html_text({ 'name' => "${name}_hh", 'size' => '2',
                            'maxlength' => '2', 'value' => $hh,
                            'disabled' => $disabled }) . ':';
        $ret .= html_text({ 'name' => "${name}_nn", 'size' => '2',
                            'maxlength' => '2', 'value' => $nn,
                            'disabled' => $disabled });
        if ($opts->{'seconds'}) {
            $ret .= ':';
            $ret .= html_text({ 'name' => "${name}_ss", 'size' => '2',
                                'maxlength' => '2', 'value' => $ss,
                                'disabled' => $disabled });
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
# des: Creates a drop-down box or listbox HTML form element (the <select> tag).
# info:
# args: opts
# des-opts: A hashref of options. Special options are:
#           raw: inserts value unescaped into select tag;
#           noescape: won't escape key values if set to 1
#           disabled: disables the element;
#           include_ids: bool.  if true, puts id attributes on each element in the drop-down.
#           multiple: creates a drop-down if 0, a multi-select listbox if 1;
#           selected: if multiple, an arrayref of selected values; otherwise, a scalar equalling the selected value;
#           All other options will be treated as html attribute/value pairs
# returns: the generated HTML.
# </WCMFUNC>
sub html_select
{
    my $opts = shift;
    my @items = @_;
    my $ehtml = $opts->{'noescape'} ? 0 : 1;
    my $ret;
    $ret .= "<select";
    $ret .= " $opts->{'raw'}" if $opts->{'raw'};
    $ret .= " disabled='disabled'" if $opts->{'disabled'};
    $ret .= " multiple='multiple'" if $opts->{'multiple'};
    foreach (grep { ! /^(raw|disabled|selected|noescape|multiple)$/ } keys %$opts) {
        $ret .= " $_=\"" . ($ehtml ? ehtml($opts->{$_}) : $opts->{$_}) . "\"";
    }
    $ret .= ">";

    # build hashref from arrayref if multiple selected
    my $selref = { map { $_, 1 } @{$opts->{'selected'}} }
        if $opts->{'multiple'} && ref $opts->{'selected'} eq 'ARRAY';

    my $did_sel = 0;
    while (defined (my $value = shift @items)) {

        # items can be either pairs of $value, $text or a list of $it hashrefs (or a mix)
        my $it = {};
        my $text;
        if (ref $value) {
            $it = $value;
            $value = $it->{value};
            $text = $it->{text};
        } else {
            $text = shift @items;
        }

        my $sel = "";
        # multiple-mode or single-mode?
        if (ref $selref eq 'HASH' && $selref->{$value} ||
            $opts->{'selected'} eq $value && !$did_sel++) {

            $sel = " selected='selected'";
        }
        $value  = $ehtml ? ehtml($value) : $value;

        my $id;
        if ($opts->{'include_ids'} && $opts->{'name'} ne "" && $value ne "") {
            $id = " id='$opts->{'name'}_$value'";
        }

        # is this individual option disabled?
        my $dis = $it->{'disabled'} ? " disabled='disabled' style='color: #999;'" : '';

        $ret .= "<option value=\"$value\"$id$sel$dis>" .
                 ($ehtml ? ehtml($text) : $text) . "</option>";
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

    my $disabled = $opts->{'disabled'} ? " disabled='disabled'" : "";
    my $ehtml = $opts->{'noescape'} ? 0 : 1;
    my $ret;
    if ($opts->{'type'} eq "radio") {
        $ret .= "<input type='radio'";
    } else {
        $ret .= "<input type='checkbox'";
    }
    if ($opts->{'selected'}) { $ret .= " checked='checked'"; }
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    foreach (grep { ! /^(disabled|type|selected|raw|noescape|label)$/ } keys %$opts) {
        $ret .= " $_=\"" . ($ehtml ? ehtml($opts->{$_}) : $opts->{$_}) . "\"";
    }
    $ret .= "$disabled />";
    my $e_label = ($ehtml ? ehtml($opts->{'label'}) : $opts->{'label'});
    $e_label = LJ::labelfy($opts->{id}, $e_label);
    $ret .= $e_label if $opts->{'label'};
    return $ret;
}

# given a string and an id, return the string
# in a label, respecting HTML
sub labelfy {
    my ($id, $text) = @_;

    $text =~ s!
        ^([^<]+)
        !
        <label for="$id">
            $1
        </label>
        !x;

    return $text;
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

    my $disabled = $opts->{'disabled'} ? " disabled='disabled'" : "";
    my $ehtml = $opts->{'noescape'} ? 0 : 1;
    my $type = $opts->{'type'} eq 'password' ? 'password' : 'text';
    my $ret;
    $ret .= "<input type=\"$type\"";
    foreach (grep { ! /^(type|disabled|raw|noescape)$/ } keys %$opts) {
        $ret .= " $_=\"" . ($ehtml ? ehtml($opts->{$_}) : $opts->{$_}) . "\"";
    }
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    $ret .= "$disabled />";
    return $ret;
}

# <WCMFUNC>
# name: html_textarea
# class: component
# des:
# info:
# args:
# des-:
# returns:
# </WCMFUNC>
sub html_textarea
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " disabled='disabled'" : "";
    my $ehtml = $opts->{'noescape'} ? 0 : 1;
    my $ret;
    $ret .= "<textarea";
    foreach (grep { ! /^(disabled|raw|value|noescape)$/ } keys %$opts) {
        $ret .= " $_=\"" . ($ehtml ? ehtml($opts->{$_}) : $opts->{$_}) . "\"";
    }
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    $ret .= "$disabled>" . ($ehtml ? ehtml($opts->{'value'}) : $opts->{'value'}) . "</textarea>";
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

    my $htmlname = ehtml($opts->{'name'});
    my $des = ehtml($opts->{'des'}) || "Pick a Color";
    my $ret;

    ## Output the preview box and picker button with script so that
    ## they don't appear when JavaScript is unavailable.
    $ret .= "<script language=\"JavaScript\"><!--\n".
            "document.write('<span style=\"border: 1px solid #000000; ".
            "padding-left: 2em; background-color: " . ehtml($opts->{'default'}) . ";\" ".
            "id=\"${htmlname}_disp\">&nbsp;</span>'); ".
            "\n--></script>\n";

    # 'onchange' argument happens when color picker button is clicked,
    # or when focus is changed to text box

    $ret .= html_text({ 'size' => 8, 'maxlength' => 7, 'name' => $htmlname, 'id' => $htmlname,
                        'onchange' => "setBGColorWithId(findel('${htmlname}_disp'),'${htmlname}.value');",
                        'onfocus' => $opts->{'onchange'},
                        'disabled' => $opts->{'disabled'}, 'value' => $opts->{'default'},
                        'noescape' => 1, 'raw' => $opts->{'raw'},
                      });

    my $disabled = $opts->{'disabled'} ? "disabled=\'disabled\'" : '';
    $ret .= "<script language=\"JavaScript\"><!--\n".
            "document.write('<button ".
            "onclick=\"spawnPicker(findel(\\'${htmlname}\\')," .
            "findel(\\'${htmlname}_disp\\'),\\'$des\\'); " .
            LJ::ejs($opts->{'onchange'}) .
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
        my $val;
        my $ehtml = 1;
        my $extra;
        if (ref $name eq 'HASH') {
            my $opts = $name;

            $val = $opts->{value};
            $name = $opts->{name};

            $ehtml = $opts->{'noescape'} ? 0 : 1;
            foreach (grep { ! /^(name|value|raw|noescape)$/ } keys %$opts) {
                $extra .= " $_=\"" . ($ehtml ? ehtml($opts->{$_}) : $opts->{$_}) . "\"";
            }

            $extra .= " $opts->{'raw'}" if $opts->{'raw'};

        } else {
            $val = shift;
        }

        $ret .= "<input type='hidden'";
        # allow override of these in 'raw'
        $ret .= " name=\"" . ($ehtml ? ehtml($name) : $name) . "\"" if $name;
        $ret .= " value=\"" . ($ehtml ? ehtml($val) : $val) . "\"" if defined $val;
        $ret .= "$extra />";
    }
    return $ret;
}

# <WCMFUNC>
# name: html_submit
# class: component
# des: Makes the HTML for a submit button
# args: name, val, opts?
# des-name: Name of form element (will be HTML escaped)
# des-val: Value of form element, and label of button (will be HTML escaped)
# des-opts: Optional hashref of additional tag attributes
# returns: HTML
# </WCMFUNC>
sub html_submit
{
    my ($name, $val, $opts) = @_;

    # if one argument, assume (undef, $val)
    if (@_ == 1) {
        $val = $name;
        $name = undef;
    }

    my ($eopts, $disabled, $raw);
    my $type = 'submit';

    my $ehtml;
    if ($opts && ref $opts eq 'HASH') {
        $disabled = " disabled='disabled'" if $opts->{'disabled'};
        $raw = " $opts->{'raw'}" if $opts->{'raw'};
        $type = 'reset' if $opts->{'type'} eq 'reset';

        $ehtml = $opts->{'noescape'} ? 0 : 1;
        foreach (grep { ! /^(raw|disabled|noescape|type)$/ } keys %$opts) {
            $eopts .= " $_=\"" . ($ehtml ? ehtml($opts->{$_}) : $opts->{$_}) . "\"";
        }
    }
    my $ret = "<input type='$type'";
    # allow override of these in 'raw'
    $ret .= " name=\"" . ($ehtml ? ehtml($name) : $name) . "\"" if $name;
    $ret .= " value=\"" . ($ehtml ? ehtml($val) : $val) . "\"" if defined $val;
    $ret .= "$eopts$raw$disabled />";
    return $ret;
}

1;
