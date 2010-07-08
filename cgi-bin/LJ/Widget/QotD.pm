package LJ::Widget::QotD;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::QotD LJ::PromoText );
use Encode qw(encode decode is_utf8);

sub need_res {
    return qw( js/widgets/qotd.js stc/widgets/qotd.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $skip = $opts{skip};
    my $domain = $opts{domain};
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();

    my $embed = $opts{embed};
    my $archive = $opts{archive};
    
    my @questions = $opts{question} || LJ::QotD->get_questions( user => $u, skip => $skip, domain => $domain );
    return "" unless @questions;

    # Navigation controlls
    unless ($opts{nocontrols}) {

        my ($month_short, $day, $num, $total) = LJ::QotD->question_info($questions[0], $u, $domain);

        #
        my $max = LJ::QotD->get_questions( user => $u, count => 1, all_filtered => 1, domain => $domain );

        $ret .= qq[<p class="i-qotd-nav">];
        if ($max > 1) {
            $ret .= qq[<i class="i-qotd-nav-first"></i><i class="i-qotd-nav-prev"></i>];
        } else {
            $ret .= qq[<i class="i-qotd-nav-first i-qotd-nav-first-dis"></i><i class="i-qotd-nav-prev i-qotd-nav-prev-dis"></i>];
        }
        $ret .= qq[<i class="i-qotd-nav-max">$max</i>];
        $ret .= qq[<span class="qotd-counter">$month_short, $day] . ($total > 1 ? "($num/$total)" : '') . qq[</span><i class="i-qotd-nav-next i-qotd-nav-next-dis"></i><i class="i-qotd-nav-last i-qotd-nav-last-dis"></i></p>];
    }

    $ret .= '<div class="b-qotd-question">';

    if ($embed) {
        $ret .= $class->qotd_display_embed( questions => \@questions, user => $u, %opts );
        $ret .= '</div>';
    } elsif ($archive) {
        $ret .= $class->qotd_display_archive( questions => \@questions, user => $u, %opts );
        $ret .= '</div>';
    } else {
        $ret .= $class->qotd_display( questions => \@questions, user => $u, %opts );
        $ret .= '</div>';
        # show promo on vertical pages
        $ret .= LJ::run_hook("promo_with_qotd", $opts{domain}) unless $opts{nopromo};
    }

    return $ret;

}

my %cyr_countries = map {lc} map { $_ => $_ } qw(AM AZ BY EE GE KG KZ LT LV MD RU TJ TM UA UZ);

sub community_name {
    my $class = shift;
    my $u = shift;

    $u = LJ::get_remote() unless $u;

    my $country;
    $country = lc $u->country if $u;
    $country = lc LJ::country_of_remote_ip() unless $country;

    return 'writersblock' .
        (exists($cyr_countries{$country}) ? '_ru' : '');
}

##
## Returns hash with question data
## 
sub get_random_question {
    my $class = shift;
    my %opts = @_;
 
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    my $domain = $opts{domain};
    my @questions = $opts{question} || LJ::QotD->get_questions( user => $u, domain => $domain );
    return unless @questions;
    return $class->_get_question_data( $questions[int rand scalar @questions], \%opts );
 }

# version suitable for embedding in journal entries
sub qotd_display_embed {
    my $class = shift;
    my %opts = @_;

    my $questions = $opts{questions} || [];

    my $ret;
    if (@$questions) {
        # table used for better inline display
        $ret .= "<div style='border: 1px solid #000; padding: 6px;'>";
        foreach my $q (@$questions) {
            my $d = $class->_get_question_data($q, \%opts);
            $ret .= "<p>$d->{text}</p><p style='font-size: 0.8em;'>$d->{from_text}$d->{between_text}$d->{extra_text}</p>";
            $ret .= "<p>$d->{answer_link} $d->{view_answers_link}$d->{impression_img}</p>";
            #$ret .= ": $d->{tracking_text} : ";
        }
        $ret .= "</div>";
    }

    return $ret;
}

# version suitable for the archive page
sub qotd_display_archive {
    my $class = shift;
    my %opts = @_;

    my $questions = $opts{questions} || [];

    my $ret;
    foreach my $q (@$questions) {
        my $d = $class->_get_question_data($q, \%opts);
        $ret .= "<p class='qotd-archive-item-date'>$d->{date}</p>";
        $ret .= "<p class='qotd-archive-item-question'>$d->{text}</p>";
        $ret .= "<p class='qotd-archive-item-answers'>$d->{answer_link} $d->{view_answers_link}$d->{impression_img}</p>";
    }

    return $ret;
}

sub qotd_display {
    my $class = shift;
    my %opts = @_;

    my $questions = $opts{questions} || [];
    my $remote = LJ::get_remote();
    my $community_name = $class->community_name($remote);

    my $ret;
    if (@$questions) {
        $ret .= "";
        foreach my $q (@$questions) {
            my $d = $class->_get_question_data($q, \%opts);
            my $subject = $d->{subject} || $q->{subject};
            my $extra_text = ($q->{extra_text} and not $opts{no_extra_text})
                                ? "<p>$q->{extra_text}</p>"
                                : "";
    
            $ret .=
                ($q->{img_url}
                    ? qq[<img src="$q->{img_url}" alt="$subject" title="$subject" class="qotd-pic" />]
                    : ''
                ) . qq[
                <div class="b-qotd-question-inner">
                    <h3>$subject</h3>
                    <p>$d->{text}<em class="i-qotd-by">$d->{from_text}</em></p>
                    $extra_text
                    <ul class="canyon">
                        <li class="canyon-section"><form action="$LJ::SITEROOT/update.bml" method="get" target="_top"><button type="submit">$d->{answer_text}</button><input type="hidden" name="qotd" value="$q->{qid}" /></form></li>
                        <li class="canyon-side">$d->{view_answers_link}</li>
                    </ul>
                </div>];
            #$ret .= qq[<div class="b-qotd-adv">$q->{extra_text}</div>] if $q->{is_special} eq 'Y';

        }
   }

    return $ret;
}

sub _format_question_text {
    my ($class, $text, $opts) = @_;
    my $target = $opts->{target};

    if ($opts->{nohtml}) {
        LJ::CleanHTML::clean_subject_all(\$text, { target => $target });
    } else {
        LJ::CleanHTML::clean_event(\$text, { target => $target });
    }
    $text =~ s/<br \/>|\r|\n/ /g if $opts->{nobr}; # Replace break lines with spaces.

    if ($opts->{trim} || $opts->{addbreaks}) {

        $text = decode('utf8', $text);

        my $break_len = $opts->{addbreaks};

        my $break_word = sub {
            my ($word) = @_;
            return $word unless $break_len;
            return $word if length($word) < $break_len;

            my @parts;
            foreach my $i (0..(length($word) / $break_len)) {
                push @parts, substr($word, $i * $break_len, $break_len);
            }

            return join(' ', @parts);
        };

        $text =~ s/(\w+)/$break_word->($1)/eg if $break_len;

        $text = encode('utf8', $text);
        $text = LJ::trim_at_word($text, $opts->{trim}) if $opts->{trim};

        $text =~ s/\s+/ /sg;

    }

    return $text;
}

sub _get_question_data {
    my $class = shift;
    my $q = shift;
    my $opts = shift;

    my $target = $opts->{target};
    
    # FIXME: this is a dirty hack because if this widget is put into a journal page
    #        as the first request of a given Apache, Apache::BML::cur_req will not
    #        be instantiated and we'll auto-vivify it with a call to BML::get_language()
    #        from within LJ::Lang.  We're working on a better fix.
    #
    #        -- Whitaker 2007/08/28

    # OK, it's time to try to fix it.
    #
    # We don't call dongerous BML::get_language() and get language code from remote
    # user's settings. This can be done even in not bml context. But in case of disaster,
    # we can revert this patch: get $text from "my $text = $q->{text};" without call $class->ml()
    # and remove $lncode and $ml_key variables.
    #
    #       -- Chernyshev 2009/01/21

    my $remote = LJ::get_remote();
    my $lncode = $opts->{lang};

    my $ml_key = $class->ml_key("$q->{qid}.text");
    my $text = $class->_format_question_text($class->ml($ml_key, undef, $lncode), $opts);

    my $subject = $class->ml( $class->ml_key("$q->{qid}.subject", undef, $lncode) );

    my $from_text = '';
    if ($q->{from_user}) {
        my $from_u = LJ::load_user($q->{from_user});
        $from_text = $class->ml('widget.qotd.entry.submittedby', {'user' => $from_u->ljuser_display({target => "_top"})}, $lncode)
            if $from_u;
    }

    my $extra_text;
    if ($q->{extra_text} && LJ::run_hook('show_qotd_extra_text', $remote)) {
        # use 'extra_trim' parameter if it is,
        # else use 'trim'.
        $opts->{trim} = $opts->{extra_trim} if exists $opts->{extra_trim} && $opts->{extra_trim};
        $extra_text = $class->_format_question_text($q->{extra_text}, $opts);
        LJ::CleanHTML::clean_event(\$extra_text, { target => $target });
    }

    my $between_text = $from_text && $extra_text ? "<br />" : "";

    my $qid = $q->{qid};
    my $view_answers_link = "";
    my $count = eval { LJ::QotD->get_count($qid) } || 0;
       $count .= "+" if $count >= $LJ::RECENT_QOTD_SIZE;
    $view_answers_link = "<a" . ($opts->{small_view_link} ? " class='small-view-link'" : '') .
            (($opts->{form_disabled} || $opts->{embed}) ? ' target="_blank"' : '') . # Open links on top, not in current frame.
            " href=\"$LJ::SITEROOT/misc/latestqotd.bml?qid=$qid\" class=\"more\" target=\"_top\">" .
                $class->ml('widget.qotd.viewanswers', {'total_count' => $count}, $lncode) .
            "</a>";

    my ($answer_link, $answer_url, $answer_text) = ("", "", "");
    unless ($opts->{no_answer_link}) {
        ($answer_link, $answer_url, $answer_text) = $class->answer_link
            ($q, user => $opts->{user},
                button_disabled => $opts->{form_disabled},
                button_as_link  => $opts->{button_as_link},
                form_disabled   => $opts->{form_disabled},
                embed           => $opts->{embed},
                lang            => $lncode);
    }

    my $impression_img = $class->impression_img($q);

    my $date = '';
    if ($q->{time_start}) {
        $date = DateTime
            -> from_epoch( epoch => $q->{time_start}, time_zone => 'America/Los_Angeles' )
            -> strftime("%B %e, %Y");
    }
    
    return {
        subject         => $subject,
        text            => $text,
        from_text       => $from_text,
        extra_text      => $extra_text,
        between_text    => $between_text,
        view_answers_link       => $view_answers_link,
        answer_link     => $answer_link,
        answer_url      => $answer_url,
        answer_text     => $answer_text,
        answers_url     => $class->answers_url($q, $opts),
        impression_img  => $impression_img,
        date            => $date,
        tracking_text   => LJ::run_hook("qotd_tracking_text", $q),
    };
}


sub answer_link {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $url = $class->answer_url($question, user => $opts{user});
    my $txt = LJ::run_hook("qotd_answer_txt", $opts{user}) || $class->ml('widget.qotd.answer', undef, $opts{lang});
    my $dis = $opts{button_disabled} ? "disabled='disabled'" : "";
    my $onclick = qq{onclick="document.location.href='$url'"};
    my $target = (($opts{form_disabled} || $opts{embed}) ? ' target="_top"' : '');

    # if button is disabled, don't attach an onclick
    my $extra = $dis ? $dis : $onclick;
    my $answer_link = $opts{button_as_link} ?
        qq{<a href=\"$url\"$target>$txt</a>} :
        qq{<input type="button" value="$txt" $extra />};

    
    return (wantarray) ? ($answer_link, $url, $txt) : $answer_link;
}

sub answer_url {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    return "$LJ::SITEROOT/update.bml?qotd=$question->{qid}";
}

sub answers_url {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    return "$LJ::SITEROOT/misc/latestqotd.bml?qotd=$question->{qid}";
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
    my $lncode = shift || $LJ::DEFAULT_LANG;

    return qq{<lj-template name="qotd" id="$question->{qid}" lang="$lncode" />};
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

sub impression_img {
    my $class = shift;
    my $question = shift;

    my $impression_url;
    if ($question->{impression_url}) {
        $impression_url = LJ::PromoText->parse_url( qid => $question->{qid}, url => $question->{impression_url} );
    }

    return $impression_url && LJ::run_hook("should_see_special_content", LJ::get_remote()) ? "<img src=\"$impression_url\" border='0' width='1' height='1' alt='' />" : "";
}

sub questions_exist_for_user {
    my $class = shift;
    my %opts = @_;

    my $skip = $opts{skip};
    my $domain = $opts{domain};
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();

    my @questions = LJ::QotD->get_questions( user => $u, skip => $skip, domain => $domain );

    return scalar @questions ? 1 : 0;
}

1;
