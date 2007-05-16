# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

{
    my $test_string = qq {
<table>
<tr>
<td>
<b>hellohellohello</b>
</td>
</tr>
</table>};

    my $test_string_trunc = $test_string;
    $test_string_trunc =~ s/hellohellohello/helloh/;

    is(LJ::html_trim($test_string, 10), $test_string_trunc, "Truncating with html works");

    is(LJ::html_trim("hello", 2), "he", "Truncating normal text");
}

1;

