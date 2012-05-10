#
# LiveJournal entry object.
#
# Just framing right now, not much to see here!
#

package LJ::Entry;
use strict;
use vars qw/ $AUTOLOAD /;
use Carp qw/ croak /;
use LJ::TimeUtil;

# internal fields:
#
#    u: object, always present
#    anum:    lazily loaded, either by ctor or _loaded_row
#    ditemid: lazily loaded
#    jitemid: always present
#    props:   hashref of props,  loaded if _loaded_props
#    subject: text of subject,   loaded if _loaded_text
#    event:   text of log event, loaded if _loaded_text
#    subject_orig: text of subject without transcoding,   present if unknown8bit
#    event_orig:   text of log event without transcoding, present if unknown8bit

#    eventtime:  mysql datetime of event, loaded if _loaded_row
#    logtime:    mysql datetime of event, loaded if _loaded_row
#    security:   "public", "private", "usemask", loaded if _loaded_row
#    allowmask:  if _loaded_row
#    posterid:   if _loaded_row
#    comments:   arrayref of comment objects on this entry

#    _loaded_text:     loaded subject/text
#    _loaded_row:      loaded log2 row
#    _loaded_props:    loaded props
#    _loaded_comments: loaded comments

my %singletons = (); # journalid->jitemid->singleton
my %loaded_comments = (); # journalid->jitemid->[comment, comment, ...]

sub reset_singletons {
    %singletons = ();
    %loaded_comments = ();
}

# <LJFUNC>
# name: LJ::Entry::new
# class: entry
# des: Gets a journal entry.
# args: uuserid, opts
# des-uuserid: A user id or user object ($u ) to load the entry for.
# des-opts: Hash of optional keypairs.
#           'jitemid' => a journal itemid (no anum)
#           'ditemid' => display itemid (a jitemid * 256 + anum)
#           'anum'    => the id passed was an ditemid, use the anum
#                        to create a proper jitemid.
# returns: A new LJ::Entry object.  undef on failure.
# </LJFUNC>
sub new
{
    my $class = shift;
    my $self  = bless {};

    my $uuserid = shift;
    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;
    my $row  = delete $opts{row};

    croak("can't supply both anum and ditemid")
        if defined $opts{anum} && defined $opts{ditemid};

    croak("can't supply both itemid and ditemid")
        if defined $opts{ditemid} && defined $opts{jitemid};

    # FIXME: don't store $u in here, or at least call LJ::load_userids() on all singletons
    #        if LJ::want_user() would have been called
    $self->{u}       = LJ::want_user($uuserid) or croak("invalid user/userid parameter: $uuserid");

    $self->{anum}    = delete $opts{anum};
    $self->{ditemid} = delete $opts{ditemid};
    $self->{jitemid} = delete $opts{jitemid};
    $self->{rlogtime}= delete $opts{rlogtime};

    # make arguments numeric
    for my $f (qw(ditemid jitemid anum)) {
        $self->{$f} = int($self->{$f}) if defined $self->{$f};
    }

    croak("need to supply either a jitemid or ditemid")
        unless defined $self->{ditemid} || defined $self->{jitemid};

    croak("Unknown parameters: " . join(", ", keys %opts))
        if %opts;

    if ( $self->{ditemid} ) {
        $self->{anum}    = $self->{ditemid} & 255;
        $self->{jitemid} = int($self->{ditemid} / 256);
    }

    # do we have a singleton for this entry?
    my $journalid = $self->{u}->{userid};
    my $jitemid   = $self->{jitemid};

    $singletons{$journalid} ||= {};
    return $singletons{$journalid}->{$jitemid}
        if $singletons{$journalid}->{$jitemid};

    # no singleton, will load row
    my $anum = $self->{anum}; # caller supplied anum
    if ($row){
        $self->absorb_row($row);
    } else {
        __PACKAGE__->preload_rows([ $self ]);
    }
    return undef if $anum and $anum != $self->{anum}; # incorrect anum -> 'no such entry'

    $self->{ditemid}  = $self->{jitemid} * 256 + $self->{anum};

    # save the singleton if it doesn't exist
    $singletons{$journalid}->{$jitemid} = $self;

    return $self;
}

# sometimes item hashes don't have a journalid arg.
# in those cases call as ($u, $item) and the $u will
# be used
sub new_from_item_hash {
    my $class = shift;
    my $arg1 = shift;
    my $item = shift;
    if (LJ::isu($arg1)) {
        $item->{journalid} ||= $arg1->id;
    } else {
        $item = $arg1;
    }

    # some item hashes have 'jitemid', others have 'itemid'
    $item->{jitemid} ||= $item->{itemid};

    croak "invalid item hash"
        unless $item && ref $item;
    croak "no journalid in item hash"
        unless $item->{journalid};
    croak "no entry information in item hash"
        unless $item->{ditemid} || ($item->{jitemid} && defined($item->{anum}));

    my $entry;

    # have a ditemid only?  no problem.
    if ($item->{ditemid}) {
        $entry = LJ::Entry->new($item->{journalid},
                                ditemid => $item->{ditemid});

    # jitemid/anum is okay too
    } elsif ($item->{jitemid} && defined($item->{anum})) {
        $entry = LJ::Entry->new($item->{journalid},
                                jitemid => $item->{jitemid},
                                anum    => $item->{anum});
    }

    return $entry;
}

sub is_delayed {
    my ($class) = @_;
    return 0;
}

sub delayedid { 
    my ($class) = @_;
    return 0;
}


sub new_from_url {
    my ($class, $url) = @_;

    if ($url =~ m!(.+)/(\d+)\.html!) {
        my $u = LJ::User->new_from_url($1) or return undef;
        return LJ::Entry->new($u, ditemid => $2);
    }

    return undef;
}

sub new_from_row {
    my $class = shift;
    my %row   = @_;

    my $journalu = LJ::load_userid($row{journalid});
    my $self = $class->new($journalu, 
                           jitemid => $row{jitemid},
                           row     => \%row, ## absorb row in the constructor.
                           );
    return $self;
}

# returns true if entry currently exists.  (it's possible for a given
# $u, to make a fake jitemid and that'd be a valid skeleton LJ::Entry
# object, even though that jitemid hasn't been created yet, or was
# previously deleted)
sub valid {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{_loaded_row};
}

sub jitemid {
    my $self = shift;
    return $self->{jitemid};
}

sub ditemid {
    my $self = shift;
    return $self->{ditemid} ||= (($self->{jitemid} * 256) + $self->anum);
}

sub reply_url {
    my $self = shift;
    return $self->url(mode => 'reply');
}

# returns permalink url
sub url {
    my $self = shift;
    my %opts = @_;
    my %args = %opts; # used later
    my $u    = $self->{u};
    my $view   = delete $opts{view};
    my $anchor = delete $opts{anchor};
    my $mode   = delete $opts{mode};
    my $style  = delete $opts{style};
    my $nc     = delete $opts{nc};

    croak "Unknown args passed to url: " . join(",", keys %opts)
        if %opts;

    my $override = LJ::run_hook("entry_permalink_override", $self, %opts);
    return $override if $override;

    $self->{'url'} ||= $u->journal_base . "/" . $self->ditemid . ".html";
    my $url = $self->{'url'};

    delete $args{anchor};
    if (%args) {
        $url .= "?";
        $url .= LJ::encode_url_string(\%args);
    }
    $url .= "#$anchor" if $anchor;
    return $url;
}

sub mobile_url {
    my $self = shift;
    my $u = $self->{u};    
    return "http://m.$LJ::DOMAIN/read/user/".$u->user.'/'. $self->ditemid;
}

sub anum {
    my $self = shift;
    return $self->{anum} if defined $self->{anum};
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{anum} if defined $self->{anum};
    croak("couldn't retrieve anum for entry");
}

# method:
#   $entry->correct_anum
#   $entry->correct_anum($given_anum)
# if no given anum, gets it from the provided ditemid to constructor
sub correct_anum {
    my $self = shift;
    my $given = defined $_[0] ? int(shift) : $self->{anum};
    return 0 unless $self->valid;
    return 0 unless defined $self->{anum} && defined $given;
    return $self->{anum} == $given;
}

# returns LJ::User object for the poster of this entry
sub poster {
    my $self = shift;
    return LJ::load_userid($self->posterid);
}

sub posterid {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{posterid};
}

sub journalid {
    my $self = shift;
    return $self->{u}{userid};
}

sub journal {
    my $self = shift;
    return $self->{u};
}

sub eventtime_mysql {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{eventtime}; 
}

sub logtime_mysql {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{logtime};
}

sub logtime_unix {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return LJ::TimeUtil->mysqldate_to_time($self->{logtime}, 1);
}

sub modtime_unix {
    my $self = shift;
    __PACKAGE__->preload_rows ([ $self ]) unless $self->{_loaded_row};
    __PACKAGE__->preload_props([ $self ]) unless $self->{_loaded_props};

    return LJ::TimeUtil->mysqldate_to_time($self->{logtime}, 1);
}

sub security {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{security};
}

sub is_public {
    my ($self) = @_;

    return $self->security eq 'public';
}

sub allowmask {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{allowmask};
}

sub preload {
    my ($class, $entlist) = @_;
    $class->preload_rows($entlist);
    $class->preload_props($entlist);
    # TODO: $class->preload_text($entlist);
}

# class method:
sub preload_rows {
    my ($class, $entlist) = @_;
    foreach my $en (@$entlist) {
        next if $en->{_loaded_row};

        my $lg = LJ::get_log2_row($en->{u}, $en->{jitemid});
        next unless $lg;

        # absorb row into given LJ::Entry object
        $en->absorb_row($lg);
    }
}

sub absorb_row {
    my ($self, $row) = @_;

    $self->{$_} = $row->{$_} foreach (qw(allowmask posterid eventtime logtime security anum));
    $self->{_loaded_row} = 1;
}

# class method:
# LJ::Entry->preload_props(\@entries);
# @entries - array of LJ::Entry objects
#
# See also instance method '_load_props'
# 
sub preload_props {
    my ($class, $entlist) = @_;
    
    ## %needed_to_load: userid --> [LJ::Entry, LJ::Entry, ... ] 
    ## %users:          userid --> LJ::User
    my (%needed_to_load, %users); 
    
    foreach my $en (@$entlist) {
        next if $en->{_loaded_props};
        my $u = $en->{u};
        my $userid = $u->{userid};
        push @{ $needed_to_load{$userid} }, $en;
        $users{$userid}= $u;
    }
    while (my ($userid, $u) = each %users) {
        my $props = {};
        my @jitemids = map {$_->{jitemid}} @{ $needed_to_load{$userid} };
        LJ::load_log_props2($u, \@jitemids, $props);
        foreach my $en (@{ $needed_to_load{$userid} }) {
            $en->{props} = $props->{ $en->{jitemid} };
            $en->{_loaded_props} = 1;
        }
    }
}

# returns array of tags for this post
sub tags {
    my $self = shift;

    my $taginfo = LJ::Tags::get_logtags($self->journal, $self->jitemid);
    return () unless $taginfo;

    my $entry_taginfo = $taginfo->{$self->jitemid};
    return () unless $entry_taginfo;

    return values %$entry_taginfo;
}

sub handle_prefetched_text {
    my ( $self, $subject, $event ) = @_;

    $self->{subject}      = $subject;
    $self->{event}        = $event;

    if ($self->prop("unknown8bit")) {
        # save the old ones away, so we can get back at them if we really need to
        $self->{subject_orig}  = $self->{subject};
        $self->{event_orig}    = $self->{event};

        # FIXME: really convert all the props?  what if we binary-pack some in the future?
        LJ::item_toutf8($self->{u}, \$self->{'subject'}, \$self->{'event'}, $self->{props});
    }

    $self->{_loaded_text} = 1;
}

sub handle_prefetched_tags {
    my ( $self, $tags ) = @_;

    $self->{tags} = $tags;
    $self->{_loaded_tags} = 1;
}

# returns true if loaded, zero if not.
# also sets _loaded_text and subject and event.
sub _load_text {
    my $self = shift;
    return 1 if $self->{_loaded_text};

    my $ret = LJ::get_logtext2($self->{'u'}, $self->{'jitemid'});
    my $lt = $ret->{$self->{jitemid}};
    return 0 unless $lt;

    $self->handle_prefetched_text( $lt->[0], $lt->[1] );

    return 1;
}

