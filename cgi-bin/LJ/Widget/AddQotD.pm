package LJ::Widget::AddQotD;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::QotD );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $qid = $opts{qid};
    my ($text, $tags, $img_url, $extra_text);
    my ($start_month, $start_day, $start_year);
    my ($end_month, $end_day, $end_year);
    if ($qid) {
        my $question = LJ::QotD->get_single_question($opts{qid})
            or die "Invalid question: $qid";

        $text = $question->{text};
        $tags = LJ::QotD->remove_default_tags($question->{tags});
        $img_url = $question->{img_url};
        $extra_text = $question->{extra_text};

        my $start_date = DateTime->from_epoch( epoch => $question->{time_start}, time_zone => 'America/Los_Angeles' );
        my $end_date = DateTime->from_epoch( epoch => $question->{time_end}, time_zone => 'America/Los_Angeles' );
        $start_month = $start_date->month;
        $start_day = $start_date->day;
        $start_year = $start_date->year;
        $end_month = $end_date->month;
        $end_day = $end_date->day;
        $end_year = $end_date->year;
    }

    # default values for year/month/day = today's date
    # unless we're editing, in which case use the given question's dates
    my $time_now = DateTime->now(time_zone => 'America/Los_Angeles');
    unless ($start_month && $start_day && $start_year) {
        $start_month = $time_now->month;
        $start_day = $time_now->day;
        $start_year = $time_now->year;
    }
    unless ($end_month && $end_day && $end_year) {
        $end_month = $time_now->month;
        $end_day = $time_now->day;
        $end_year = $time_now->year;
    }

    # form entry
    my $ret =
        "<?p (<a href='$LJ::SITEROOT/admin/qotd/manage.bml'>" . 
        "Manage questions</a>) p?>" . 
        "<?p Enter a new Question of the Day. p?>";

    $ret .= $class->start_form;

    $ret .= "<table><tr><td>Start Date:</td><td>";
    $ret .= $class->html_select
        ( name => 'month_start',
          selected => $start_month,
          list => [ map { $_, LJ::Lang::month_long($_) } 1..12 ] ) . " ";

    $ret .= $class->html_text
        ( name => 'day_start',
          size => 2,
          maxlength => 2,
          value => $start_day ) . " ";

    $ret .= $class->html_text
        ( name => 'year_start',
          size => 4,
          maxlength => 4,
          value => $start_year ) . " @ 12:00 AM</td></tr>";

    $ret .= "<tr><td>End Date:</td><td>";
    $ret .= $class->html_select
        ( name => 'month_end',
          selected => $end_month,
          list => [ map { $_, LJ::Lang::month_long($_) } 1..12 ] ) . " ";

    $ret .= $class->html_text
        ( name => 'day_end',
          size => 2,
          maxlength => 2,
          value => $end_day ) . " ";

    $ret .= $class->html_text
        ( name => 'year_end',
          size => 4,
          maxlength => 4,
          value => $end_year ) . " @ 11:59 PM</td></tr>";

    $ret .= "<tr><td valign='top'>Question:</td><td>";
    $ret .= $class->html_textarea
        ( name => 'text',
          raw => 5,
          cols => 30,
          wrap => 'soft',
          value => $text ) . "<br /><small>HTML allowed</small></td></tr>";

    $ret .= "<tr><td valign='top'>Entry Tags (optional):</td><td>";
    $ret .= $class->html_text
        ( name => 'tags',
          size => 30,
          value => $tags ) . "<br /><small>\"writer's block\" will always be included as a tag automatically</small></td></tr>";

    $ret .= "<tr><td>Image URL (optional):</td><td>";
    $ret .= $class->html_text
        ( name => 'img_url',
          size => 30,
          value => $img_url ) . "</td></tr>";

    $ret .= "<tr><td valign='top'>" . $class->ml('widget.addqotd.extratext') . "</td><td>";
    $ret .= $class->html_textarea
        ( name => 'extra_text',
          raw => 5,
          cols => 30,
          wrap => 'soft',
          value => $extra_text ) . "<br /><small>" . $class->ml('widget.addqotd.extratext.note') . "</small></td></tr>";

    $ret .= $class->html_hidden
        ( qid => $qid );

    $ret .= "<tr><td colspan='2' align='center'>";
    $ret .= $class->html_submit('Submit') . "</td></tr>";
    $ret .= "</table>";
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $time_start = DateTime->new
        ( year      => $post->{year_start}+0, 
          month     => $post->{month_start}+0, 
          day       => $post->{day_start}+0, 

          # Yes, this specific timezone
          time_zone => 'America/Los_Angeles' );

    my $time_end = DateTime->new
        ( year      => $post->{year_end}+0, 
          month     => $post->{month_end}+0, 
          day       => $post->{day_end}+0, 
          hour      => 23, 
          minute    => 59, 
          second    => 59, 

          # Yes, this specific timezone
          time_zone => 'America/Los_Angeles' );

    # Make sure the start time is before the end time
    if (DateTime->compare($time_start, $time_end) != -1) {
        die "Start time must be before end time";
    }

    # Make sure there's text
    die "No question specified." unless $post->{text};

    LJ::QotD->store_question (
         qid        => $post->{qid},
         time_start => $time_start->epoch,
         time_end   => $time_end->epoch,
         active     => 'Y',
         text       => $post->{text},
         tags       => LJ::QotD->add_default_tags($post->{tags}),
         img_url    => LJ::CleanHTML::canonical_url($post->{img_url}),
         extra_text => $post->{extra_text},
    );

    return;
}

1;
