#!/usr/bin/perl
package LJ::EmbedModule;
use strict;
use Carp qw (croak);
use Class::Autouse qw (
                       LJ::Auth
                       );

# can optionally pass in an id of a module to change its contents
# returns module id
sub save_module {
    my ($class, %opts) = @_;

    my $contents = $opts{contents} || '';
    my $id       = $opts{id};
    my $journal  = $opts{journal}
        or croak "No journal passed to LJ::EmbedModule::save_module";

    # are we creating a new entry?
    unless ($id) {
        $id = LJ::alloc_user_counter($journal, 'D')
            or die "Could not allocate embed module ID";
    }

    $journal->do("REPLACE INTO embedcontent (userid, moduleid, content) VALUES ".
                 "(?, ?, ?)", undef, $journal->userid, $id, $contents);
    die $journal->errstr if $journal->err;

    # save in memcache
    my $memkey = $class->memkey($journal->userid, $id);
    LJ::MemCache::set($memkey, $contents);

    return $id;
}

# takes a scalarref to entry text and expands lj-embed tags
sub expand_entry {
    my ($class, $journal, $entryref) = @_;

    my $expand = sub {
        my $moduleid = shift;
        return "[Error: no module id]" unless $moduleid;
        return $class->module_iframe_tag($journal, $moduleid);
    };

    $class->parse_module_embed($journal, $entryref, expand => 1);
}

# take a scalarref to a post, parses any lj-embed tags, saves the contents
# of the tags and replaces them with a module tag with the id.
sub parse_module_embed {
    my ($class, $journal, $postref, %opts) = @_;

    return unless $postref && $$postref;

    # do we want to replace with the lj-embed tags or iframes?
    my $expand = $opts{expand};

    # if this is editing mode, then we want to expand embed tags for editing
    my $edit = $opts{edit};

    my $p = HTML::TokeParser->new($postref);
    my $newdata = '';
    my $embedopen = 0;
    my $embedcontents = '';
    my $embedid;

  TOKEN:
    while (my $token = $p->get_token) {
        my $type = $token->[0];
        my $tag  = $token->[1];
        my $attr = $token->[2];  # hashref

        if ($type eq "S") {
            # start tag
            if (lc $tag eq "lj-embed" && ! $LJ::DISABLED{embed_module}) {
                if ($attr->{'/'}) {
                    # this is an already-existing lj-embed tag.
                    if ($expand) {
                        if ($attr->{id}+0) {
                            $newdata .= $class->module_iframe_tag($journal, $attr->{id});
                        } else {
                            $newdata .= "[Error: lj-embed tag with no id]";
                        }
                    } elsif ($edit) {
                        my $content = $class->module_content(moduleid  => $attr->{id},
                                                             journalid => $journal->id);
                        $newdata .= qq{<lj-embed id="$attr->{id}">\n$content\n</lj-embed>};
                    } else {
                        $newdata .= qq(<lj-embed id="$attr->{id}" />);
                    }
                    next TOKEN;
                } else {
                    $embedopen = 1;
                    $embedcontents = '';
                    $embedid = $attr->{id};
                }

                next TOKEN;
            } else {
                my $tagcontent = "<$tag";
                my $selfclose;
                foreach (keys %$attr) {
                    if ($_ eq '/') {
                        $selfclose = 1;
                        next;
                    }

                    $tagcontent .= " $_=\"$attr->{$_}\"";
                }
                $tagcontent .= $selfclose ? "/>" : ">";

                if ($embedopen) {
                    # capture this in the embed contents cuz we're in an lj-embed tag
                    $embedcontents .= $tagcontent;
                } else {
                    # this is outside an lj-embed tag, ignore it
                    $newdata .= $tagcontent;
                }
            }
        } elsif ($type eq "T" || $type eq "D") {
            # tag contents
            if ($embedopen) {
                # we're in a lj-embed tag, capture the contents
                $embedcontents .= $token->[1];
            } else {
                # whatever, we don't care about this
                $newdata .= $token->[1];
            }
        } elsif ($type eq 'E') {
            # end tag
            if ($tag eq 'lj-embed') {
                if ($embedopen) {
                    $embedopen = 0;
                    if ($embedcontents) {
                        # ok, we have a lj-embed tag with stuff in it.
                        # save it and replace it with a tag with the id
                        $embedid = LJ::EmbedModule->save_module(
                                                                contents => $embedcontents,
                                                                id       => $embedid,
                                                                journal  => $journal,
                                                                );

                        if ($embedid) {
                            if ($expand) {
                                $newdata .= $class->module_iframe_tag($journal, $embedid);
                            } elsif ($edit) {
                                my $content = $class->module_content(moduleid  => $attr->{id},
                                                                     journalid => $journal->id);
                                $newdata .= qq{<lj-embed id="$attr->{id}">\n$content\n</lj-embed>};
                            } else {
                                $newdata .= qq(<lj-embed id="$embedid" />);
                            }
                        }
                    }
                    $embedid = undef;
                } else {
                    $newdata .= "[Error: close lj-embed tag without open tag]";
                }
            } else {
                if ($embedopen) {
                    $embedcontents .= "</$tag>";
                } else {
                    $newdata .= "</$tag>";
                }
            }
        }
    }

    $$postref = $newdata;
}

sub module_iframe_tag {
    my ($class, $u, $moduleid) = @_;

    my $journalid = $u->userid;
    $moduleid += 0;

    my $auth_token = LJ::eurl(LJ::Auth->sessionless_auth_token('embedcontent', moduleid => $moduleid, journalid => $journalid));
    return qq {<iframe src="http://$LJ::EMBED_MODULE_DOMAIN/?journalid=$journalid&moduleid=$moduleid&auth_token=$auth_token" class="lj_embedcontent"></iframe>};
}

sub module_content {
    my ($class, %opts) = @_;

    my $moduleid  = $opts{moduleid}+0 or croak "No moduleid";
    my $journalid = $opts{journalid}+0 or croak "No journalid";

    # try memcache
    my $memkey = $class->memkey($journalid, $moduleid);
    my $content = LJ::MemCache::get($memkey);
    return $content if $content;

    my $journal = LJ::load_userid($journalid) or die "Invalid userid $journalid";
    my $dbid; # module id from the database
    ($content, $dbid) = $journal->selectrow_array("SELECT content, moduleid FROM embedcontent WHERE " .
                                                  "moduleid=? AND userid=?",
                                                  undef, $moduleid, $journalid);
    die $journal->errstr if $journal->err;

    $content ||= '';
    # save in memcache if we got something out of the db
    LJ::MemCache::set($memkey, $content) if $dbid;

    # if we didn't get a moduleid out of the database then this entry is not valid
    return $dbid ? $content : "[Invalid lj-embed id $moduleid]";
}

sub memkey {
    my ($class, $journalid, $moduleid) = @_;
    return [$journalid, "embedcont:$journalid:$moduleid"];
}

1;