sub prop {
    my ($self, $prop) = @_;
    $self->_load_props unless $self->{_loaded_props};

    return $self->{props} unless $prop;
    return $self->{props}{$prop};
}

sub props {
    my ($self, $prop) = @_;
    $self->_load_props unless $self->{_loaded_props};

    return $self->{props} || {};
}

sub handle_prefetched_props {
    my ($self, $props) = @_;

    $self->{props} = $props;
    $self->{_loaded_props} = 1;
}

sub _load_props {
    my $self = shift;

    return 1 if $self->{_loaded_props};

    my $props = {};
    LJ::load_log_props2($self->{u}, [ $self->jitemid ], $props);
    $self->handle_prefetched_props($props->{$self->jitemid});

    return 1;
}

sub set_prop {
    my $self = shift;
    my $prop = shift;
    my $val = shift;

    LJ::set_logprop($self->journal, $self->jitemid, { $prop => $val });
    $self->{props}{$prop} = $val;
    return 1;
}


# called automatically on $event->comments
# returns the same data as LJ::get_talk_data, with the addition
# of 'subject' and 'event' keys.
sub _load_comments
{
    my $self = shift;
    return 1 if $self->{_loaded_comments};

    # need to load using talklib API
    my $comment_ref = LJ::Talk::get_talk_data($self->journal, 'L', $self->jitemid);
    die "unable to load comment data for entry"
        unless ref $comment_ref;

    # instantiate LJ::Comment singletons and set them on our $self
    # -- members were filled in to the LJ::Comment singleton during the talklib call,
    #    so we'll just re-instantiate here and rely on the fact that the singletons
    #    already exist and have db rows absorbed into them
    $self->set_comment_list
        ( map { LJ::Comment->new( $self->journal, jtalkid => $_->{talkid}) }
          values %$comment_ref );

    return $self;
}

sub comment_list {
    my $self = shift;
    $self->_load_comments unless $self->{_loaded_comments};
    return @{ $loaded_comments{ $self->journalid }->{ $self->jitemid } || [] };
}

sub set_comment_list {
    my $self = shift;

    $loaded_comments{ $self->journalid }->{ $self->jitemid } = \@_;
    $self->{_loaded_comments} = 1;

    return 1;
}

sub reply_count_memkey {
    my ($u, $nodeid) = @_;
    my $userid = LJ::want_userid($u);
    return [$userid, "rp:$userid:$nodeid"];
}

sub reply_count {
    my $self = shift;
    my $rc = $self->prop('replycount');
    return $rc if defined $rc;
    return LJ::Talk::get_replycount($self->journal, $self->jitemid);
}

# returns "Leave a comment", "1 comment", "2 comments" etc
sub comment_text {
    my $self = shift;

    my $comments;

    my $comment_count = $self->reply_count;
    if ($comment_count) {
        $comments = $comment_count == 1 ? "1 Comment" : "$comment_count Comments";
    } else {
        $comments = "Leave a comment";
    }

    return $comments;
}


# used in comment notification email headers
sub email_messageid {
    my $self = shift;
    return "<" . join("-", "entry", $self->journal->id, $self->ditemid) . "\@$LJ::DOMAIN>";
}

sub atom_id {
    my $self = shift;

    my $u       = $self->{u};
    my $ditemid = $self->ditemid;

    return "urn:lj:$LJ::DOMAIN:atom1:$u->{user}:$ditemid";
}

# returns an XML::Atom::Entry object for a feed
sub atom_entry {
    my $self = shift;
    my $opts = shift || {};  # synlevel ("full"), apilinks (bool)

    my $entry     = XML::Atom::Entry->new();
    my $entry_xml = $entry->{doc};

    my $u       = $self->{u};
    my $ditemid = $self->ditemid;
    my $jitemid = $self->{jitemid};

    # AtomAPI interface path
    my $api = $opts->{'apilinks'} ? "$LJ::SITEROOT/interface/atom" :
                                    "$LJ::SITEROOT/users/$u->{user}/data/atom";

    $entry->title($self->subject_text);
    $entry->id($self->atom_id);

    my $author = XML::Atom::Person->new();
    $author->name($self->poster->{name});
    $entry->author($author);

    my $make_link = sub {
        my ( $rel, $type, $href, $title ) = @_;
        my $link = XML::Atom::Link->new;
        $link->rel($rel);
        $link->type($type);
        $link->href($href);
        $link->title($title) if $title;
        return $link;
    };

    $entry->add_link($make_link->( 'alternate', 'text/html', $self->url));
    $entry->add_link($make_link->(
                                  'service.edit',      'application/x.atom+xml',
                                  "$api/edit/$jitemid", 'Edit this post'
                                  )
                     ) if $opts->{'apilinks'};

    my $event_date = LJ::TimeUtil->time_to_w3c($self->logtime_unix, "");
    my $modtime    = LJ::TimeUtil->time_to_w3c($self->modtime_unix, 'Z');

    $entry->published($event_date);
    $entry->issued   ($event_date);   # COMPAT

    $entry->updated ($modtime);
    $entry->modified($modtime);

    # XML::Atom 0.9 doesn't support categories.   Maybe later?
    foreach my $tag ($self->tags) {
        $tag = LJ::exml($tag);
        my $category = $entry_xml->createElement( 'category' );
        $category->setAttribute( 'term', $tag );
        $entry_xml->getDocumentElement->appendChild( $category );
    }

    my $syn_level = $opts->{synlevel} || $u->prop("opt_synlevel") || "full";

    # if syndicating the complete entry
    #   -print a content tag
    # elsif syndicating summaries
    #   -print a summary tag
    # else (code omitted), we're syndicating title only
    #   -print neither (the title has already been printed)
    #   note: the $event was also emptied earlier, in make_feed
    #
    # a lack of a content element is allowed,  as long
    # as we maintain a proper 'alternate' link (above)
    if ($syn_level eq 'full') {
        # Do this manually for now, until XML::Atom supports new
        # content type classifications.
        my $content = $entry_xml->createElement( 'content' );
        $content->setAttribute( 'type', 'html' );
        $content->appendTextNode( $self->event_html );
        $entry_xml->getDocumentElement->appendChild( $content );
    } elsif ($syn_level eq 'summary') {
        my $summary = $entry_xml->createElement( 'summary' );
        $summary->setAttribute( 'type', 'html' );
        $summary->appendTextNode( $self->event_summary );
        $entry_xml->getDocumentElement->appendChild( $summary );
    }

    return $entry;
}

# returns the entry as an XML Atom string, without the XML prologue
sub as_atom
{
    my $self  = shift;
    my $entry = $self->atom_entry;
    my $xml   = $entry->as_xml;
    $xml =~ s!^<\?xml.+?>\s*!!s;
    return $xml;
}

sub as_sms {
    my $self = shift;
    my %opts = @_;
    my $for_u  = delete $opts{for_u};
    croak "invalid for_u arg to as_sms"
        unless LJ::isu($for_u);
    my $maxlen = delete $opts{maxlen} || 160;
    croak "invalid parameters: " . join(",", keys %opts)
        if %opts;

    my $ret = "";

    # is this a community or journal post?
    if ($self->journalid != $self->posterid) {
        $ret .= "(" . $self->journal->display_name . ") ";
    }

    # add in poster's username
    $ret .= $self->poster->display_name . ":\n";

    # now for the first $maxlen characters of the subject,
    # falling back to the first $maxlen characters of the post
    foreach my $meth (qw(subject_text event_text)) {
        my $text = LJ::strip_html($self->$meth) or next;
        $ret .= $for_u->max_sms_substr
            ($text, maxlen => $maxlen, suffix => "...");
        last;
    }

    return $ret;
}

sub as_paged_sms {
    my $self = shift;
    my %opts = @_;
    my $for_u = delete $opts{for_u};
    my $page  = delete $opts{page} || 1;
    $page = 1 if $page > 99;
    croak "invalid parameters: " . join(",", keys %opts)
        if %opts;

    my $full_text;
    {
        my $subj_text = $self->subject_text;
        my $body_text = $self->event_text;

        if ($subj_text) {
            $full_text = "[$subj_text] " . $body_text;
        } else {
            $full_text = "$body_text";
        }

        # full text should be devoid of html tags, with the
        # exception of lj (user|comm) which just become a
        # username
        $full_text = LJ::strip_html($full_text);
    }

    my $header = "";

    # is this a community or journal post?
    if ($self->journalid != $self->posterid) {
        $header .= "(" . $self->journal->display_name . ") ";
    }

    # add in poster's username
    $header .= $self->poster->display_name;

    my %pageret = ();
    my $maxpage = 1;

    { # lexical scope for 'use bytes' ...
        use bytes;

      PAGE:
        foreach my $currpage (1..99) {

            # Note:  This is acknowledged to be ghetto.  We set '99' for the max page
            #        number while we still build the list so that at the end once there
            #        is a real max number we can replace it.  So the character capacity
            #        of a single '9' is lost when the total number of pages is single-digit
            my $page_head   = "${header} ($currpage of 99)\n";
            my $page_suffix = "...";

            # if the length of this bit of text is greater than our page window,
            # then append whatever fits and move onto the next page
            # - note that max_sms_substr works on utf-8 character boundaries, so
            #   doing a subsequent length($to_append) is utf-8-safe
            my $new_page   = $for_u->max_sms_substr($page_head . $full_text, suffix => $page_suffix);
            my $offset     = length($new_page) - (length($page_head) + length($page_suffix));
            $full_text     = substr($full_text, $offset);

            # remember this created page
            $pageret{$currpage} = $new_page;

            # stop creating new pages once $full_text is drained
            unless (length $full_text) {

                # strip "..." off of this page since it's the last
                $pageret{$currpage} =~ s/$page_suffix$//;

                $maxpage = $currpage;
                last PAGE;
            }
        }
    }

    # did the user request an out-of-bounds page?
    $page = 1 unless exists $pageret{$page};

    # we reserved '99' for length checking above, now replace that with the real max number of pages
    $pageret{$page} =~ s/\($page of 99\)/\($page of $maxpage\)/;

    return $pageret{$page};
}


