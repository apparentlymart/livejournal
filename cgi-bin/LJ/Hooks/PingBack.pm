package LJ::Hooks::PingBack;
use strict;
use Class::Autouse qw (LJ::PingBack);

#
LJ::register_hook("add_extra_options_to_manage_comments", sub {
    my $u = shift;

    return; # Disable user-specific pingback options
            # and Enable pingback by default

=head
    return unless LJ::PingBack->has_user_pingback($u);

    ## Option value 'L' (Livejournal only) is removed, it means 'O' (Open) now
    my $selected_value = $u->prop('pingback');
    $selected_value = 'D' unless $selected_value =~ /^[OLD]$/;
    $selected_value = 'O' if $selected_value eq 'L';
    
    # PingBack options
    my $ret = '';
    $ret .= "<tr><td class='field_name'>" . BML::ml('.pingback') . "</td>\n<td>";
    $ret .= BML::ml('.pingback.process') . "&nbsp;";
    $ret .= LJ::html_select({ 'name' => 'pingback', 'selected' => $selected_value },
                              "O" => BML::ml(".pingback.option.open"),
                              "D" => BML::ml(".pingback.option.disabled"),
                            );
    $ret .= "</td></tr>\n";
    return $ret;
=cut

});

#
LJ::register_hook("process_extra_options_for_manage_comments", sub {
    my $u    = shift;
    my $POST = shift;

    return; # Disable user-specific pingback options
            # and Enable pingback by default

    return unless LJ::PingBack->has_user_pingback($u);

    $POST->{'pingback'} = "D" unless $POST->{'pingback'}  =~ /^[OLD]$/;
    return 'pingback';

});



# Draw widget with event's pingback option selector
LJ::register_hook("add_extra_entryform_fields", sub {
    my $args     = shift;
    my $tabindex = $args->{tabindex};
    my $opts     = $args->{opts};

    return if $LJ::DISABLED{'pingback'};
    return if $opts->{remote} and
              not LJ::PingBack->has_user_pingback($opts->{remote});
    
    return; # Disable user-specific pingback options
            # and Enable pingback by default
=head
    # PINGBACK widget
    return "
    <p class='pkg'>
        <span class='inputgroup-right'>
        <label for='prop_pingback' class='left options'>" . BML::ml('entryform.pingback') . "</label>
        " . LJ::html_select({ 'name'     => 'prop_pingback', 
                              'id'       => 'prop_pingback',
                              'class'    => 'select',
                              'selected' => $opts->{'prop_pingback'},
                              'tabindex' => $tabindex->(),
                              }, 
                              { value => "J", text => BML::ml("pingback.option.journal_default") },
                              { value => "O", text => BML::ml("pingback.option.open") },
                              { value => "D", text => BML::ml("pingback.option.disabled") },
                              ) . "
        " . LJ::help_icon_html("pingback_faq", "", " ") . "
        </span>
    </p>
    ";
=cut

});

# Fetch pingback's option from POST data
LJ::register_hook("decode_entry_form", sub {
    my ($POST, $req) = @_;
    
    return; # Disable user-specific pingback options
            # and Enable pingback by default

    #$req->{prop_pingback} = $POST->{prop_pingback};
    
});

# Process event's pingback option for new entry
LJ::register_hook("postpost", sub {
    my $args     = shift;
    my $security = $args->{security};
    my $entry    = $args->{entry};
    my $journal  = $args->{journal};

    return unless LJ::PingBack->has_user_pingback($journal);

    # check security
    return if $security ne 'public';

=head
    # define pingback prop value
    my $prop_pingback = $args->{props}->{pingback};
    if ($prop_pingback eq 'J'){ 
        # use journal's default
        $args->{entry}->set_prop('pingback' => undef); # do not populate db with "(J)ournal default" value.
        $prop_pingback = $journal->prop('pingback');
    }

    return if $prop_pingback eq 'D'  # pingback is strictly disabled 
              or not $prop_pingback; # or not enabled.
=cut
    my $prop_pingback = 'O'; # Open
    #
    LJ::PingBack->notify(
        uri  => $entry->url,
        mode => $prop_pingback,
    );
    
});

# Process event's pingback option for updated entry
LJ::register_hook("editpost", sub {
    my $entry = shift;

    return unless LJ::PingBack->has_user_pingback($entry->journal);

    # check security
    return if $entry->security ne 'public';

=head
    # define pingback prop value
    my $prop_pingback = $entry->prop("pingback");
    if ($prop_pingback eq 'J'){ 
        # use journal's default
        $entry->set_prop('pingback' => undef); # do not populate db with "(J)ournal default" value.
        $prop_pingback = $entry->journal->prop('pingback');
    }

    return if $prop_pingback eq 'D'  # pingback is strictly disabled 
              or not $prop_pingback; # or not enabled.
=cut
    my $prop_pingback = 'O'; # Open

    #
    LJ::PingBack->notify(
        uri  => $entry->url,
        mode => $prop_pingback,
    );

});


#
LJ::register_hook("after_journal_content_created", sub {
    my $opts     = shift;
    my $html_ref = shift;

    my $entry = $opts->{ljentry};

    return; # External public endpoint is disabled
            # and there is no internal yet.

    return unless LJ::Request->is_inited;
    return unless $entry;
    return unless LJ::Request->notes("view") eq 'entry';
    return unless LJ::PingBack->has_user_pingback($entry->journal);

    if (LJ::PingBack->should_entry_recieve_pingback($entry)){
        LJ::Request->set_header_out('X-Pingback', $LJ::PINGBACK->{uri});
    }
    
});


1;
