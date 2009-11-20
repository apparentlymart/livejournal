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

    $event = LJ::Widget::QotD->render(
        user        => $u,
        embed       => 1,
        lang        => $lang, 
        nocontrols  => 1,
        question    => $question,
    );

    $opts->{event}      = $event;
    $opts->{journal}    = $entry->journal->ljuser_display();

    # add tag info for entries that have tags
    my $tags = '';
    if ($entry->tags) {
        $tags = LJ::Lang::get_text($lang, 'esn.tags', undef, {
            tags => join(', ', $entry->tags )
        });
    }
    $opts->{tags}       = $tags,
    $opts->{entry_url}  = $entry->url;

    return
        LJ::Lang::get_text($lang, 'esn.writersblock.email', undef, $opts) . "\n\n";
});

1;