# raw utf8 text, with no HTML cleaning
sub subject_raw {
    my $self = shift;
    $self->_load_text  unless $self->{_loaded_text};
    return $self->{subject};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub subject_orig {
    my $self = shift;
    $self->_load_text  unless $self->{_loaded_text};
    return $self->{subject_orig} || $self->{subject};
}

# raw utf8 text, with no HTML cleaning
sub event_raw {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{event};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub event_orig {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{event_orig} || $self->{event};
}

sub subject_html
{
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    my $subject = $self->{subject};
    LJ::CleanHTML::clean_subject( \$subject ) if $subject;
    return $subject;
}

sub subject_text
{
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    my $subject = $self->{subject};
    LJ::CleanHTML::clean_subject_all( \$subject ) if $subject;
    return $subject;
}

# instance method.  returns HTML-cleaned/formatted version of the event
# optional $opt may be:
#    undef:   loads the opt_preformatted key and uses that for formatting options
#    1:       treats entry as preformatted (no breaks applied)
#    0:       treats entry as normal (newlines convert to HTML breaks)
#    hashref: passed to LJ::CleanHTML::clean_event verbatim
sub event_html
{
    my ($self, $opts) = @_;

    if (! defined $opts) {
        $opts = {};
    } elsif (! ref $opts) {
        $opts = { preformatted => $opts };
    }

    unless ( exists $opts->{'preformatted'} ) {
        $opts->{'preformatted'} = $self->prop('opt_preformatted');
    }

    my $remote = LJ::get_remote();
    my $suspend_msg = $self->should_show_suspend_msg_to($remote) ? 1 : 0;
    $opts->{suspend_msg} = $suspend_msg;
    $opts->{unsuspend_supportid} = $suspend_msg ? $self->prop("unsuspend_supportid") : 0;

    if($opts->{no_cut_expand}) {
        $opts->{expand_cut} = 0;
        $opts->{cuturl}     = $self->url . '?page=' . $opts->{page} . '&cut_expand=1';
    } elsif (!$opts->{cuturl}) {
        $opts->{expand_cut} = 1;
        $opts->{cuturl}     = $self->url;
    }
    $opts->{journalid} = $self->journalid;
    $opts->{posterid}  = $self->posterid;
    $opts->{entry_url} = $self->prop('reposted_from') || $self->url;

    $self->_load_text unless $self->{_loaded_text};
    my $event = $self->{event};
    LJ::CleanHTML::clean_event(\$event, $opts);

    LJ::expand_embedded($self->{u}, $self->ditemid, $remote, \$event, video_placeholders => $opts->{'video_placeholders'} );
    return $event;
}

# like event_html, but trimmed to $char_max
sub event_html_summary {
    my ($self, $char_max, $opts) = @_;
    return LJ::html_trim($self->event_html($opts), $char_max);
}

sub event_text
{
    my $self = shift;
    my $event = $self->event_raw;
    if ( $event ) {
        LJ::CleanHTML::clean_event( \$event, {
            'textonly'  => 1,
            'journalid' => $self->journalid,
            'posterid'  => $self->posterid,
            'entry_url' => $self->url,
        } );
    }
    return $event;
}

# like event_html, but truncated for summary mode in rss/atom
sub event_summary {
    my $self = shift;

    my $url = $self->url;
    my $readmore = "<b>(<a href=\"$url\">Read more ...</a>)</b>";

    my $event = $self->event_html;

    # assume the first paragraph is terminated by two <br> or a </p>
    # valid XML tags should be handled, even though it makes an uglier regex
    if ($event =~ m!(.*)(((<br\s*/?\>(</br\s*>)?\s*){2})|(</p\s*>))!i) {
        # everything before the matched tag + the tag itself
        # + a link to read more
        $event = $1 . $2 . $readmore;
    }
    return $event;
}

sub comments_manageable_by {
    my ($self, $remote) = @_;
    return 0 unless $self->valid;
    return 0 unless $remote;
    my $u = $self->{u};
    return
        $remote->{userid} == $u->{userid} ||
        $remote->{userid} == $self->posterid ||
        $remote->can_manage($u) ||
        $remote->can_sweep($u);
}

# instance method:  returns bool, if remote user can view this entry
# is duplicate to LJ::can_view (LJ/User.pm), it is hard translate one to other because different entry attributes hashrefs
sub visible_to
{
    my ($self, $remote, $opts) = @_;
    return 0 unless $self->valid;

    # can see anything with viewall
    return 1 if $opts->{'viewall'};

    # can't see anything unless the journal is visible
    # unless you have viewsome. then, other restrictions apply
    if (!$opts->{'viewsome'}) {
        return 0 if $self->journal->{statusvis} =~ m/[DSX]/;

        # can't see anything by suspended users
        my $poster = $self->poster;
        return 0 if $poster->{statusvis} eq 'S';

        # if poster choosed to delete jouranl and all external content, 
        # then don't show his/her entries, except in some protected journals like 'lj_core'
        if ($poster->{statusvis} eq 'D') {
            my ($purge_comments, $purge_community_entries) = split /:/, $poster->prop("purge_external_content");
            if ($purge_community_entries) {
                my $journal_name = $self->journal->{user};
                if (!$LJ::JOURNALS_WITH_PROTECTED_CONTENT{$journal_name}) {
                    return 0;
                }
            }
        }

        # can't see suspended entries
        return 0 if $self->is_suspended_for($remote);
    }

    # public is okay
    return 1 if $self->{'security'} eq "public";

    # must be logged in otherwise
    return 0 unless $remote;

    my $userid   = int($self->{u}{userid});
    my $remoteid = int($remote->{userid});

    # owners can always see their own.
    return 1 if $userid == $remoteid;

    # author in community can always see their post
    return 1 if $remoteid == $self->posterid and not $LJ::JOURNALS_WITH_PROTECTED_CONTENT{ $self->journal->{user} };

    # other people can't read private
    return 0 if $self->{'security'} eq "private";

    # should be 'usemask' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless $self->{'security'} eq "usemask";

    # if it's usemask, we have to refuse non-personal journals,
    # so we have to load the user
    return 0 unless $remote->{'journaltype'} eq 'P' || $remote->{'journaltype'} eq 'I';

    my $gmask = LJ::get_groupmask($userid, $remoteid);
    my $allowed = (int($gmask) & int($self->{'allowmask'}));
    return $allowed ? 1 : 0;  # no need to return matching mask
}

# returns hashref of (kwid => tag) for tags on the entry
sub tag_map {
    my $self = shift;
    my $tags = LJ::Tags::get_logtags($self->{u}, $self->jitemid);
    return {} unless $tags;
    return $tags->{$self->jitemid} || {};
}

# returns a LJ::Userpic object for this post, or undef
# currently this is for the permalink view, not for the friends view
# context.  TODO: add a context option for friends page, and perhaps
# respect $remote's userpic viewing preferences (community shows poster
# vs community's picture)
sub userpic {
    my $self = shift;

    my $up = $self->poster;

    # try their entry-defined userpic keyword, then their custom
    # mood, then their standard mood
    my $key = $self->prop('picture_keyword') ||
        $self->prop('current_mood') ||
        LJ::mood_name($self->prop('current_moodid'));

    # return the picture from keyword, if defined
    my $picid = LJ::get_picid_from_keyword($up, $key);
    return LJ::Userpic->new($up, $picid) if $picid;

    # else return poster's default userpic
    return $up->userpic;
}

sub userpic_kw_from_props {
    my ($class, $props) = @_;

    return $props->{'picture_keyword'} ||
        $props->{'current_mood'} ||
        LJ::mood_name($props->{'current_moodid'});
}


# returns true if the user is allowed to share an entry via Tell a Friend
# $u is the logged-in user
# $item is a hash containing Entry info
sub can_tellafriend {
    my ($entry, $u) = @_;

    return 1 if $entry->security eq 'public';
    return 0 if $entry->security eq 'private';

    # friends only
    return 0 unless $entry->journal->is_person;
    return 0 unless LJ::u_equals($u, $entry->poster);
    return 1;
}

sub search_index_id {
    my $entry = shift;

    return 'entry_' . $entry->journalid . '_'  . $entry->jitemid;
}

sub search_document {
    my $entry = shift;

    my $content = $entry->subject_text . ' ' . $entry->event_text;

    # append log metadata to end of content
    my $metadata = '';

    my $mood = $entry->prop('current_mood') || LJ::mood_name($entry->prop('current_moodid')) || '';
    $content .= "\n$mood\n";

    # add location and music
    $content .= join("\n", map { $entry->prop($_) } qw/current_location current_music/);

    my $doc = LJ::Search->document(
                                   id          => $entry->search_index_id,
                                   content     => $content,
                                   date        => $entry->logtime_unix,
                                   );

    $doc->stored('id', 1); # store the id field and index it

    return $doc;
}

# defined by the entry poster
sub adult_content {
    my $self = shift;

    return $self->prop('adult_content');
}

# defined by an admin
sub admin_content_flag {
    my $self = shift;

    return $self->prop('admin_content_flag');
}

# uses both poster- and admin-defined props to figure out the adult content level
sub adult_content_calculated {
    my $self = shift;

    return "explicit" if $self->admin_content_flag eq "explicit_adult";
    return $self->adult_content;
}

sub qotdid {
    my $self = shift;

    return $self->prop('qotdid');
}

# don't use this anymore, instead check for is_special flag on question
sub is_special_qotd_entry {
    my $self = shift;

    my $qotdid = $self->qotdid;
    my $poster = $self->poster;

    if ($qotdid && $poster && LJ::run_hook("show_qotd_title_change", $poster)) {
        return 1;
    }

    return 0;
}

sub qct_value_for_ads {
    my $self = shift;

    return 0 unless LJ::is_enabled("content_flag");

    my $adult_content = $self->adult_content_calculated;
    my $admin_flag = $self->admin_content_flag;

    if ($LJ::CONTENT_FLAGS{$adult_content} && $LJ::CONTENT_FLAGS{$adult_content}->{qct_value_for_ads}) {
        return $LJ::CONTENT_FLAGS{$adult_content}->{qct_value_for_ads};
    }
    if ($LJ::CONTENT_FLAGS{$admin_flag} && $LJ::CONTENT_FLAGS{$admin_flag}->{qct_value_for_ads}) {
        return $LJ::CONTENT_FLAGS{$admin_flag}->{qct_value_for_ads};
    }

    return 0;
}

sub should_block_robots {
    my $self = shift;

    return 1 if $self->journal->prop('opt_blockrobots');

    return 0 unless LJ::is_enabled("content_flag");

    my $adult_content = $self->adult_content_calculated;
    my $admin_flag = $self->admin_content_flag;

    return 1 if $LJ::CONTENT_FLAGS{$adult_content} && $LJ::CONTENT_FLAGS{$adult_content}->{block_robots};
    return 1 if $LJ::CONTENT_FLAGS{$admin_flag} && $LJ::CONTENT_FLAGS{$admin_flag}->{block_robots};
    return 0;
}

sub can_be_added_to_verticals_by_admin {
    my $self = shift;
    my %opts = @_;

    return LJ::Vertical->check_entry_for_addition_and_display($self) &&
           ($opts{ignore_image_restrictions} ? 1 : LJ::Vertical->check_entry_for_image_restrictions($self, ignore_image_sizes => 1)) ? 1 : 0;
}

sub should_be_added_to_verticals {
    my $self = shift;
    my %opts = @_;

    return LJ::Vertical->check_entry_for_addition($self, %opts) &&
           LJ::Vertical->check_entry_for_addition_and_display($self) ? 1 : 0;
}

sub should_show_in_verticals {
    my $self = shift;
    my %opts = @_;

    return LJ::Vertical->check_entry_for_addition_and_display($self) &&
           LJ::Vertical->check_entry_for_display($self) ? 1 : 0;
}

sub verticals_list {
    my $self = shift;

    my $verticals_list = $self->prop("verticals_list");
    return () unless $verticals_list;

    my @verticals = split(/\s*,\s*/, $verticals_list);
    return @verticals ? @verticals : ();
}

sub verticals_list_for_ad {
    my $self = shift;

    my @verticals = $self->verticals_list;
    my @verticals_for_ad;
    if (@verticals) {
        foreach my $vertname (@verticals) {
            my $vertical = LJ::Vertical->load_by_name($vertname);
            next unless $vertical;

            push @verticals_for_ad, $vertical->ad_name;
        }
    }

    # remove parent verticals if any of their subverticals are in the list
    my %vertical_in_list = map { $_ => 1 } @verticals_for_ad;
    foreach my $vertname (@verticals_for_ad) {
        my $vertical = LJ::Vertical->load_by_name($vertname);
        next unless $vertical;

        foreach my $child ($vertical->children) {
            if ($vertical_in_list{$child->ad_name}) {
                delete $vertical_in_list{$vertical->ad_name};
            }
        }
    }
    @verticals_for_ad = keys %vertical_in_list;

    return @verticals_for_ad ? @verticals_for_ad : ();
}

sub add_to_vertical {
    my $self = shift;
    my $vertname = shift;

    my @verticals = $self->verticals_list;
    return 1 if grep { $_ eq $vertname } @verticals;

    push @verticals, $vertname;
    my $newval = join(",", @verticals);
    $self->set_prop( verticals_list => $newval );

    return 1;
}

sub remove_from_vertical {
    my $self = shift;
    my $vertname = shift;

    my @verticals = $self->verticals_list;
    my @newkeys = grep { $_ ne $vertname } @verticals;
    return 1 if @newkeys == @verticals;

    my $newval = join(",", @newkeys);
    $self->set_prop( verticals_list => $newval );

    return 1;
}

sub syn_link {
    my $self = shift;

    return $self->prop('syn_link');
}

# group names to be displayed with this entry
# returns nothing if remote is not the poster of the entry
# returns names as links to the /security/ URLs if the user can use those URLs
# returns names as plaintext otherwise
sub group_names {
    my $self = shift;

    my $remote = LJ::get_remote();
    my $poster = $self->poster;

    if ($self->allowmask > 1 && $poster && $poster->equals($remote)) {
        my $groups = LJ::get_friend_group($poster);

        # if the poster has friend groups, return the ones to which this entry is filtered
        if (keys %$groups) {
            my @friendgroups = ();

            foreach my $groupid (keys %$groups) {
                next unless $self->allowmask & 1 << $groupid;

                my $name = LJ::ehtml($groups->{$groupid}->{groupname});
                my $url = $poster->journal_base . "/security/group:$name";

                my $group_text = $remote->get_cap("security_filter") || $poster->get_cap("security_filter") ? "<a href='$url'>$name</a>" : $name;
                push @friendgroups, $group_text;
            }

            return join(', ', @friendgroups) if @friendgroups;
        }
    }

    return "";
}

sub statusvis {
    my $self = shift;

    return $self->prop("statusvis") eq "S" ? "S" : "V";
}

sub is_visible {
    my $self = shift;

    return $self->statusvis eq "V" ? 1 : 0;
}

sub is_suspended {
    my $self = shift;

    return $self->statusvis eq "S" ? 1 : 0;
}

# same as is_suspended, except that it returns 0 if the given user can see the suspended entry
sub is_suspended_for {
    my $self = shift;
    my $u = shift;

    return 0 unless $self->is_suspended;
    return 0 if LJ::check_priv($u, 'canview', 'suspended');
    return 0 if LJ::isu($u) && $u->equals($self->poster);
    return 1;
}

sub should_show_suspend_msg_to {
    my $self = shift;
    my $u = shift;

    return $self->is_suspended && !$self->is_suspended_for($u) ? 1 : 0;
}

# some entry props must keep all their history
sub put_logprop_in_history {
    my ($self, $prop, $old_value, $new_value, $note) = @_;

    my $p = LJ::get_prop("log", $prop);
    return undef unless $p;

    my $propid = $p->{id};

    my $u = $self->journal;
    $u->do("INSERT INTO logprop_history (journalid, jitemid, propid, change_time, old_value, new_value, note) VALUES (?, ?, ?, unix_timestamp(), ?, ?, ?)",
           undef, $self->journalid, $self->jitemid, $propid, $old_value, $new_value, $note);
    return undef if $u->err;
    return 1;
}

sub comments_shown {
    my ($self) = @_;

    return 0 unless $self->journal->{'opt_showtalklinks'} eq 'Y';
    return 0 if $self->prop('opt_nocomments');

    return 1;
}

sub posting_comments_allowed {
    my ($self) = @_;

    return 0 unless $self->journal->{'opt_showtalklinks'} eq 'Y';
    return 0 if $self->prop('opt_nocomments');
    return 0 if $self->prop('opt_lockcomments');

    return 1;
}

sub everyone_can_comment {
    my ($self) = @_;

    return 0 unless $self->posting_comments_allowed;
    return 0 unless $self->journal->{'opt_whocanreply'} eq 'all';

    return 1;
}

sub registered_can_comment {
    my ($self) = @_;

    return 1 if $self->everyone_can_comment;
    return 1 if $self->journal->{'opt_whocanreply'} eq 'reg';

    return 0;
}

sub friends_can_comment {
    my ($self) = @_;

    return 1 if $self->registered_can_comment;
    return 1 if $self->journal->{'opt_whocanreply'} eq 'friends';

    return 0;
}

# mark/unmark entry in 'compressed' field to skip/include it in LJ::get_recent_items() call
sub mark_suspended {
    my $self = shift;
    my $value = shift;

    my $u = $self->journal;
    $u->do("UPDATE log2 SET compressed=? WHERE journalid=? AND jitemid=?",
           undef, $value, $self->journalid, $self->jitemid);
    return undef if $u->err;
    return 1;
}

# get skip/include status for LJ::get_recent_items() call
sub get_suspended_mark {
    my $self = shift;

    # we cannot use preload_rows() because memcache does not contain 'compressed' field
    # and most code of LJ does not need this field,
    # so, there are no reasons to include it into memcache

    my $u = $self->journal;
    my $compressed = $u->selectrow_array("SELECT compressed FROM log2 WHERE journalid=? AND jitemid=? ", undef, $self->journalid, $self->jitemid);
    return $compressed;
}

## returns 'yes' if entry is ads-eligible (there are no offensive terms etc), and 'no' otherwise
sub check_for_negative_terms {
    my $self = shift;
    
    my $tags = $self->prop('personifi_tags');
    return $1 if $tags =~ /nterms:(\w+)/;
    my $nterms = ( ($self->subject_raw . ' '. $self->event_raw) =~ /($LJ::NEGATIVE_TERMS)/) ?'no':'yes';
    $self->set_prop(personifi_tags => ($tags?"$tags,":'') . "nterms:$nterms");
    return $nterms;
}

# returns a hashref: { title => '', description => '', image => $url }
sub extract_metadata {
    my ($self) = @_;

    my %meta;

    $meta{'title'} = LJ::Text->drop_html( $self->subject_raw );

    $meta{'description'} = eval {
        my $text = $self->event_raw;
        $text = LJ::Text->drop_html($text);
        $text = LJ::Text->truncate_to_word_with_ellipsis( 'str' => $text, 'bytes' => 300 );
        return $text;
    };
    die "cannot get entry description: $@" unless defined $meta{'description'};

    $meta{'image'} = eval {
        my $text = $self->event_raw;
        my $images = LJ::html_get_img_urls( \$text, 'exclude_site_imgs' => 1 );
        return $images->[0] if $images && @$images;

        my $userpic = $self->userpic;
        return $userpic->url if $userpic;

        my $journal = $self->journal;
        my ($userhead_url) = $journal->userhead;

        # for now, LJ::User::userhead may return a relative path,
        # so let's fix this
        unless ( $userhead_url =~ /^https?:\/\// ) {
            $userhead_url = $LJ::IMGPREFIX . '/' . $userhead_url . "?v=3";
        }

        return $userhead_url;
    };
    die "cannot get entry image: $@" unless defined $meta{'image'};

    return \%meta;
}

sub is_sticky {
    my ($self) = @_;

    my $u = $self->{u};
    my $sticky_entry_id = $u->get_sticky_entry_id();
    return 0 unless $sticky_entry_id;
    return $self->jitemid == $sticky_entry_id;
}

sub can_delete_journal_item {
    my $class = shift;
    return LJ::can_delete_journal_item(@_);
}

package LJ;

use Class::Autouse qw (
                       LJ::Poll
                       LJ::EmbedModule
                       LJ::Tidy
                       );

# <LJFUNC>
# name: LJ::get_logtext2multi
# des: Gets log text from clusters.
# info: Fetches log text from clusters. Trying slaves first if available.
# returns: hashref with keys being "jid jitemid", values being [ $subject, $body ]
# args: idsbyc
# des-idsbyc: A hashref where the key is the clusterid, and the data
#             is an arrayref of [ ownerid, itemid ] array references.
# </LJFUNC>
sub get_logtext2multi
{
    &nodb;
    return _get_posts_raw_wrapper(shift, "text");
}

# this function is used to translate the old get_logtext2multi and load_log_props2multi
# functions into using the new get_posts_raw.  eventually, the above functions should
# be taken out of the rest of the code, at which point this function can also die.
sub _get_posts_raw_wrapper {
    # args:
    #   { cid => [ [jid, jitemid]+ ] }
    #   "text" or "props"
    #   optional hashref to put return value in.  (see get_logtext2multi docs)
    # returns: that hashref.
    my ($idsbyc, $type, $ret) = @_;
    my $opts = {};
    if ($type eq 'text') {
        $opts->{text_only} = 1;
    } elsif ($type eq 'prop') {
        $opts->{prop_only} = 1;
    } else {
        return undef;
    }

    my @postids;
    while (my ($cid, $ids) = each %$idsbyc) {
        foreach my $pair (@$ids) {
            push @postids, [ $cid, $pair->[0], $pair->[1] ];
        }
    }
    my $rawposts = LJ::get_posts_raw($opts, @postids);

    # add replycounts fields to props
    if ($type eq "prop") {
        while (my ($k, $v) = each %{$rawposts->{"replycount"}||{}}) {
            $rawposts->{prop}{$k}{replycount} = $rawposts->{replycount}{$k};
        }
    }

    # translate colon-separated (new) to space-separated (old) keys.
    $ret ||= {};
    while (my ($id, $data) = each %{$rawposts->{$type}}) {
        $id =~ s/:/ /;
        $ret->{$id} = $data;
    }
    return $ret;
}

# <LJFUNC>
# name: LJ::get_posts_raw
# des: Gets raw post data (text and props) efficiently from clusters.
# info: Fetches posts from clusters, trying memcache and slaves first if available.
# returns: hashref with keys 'text', 'prop', or 'replycount', and values being
#          hashrefs with keys "jid:jitemid".  values of that are as follows:
#          text: [ $subject, $body ], props: { ... }, and replycount: scalar
# args: opts?, id
# des-opts: An optional hashref of options:
#            - memcache_only:  Don't fall back on the database.
#            - text_only:  Retrieve only text, no props (used to support old API).
#            - prop_only:  Retrieve only props, no text (used to support old API).
# des-id: An arrayref of [ clusterid, ownerid, itemid ].
# </LJFUNC>
sub get_posts_raw {
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    my $ret = {};
    my $sth;

    LJ::load_props('log') unless $opts->{text_only};

    # throughout this function, the concept of an "id"
    # is the key to identify a single post.
    # it is of the form "$jid:$jitemid".

    # build up a list for each cluster of what we want to get,
    # as well as a list of all the keys we want from memcache.
    my %cids;      # cid => 1
    my $needtext;  # text needed:  $cid => $id => 1
    my $needprop;  # props needed: $cid => $id => 1
    my $needrc;    # replycounts needed: $cid => $id => 1
    my @mem_keys;

    # if we're loading entries for a friends page,
    # silently failing to load a cluster is acceptable.
    # but for a single user, we want to die loudly so they don't think
    # we just lost their journal.
    my $single_user;

    # because the memcache keys for logprop don't contain
    # which cluster they're in, we also need a map to get the
    # cid back from the jid so we can insert into the needfoo hashes.
    # the alternative is to not key the needfoo hashes on cluster,
    # but that means we need to grep out each cluster's jids when
    # we do per-cluster queries on the databases.
    my %cidsbyjid;

    foreach my $post (@_) {
        my ($cid, $jid, $jitemid) = @{$post};
        my $id = "$jid:$jitemid";

        if ( not defined $single_user ) {
            $single_user = $jid;
        }
        elsif ( $single_user and $jid != $single_user ) {
            # multiple users
            $single_user = 0;
        }

        $cids{$cid} = 1;
        $cidsbyjid{$jid} = $cid;

        unless ($opts->{prop_only}) {
            $needtext->{$cid}{$id} = 1;
            push @mem_keys, [$jid,"logtext:$cid:$id"];
        }

        unless ($opts->{text_only}) {
            $needprop->{$cid}{$id} = 1;
            push @mem_keys, [$jid,"logprop2:$id"];
            $needrc->{$cid}{$id} = 1;
            push @mem_keys, [$jid,"rp:$id"];
        }
    }

    # first, check memcache.
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};

    while (my ($k, $v) = each %$mem) {
        next unless defined $v;
        next unless $k =~ /(\w+):(?:\d+:)?(\d+):(\d+)/;

        my ($type, $jid, $jitemid) = ($1, $2, $3);
        my $cid = $cidsbyjid{$jid};
        my $id = "$jid:$jitemid";

        if ($type eq "logtext") {
            delete $needtext->{$cid}->{$id};
            $ret->{'text'}->{$id} = $v;
        }
        elsif ($type eq "logprop2" && ref $v eq "HASH") {
            delete $needprop->{$cid}->{$id};
            $ret->{'prop'}->{$id} = $v;
        }
        elsif ($type eq "rp") {
            delete $needrc->{$cid}->{$id};
            $ret->{'replycount'}->{$id} = int($v); # remove possible spaces
        }
    }

    # we may be done already.
    return $ret if $opts->{memcache_only};

    unless ( values %$needtext or values %$needprop
        or values %$needrc ) {
        convert_href_props( $ret->{'prop'} );
        return $ret;
    }

    # otherwise, hit the database.
    foreach my $cid (keys %cids) {
        # for each cluster, get the text/props we need from it.
        my $cneedtext = $needtext->{$cid} || {};
        my $cneedprop = $needprop->{$cid} || {};
        my $cneedrc   = $needrc->{$cid} || {};

        next unless %$cneedtext or %$cneedprop or %$cneedrc;

        my $make_in = sub {
            my @in;
            foreach my $id (@_) {
                my ($jid, $jitemid) = map { $_ + 0 } split(/:/, $id);
                push @in, "(journalid=$jid AND jitemid=$jitemid)";
            }
            return join(" OR ", @in);
        };

        # now load from each cluster.
        my $fetchtext = sub {
            my $db = shift;
            return unless %$cneedtext;
            my $in = $make_in->(keys %$cneedtext);
            $sth = $db->prepare("SELECT journalid, jitemid, subject, event ".
                                "FROM logtext2 WHERE $in");
            $sth->execute;
            while (my ($jid, $jitemid, $subject, $event) = $sth->fetchrow_array) {
                LJ::text_uncompress(\$event);
                my $id = "$jid:$jitemid";
                my $val = [ $subject, $event ];
                $ret->{text}{$id} = $val;
                LJ::MemCache::add([$jid,"logtext:$cid:$id"], $val);
                delete $cneedtext->{$id};
            }
        };

        my $fetchprop = sub {
            my $db = shift;
            return unless %$cneedprop;
            my $in = $make_in->(keys %$cneedprop);

            $sth = $db->prepare("SELECT journalid, jitemid, propid, value ".
                                "FROM logprop2 WHERE $in");
            $sth->execute;
            my %gotid;

            while (my ($jid, $jitemid, $propid, $value) = $sth->fetchrow_array) {
                my $id = "$jid:$jitemid";
                $ret->{'prop'}->{$id}->{$propid} = $value;
                $gotid{$id} = 1;
            }

            foreach my $id (keys %gotid) {
                my ($jid, $jitemid) = map { $_ + 0 } split(/:/, $id);
                LJ::MemCache::add([$jid, "logprop2:$id"], $ret->{prop}->{$id});
                delete $cneedprop->{$id};
            }
        };

        my $fetchrc = sub {
            my $db = shift;
            return unless %$cneedrc;

            my $in = $make_in->(keys %$cneedrc);
            $sth = $db->prepare("SELECT journalid, jitemid, replycount FROM log2 WHERE $in");
            $sth->execute;

            while (my ($jid, $jitemid, $rc) = $sth->fetchrow_array) {
                my $id = "$jid:$jitemid";
                $ret->{replycount}{$id} = $rc;
                LJ::MemCache::add([$jid, "rp:$id"], $rc);
                delete $cneedrc->{$id};
            }
        };

        my $dberr = sub {
            die "Couldn't connect to database" if $single_user;
            next;
        };

        # run the fetch functions on the proper databases, with fallbacks if necessary.
        my ($dbcm, $dbcr);

        if (@LJ::MEMCACHE_SERVERS or $opts->{use_master}) {
            $dbcm ||= LJ::get_cluster_master($cid) or $dberr->();
            $fetchtext->($dbcm) if %$cneedtext;
            $fetchprop->($dbcm) if %$cneedprop;
            $fetchrc->($dbcm) if %$cneedrc;
        }
        else {
            $dbcr ||= LJ::get_cluster_reader($cid);

            if ($dbcr) {
                $fetchtext->($dbcr) if %$cneedtext;
                $fetchprop->($dbcr) if %$cneedprop;
                $fetchrc->($dbcr) if %$cneedrc;
            }

            # if we still need some data, switch to the master.
            if (%$cneedtext or %$cneedprop) {
                $dbcm ||= LJ::get_cluster_master($cid) or $dberr->();
                $fetchtext->($dbcm);
                $fetchprop->($dbcm);
                $fetchrc->($dbcm);
            }
        }

        # and finally, if there were no errors,
        # insert into memcache the absence of props
        # for all posts that didn't have any props.
        foreach my $id (keys %$cneedprop) {
            my ($jid, $jitemid) = map { $_ + 0 } split(/:/, $id);
            LJ::MemCache::set([$jid, "logprop2:$id"], {});
        }
    }

    for my $key ( keys %{$ret->{'prop'}} ) {
        convert_href_props( $ret->{'prop'}->{$key} );
    }

    return $ret;
}

sub get_posts
{
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    my $rawposts = get_posts_raw($opts, @_);

    # fix up posts as needed for display, following directions given in opts.


    # XXX this function is incomplete.  it should also HTML clean, etc.
    # XXX we need to load users when we have unknown8bit data, but that
    # XXX means we have to load users.


    while (my ($id, $rp) = each %$rawposts) {
        if ($LJ::UNICODE && $rp->{props}{unknown8bit}) {
            #LJ::item_toutf8($u, \$rp->{text}[0], \$rp->{text}[1], $rp->{props});
        }
    }

    return $rawposts;
}

#
# returns a row from log2, trying memcache
# accepts $u + $jitemid
# returns hash with: posterid, eventtime, logtime,
# security, allowmask, journalid, jitemid, anum.

sub get_log2_row
{
    my ($u, $jitemid) = @_;
    my $jid = $u->{'userid'};

    my $memkey = [$jid, "log2:$jid:$jitemid"];
    my ($row, $item);

    $row = LJ::MemCache::get($memkey);

    if ($row) {
        @$item{'posterid', 'eventtime', 'logtime', 'allowmask', 'ditemid'} = unpack("NNNNN", $row);
        $item->{'security'} = ($item->{'allowmask'} == 0 ? 'private' :
                               ($item->{'allowmask'} == 2**31 ? 'public' : 'usemask'));
        $item->{'journalid'} = $jid;
        @$item{'jitemid', 'anum'} = (int($item->{'ditemid'} / 256), $item->{'ditemid'} % 256);
        $item->{'eventtime'} = LJ::TimeUtil->mysql_time($item->{'eventtime'}, 1);
        $item->{'logtime'} = LJ::TimeUtil->mysql_time($item->{'logtime'}, 1);

        return $item;
    }

    my $db = LJ::get_cluster_def_reader($u);
    return undef unless $db;

    my $sql = "SELECT posterid, eventtime, logtime, security, allowmask, " .
              "anum FROM log2 WHERE journalid=? AND jitemid=?";

    $item = $db->selectrow_hashref($sql, undef, $jid, $jitemid);
    return undef unless $item;
    $item->{'journalid'} = $jid;
    $item->{'jitemid'} = $jitemid;
    $item->{'ditemid'} = $jitemid*256 + $item->{'anum'};

    my ($sec, $eventtime, $logtime);
    $sec = $item->{'allowmask'};
    $sec = 0 if $item->{'security'} eq 'private';
    $sec = 2**31 if $item->{'security'} eq 'public';
    $eventtime = LJ::TimeUtil->mysqldate_to_time($item->{'eventtime'}, 1);
    $logtime = LJ::TimeUtil->mysqldate_to_time($item->{'logtime'}, 1);

    # note: this cannot distinguish between security == private and security == usemask with allowmask == 0 (no groups)
    # both should have the same display behavior, but we don't store the security value in memcache
    $row = pack("NNNNN", $item->{'posterid'}, $eventtime, $logtime, $sec,
                $item->{'ditemid'});
    LJ::MemCache::set($memkey, $row);

    return $item;
}

# get 2 weeks worth of recent items, in rlogtime order,
# using memcache
# accepts $u or ($jid, $clusterid) + $notafter - max value for rlogtime
# $update is the timeupdate for this user, as far as the caller knows,
# in UNIX time.
# returns hash keyed by $jitemid, fields:
# posterid, eventtime, rlogtime,
# security, allowmask, journalid, jitemid, anum.

sub get_log2_recent_log
{
    my ($u, $cid, $update, $notafter, $events_date) = @_;
    my $jid = LJ::want_userid($u);
    $cid ||= $u->{'clusterid'} if ref $u;

    my $DATAVER = "3"; # 1 char

    my $use_cache = 1;

    # timestamp
    $events_date = int $events_date;
    $use_cache = 0 if $events_date; # do not use memcache for dayly friends log

    my $memkey  = [$jid, "log2lt:$jid"];
    my $lockkey = $memkey->[1];
    my ($rows, $ret);

    $rows = LJ::MemCache::get($memkey) if $use_cache;
    $ret = [];

    my $construct_singleton = sub {
        foreach my $row (@$ret) {
            $row->{journalid} = $jid;

            # FIX:
            # logtime param should be datetime, not unixtimestamp.
            #
            $row->{logtime} = LJ::TimeUtil->mysql_time($LJ::EndOfTime - $row->{rlogtime}, 1);
            # construct singleton for later
            LJ::Entry->new_from_row(%$row);
        }

        return $ret;
    };

    my $rows_decode = sub {
        return 0
            unless $rows && substr($rows, 0, 1) eq $DATAVER;
        my $tu = unpack("N", substr($rows, 1, 4));

        # if update time we got from upstream is newer than recorded
        # here, this data is unreliable
        return 0 if $update > $tu;

        my $n = (length($rows) - 5 )/20;
        for (my $i=0; $i<$n; $i++) {
            my ($posterid, $eventtime, $rlogtime, $allowmask, $ditemid) =
                unpack("NNNNN", substr($rows, $i*20+5, 20));
            next if $notafter and $rlogtime > $notafter;
            $eventtime = LJ::TimeUtil->mysql_time($eventtime, 1);
            my $security = $allowmask == 0 ? 'private' :
                ($allowmask == 2**31 ? 'public' : 'usemask');
            my ($jitemid, $anum) = (int($ditemid / 256), $ditemid % 256);
            my $item = {};
            @$item{'posterid','eventtime','rlogtime','allowmask','ditemid',
                   'security','journalid', 'jitemid', 'anum'} =
                       ($posterid, $eventtime, $rlogtime, $allowmask,
                        $ditemid, $security, $jid, $jitemid, $anum);
            $item->{'ownerid'} = $jid;
            $item->{'itemid'} = $jitemid;
            push @$ret, $item;
        }
        return 1;
    };

    return $construct_singleton->()
        if $rows_decode->();
    $rows = "";

    my $db = LJ::get_cluster_def_reader($cid);
    # if we use slave or didn't get some data, don't store in memcache
    my $dont_store = 0;
    unless ($db) {
        $db = LJ::get_cluster_reader($cid);
        $dont_store = 1;
        return undef unless $db;
    }

    #
    my $lock = $db->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    return undef unless $lock;

    if ($use_cache){
    # try to get cached data in exclusive context
        $rows = LJ::MemCache::get($memkey);
        if ($rows_decode->()) {
            $db->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);
            return $construct_singleton->();
        }
    }

    # ok. fetch data directly from DB.
    $rows = "";

    # get reliable update time from the db
    # TODO: check userprop first
    my $tu;
    my $dbh = LJ::get_db_writer();
    if ($dbh) {
        $tu = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP(timeupdate) " .
                                    "FROM userusage WHERE userid=?",
                                    undef, $jid);
        # if no mistake, treat absence of row as tu==0 (new user)
        $tu = 0 unless $tu || $dbh->err;

        LJ::MemCache::set([$jid, "tu:$jid"], pack("N", $tu), 30*60)
            if defined $tu;
        # TODO: update userprop if necessary
    }

    # if we didn't get tu, don't bother to memcache
    $dont_store = 1 unless defined $tu;

    # get reliable log2lt data from the db
    my $max_age = $LJ::MAX_FRIENDS_VIEW_AGE || 3600*24*14; # 2 weeks default
    my $sql = "
        SELECT
            jitemid, posterid, eventtime, rlogtime,
            security, allowmask, anum, replycount
         FROM log2
         USE INDEX (rlogtime)
         WHERE
                journalid=?
         " .
         ($events_date
            ?
              "AND rlogtime <= ($LJ::EndOfTime - $events_date)
               AND rlogtime >= ($LJ::EndOfTime - " . ($events_date + 24*3600) . ")"
            :
            "AND rlogtime <= ($LJ::EndOfTime - UNIX_TIMESTAMP()) + $max_age"
         );

    my $sth = $db->prepare($sql);
    $sth->execute($jid);
    my @row = ();
    push @row, $_ while $_ = $sth->fetchrow_hashref;
    @row = sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} } @row;
    my $itemnum = 0;

    foreach my $item (@row) {
        $item->{'ownerid'} = $item->{'journalid'} = $jid;
        $item->{'itemid'} = $item->{'jitemid'};
        push @$ret, $item;

        my ($sec, $ditemid, $eventtime, $logtime);
        $sec = $item->{'allowmask'};
        $sec = 0 if $item->{'security'} eq 'private';
        $sec = 2**31 if $item->{'security'} eq 'public';
        $ditemid = $item->{'jitemid'}*256 + $item->{'anum'};
        $eventtime = LJ::TimeUtil->mysqldate_to_time($item->{'eventtime'}, 1);

        $rows .= pack("NNNNN",
                      $item->{'posterid'},
                      $eventtime,
                      $item->{'rlogtime'},
                      $sec,
                      $ditemid);

        if ($use_cache && $itemnum++ < 50) {
            LJ::MemCache::add(LJ::Entry::reply_count_memkey($jid, $item->{'jitemid'}), $item->{'replycount'});
        }
    }

    $rows = $DATAVER . pack("N", $tu) . $rows;

    # store journal log in cache
    LJ::MemCache::set($memkey, $rows)
        if $use_cache and not $dont_store;

    $db->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);
    return $construct_singleton->();
}

