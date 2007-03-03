package LJ::Setting::Interests;
use base 'LJ::Setting';
use strict;
use warnings;

sub tags { qw(interests interest likes about) }

sub as_html {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;
    my $ret;

    # load interests
    my @interest_list;
    my $interests = $u->interests;
    foreach my $int (sort keys %$interests) {
        push @interest_list, $int if LJ::text_in($int);
    }

    $ret .= $class->ml('.setting.interests.question') . "<br />";
    $ret .= $class->ml('.setting.interests.desc') . "<br />";
    $ret .= LJ::html_textarea({ 'name' => "${key}interests", 'id' => "interests_box", 'value' => join(", ", @interest_list),
                                'rows' => '10', 'cols' => '50', 'wrap' => 'soft' }) . "<br />";
    $ret .= "<small>" . $class->ml('.setting.interests.note') . "</small>";
    $ret .= $class->errdiv($errs, "interests");

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;

    my $interest_list = $class->get_arg($args, "interests");
    my @ints = LJ::interest_string_to_list($interest_list);
    my $intcount = scalar @ints;
    my @interrors = ();

    # Don't bother validating the interests if there are already too many
    if ($intcount > 150) {
        $class->errors("interests" => LJ::Lang::ml('error.interest.excessive', { intcount => $intcount }));
    }

    # Clean interests and make sure they're valid
    my @valid_ints = LJ::validate_interest_list(\@interrors, @ints);
    if (@interrors > 0) {
        $class->errors("interests" => map { LJ::Lang::ml(@$_) } @interrors);
    }

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $interest_list = $class->get_arg($args, "interests");
    my @new_interests = LJ::interest_string_to_list($interest_list);
    my $old_interests = $u->interests;

    $u->set_interests($old_interests, \@new_interests);
}

1;
