package LJ::JSUtil;
use strict;

#<LJFUNC>
# name: LJ::JSUtil::autocomplete
# class: web
# des: given the name of a form filed and a list of strings, return the
#      JavaScript needed to turn on autocomplete for the given field.
# returns: HTML/JS to insert in an HTML page
# </LJFUNC>
sub autocomplete {
    my %opts = @_;

    my $fieldid = $opts{field};
    my @list = @{$opts{list}};

    # create formatted string to use as a javascript list
    @list = sort { lc $a cmp lc $b } @list;
    @list = map { $_ = "\"$_\"" } @list;
    my $formatted_list = join(",", @list);

    return qq{
    <script type="text/javascript">
        function AutoCompleteFriends(ele) \{
            var keywords = new InputCompleteData([$formatted_list], "ignorecase");
            new InputComplete(ele, keywords);
        \}
        if ('$fieldid' && \$('$fieldid')) AutoCompleteFriends(\$('$fieldid'));
    </script>
    };
}

1;