sub get_log2_recent_user
{
    my $opts = shift;
    my $ret = [];

    my $log = LJ::get_log2_recent_log($opts->{'userid'}, $opts->{'clusterid'},
              $opts->{'update'}, $opts->{'notafter'}, $opts->{events_date},);

    ## UNUSED: my $left     = $opts->{'itemshow'};
    my $notafter = $opts->{'notafter'};
    my $remote   = $opts->{'remote'};

    my %mask_for_remote = (); # jid => mask for $remote
    foreach my $item (@$log) {
        ## UNUSED: last unless $left;
        last if $notafter and $item->{'rlogtime'} > $notafter;
        next unless $remote || $item->{'security'} eq 'public';
        next if $item->{'security'} eq 'private'
            and $item->{'journalid'} != $remote->{'userid'};
        if ($item->{'security'} eq 'usemask') {
            next unless $remote->{'journaltype'} eq "P" || $remote->{'journaltype'} eq 'I';
            my $permit = ($item->{'journalid'} == $remote->{'userid'});
            unless ($permit) {
                # $mask for $item{journalid} should always be the same since get_log2_recent_log
                # selects based on the $u we pass in; $u->id == $item->{journalid} from what I can see
                # -- we'll store in a per-journalid hash to be safe, but still avoid
                #    extra memcache calls
                my $mask = $mask_for_remote{$item->{journalid}};
                unless (defined $mask) {
                    $mask = LJ::get_groupmask($item->{'journalid'}, $remote->{'userid'});
                    $mask_for_remote{$item->{journalid}} = $mask;
                }
                $permit = $item->{'allowmask'}+0 & $mask+0;
            }
            next unless $permit;
        }

        # date conversion
        if ($opts->{'dateformat'} eq "S2") {
            $item->{'alldatepart'} = LJ::TimeUtil->alldatepart_s2($item->{'eventtime'});

            # conversion to get the system time of this entry
            my $logtime = LJ::TimeUtil->mysql_time($LJ::EndOfTime - $item->{rlogtime}, 1);
            $item->{'system_alldatepart'} = LJ::TimeUtil->alldatepart_s2($logtime);
        } else {
            $item->{'alldatepart'} = LJ::TimeUtil->alldatepart_s1($item->{'eventtime'});
        }
        push @$ret, $item;
    }

    return @$ret;
}

