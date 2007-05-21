package LJ::Widget::ManageQotD;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::QotD );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $get = delete $opts{get};

    my $ret = "";

    # default values for year/month
    my $year  = $get->{year}+0;
    my $month = $get->{month}+0;

    # if year and month aren't defined, use the current month
    unless ($year && $month) {
        my @time = localtime();
        $year  = $time[5]+1900;
        $month = $time[4]+1;
    }

    $ret .= "<?p (<a href='$LJ::SITEROOT/admin/qotd/add.bml'>Add a question</a>) p?>";
    $ret .= "<?p Select a month to view all questions that started during that month. p?>";

    # TODO: supported way for widgets to do GET forms?
    #       -- lame that GET/POST is done differently in here
    $ret .= "<form method='GET'>";
    $ret .= "<?p Year: " . LJ::html_text({ name => 'year', size => '4', maxlength => '4', value => $year }) . " ";
    $ret .= "Month: " . LJ::html_select({ name => 'month', selected => $month }, map { $_, LJ::Lang::month_long($_) } 1..12) . " p?>";
    $ret .= "<?p " . LJ::html_submit('View Question(s)') . " p?>";
    $ret .= "</form>";

    $ret .= "<hr style='clear: both;' />";

    $ret .= $class->start_form;

    my @this_months_questions = LJ::QotD->get_all_questions_for_month($year, $month);
    return $ret . "<?p No questions started during the selected month. p?>" unless @this_months_questions;

    $ret .= "<table border='1' cellpadding='3'>";
    $ret .= "<tr><th>Image</th><th>Subject</th><th>Question</th><th>Extra Text</th><th>Tags</th><th>Submitted By</th><th>Start Date</th><th>End Date</th><th colspan='2'>Active Status</th><th>Edit</th></tr>";
    foreach my $row (@this_months_questions) {
        my $start_date = DateTime->from_epoch( epoch => $row->{time_start}, time_zone => 'America/Los_Angeles' );
        my $end_date = DateTime->from_epoch( epoch => $row->{time_end}, time_zone => 'America/Los_Angeles' );
        my $tags = LJ::QotD->remove_default_tags($row->{tags});
        my $from_u = LJ::load_user($row->{from_user});
        LJ::CleanHTML::clean_subject(\$row->{subject});
        LJ::CleanHTML::clean_event(\$row->{text});
        LJ::CleanHTML::clean_event(\$row->{extra_text});

        $ret .= "<tr>";
        if ($row->{img_url}) {
            $ret .= "<td><img src='$row->{img_url}' /></td>";
        } else {
            $ret .= "<td>&nbsp;</td>";
        }
        $ret .= $row->{subject} ? "<td>$row->{subject}</td>" : "<td>&nbsp;</td>";
        $ret .= "<td>$row->{text}</td>";
        $ret .= $row->{extra_text} ? "<td>$row->{extra_text}</td>" : "<td>(none)</td>";
        $ret .= $tags ? "<td>$tags</td>" : "<td>&nbsp;</td>";
        $ret .= $from_u ? "<td>" . $from_u->ljuser_display . "</td>" : "<td>&nbsp;</td>";
        $ret .= "<td>" . $start_date->strftime("%F %r %Z")  . "</td>";
        $ret .= "<td>" . $end_date->strftime("%F %r %Z")  . "</td>";
        $ret .= $class->get_active_text($row->{qid}, $row->{active});
        $ret .= "<td>(<a href='$LJ::SITEROOT/admin/qotd/add.bml?qid=$row->{qid}'>edit</a>)</td>";
        $ret .= "</tr>";
    }
    $ret .= "</table>";

    $ret .= $class->end_form;

    return $ret;
}

sub get_active_text {
    my $class = shift;
    my ($qid, $active) = @_;

    my ($curr_state, $verb) = $active eq 'Y' ? ("active", "inactivate") : ("inactive", "activate");
    my $to_state = $curr_state eq 'active' ? 'inactive' : 'active';
    return "<td>$curr_state</td><td>" . $class->html_submit("chg:$to_state:$qid", $verb) . "</td>";
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    # find which to activate/inactivate
    # do the action
    my ($state, $qid);
    while (my ($k, $v) = each %$post) {
        next unless $k =~ /^chg:((?:in)?active):(\w+)/;
        ($state, $qid) = ($1, $2);
        last;
    }

    die "Invalid state for status change"
        unless $state;

    return LJ::QotD->change_active_status($qid, to => $state);
}

1;
