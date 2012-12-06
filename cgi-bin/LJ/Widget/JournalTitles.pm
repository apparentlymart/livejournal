package LJ::Widget::JournalTitles;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub ajax { 1 }
sub authas { 1 }
sub need_res { qw(
        stc/widgets/journaltitles.css
        js/jquery/customize/jquery.lj.journalTitles.js
    )
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $no_theme_chooser = $opts{'no_theme_chooser'} || 0;

    my $template = LJ::HTML::Template->new(
        { 'use_expr' => 1 },
        'filename' => $ENV{'LJHOME'} . '/templates/Widgets/journal_titles.tmpl',
    );

    my @titles_out;
    foreach my $title ( qw( journaltitle journalsubtitle friendspagetitle ) ) {
        next if $title eq 'friendspagetitle' &&
            ! LJ::is_enabled('friendsfeed_optout');

        push @titles_out, {
            'id' => $title,
            'name' => LJ::Lang::ml("widget.journaltitles.$title"),
            'value' => $u->prop($title),
        };
    }

    $template->param(
        'helpicon'         => LJ::help_icon('journal_titles') || '',
        'form_auth'        => LJ::form_auth() || '',
        'no_theme_chooser' => $no_theme_chooser,
        'titles'           => \@titles_out,
    );

    return $template->output;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $eff_val = LJ::text_trim($post->{title_value}, 0, LJ::std_max_length());
    $eff_val = "" unless $eff_val;
    $u->set_prop($post->{which_title}, $eff_val);

    return;
}

1;
