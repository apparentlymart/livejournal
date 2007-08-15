package LJ::Widget::QotD;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::QotD );

sub need_res {
    return qw( js/widgets/qotd.js stc/widgets/qotd.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $skip = $opts{skip};
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();

    my @questions = $opts{question} || LJ::QotD->get_questions( user => $u, skip => $skip );

    my $title = LJ::run_hook("qotd_title", $u) || $class->ml('widget.qotd.title');
    $ret .= "<h2>$title";

    unless ($opts{nocontrols}) {
        $ret .= "<span class='qotd-controls'>";
        $ret .= "<img id='prev_questions' src='$LJ::IMGPREFIX/arrow-spotlight-prev.gif' alt='Previous' /> ";
        $ret .= "<img id='next_questions' src='$LJ::IMGPREFIX/arrow-spotlight-next.gif' alt='Next' />";
        $ret .= "</span>";
    }

    $ret .= "</h2>";
    $ret .= "<div id='all_questions'>" unless $opts{nocontrols};
    $ret .= $class->qotd_display( questions => \@questions, user => $u );
    $ret .= "</div>" unless $opts{nocontrols};

    return $ret;
}

sub qotd_display {
    my $class = shift;
    my %opts = @_;

    my $questions = $opts{questions} || [];
    my $remote = LJ::get_remote();

    my $ret;
    if (@$questions) {
        $ret .= "<div class='qotd pkg'>";
        foreach my $q (@$questions) {
            my $ml_key = $class->ml_key("$q->{qid}.text");
            my $text = $class->ml($ml_key);
            LJ::CleanHTML::clean_event(\$text);

            my $extra_text;
            if ($q->{extra_text} && LJ::run_hook('show_qotd_extra_text', $remote)) {
                $ml_key = $class->ml_key("$q->{qid}.extra_text");
                $extra_text = $class->ml($ml_key);
                LJ::CleanHTML::clean_event(\$extra_text);
            }

            my $from_text;
            if ($q->{from_user}) {
                my $from_u = LJ::load_user($q->{from_user});
                $from_text = $class->ml('widget.qotd.entry.submittedby', {'user' => $from_u->ljuser_display}) . "<br />"
                    if $from_u;
            }

            if ($q->{img_url}) {
                if ($q->{link_url}) {
                    $ret .= "<a href='$q->{link_url}'><img src='$q->{img_url}' class='qotd-img' alt='' /></a>";
                } else {
                    $ret .= "<img src='$q->{img_url}' class='qotd-img' alt='' />";
                }
            }
            $ret .= "<p>$text " . $class->answer_link($q, user => $opts{user}) . "</p>";
            my $suggest = "<a href='mailto:feedback\@livejournal.com'>Suggestions</a>";
            $ret .= "<p class='detail'><span class='suggestions'>$suggest</span>$from_text$extra_text&nbsp;</p>";
        }
        $ret .= "</div>";
    }

    return $ret;
}

sub answer_link {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $url = $class->answer_url($question, user => $opts{user});
    return "<a href=\"$url\" class='answer'>" . $class->ml('widget.qotd.answer') . "</a>";
}

sub answer_url {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    return "$LJ::SITEROOT/update.bml?qotd=$question->{qid}";
}

sub subject_text {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $ml_key = $class->ml_key("$question->{qid}.subject");
    my $subject = LJ::run_hook("qotd_subject", $opts{user}, $class->ml($ml_key)) ||
        $class->ml('widget.qotd.entry.subject', {'subject' => $class->ml($ml_key)});

    return $subject;
}

sub embed_text {
    my $class = shift;
    my $question = shift;

    return qq{<lj-template name="qotd" id="$question->{qid}"></lj-template>};
}    

sub event_text {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    my $ml_key = $class->ml_key("$question->{qid}.text");

    my $event = $class->ml($ml_key);
    my $from_user = $question->{from_user};
    my $extra_text = LJ::run_hook('show_qotd_extra_text', $remote) ? $question->{extra_text} : "";

    if ($from_user || $extra_text) {
        $event .= "\n<span style='font-size: smaller;'>";
        $event .= $class->ml('widget.qotd.entry.submittedby', {'user' => "<lj user='$from_user'>"}) if $from_user;
        $event .= "\n" if $from_user && $extra_text;
        $event .= $extra_text if $extra_text;
        $event .= "</span>";
    }

    return $event;
}

sub tags_text {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $tags = $question->{tags};

    return $tags;
}

1;
