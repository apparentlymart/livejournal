package LJ::Portal::Box::CProd; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "CProd";
our $_box_description = 'Were you aware?';
our $_box_name = "<a href='$LJ::SITEROOT/didyouknow'>Did You Know?</a>";

sub generate_content {
    my $self = shift;
    my $content = '';

    my $u = $self->{u};
    $content = LJ::CProd->full_box_for($u) || "You know everything!";

    return $content;
}

# mark this cprod as having been viewed
sub box_updated {
    my $self = shift;

    my $u = $self->{u};
    my $prod = LJ::CProd->prod_to_show($u);
    LJ::CProd->mark_acked($u, $prod) if $prod;
    return '';
}

#######################################

sub box_description { $_box_description; }
sub box_name { $_box_name; }
sub box_class { $_box_class; }
sub can_refresh { 1 }

1;