##
## see subs 'get_itemid_after2' and 'get_itemid_before2'
##
sub get_itemid_near2
{
    my $u = shift;
    my $jitemid = shift;
    my $after_before = shift;

    $jitemid += 0;

    my ($order, $cmp1, $cmp2, $cmp3, $cmp4);
    if ($after_before eq "after") {
        ($order, $cmp1, $cmp2, $cmp3, $cmp4) = ("DESC", "<=", ">", sub {$a->[0] <=> $b->[0]}, sub {$b->[2] <=> $a->[2]} );
    } elsif ($after_before eq "before") {
        ($order, $cmp1, $cmp2, $cmp3, $cmp4) = ("ASC",  ">=", "<", sub {$b->[0] <=> $a->[0]}, sub {$a->[2] <=> $b->[2]} );
    } else {
        return 0;
    }

    my $dbr = LJ::get_cluster_reader($u);
    unless ($dbr){
        warn "Can't connect to cluster reader. Cluster: " . $u->clusterid;
        return 0;
    }

    my $jid = $u->{'userid'}+0;
    my $field = $u->{'journaltype'} eq "P" ? "revttime" : "rlogtime";

    my $stime = $dbr->selectrow_array("SELECT $field FROM log2 WHERE ".
                                      "journalid=$jid AND jitemid=$jitemid");
    return 0 unless $stime;

    my $secwhere = "AND security='public'";
    my $remote = LJ::get_remote();

    if ($remote) {
        if ($remote->{'userid'} == $u->{'userid'}) {
            $secwhere = "";   # see everything
        } elsif ($remote->{'journaltype'} eq 'P' || $remote->{'journaltype'} eq 'I') {
            my $gmask = LJ::get_groupmask($u, $remote);
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    ##
    ## We need a next/prev record in journal before/after a given time
    ## Since several records may have the same time (time is rounded to 1 minute),
    ## we're ordering them by jitemid. So, the SQL we need is
    ##      SELECT * FROM log2
    ##      WHERE journalid=? AND rlogtime>? AND jitmemid<?
    ##      ORDER BY rlogtime, jitemid DESC
    ##      LIMIT 1
    ## Alas, MySQL tries to do filesort for the query.
    ## So, we sort by rlogtime only and fetch all (2, 10, 50) records
    ## with the same rlogtime (we skip records if rlogtime is different from the first one).
    ## If rlogtime of all fetched records is the same, increase the LIMIT and retry.
    ## Then we sort them in Perl by jitemid and takes just one.
    ##
    my $result_ref;
    foreach my $limit (2, 10, 50, 100) {
        $result_ref = $dbr->selectall_arrayref(
            "SELECT jitemid, anum, $field FROM log2 use index (rlogtime,revttime) ".
                "WHERE journalid=? AND $field $cmp1 ? AND jitemid <> ? ".
                $secwhere. " ".
                "ORDER BY $field $order LIMIT $limit",
            undef, $jid, $stime, $jitemid
        );

        my %hash_times = ();
        map {$hash_times{$_->[2]} = 1} @$result_ref;

        # If we has one the only 'time' in $limit fetched rows,
        # may be $limit cuts off our record. Increase the limit and repeat.
        if (((scalar keys %hash_times) > 1) || (scalar @$result_ref) < $limit) {
            my @result;

            # Remove results with the same time but the jitemid is too high or low
            if ($after_before eq "after") {
                @result = grep { $_->[2] != $stime || $_->[0] > $jitemid } @$result_ref;
            } elsif ($after_before eq "before") {
                @result = grep { $_->[2] != $stime || $_->[0] < $jitemid } @$result_ref;
            }

            # Sort result by jitemid and get our id from a top.
            @result =  sort $cmp3 @result;

            # Sort result by revttime
            @result =  sort $cmp4 @result;

            my ($id, $anum) = ($result[0]->[0], $result[0]->[1]);
            return 0 unless $id;
            return wantarray() ? ($id, $anum) : ($id*256 + $anum);
        }
    }
    return 0;
}

##
## Returns ID (a pair <jitemid, anum> in list context, ditmeid in scalar context)
## of a journal record that follows/preceeds the given record.
## Input: $u, $jitemid
##
sub get_itemid_after2  { return get_itemid_near2(@_, "after");  }
sub get_itemid_before2 { return get_itemid_near2(@_, "before"); }

sub get_latest_ditemid {
    my ($u, $opts) = @_;

    my $dbr = LJ::get_cluster_reader($u);
    unless ($dbr){
        warn "Can't connect to cluster reader. Cluster: " . $u->clusterid;
        return 0;
    }

    # Do I need to skip sticky entry?
    my $skip_sticky_item_sql = '';
    my $sticky_id = $u->get_sticky_entry_id;
    if ( $opts->{'skip_sticky_item'} && $sticky_id ) {
        #$skip_sticky_item_sql = "AND jitemid <> $sticky_id";
    }

    my $jid = $u->userid;
    my $field = $u->is_person ? "revttime" : "rlogtime";

    my $secwhere = "AND security='public'";
    my $remote = LJ::get_remote();

    if ($remote) {
        if ($remote->userid == $u->userid) {
            $secwhere = "";   # see everything
        } elsif ($remote->is_person || $remote->is_identity) {
            my $gmask = LJ::get_groupmask($u, $remote);
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    my $res = $dbr->selectcol_arrayref( "SELECT jitemid, anum FROM log2 use index (rlogtime,revttime) ".
                                        "WHERE journalid=? $skip_sticky_item_sql ".
                                        $secwhere. " ".
                                        "ORDER BY $field LIMIT 1", undef, $jid);
    my $itemid = $res->[0];
    my $anum   = $res->[1];

    return 0 unless $itemid;
    return ($itemid*256 + $anum);
}

sub get_after_item_link {
    my ($u, $opts) = @_;

    my $sticky_id =  $u->get_sticky_entry_id;
    my $use_sticky = $opts->{'use_sticky'} && LJ::is_enabled('sticky_entries');

    my $itemid = $opts->{'itemid'};
    my $jumpid = get_itemid_near2( $u,
                                   $itemid,
                                   'after',
                                   { 'skip_sticky' => $use_sticky } );
    
    if (!$jumpid) {
        return undef;
    }
    return $u->journal_base . "/$jumpid.html";
}


sub get_before_item_link {
    my ($u, $opts) = @_;

    my $sticky_id = $u->get_sticky_entry_id;
    my $use_sticky = $opts->{'use_sticky'} && LJ::is_enabled('sticky_entries');

    my $itemid = $opts->{'itemid'};

    my $jumpid = get_itemid_near2( $u,
                                   $itemid,
                                   'before',
                                   { 'skip_stucky' => $use_sticky });
    if (!$jumpid) {
        return undef;
    }
    return $u->journal_base . "/$jumpid.html";
}



sub set_logprop {
    my ($u, $jitemid, $hashref, $logprops) = @_;  # hashref to set, hashref of what was done

    $jitemid += 0;
    my $uid = $u->{'userid'} + 0;
    my $kill_mem = 0;
    my $del_ids;
    my $ins_values;

    while (my ($k, $v) = each %{$hashref||{}}) {
        my $prop = LJ::get_prop("log", $k);
        next unless $prop;

        $kill_mem = 1 unless $prop eq "commentalter";

        if ($v) {
            $ins_values .= "," if $ins_values;
            $ins_values .= "($uid, $jitemid, $prop->{'id'}, " . $u->quote($v) . ")";
            $logprops->{$k} = $v;
        }
        else {
            $del_ids .= "," if $del_ids;
            $del_ids .= $prop->{'id'};
        }
    }

    $u->do("REPLACE INTO logprop2 (journalid, jitemid, propid, value) ".
           "VALUES $ins_values") if $ins_values;
    $u->do("DELETE FROM logprop2 WHERE journalid=? AND jitemid=? ".
           "AND propid IN ($del_ids)", undef, $u->{'userid'}, $jitemid) if $del_ids;

    LJ::MemCache::delete([$uid,"logprop2:$uid:$jitemid"]) if $kill_mem;
}

# <LJFUNC>
# name: LJ::load_log_props2
# class:
# des:
# info:
# args: db?, uuserid, listref, hashref
# des-:
# returns:
# </LJFUNC>
sub load_log_props2 {
    my $db = isdb($_[0]) ? shift @_ : undef;

    my ($uuserid, $listref, $hashref) = @_;
    my $userid = want_userid($uuserid);
    return unless ref $hashref eq "HASH";

    my %needprops;
    my %needrc;
    my %rc;
    my @memkeys;

    foreach ( @$listref ) {
        my $id          = $_ + 0;
        $needprops{$id} = 1;
        $needrc{$id}    = 1;
        push @memkeys, [$userid, "logprop2:$userid:$id"];
        push @memkeys, LJ::Entry::reply_count_memkey($userid, $id);
    }

    return unless %needprops || %needrc;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    while ( my ($k, $v) = each %$mem ) {
        next unless $k =~ /(\w+):(\d+):(\d+)/;
        my ( $memkey, $uid, $pid ) = ( $1, $2, $3 );

        if ( $memkey eq 'logprop2' ) {
            next unless ref $v eq "HASH";

            my @vkeys = keys %$v;
            next if $vkeys[0] =~ /\D/;

            delete $needprops{$pid};
            $hashref->{$pid} = $v;
        }

        if ( $memkey eq 'rp' ) {
            delete $needrc{$pid};
            $rc{$pid} = int($v);  # change possible "0   " (true) to "0" (false)
        }
    }

    foreach ( keys %rc ) {
        $hashref->{$_}{'replycount'} = $rc{$_};
    }

    unless ( %needprops || %needrc ) {
        for my $jitemid ( keys %$hashref ) {
            convert_href_props( $hashref->{$jitemid} );
        }

        return;
    }

    unless ( $db ) {
        my $u = LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) :  LJ::get_cluster_reader($u);

        return unless $db;
    }

    if ( %needprops ) {
        LJ::load_props("log");
        my $in = join(",", keys %needprops);
        my $sth = $db->prepare("SELECT jitemid, propid, value FROM logprop2 ".
                                 "WHERE journalid=? AND jitemid IN ($in)");
        $sth->execute($userid);

        while (my ($jitemid, $propid, $value) = $sth->fetchrow_array) {
            $hashref->{$jitemid}->{ $propid } = $value;
        }

        foreach my $id (keys %needprops) {
            LJ::MemCache::set([$userid,"logprop2:$userid:$id"], $hashref->{$id} || {});
          }
    }

    if (%needrc) {
        my $in = join(",", keys %needrc);
        my $sth = $db->prepare("SELECT jitemid, replycount FROM log2 WHERE journalid=? AND jitemid IN ($in)");
        $sth->execute($userid);
        while (my ($jitemid, $rc) = $sth->fetchrow_array) {
            $hashref->{$jitemid}->{'replycount'} = $rc;
            LJ::MemCache::add(LJ::Entry::reply_count_memkey($userid, $jitemid), $rc);
        }
    }

    for my $jitemid ( keys %$hashref ) {
        convert_href_props( $hashref->{$jitemid} );
    }
}

# <LJFUNC>
# name: LJ::convert_href_props
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub convert_href_props {
    my $href = shift;
    my %new_href;
    LJ::load_props('log');

    for my $key ( keys %$href ) {
        my $prop = $href->{$key};

        if ( $key eq 'replycount' ) {
            $new_href{ 'replycount' } = $prop;
        }
        elsif ( exists $LJ::CACHE_PROPID{'log'}->{$key} ) {
            $new_href{ $LJ::CACHE_PROPID{'log'}->{$key}->{'name'} } = $prop;
        }
    }

    %$href = %new_href;
}

# <LJFUNC>
# name: LJ::load_log_props2multi
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_log_props2multi
{
    &nodb;
    my ($ids, $props) = @_;
    _get_posts_raw_wrapper($ids, "prop", $props);
}

# <LJFUNC>
# name: LJ::delete_entry
# des: Deletes a user's journal entry
# args: uuserid, jitemid, quick?, anum?
# des-uuserid: Journal itemid or $u object of journal to delete entry from
# des-jitemid: Journal itemid of item to delete.
# des-quick: Optional boolean.  If set, only [dbtable[log2]] table
#            is deleted from and the rest of the content is deleted
# des-anum: The log item's anum, which'll be needed to delete lazily
#           some data in tables which includes the anum, but the
#           log row will already be gone so we'll need to store it for later.
# returns: boolean; 1 on success, 0 on failure.
# </LJFUNC>
sub delete_entry
{
    my ($uuserid, $jitemid, $quick, $anum) = @_;
    my $jid = LJ::want_userid($uuserid);
    my $u = ref $uuserid ? $uuserid : LJ::load_userid($jid);
    $jitemid += 0;

    my $and;
    if (defined $anum) { $and = "AND anum=" . ($anum+0); }

    LJ::run_hooks("deletepost", $jid, $jitemid, $anum);

    # delete tags
    LJ::Tags::delete_logtags($u, $jitemid);

    LJ::run_hooks('report_entry_delete', $u->{'userid'}, $jitemid);
    my $dc = $u->log2_do(undef, "DELETE FROM log2 WHERE journalid=$jid AND jitemid=$jitemid $and");
    LJ::MemCache::delete([$jid, "log2:$jid:$jitemid"]);
    LJ::MemCache::decr([$jid, "log2ct:$jid"]) if $dc > 0;

    if ( $jitemid == $u->get_sticky_entry_id() ){
        $u->remove_sticky_entry_id();
    }

    # if this is running the second time (started by the cmd buffer),
    # the log2 row will already be gone and we shouldn't check for it.
    my $sclient = $quick ? LJ::theschwartz() : undef;
    if ($quick && $sclient) {
        return 1 if $dc < 1;  # already deleted?
        return 1 if $sclient->insert("LJ::Worker::DeleteEntry", {
            uid     => $jid,
            jitemid => $jitemid,
            anum    => $anum,
        });
        return 0;
    }

    # delete from clusters
    LJ::run_hooks('report_entry_text_delete', $jid, $jitemid);
    foreach my $t (qw(logtext2 logprop2 logsec2)) {
        $u->do("DELETE FROM $t WHERE journalid=$jid AND jitemid=$jitemid");
    }
    $u->dudata_set('L', $jitemid, 0);

    # delete all comments
    LJ::delete_all_comments($u, 'L', $jitemid);

    return 1;
}

# <LJFUNC>
# name: LJ::mark_entry_as_spam
# class: web
# des: Copies an entry in a community into the global [dbtable[spamreports]] table.
# args: journalu_uid, jitemid
# des-journalu_uid: User object of journal (community) entry was posted in, or the userid of it.
# des-jitemid: ID of this entry.
# returns: 1 for success, 0 for failure
# </LJFUNC>
sub mark_entry_as_spam {
    my ($journalu, $jitemid) = @_;
    $journalu = LJ::want_user($journalu);
    $jitemid += 0;
    return 0 unless $journalu && $jitemid;

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbcr && $dbh;

    my $item = LJ::get_log2_row($journalu, $jitemid);
    return 0 unless $item;

    # step 1: get info we need
    my $logtext = LJ::get_logtext2($journalu, $jitemid);
    my ($subject, $body, $posterid) = ($logtext->{$jitemid}[0], $logtext->{$jitemid}[1], $item->{posterid});
    return 0 unless $body;

    # step 2: insert into spamreports
    $dbh->do('INSERT INTO spamreports (reporttime, posttime, journalid, posterid, subject, body, report_type) ' .
             'VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(?), ?, ?, ?, ?, \'entry\')',
              undef, $item->{logtime}, $journalu->{userid}, $posterid, $subject, $body);

    LJ::run_hooks('spam_entry', $journalu, $item->{ditemid}, $posterid);

    return 0 if $dbh->err;
    return 1;
}

# Same as previous, but mark as spam moderated event selected by modid.
sub reject_entry_as_spam {
    my ($journalu, $modid) = @_;
    $journalu = LJ::want_user($journalu);
    $modid += 0;
    return 0 unless $journalu && $modid;

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbcr && $dbh;

    # step 1: get info we need
    my ($posterid, $logtime) = $dbcr->selectrow_array(
        "SELECT posterid, logtime FROM modlog WHERE journalid=? AND modid=?",
        undef, $journalu->{'userid'}, $modid);

    my $frozen = $dbcr->selectrow_array(
        "SELECT request_stor FROM modblob WHERE journalid=? AND modid=?",
        undef, $journalu->{'userid'}, $modid);

    use Storable;
    my $req = $frozen ? Storable::thaw($frozen) : {};

    my ($subject, $body) = ($req->{subject}, $req->{event});
    return 0 unless $body;

    # step 2: insert into spamreports
    $dbh->do('INSERT INTO spamreports (reporttime, posttime, journalid, posterid, subject, body, report_type) ' .
             'VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(?), ?, ?, ?, ?, \'entry\')',
              undef, $logtime, $journalu->{userid}, $posterid, $subject, $body);

    LJ::run_hooks('spam_entry', $journalu, $modid, $posterid);

    return 0 if $dbh->err;
    return 1;
}

# replycount_do
# input: $u, $jitemid, $action, $value
# action is one of: "init", "incr", "decr"
# $value is amount to incr/decr, 1 by default

sub replycount_do {
    my ($u, $jitemid, $action, $value) = @_;

    # check action name
    die "unknown action: $action" 
        unless $action =~ /^(init)|(incr)|(decr)$/;
    
    $value = 1 unless defined $value;
    my $uid = $u->{'userid'};
    my $memkey = LJ::Entry::reply_count_memkey($uid, $jitemid);

    # "init" is easiest and needs no lock (called before the entry is live)
    if ($action eq 'init') {
        LJ::MemCache::set($memkey, "0   ");
        return 1;
    }

    return 0 unless $u->writer;
    
    ##
    my $update_memc = $action eq 'decr'
            ? sub { LJ::MemCache::decr($memkey, $value) }
            : sub { LJ::MemCache::incr($memkey, $value) };
    
    my $entry = LJ::Entry->new( $u, 'jitemid' => $jitemid );
    LJ::run_hooks( 'replycount_change', $entry );

    ##
    my $sql_sign = $action eq 'decr' ? '-' : '+';
    my $sql = "UPDATE log2 SET replycount=LAST_INSERT_ID(replycount $sql_sign $value) WHERE journalid=? AND jitemid=?";
    
    unless ( LJ::MemCache::can_gets() ){
    # used Cache::Memcached driver that does not support 'gets' and 'cas' commands
        $u->selectrow_array("SELECT GET_LOCK(?,10)", undef, $memkey);

        my $ret = $update_memc->();
        LJ::run_hooks('report_entry_update', $uid, $jitemid);
        $u->do($sql, undef, $uid, $jitemid);

        if (@LJ::MEMCACHE_SERVERS && ! defined $ret) {
            my ($rc) = $u->selectrow_array("SELECT LAST_INSERT_ID()");
            LJ::MemCache::set($memkey, sprintf("%-4d", $rc)) if defined $rc;
        }

        $u->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $memkey);
    
    } else {
    # used Cache::Memcached::Fast

        my $ret = $update_memc->();
        LJ::run_hooks('report_entry_update', $uid, $jitemid);
        $u->do($sql, undef, $uid, $jitemid);
        if (@LJ::MEMCACHE_SERVERS and not defined $ret) {
            ## Lock free update 
            my $max_loops = 100; # prevent infinite loop
            while ($max_loops--){
                my $gets = LJ::MemCache::gets($memkey); # get [cas, $val]
                if (not $gets){
                    my $add_res = LJ::MemCache::add($memkey, sprintf("%-4d", 1)); # init value
                    next;
                }
                my ($rc) = $u->selectrow_array("SELECT replycount FROM log2 WHERE journalid=$uid AND jitemid=$jitemid");
                my $cas = $gets->[0];
                LJ::MemCache::cas($memkey, $cas, $rc);
            }
        }
    }

    return 1;
}

# replyspamcount_do
# input: $u, $jitemid, $action, $value
# action is one of: "init", "incr", "decr"

sub replyspamcount_do {
    my ($u, $jitemid, $action, $value) = @_;

    # check action name
    die "unknown action: $action" 
        unless $action =~ /^(init)|(incr)|(decr)$/;
    
    return 0 unless $value;
    
    my $entry = LJ::Entry->new( $u, 'jitemid' => $jitemid );
    my $spam_counter = $entry->prop('spam_counter') || 0;
    
    if ($action eq 'init') {
        $entry->set_prop('spam_counter', 0);
        return 1;
    } elsif ($action eq 'decr') {
        return 0 if $spam_counter - $value < 0;
        $entry->set_prop('spam_counter', $spam_counter - $value);
    } elsif ($action eq 'incr') {
        $entry->set_prop('spam_counter', $spam_counter + $value);
    }
    
    return 1;
}

# <LJFUNC>
# name: LJ::get_logtext2
# des: Efficiently retrieves a large number of journal entry text, trying first
#      slave database servers for recent items, then the master in
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_talktext2]].
# args: u, opts?, jitemid*
# returns: hashref with keys being jitemids, values being [ $subject, $body ]
# des-opts: Optional hashref of special options.  NOW IGNORED (2005-09-14)
# des-jitemid: List of jitemids to retrieve the subject & text for.
# </LJFUNC>
sub get_logtext2 {
    my $u = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'} + 0;
    my $opts = ref $_[0] ? shift : {};  # this is now ignored

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;

    foreach (@_) {
        my $id = $_ + 0;
        $need{$id} = 1;
        push @mem_keys, [$journalid, "logtext:$clusterid:$journalid:$id"];
    }

    # pass 1: memcache
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};

    while (my ($k, $v) = each %$mem) {
        next unless $v;
        $k =~ /:(\d+):(\d+):(\d+)/;
        delete $need{$3};
        $lt->{$3} = $v;
    }

    return $lt unless %need;

    # pass 2: databases
    my $db = LJ::get_cluster_def_reader($clusterid);
    die "Can't get database handle loading entry text" unless $db;

    my $jitemid_in = join(", ", keys %need);
    my $sth = $db->prepare("SELECT jitemid, subject, event FROM logtext2 ".
                           "WHERE journalid=$journalid AND jitemid IN ($jitemid_in)");
    $sth->execute;

    while (my ($id, $subject, $event) = $sth->fetchrow_array) {
        LJ::text_uncompress(\$event);
        my $val = [ $subject, $event ];
        $lt->{$id} = $val;
        LJ::MemCache::add([$journalid, "logtext:$clusterid:$journalid:$id"], $val);
        delete $need{$id};
    }

    return $lt;
}

