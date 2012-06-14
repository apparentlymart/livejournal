package LJ::Widget::EntryChooser;
use strict;
use warnings;

use base qw( LJ::Widget::Template );

sub need_res {
    qw(
        stc/widgets/entrychooser.css
        js/jquery/jquery.lj.editentriesmanager.js
    );
}

sub template_filename {
    return $ENV{'LJHOME'} . '/templates/Widgets/entry_chooser.tmpl';
}

sub prepare_template_params {
    my ( $class, $template, $opts ) = @_;

    my $entries = $opts->{'entries'};
    my $remote = LJ::get_remote();

    my @entries_display;

    foreach my $entry (@$entries) {
        my $repost_entry_obj;
        my $replacement_event_text;
        my $repost_url;
        my $removed;
        my $delete_real_attr_link;
        
        my $content =  { 'original_post_obj' => \$entry,
                         'event'             => \$replacement_event_text,
                         'removed'           => \$removed,
                         'repost_obj'        => \$repost_entry_obj, };

        # substute content of original post
        my $entry_reposted = LJ::Entry::Repost->substitute_content( $entry, $content );

        # can we show it?
        if ($entry_reposted && !$entry->visible_to($remote)) {
            $entry                  = $repost_entry_obj;
            $repost_url             = $entry->url;
            $replacement_event_text = $entry->event_raw;
            $repost_entry_obj       = undef;
        }

        my $entry_id = $entry->is_delayed ? $entry->delayedid : $entry->ditemid;
        my $entry_can_edit = 
            $entry->poster->equals($remote) &&
            ! $entry->journal->is_readonly &&
            ! $entry->poster->is_readonly;

        $entry_can_edit = 0 if $entry_reposted;

        my $poster_ljuser = $opts->{'show_posters'}
            ? $entry->poster->ljuser_display
            : '';
        $poster_ljuser = '' if $removed;

        my $entry_is_delayed = $entry->is_delayed;
        my $entry_is_sticky  = ($entry->is_sticky
                                    && LJ::is_enabled('sticky_entries'));

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
        my $usejournal = $entry->journal->username;
        $edit_link_base .= 'usejournal=' . $usejournal . '&';

        if ( $entry->is_delayed ) {
            $edit_link_base .= 'delayedid=' . $entry->delayedid . '&';
        } else {
            $edit_link_base .= 'itemid=' . $entry->ditemid . '&';
        }

        my $edit_link   = $edit_link_base . 'mode=edit';
        my $delete_link = $edit_link_base . 'mode=delete';

        my $delete_real_link;
        if ($repost_entry_obj && !$repost_entry_obj) {
            $delete_real_link = "$LJ::SITEROOT/editjournal.bml?" . 
                               'usejournal=' . $repost_entry_obj->journal->user . '&' .
                               'itemid=' . $repost_entry_obj->ditemid;
        } elsif ($removed) {
            $delete_real_attr_link = $entry->url;
        }

        my $entry_url =  $entry->url;
        my $entry_subject = $entry->subject_text;

        my $alldateparts;
        if ($entry->is_delayed) {
            $alldateparts = $entry->alldatepart;
        } else {
            my $eventtime = $repost_entry_obj ? $repost_entry_obj->eventtime_mysql : $entry->{'eventtime'};
            $eventtime ||= $entry->eventtime_mysql;
            $alldateparts = LJ::TimeUtil->alldatepart_s2($eventtime);
        }

        my ($year, $mon, $mday, $hour, $min) = split(/\D/, $alldateparts);
        my $monthlong = BML::ml(LJ::Lang::month_long_langcode($mon));

        my $datetext = $opts->{'scheduled'} || "";
        my $date_display = "$datetext $monthlong $mday, $year, $hour:$min";

        my $event_raw = $entry->is_delayed ? $entry->event : $entry->event_raw;
        my $entry_text_display = LJ::ehtml( LJ::durl( $event_raw ) );
        $entry_text_display =~ s{\n}{<br />}g;

        my $entry_taglist = '';
        if ( my @taglist = $entry->tags ) {
            $entry_taglist = join( ', ', @taglist );
        }

        my $final_entry_url = $repost_url ? $repost_url : $entry_url;
        $final_entry_url = '' if $removed;

        push @entries_display, {
            'entry_id'           => $entry_id,
            'entry_can_edit'     => $entry_can_edit,
            'poster_ljuser'      => $poster_ljuser,
            'entry_is_delayed'   => $entry_is_delayed,
            'entry_is_sticky'    => $entry_is_sticky,
            'entry_security'     => $entry_security,
            'edit_link'          => $edit_link,
            'delete_link'        => $delete_link,
            'entry_url'          => $final_entry_url,
            'entry_subject'      => $entry_subject,
            'date_display'       => $date_display,
            'entry_text_display' => $replacement_event_text ? $replacement_event_text :
                                                              $entry_text_display,
            'entry_taglist'      => $entry_taglist,
            'entry_reposted'     => $entry_reposted,
            'delete_real_link'   => $delete_real_link,
            'delete_real_attr_link' => $delete_real_attr_link,
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
