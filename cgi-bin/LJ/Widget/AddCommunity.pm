package LJ::Widget::AddCommunity;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/addcommunity.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    return <<EOT;
<h2>Add community</h2>
<form action='$LJ::SITEROOT/search/' method='post'>
Please submit your suggestion for Community<br />
Directory. Or submit your suggestion for <a href="#">Spotlight</a>.<br />
<input type="submit">
</form>
EOT
}

1;