# <LJFUNC>
# name: LJ::item_link
# class: component
# des: Returns URL to view an individual journal item.
# info: The returned URL may have an ampersand in it.  In an HTML/XML attribute,
#       these must first be escaped by, say, [func[LJ::ehtml]].  This
#       function doesn't return it pre-escaped because the caller may
#       use it in, say, a plain-text e-mail message.
# args: u, itemid, anum?
# des-itemid: Itemid of entry to link to.
# des-anum: If present, $u is assumed to be on a cluster and itemid is assumed
#           to not be a $ditemid already, and the $itemid will be turned into one
#           by multiplying by 256 and adding $anum.
# returns: scalar; unescaped URL string
# </LJFUNC>
sub item_link
{
    my ($u, $itemid, $anum, @args) = @_;
    my $ditemid = $itemid*256 + $anum;

    # XXX: should have an option of returning a url with escaped (&amp;)
    #      or non-escaped (&) arguments.  a new link object would be best.
    my $args = @args ? "?" . join("&amp;", @args) : "";
    return LJ::journal_base($u) . "/$ditemid.html$args";
}

# <LJFUNC>
# name: LJ::expand_embedded
# class:
# des: Used for expanding embedded content like polls, for entries.
# info: The u-object of the journal in question transmits to the function
#       and its hooks.
# args: u, ditemid, remote, eventref, opts?
# des-eventref:
# des-opts:
# returns:
# </LJFUNC>

