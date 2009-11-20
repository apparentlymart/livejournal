package LJ::Hooks::WritersBlock;
use strict;

use Class::Autouse qw(
    LJ::PersistentQueue
    LJ::QotD
    LJ::Widget::QotD
);

my @_ml_strings = (
    'esn.writersblock.subject',     # 'There is a new entry by [[poster]][[about]] in [[journal]]![[tags]]',
    'esn.writersblock.email',       # '[[who]] posted a new entry in [[journal]]!',
);

LJ::register_hook('esn_new_journal_post_subject_writersblock', sub {
    my $u           = shift;
    my $entry       = shift;

    return LJ::Lang::get_text(
        $u->prop('browselang'),
        'esn.writersblock.subject', undef,
        {
            title   => $entry->subject_raw(),
            journal => $entry->journal->display_username(),
        });
});

LJ::register_hook('esn_new_journal_post_email_writersblock', sub {
    my $u       = shift;
    my $entry   = shift;
    my $opts    = shift;

    # Precache text lines
    my $lang = $u->prop('browselang');
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings);

    my $event = $entry->event_raw();
    $event =~ /^<lj-template name="qotd" id="(\d+)" \/>$/;
    my $qid = $1;

    return '' unless $qid;

    my $question = LJ::QotD->get_single_question($qid);
    return '' unless $question;

    if ($opts->{is_html}) {
        $opts->{openlink}   = '<a href="' . $entry->url . '">';
        $opts->{closelink}  = '</a>';
        $opts->{event} = '<br /><br />'. LJ::Widget::QotD->render(
            user        => $u,
            embed       => 1,
            lang        => $lang, 
            nocontrols  => 1,
            question    => $question,
        ) . '<br />';
    } else {
        $opts->{openlink}   = '';
        $opts->{closelink}  = '';

        my $qotd = new LJ::Widget::QotD;
        my $ml_text;
        if ($question) {
            my $ml_key = $qotd->ml_key("$question->{qid}.text");
            my $ml_text = $qotd->ml($ml_key, undef, $lang);
            LJ::CleanHTML::clean_event(\$ml_text);
            $opts->{event} = $ml_text;
        }
    }

    return
        LJ::Lang::get_text($lang, 'esn.writersblock.email', undef, $opts) . "\n\n";
});

1;
