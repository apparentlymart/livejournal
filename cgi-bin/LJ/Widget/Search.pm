package LJ::Widget::Search;

use strict;
use base qw(LJ::Widget);
use vars qw(%GET %POST);

use Carp qw(croak);

sub need_res { qw(stc/widgets/search.css) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    if ($opts{type} eq 'yandex') {
        return "" unless LJ::is_enabled('yandex_search_page');

        # ML-vars
        my %ML;
        foreach my $k (qw(name find findall findposts findcomments findusers findfaq)) {
            $ML{"widget.search.yandex.$k"} = $class->ml("widget.search.yandex.$k")
        }

return <<EOF
<div class="search-forms">
<h1>$ML{'widget.search.yandex.name'}</h1>
<form action="/search/" method="get" id="search_form_basic" class="form-on">
<div class="search-item search-query">
<table>
<tbody>
<tr>
<td width="60%">
    <label for="basic_query"><input id="basic_query" name="q" class="type-text" value="" type="search"></label>
</td>
<td width="5%">
    <button type="submit">$ML{'widget.search.yandex.find'}</button>
</td>
</tr>
<tr>
<td width="35%">
    <select id="area_basic_query" class="type-select" name="area">
        <option value="default">$ML{'widget.search.yandex.findall'}</option>
        <option value="posts">$ML{'widget.search.yandex.findposts'}</option>
        <option value="comments">$ML{'widget.search.yandex.findcomments'}</option>
        <option value="journals">$ML{'widget.search.yandex.findusers'}</option>
        <option value="faq">$ML{'widget.search.yandex.findfaq'}</option>
    </select>
</td>
</tr>
</tbody></table>
</div>
</fieldset>
</form>
</div>
EOF
    }

    my $ret;

    my $single_search = $opts{single_search};
    my ($select_box, $search_btn);

    my @search_opts = (
        'int' => $class->ml('.widget.search.interest'),
        'region' => $class->ml('.widget.search.region'),
        'user' => $class->ml('.widget.search.username'),
        'email' => $class->ml('.widget.search.email'),
        'aolim' => $class->ml('.widget.search.aim'),
        'icq' => $class->ml('.widget.search.icq'),
        'jabber' => $class->ml('.widget.search.jabber'),
        'msn' => $class->ml('.widget.search.msn'),
        'yahoo' => $class->ml('.widget.search.yahoo'),
    );

    if ($single_search eq "interest") {
        $ret .= "<p class='search-interestonly'>" . $class->ml('widget.search.interestonly') . "</p>";
        $select_box = LJ::html_hidden( type => "int" );
        $search_btn = LJ::html_submit($class->ml('widget.search.interestonly.btn'));
    } else {
        $ret .= "<h2>" . $class->ml('.widget.search.title') . "</h2>\n";
        $select_box = LJ::html_select({name => 'type', selected => 'int', class => 'select'}, @search_opts) . " ";
        $search_btn = LJ::html_submit($class->ml('.widget.search.submit'));
    }

    $ret .= "<form action='$LJ::SITEROOT/multisearch.bml' method='post'>\n";
    $ret .= $select_box;
    $ret .= LJ::html_text({name => 'q', 'class' => 'text', 'size' => 30}) . " ";
    $ret .= $search_btn;
    $ret .= "</form>";

    return $ret;
}

1;
