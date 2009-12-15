package LJ::Widget::Schools::LogItem;

use strict;
use base qw(LJ::Widget);
use Data::Dumper;

sub should_render { return 1; }

sub render_body {
    my ($class, %opts) = @_;

    my $item = $opts{'item'};

    my $ret = '';

    my $columns = 1;
    foreach my $k (qw(schoolid2 name2 country2 state2 city2 url2)) {
        $columns = 2 if $item->{$k};
    }

    my $u = LJ::want_user($item->{'userid'});
    my $lju = LJ::ljuser($u);
    my $time = scalar(localtime($item->{'time'}));

    if ($columns == 1) {
        $ret .= qq{
            <table cellspacing=0 cellpadding=3 border=0>
            <tr><th width="20%">What</th><th width="80%">Value</th></tr>
            <tr><th>Change initiator</th><td>$lju</td></tr>
            <tr><th>Change time</th><td>$time</td></tr>
            <tr><th>Action</th><td>$item->{'action'}</td></tr>
        };

        $ret .= qq{
            <tr><th>School ID</th><td>$item->{'schoolid1'}</td></tr>
        } if ($item->{'schoolid1'});

        $ret .= qq{
            <tr><th>Country</th><td>$item->{'country1'}</td></tr>
        } if ($item->{'country1'});

        $ret .= qq{
            <tr><th>State</th><td>$item->{'state1'}</td></tr>
        } if ($item->{'state1'});

        $ret .= qq{
            <tr><th>City</th><td>$item->{'city1'}</td></tr>
        } if ($item->{'city1'});

        $ret .= qq{
            <tr><th>Name</th><td>$item->{'name1'}</td></tr>
        } if ($item->{'name1'});

        $ret .= qq{
            <tr><th>Website URL</th><td>$item->{'url1'}</td></tr>
        } if ($item->{'url1'});

        $ret .= qq{
            </table>
        };
    } else {
        $ret .= qq{
            <table cellspacing=0 cellpadding=3 border=0>
            <tr>
                <th width="20%">What</th>
                <th width="40%">Before</th>
                <th width="40%">After</th>
            </tr>
            <tr><th>Change initiator</th><td colspan=2>$lju</td></tr>
            <tr><th>Change time</th><td colspan=2>$time</td></tr>
            <tr><th>Action</th><td colspan=2>$item->{'action'}</td></tr>
        };

        my $sid = $item->{'schoolid1'} || $item->{'schoolid2'};
        $ret .= qq {
            <tr><th>School ID</th><td colspan=2>$sid</td></tr>
        } if ($item->{'schoolid1'} == $item->{'schoolid2'});

        $ret .= qq{
            <tr>
                <th>School ID</th>
                <td>$item->{'schoolid1'}</td>
                <td>$item->{'schoolid2'}</td>
            </tr>
        } if (($item->{'schoolid1'} || $item->{'schoolid2'}) &&
            $item->{'schoolid1'} != $item->{'schoolid2'});

        $ret .= qq{
            <tr>
                <th>Country</th>
                <td>$item->{'country1'}</td>
                <td>$item->{'country2'}</td>
            </tr>
        } if (($item->{'country1'} || $item->{'country2'}) &&
            $item->{'country1'} ne $item->{'country2'});

        $ret .= qq{
            <tr>
                <th>State</th>
                <td>$item->{'state1'}</td>
                <td>$item->{'state2'}</td>
            </tr>
        } if (($item->{'state1'} || $item->{'state2'}) &&
            $item->{'state1'} ne $item->{'state2'});

        $ret .= qq{
            <tr>
                <th>City</th>
                <td>$item->{'city1'}</td>
                <td>$item->{'city2'}</td>
            </tr>
        } if (($item->{'city1'} || $item->{'city2'}) &&
            $item->{'city1'} ne $item->{'city2'});

        $ret .= qq{
            <tr>
                <th>Name</th>
                <td>$item->{'name1'}</td>
                <td>$item->{'name2'}</td>
            </tr>
        } if (($item->{'name1'} || $item->{'name2'}) &&
            $item->{'name1'} ne $item->{'name2'});

        $ret .= qq{
            <tr>
                <th>Website URL</th>
                <td>$item->{'url1'}</td>
                <td>$item->{'url2'}</td>
            </tr>
        } if (($item->{'url1'} || $item->{'url2'}) &&
            $item->{'url1'} ne $item->{'url2'});

        $ret .= qq{
            </table>
        };
    }

    $ret .= '<?hr?>';

    return $ret;
}

1;