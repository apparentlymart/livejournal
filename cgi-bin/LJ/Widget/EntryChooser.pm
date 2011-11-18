package LJ::Widget::EntryChooser;
use strict;
use warnings;

use base qw( LJ::Widget::Template );

sub template_filename {
    return $ENV{'LJHOME'} . '/templates/Widgets/entry_chooser.tmpl';
}

sub prepare_template_params {
    my ( $class, $template, $opts ) = @_;

    my $entries = $opts->{'entries'};
    my $remote = LJ::get_remote();

    my @entries_display;

    foreach my $entry (@$entries) {
        my $entry_can_edit = 
            $entry->poster->equals($remote) &&
            ! $entry->journal->is_readonly &&
            ! $entry->poster->is_readonly;

        my $poster_ljuser = $opts->{'show_posters'}
            ? $entry->poster->ljuser_display
            : '';

        my $entry_is_delayed = $entry->is_delayed;
        my $entry_is_sticky  = $entry->is_sticky;

        ### security indicator
        my $entry_security = 'public';
        if ( $entry->security eq 'private' ) {
            $entry_security = 'private';
        } elsif ( $entry->security eq 'usemask' ) {
            if ( $entry->allowmask == 0 ) {
                $entry_security = 'private';
            } elsif ( $entry->allowmask > 1 ) {
                $entry_security = 'groups';
            } else {
                $entry_security = 'friends';
            }
        }

        my $edit_link_base = "$LJ::SITEROOT/editjournal.bml?";

        $edit_link_base .= 'usejournal=' . $entry->journal->username . '&';

        if ( $entry->is_delayed ) {
            $edit_link_base .= 'delayedid=' . $entry->delayedid . '&';
        } else {
            $edit_link_base .= 'itemid=' . $entry->ditemid . '&';
        }

        my $edit_link   = $edit_link_base . 'mode=edit';
        my $delete_link = $edit_link_base . 'mode=delete';

        my $entry_url     = $entry->url;
        my $entry_subject = $entry->subject_text;

        my $alldateparts;
        if ($entry->is_delayed) {
            $alldateparts = $entry->alldatepart;
        } else {
            $alldateparts = LJ::TimeUtil->alldatepart_s2($entry->{'eventtime'});
        }
        my ($year, $mon, $mday, $hour, $min) = split(/\D/, $alldateparts);
        my $monthlong = BML::ml(LJ::Lang::month_long_langcode($mon));

        my $date_display = "$monthlong $mday, $year, $hour:$min";

        my $entry_text_display =
            LJ::ehtml( LJ::durl( $entry->event_raw ) );
        $entry_text_display =~ s{\n}{<br />}g;

        my $entry_taglist = '';
        if ( my @taglist = $entry->tags ) {
            $entry_taglist = join( ', ', @taglist );
        }

        push @entries_display, {
            'entry_can_edit'     => $entry_can_edit,
            'poster_ljuser'      => $poster_ljuser,
            'entry_is_delayed'   => $entry_is_delayed,
            'entry_is_sticky'    => $entry_is_sticky,
            'entry_security'     => $entry_security,
            'edit_link'          => $edit_link,
            'delete_link'        => $delete_link,
            'entry_url'          => $entry_url,
            'entry_subject'      => $entry_subject,
            'date_display'       => $date_display,
            'entry_text_display' => $entry_text_display,
            'entry_taglist'      => $entry_taglist,
        };
    }

    $template->param(
        'link_prev' => $opts->{'link_prev'},
        'link_next' => $opts->{'link_next'},
        'entries'   => \@entries_display,
        'adhtml'    => $opts->{'adhtml'},
    );
}

1;