sub expand_embedded
{
    &nodb;
    my ($u, $ditemid, $remote, $eventref, %opts) = @_;
    LJ::Poll->expand_entry($eventref) unless $opts{preview};
    LJ::EmbedModule->expand_entry($u, $eventref, %opts);
    LJ::run_hooks("expand_embedded", $u, $ditemid, $remote, $eventref, %opts);
}

# <LJFUNC>
# name: LJ::item_toutf8
# des: convert one item's subject, text and props to UTF-8.
#      item can be an entry or a comment (in which cases props can be
#      left empty, since there are no 8bit talkprops).
# args: u, subject, text, props
# des-u: user hashref of the journal's owner
# des-subject: ref to the item's subject
# des-text: ref to the item's text
# des-props: hashref of the item's props
# returns: nothing.
# </LJFUNC>
sub item_toutf8
{
    my ($u, $subject, $text, $props) = @_;
    return unless $LJ::UNICODE;
    $props ||= {};

    my $convert = sub {
        my $rtext = shift;
        my $error = 0;
        my $res = LJ::text_convert($$rtext, $u, \$error);
        if ($error) {
            LJ::text_out($rtext);
        } else {
            $$rtext = $res;
        };
        return;
    };

    $convert->($subject);
    $convert->($text);

    # FIXME: really convert all the props?  what if we binary-pack some in the future?
    foreach(keys %$props) {
        $convert->(\$props->{$_});
    }
    return;
}

