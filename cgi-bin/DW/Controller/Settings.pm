#!/usr/bin/perl
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.

package DW::Controller::Settings;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller;
use DW::FormErrors;

=head1 NAME

DW::Controller::Settings - Controller for settings/settings-related pages

=cut

DW::Routing->register_string( "/accountstatus", \&account_status_handler, app => 1 );

sub account_status_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $remote = $rv->{remote};
    my $get = $r->get_args;

    my $authas = $get->{authas} || $remote->{user};
    my $u = LJ::get_authas_user( $authas );
    return error_ml( 'error.invalidauth' ) unless $u;

    my $ml_scope = "/settings/accountstatus.tt";
    my @statusvis_options = $u->is_suspended
                                ? ( 'S' => LJ::Lang::ml( "$ml_scope.journalstatus.select.suspended" ) )
                                : ( 'V' => LJ::Lang::ml( "$ml_scope.journalstatus.select.activated" ),
                                    'D' => LJ::Lang::ml( "$ml_scope.journalstatus.select.deleted" ),
                                );
    my %statusvis_map = @statusvis_options;

    my $errors = DW::FormErrors->new;

    # TODO: this feels like a misuse of DW::FormErrors. Make a new class?
    my $messages = DW::FormErrors->new;
    my $warnings = DW::FormErrors->new;

    my $post;
    if ( $r->did_post && LJ::check_referer( '/accountstatus' ) ) {
        $post = $r->post_args;
        my $new_statusvis  = $post->{statusvis};

        # are they suspended?
        $errors->add( "", ".error.nochange.suspend" )
            if $u->is_suspended;

        # are they expunged?
        $errors->add( "", '.error.nochange.expunged' )
            if $u->is_expunged;

        # invalid statusvis
        $errors->add( "", '.error.invalid' )
            unless $new_statusvis eq 'D' || $new_statusvis eq 'V';

        my $did_change = $u->statusvis ne $new_statusvis;
        # no need to change?
        $messages->add( "", $u->is_community ? '.message.nochange.comm' : '.message.nochange', { statusvis => $statusvis_map{$new_statusvis} } )
            unless $did_change;

        if ( ! $errors->exist && $did_change  ) {
            my $res = 0;

            my $ip = $r->get_remote_ip;

            my @date = localtime( time );
            my $date = sprintf( "%02d:%02d %02d/%02d/%04d", @date[2,1], $date[3], $date[4]+1, $date[5]+1900 );

            if ( $new_statusvis eq 'D' ) {

                $res = $u->set_deleted;

                $u->set_prop( delete_reason => $post->{reason} || "" );

                if( $res ) {
                    # sending ESN status was changed
                    LJ::Event::SecurityAttributeChanged->new($u, {
                        action   => 'account_deleted',
                        ip       => $ip,
                        datetime => $date,
                    })->fire;
                }
            } elsif ( $new_statusvis eq 'V' ) {
                ## Restore previous statusvis of journal. It may be different
                ## from 'V', it may be read-only, or locked, or whatever.
                my @previous_status = grep { $_ ne 'D' } $u->get_previous_statusvis;
                my $new_status = $previous_status[0] || 'V';
                my $method = {
                    V => 'set_visible',
                    L => 'set_locked',
                    M => 'set_memorial',
                    O => 'set_readonly',
                    R => 'set_renamed',
                }->{$new_status};
                $errors->add_string( "", "Can't set status '" . LJ::ehtml( $new_status ) . "'" ) unless $method;

                unless ( $errors->exist ) {
                    $res = $u->$method;

                    $u->set_prop( delete_reason => "" );

                    if( $res ) {
                        LJ::Event::SecurityAttributeChanged->new($u ,  {
                            action   => 'account_activated',
                            ip       => $ip,
                            datetime => $date,
                        })->fire;

                        $did_change = 1;
                    }
                }
            }

            # error updating?
            $errors->add( "", ".error.db" ) unless $res;

            unless ( $errors->exist ) {
                $messages->add( "", $u->is_community ? '.message.success.comm' : '.message.success', { statusvis => $statusvis_map{$new_statusvis} } );

                if ( $new_statusvis eq 'D' ) {
                    $messages->add( "", $u->is_community ? ".message.deleted.comm" : ".message.deleted2", { sitenameshort => $LJ::SITENAMESHORT } );

                    # are they leaving any community admin-less?
                    if ( $u->is_person ) {
                        my $cids = LJ::load_rel_target( $remote, "A" );
                        my @warn_comm_ids;

                        if ( $cids ) {
                            # verify there are visible maintainers for each community
                            foreach my $cid ( @$cids ) {
                                push @warn_comm_ids, $cid
                                    unless
                                        grep { $_->is_visible }
                                        values %{ LJ::load_userids(
                                                      @{ LJ::load_rel_user( $cid, 'A' ) }
                                                  ) };
                            }

                            # and if not, warn them about it
                            if ( @warn_comm_ids ) {
                                my $commlist = '<ul>';
                                $commlist .= '<li>' . $_->ljuser_display . '</li>'
                                    foreach values %{ LJ::load_userids( @warn_comm_ids ) };
                                $commlist .= '</ul>';

                                $warnings->add( "", '.message.noothermaintainer', {
                                    commlist => $commlist,
                                    manage_url => LJ::create_url( "/communities/list" ),
                                    pagetitle => LJ::Lang::ml( '/communities/list.tt.title' ),
                                } );
                            }
                        }

                    }
                }
            }
        }
    }

    my $vars = {
        form_url => LJ::create_url( undef, keep_args => [ 'authas' ] ),
        extra_delete_text => LJ::Hooks::run_hook( "accountstatus_delete_text", $u ),
        statusvis_options => \@statusvis_options,

        u => $u,
        delete_reason => $u->prop( 'delete_reason' ),

        errors => $errors,
        messages => $messages,
        warnings => $warnings,
        formdata => $post,
    };
    return DW::Template->render_template( 'settings/accountstatus.tt', $vars );
}

1;