# --= counters API for 'I like it!' button support =--
# TODO: Must we check is this entry really exists?
# TODO: Must we clean rates when delete entry?

# LJ::is_eventrate_enable($journal);
# returns non zero if rate is enabled for selected journal.
sub is_eventrate_enable {
    my $journal = shift;
    $journal = LJ::get_remote() unless $journal;
    return ($journal->prop('ilikeit_enable')) ? 1 : 0;
}

sub _update_total_counter {
    my ($dbcm, $journalid, $itemid, $counter) = @_;

    my $count = LJ::get_eventratescounters($journalid, $itemid) + $counter;

    $count = 0 if $count < 0;

    if ($count) {
        $dbcm->do("REPLACE eventratescounters (journalid,itemid,count)".
            "VALUES($journalid,$itemid,$count)");
    } else {
        $dbcm->do("DELETE FROM eventratescounters".
            " WHERE journalid=$journalid AND itemid=$itemid");
    }
    LJ::MemCache::set([$journalid, "eventratescounts:$journalid:$itemid"], $count);
}

# LJ::reset_eventrate($journalid, $itemid [, $userid[, userid ...]]);
sub reset_eventrate
{
    my $journalid   = shift;
    my $itemid      = shift;
    my @userids     = @_;

    my $journal = LJ::want_user($journalid);
    return 0 unless is_eventrate_enable($journal);

    unless (@userids) {
        my $remote = LJ::get_remote();
        return 0 unless $remote;
        @userids = ( $remote->userid() );
    }

    # get a list if user id which was rate selected entry.
    @userids = LJ::get_eventrates(
        journalid   => $journalid,
        itemid      => $itemid,
        userids     => \@userids,
    );

    my $clusterid = $journal->{'clusterid'};

    my $dbcm = LJ::get_cluster_master($clusterid);
    die "Can't get database handle" unless $dbcm;

    my $sth = $dbcm->prepare("DELETE FROM eventrates".
        " WHERE journalid = ? AND itemid = ? AND userid = ?") or die $dbcm->errstr;

    my $counter = 0;
    foreach my $uid (@userids) {
        # TODO: check rights of $remote to rate a post as $uid.
        if ($sth->execute($journalid,$itemid,$uid)) {
            LJ::MemCache::set([$journalid,"eventrates:$journalid:$itemid:$uid"], 0);
            $counter++;
        } else {
            warn "SQL DELETE error: ", $dbcm->errstr,  "\n";
        }
    }

    _update_total_counter($dbcm, $journalid, $itemid, -$counter) if $counter;

    return $counter;
}

# LJ::set_eventrate($journalid, $itemid, $userid [, $userid ...]);
# TODO: userid must be from LJ::get_remote() in security reasons.
sub set_eventrate
{
    my $journalid   = shift;
    my $itemid      = shift;
    my @userids     = @_;

    my $journal = LJ::want_user($journalid);
    return 0 unless is_eventrate_enable($journal);

    my $clusterid = $journal->{'clusterid'};

    my $dbcm = LJ::get_cluster_master($clusterid);
    die "Can't get database handle" unless $dbcm;

    my $sth = $dbcm->prepare("INSERT INTO eventrates(journalid,itemid,userid,changetime)".
        " VALUES (?, ?, ?, NOW())") or die $dbcm->errstr;

    my @uids = ();
    unless (@userids) {
        my $remote = LJ::get_remote();
        return 0 unless $remote;
        @userids = ( $remote->userid() );
    }

    foreach my $uid (@userids) {
        # TODO: check rights of $remote to rate a post as $uid.
        if ($sth->execute($journalid,$itemid,$uid)) {
            LJ::MemCache::set([$journalid,"eventrates:$journalid:$itemid:$uid"], 1);
            push @uids, $uid;
        } else {
            warn "Error: ", $dbcm->errstr,  "\n"
                unless $dbcm->errstr =~ /Duplicate entry/i;
            # 'Duplicate entry' is normal. This is means that sombody try to
            # rate same post twice.
        }
    }

    _update_total_counter($dbcm, $journalid, $itemid, scalar @uids) if @uids;

    return @uids;
}

# LJ::get_eventratescounters($journalid,$itemid)
sub get_eventratescounters
{
    my $journalid   = shift;
    my $itemid      = shift;

    my $journal = LJ::want_user($journalid);
    return unless is_eventrate_enable($journal);

    my $count = LJ::MemCache::get([$journalid, "eventratescounts:$journalid:$itemid"]);
    return $count if $count;

    my $clusterid = $journal->{'clusterid'};

    my $db = LJ::get_cluster_def_reader($clusterid);
    die "Can't get database handle" unless $db;

    $count = $db->selectrow_array("SELECT count FROM eventratescounters".
        " WHERE journalid=$journalid AND itemid=$itemid");

    $count ||= 0;

    LJ::MemCache::set([$journalid, "eventratescounts:$journalid:$itemid"], $count);

    return $count;
}

# LJ::get_eventrates(
#   journalid => $journalid,
#   itemid => $itemid,
# [ userids => \@userids, ]
# [ limits => ['start,' . ] 'limit' ],
# );
#
# Parameters between '[' and ']' is optional.
sub get_eventrates
{
    my %opts    = @_;

    my $journalid   = $opts{'journalid'};

    my $journal = LJ::want_user($journalid);
    return unless is_eventrate_enable($journal);

    my $itemid      = $opts{'itemid'};

    my @userids = ();

    # If we has 'userids' parameter and it is array ref
    # and this array contains non zero user id,
    # then we check for this list of users.
    # Else we return complete list of users who rates post
    # specified by journalid and jitemid.
    if ($opts{'userids'} &&
        'ARRAY' eq ref $opts{'userids'} &&
        grep { $_+0 > 0 } @{$opts{'userids'}}) {    # check if this userid(s) is in a list
        # pass 1: memcache

        # keep track of itemids we still need to load.
        my %need;
        my @mem_keys;
        foreach (@{$opts{'userids'}}) {
            my $id = $_+0;
            next unless $id; # Don't remember anonymous.
            $need{$id} = 1;
            push @mem_keys, [ $journalid, "eventrates:$journalid:$itemid:$id" ];
        }

        my $mem = LJ::MemCache::get_multi(@mem_keys) || {};

        while (my ($k, $v) = each %$mem) {
            next unless $v;
            my (undef, undef, undef, $uid) = split(":", $k);
            delete $need{$uid};
            push @userids, $uid
        }

        return @userids unless %need;   # all keys was found in memcache

        # pass 2: databases

        my $clusterid = $journal->{'clusterid'};

        my $db = LJ::get_cluster_def_reader($clusterid);
        die "Can't get database handle" unless $db;

        my $userid_in = join(", ", keys %need);

        my $sth = $db->prepare("SELECT userid FROM eventrates".
            " WHERE journalid=$journalid AND itemid=$itemid AND userid in ($userid_in)");
        $sth->execute;

        while (my ($id) = $sth->fetchrow_array) {
            push @userids, $id;
            LJ::MemCache::set([$journalid,"eventrates:$journalid:$itemid:$id"], 1);
        }

    } else {   # fetch and return list of user ids

        my $limits = $opts{'limits'} || 10;

        my $clusterid = $journal->{'clusterid'};

        my $db = LJ::get_cluster_def_reader($clusterid);
        die "Can't get database handle loading entry text" unless $db;

        my $sth = $db->prepare("SELECT userid FROM eventrates".
            " WHERE journalid=? AND itemid=?".
            " ORDER BY changetime LIMIT $limits");

        $sth->execute($journalid,$itemid);
        while (my ($id) = $sth->fetchrow_array) {
            push @userids, $id;
            LJ::MemCache::set([$journalid,"eventrates:$journalid:$itemid:$id"], 1);
        }
    }

    return @userids;
}

sub get_aggregated_entry {
    my ($row, $opts) = @_;
    my $entry = eval { LJ::Entry->new_from_item_hash($row) };
    
    return unless $entry;

    return unless $opts->{attrs} && ref $opts->{attrs}; 

    foreach my $method (@{$opts->{attrs}}) {
        my @result = eval {$entry->$method};
        ($row->{$method}) = @result > 1 ? \@result : @result;
    }

    my $remote;

    if ($opts->{trim_widgets}) {
        $row->{event_raw} ||= $entry->event_raw;
        $row->{event_raw} = LJ::trim_widgets(
            length     => $opts->{trim_widgets},
            img_length => $opts->{widgets_img_length},
            text       => $row->{event_raw},
            read_more  => '<a href="' . $entry->url . '"> ...</a>',
        )
    };

    if ($opts->{get_video_ids}) {
        $row->{event_raw} ||= $entry->event_raw;
        LJ::EmbedModule->expand_entry($entry->poster, \$row->{event_raw}, get_video_id => 1);
    }

    if ($opts->{get_polls}) {
        $row->{event_raw} ||= $entry->event_raw;
        $remote = LJ::load_userid($opts->{remote_id}) if (!$remote && $opts->{remote_id}); 
        LJ::Poll->expand_entry(\$row->{event_raw}, getpolls => 1, viewer => $remote );
    }

    if ($opts->{asxml}) {
        my $tidy = LJ::Tidy->new();
        $row->{event_raw} ||= $entry->event_raw;
        $row->{event_raw} = $tidy->clean( $row->{event_raw} );
    }
    
    if ($opts->{parseljtags}) {
        $row->{event_raw} ||= $entry->event_raw;
        $row->{event_raw} = LJ::convert_lj_tags_to_links(
            event => $row->{event_raw},
            embed_url => $entry->url);
    }

}

1;
