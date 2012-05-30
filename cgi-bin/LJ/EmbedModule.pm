#!/usr/bin/perl
package LJ::EmbedModule;
use strict;
use Carp qw (croak);
use Class::Autouse qw (
                       LJ::Auth
                       HTML::TokeParser
                       );
use Encode;

# states for a finite-state machine we use in parse()
use constant {
    # reading plain html without <object>, <embed> or <lj-embed>
    REGULAR => 1,

    # inside <object> or <embed> tag
    IMPLICIT => 2,

    # inside explicit <lj-embed> tag
    EXPLICIT => 3,

    # maximum embed width and height
    MAX_WIDTH => 1100,
    MAX_HEIGHT => 1100,
};

# can optionally pass in an id of a module to change its contents
# returns module id
sub save_module {
    my ($class, %opts) = @_;

    my $contents = $opts{contents} || '';
    my $id       = $opts{id};
    my $journal  = $opts{journal}
        or croak "No journal passed to LJ::EmbedModule::save_module";
    my $preview = $opts{preview};

    my $need_new_id = !defined $id;

    if (defined $id) {
        my $old_content = $class->module_content( moduleid => $id,
            journalid => LJ::want_userid($journal) ) || '';
        my $new_content = $contents;

        # old content is cleaned by module_content(); new is not
        LJ::CleanHTML::clean(\$new_content, {
            addbreaks => 0,
            tablecheck => 0,
            mode => 'allow',
            allow => [qw(object embed)],
            deny => [qw(script iframe)],
            remove => [qw(script iframe)],
            ljcut_disable => 1,
            cleancss => 0,
            extractlinks => 0,
            noautolinks => 1,
            extractimages => 0,
            noexpandembedded => 1,
            transform_embed_nocheck => 1,
        });

        $old_content =~ s/\s//sg;
        $new_content =~ s/\s//sg;

        $need_new_id = 1 unless $old_content eq $new_content;
    }

    # are we creating a new entry?
    if ($need_new_id) {
        $id = LJ::alloc_user_counter($journal, 'D')
            or die "Could not allocate embed module ID";
    }

    my $cmptext = 'C-' . LJ::text_compress($contents);

    ## embeds for preview are stored in a special table,
    ## where new items overwrites old ones
    my $table_name = ($preview) ? 'embedcontent_preview' : 'embedcontent';
    $journal->do("REPLACE INTO $table_name (userid, moduleid, content) VALUES ".
                "(?, ?, ?)", undef, $journal->userid, $id, $cmptext);
    die $journal->errstr if $journal->err;

    # save in memcache
    my $memkey = $class->memkey($journal->userid, $id, $preview);
    LJ::MemCache::set($memkey, $contents);

    return $id;
}

# changes <div class="ljembed"... tags from the RTE into proper lj-embed tags
sub transform_rte_post {
    my ($class, $txt) = @_;
    return $txt unless $txt && $txt =~ /ljembed/i;
    # ghetto... shouldn't use regexes to parse this
    $txt =~ s/<div\s*class="ljembed"\s*(embedid="(\d+)")?\s*>(((?!<\/div>).)*)<\/div>/<lj-embed id="$2">$3<\/lj-embed>/ig;
    $txt =~ s/<div\s*(embedid="(\d+)")?\s*class="ljembed"\s*>(((?!<\/div>).)*)<\/div>/<lj-embed id="$2">$3<\/lj-embed>/ig;
    return $txt;
}

# takes a scalarref to entry text and expands lj-embed tags
# REPLACE
sub expand_entry {
    my ($class, $journal, $entryref, %opts) = @_;

    $$entryref =~ s/(<lj\-embed[^>]+\/>)/$class->_expand_tag($journal, $1, $opts{edit}, %opts)/ge;
}

sub _expand_tag {
    my( $class, $journal, $tag, $edit, %opts ) = @_;

    my %attrs = $tag =~ /(\w+)="?(\-?\d+)"?/g;

    return '[invalid lj-embed, id is missing]' unless $attrs{id};

    if ($opts{expand_full}){
        return $class->module_content(moduleid  => $attrs{id}, journalid => $journal->id);
    } elsif ($edit) {
        return '<lj-embed ' . join(' ', map {"$_=\"$attrs{$_}\""} keys %attrs) . ">\n" .
                 $class->module_content(moduleid  => $attrs{id}, journalid => $journal->id) .
                 "\n<\/lj-embed>";
    } elsif ($opts{expand_to_link}) {
        return "<a href=\"".$opts{expand_to_link}->{link} . "\"" .
            ($opts{expand_to_link}->{target} ?
                (" target=\"" . $opts{expand_to_link}->{target} . "\"") : ''
            ) .
            ">" . $opts{expand_to_link}->{caption} . "</a>";
    } elsif ($opts{get_video_id}) {
        my $code = $class->module_content(moduleid  => $attrs{id}, journalid => $journal->id);
        my %params = $class->embed_video_info($code);

        my $out=  '<lj-embed id="'. $attrs{id} .'" ';
        while (my ($name, $val) = each %params){
            $out .= qq|$name="$val" |;
        }
        $out .= '/>';

        return $out;

    } else {
        @opts{qw /width height/} = @attrs{qw/width height/};
        return $class->module_iframe_tag($journal, $attrs{id}, %opts)
    }
};
sub embed_video_info {
    my ($class, $code) = @_;
    
    my %params = ();

    # LJSUP-8992
    if ($code =~ m!src=["']?http://www\.youtube\.com/(?:v|embed)/([\w\d\_\-]+)['"]?!) {
        $params{vid} = $1;
        $params{source} = 'youtube';

    } elsif ($code =~ m!src=["']?http://player\.vimeo\.com/video/(\d+)[?'"]?! ||
             $code =~ m!=["']?http://vimeo\.com/moogaloop\.swf\?[\d\w\_\-\&\;\=]*clip_id=(\d+)[&'"]?! ) {
        $params{vid}    = $1;
        $params{source} = 'vimeo';
    } elsif ($code =~ m!=["']?http://video\.rutube\.ru/([\dabcdef]+)['"]?!) {
        $params{vid} = $1;
        $params{source} = 'rutube';
    } elsif ($code =~ m!=["']?http://static\.video\.yandex\.ru/([\d\w\/\-\_\.]+)['"]?!) {
        $params{vid} = $1;
        $params{source} = 'yandex';
    } elsif ($code =~ m!http://img\.mail\.ru.+movieSrc=([\w\d\/\_\-\.]+)["']?!) { #"
        $params{vid} = $1;
        $params{source} = 'mail.ru';
    } elsif ($code =~ m!http://(vkontakte\.ru|vk\.com)/video_ext!) {
        my $source = $1;
        my %fields = ($code =~ /(oid|id|hash)=([\dabcdef]+)/gm);
        my $vid = delete $fields{id};
        %params = %fields;
        $params{source} = $source;
        $params{vid}    = $vid;
    }

    return %params;
}

sub add_user_to_embed {
    my ($class, $user_name, $postref) = @_;

    return unless $postref && $$postref;
    $$postref =~ s/(<\s*lj\-embed\s+id=)/<lj\-embed source_user="$user_name" id=/g;
}

# take a scalarref to a post, parses any lj-embed tags, saves the contents
# of the tags and replaces them with a module tag with the id.
# REPLACE
sub parse_module_embed {
    my ($class, $journal, $postref, %opts) = @_;

    return unless $postref && $$postref;

    return if LJ::conf_test($LJ::DISABLED{embed_module});

    # fast track out if we don't have to expand anything
    return unless $$postref =~ /lj\-embed|embed|object|iframe/i;

    # do we want to replace with the lj-embed tags or iframes?
    my $expand = $opts{expand};

    # if this is editing mode, then we want to expand embed tags for editing
    my $edit = $opts{edit};

    # previews are a special case (don't want to permanantly save to db)
    my $preview = $opts{preview};

    # deal with old-fashion calls
    if (($edit || $expand) && ! $preview) {
        return $class->expand_entry($journal, $postref, %opts);
    }

    my $text = Encode::decode_utf8($$postref);

    # ok, we can safely parse post text
    # machine state
    my $state = REGULAR;
    my $p = HTML::TokeParser->new(\$text);
    my $newtxt = '';
    my %embed_attrs = (); # ($eid, $ewidth, $eheight);
    my $embed = '';
    my @stack = ();
    my $next_preview_id = 1;

    while (my $token = $p->get_token) {
        my ($type, $tag, $attr) = @$token;
        $tag = lc $tag;
        my $newstate = undef;
        my $reconstructed = $class->reconstruct($token);

        if ($state == REGULAR) {
            if ( $tag eq 'lj-embed' && $type eq 'S' && ! $attr->{'/'} && !$attr->{'source_user'} ) {
                # <lj-embed ...>, not self-closed
                # switch to EXPLICIT state
                $newstate = EXPLICIT;

                # save embed id, width and height if they do exist in attributes
                if ($attr->{id}) {
                    $embed_attrs{id} = $attr->{id};
                }
 
                if ($attr->{width}) {
                    if ($attr->{width} > MAX_WIDTH) {
                        $embed_attrs{width} = MAX_WIDTH
                    } else {
                        $embed_attrs{width} = $attr->{width};
                    }
                }

                if ($attr->{height}) {
                    if ($attr->{height} > MAX_HEIGHT) {
                        $embed_attrs{height} = MAX_HEIGHT;
                    } else {
                        $embed_attrs{height} = $attr->{width};
                    }
                }

            } elsif ( $tag eq 'lj-embed' && $type eq 'S' && $attr->{'source_user'} ) {
                my $embed_ext = '';

                my $u = LJ::load_user($attr->{'source_user'});
                if ($u) {
                    if ($journal->equals($u)) {
                        $embed_attrs{id} = $attr->{id};

                        if ($attr->{width}) {
                            if ($attr->{width} > MAX_WIDTH) {
                                $embed_attrs{width} = MAX_WIDTH;
                            } else {
                                $embed_attrs{width} = $attr->{width};
                            }
                        }

                        if ($attr->{height}) {
                            if ($attr->{height} > MAX_HEIGHT) {
                                $embed_attrs{height} = MAX_HEIGHT;
                            } else {
                                $embed_attrs{height} = $attr->{height};
                            }
                        }

                        my @embed_attributes
                            = map { exists $embed_attrs{$_} ? "$_=\"$embed_attrs{$_}\"" : () } qw / id width height /;
                        $embed_ext = "<lj-embed " . join(' ', @embed_attributes) . "/>";
                    } else {
                        $embed_attrs{id} = undef;
                        $embed_ext = $class->module_content( moduleid  => $attr->{id},
                                                             journalid => $u->userid );
                        if ($embed_ext ne "") {
                            if ($attr->{width}) {
                                if ($attr->{width} > MAX_WIDTH) {
                                    $embed_attrs{width} = MAX_WIDTH;
                                } else {
                                    $embed_attrs{width} = $attr->{width};
                                }
                            }

                            if ($attr->{height}) {
                                if ($attr->{height} > MAX_HEIGHT) {
                                    $embed_attrs{height} = MAX_HEIGHT;
                                } else {
                                    $embed_attrs{height} = $attr->{height};
                                }
                            }
                        }
                    }
                }
                unless ($attr->{'/'}) {
                    $newstate = EXPLICIT;
                    # tag balance
                    push @stack, $tag;
                    $embed = $embed_ext;
                } else {
                    $newstate = REGULAR;
                    $newtxt .= $embed_ext;
                }

            } elsif (($tag eq 'object' || $tag eq 'embed' || $tag eq 'iframe') && $type eq 'S') {
                # <object> or <embed>
                # switch to IMPLICIT state unless it is a self-closed tag
                unless ($attr->{'/'}) {
                    $newstate = IMPLICIT;
                    # tag balance
                    push @stack, $tag;
                    $embed .= $reconstructed;
                } else {
                    $newstate = REGULAR;
                    $newtxt .= $reconstructed;
                }
                # append the tag contents to new embed buffer, so we can convert in to lj-embed later
            } else {
                # otherwise stay in REGULAR
                $newtxt .= $reconstructed;
            }
        } elsif ($state == IMPLICIT) {
            if ($tag eq 'object' || $tag eq 'embed' || $tag eq 'iframe') {
                if ($type eq 'E') {
                    # </object> or </embed>
                    # update tag balance, but only if we have a valid balance up to this moment
                    pop @stack if $stack[-1] eq $tag;
                    # switch to REGULAR if tags are balanced (stack is empty), stay in IMPLICIT otherwise
                    $newstate = REGULAR unless @stack;
                } elsif ($type eq 'S') {
                    # <object> or <embed>
                    # mind the tag balance, do not update it in case of a self-closed tag
                    push @stack, $tag unless $attr->{'/'};
                }
            }
            # append to embed buffer
            $embed .= $reconstructed;

        } elsif ($state == EXPLICIT) {
            if ($tag eq 'lj-embed' && $type eq 'E') {
                # </lj-embed> - that's the end of explicit embed block, switch to REGULAR
                $newstate = REGULAR;
            } else {
                # continue appending cwontents to embed buffer
                $embed .= $reconstructed;
            }
        } else {
            # let's be paranoid
            die "Invalid state: '$state'";
        }

        # we decided to switch back to REGULAR and have something in embed buffer
        # so let's save buffer as an embed module and start all over again
        if ($newstate == REGULAR && $embed) {
            $embed = Encode::encode_utf8($embed);
            if (!$embed_attrs{id} || $preview) {
                $embed_attrs{id} = $class->save_module(
                                            id => ($preview ? $next_preview_id++ : $embed_attrs{id}),
                                            contents => $embed,
                                            journal  => $journal,
                                            preview => $preview,
                );
            }

            $newtxt .= "<lj-embed " . join(' ', map { exists $embed_attrs{$_} ? "$_=\"$embed_attrs{$_}\"" : () } qw / id width height /) . "/>";
            $embed = '';
            %embed_attrs = ();
        }

        # switch the state if we have a new one
        $state = $newstate if defined $newstate;
    }

    # update passed text
    $$postref = Encode::encode_utf8($newtxt);
}

sub module_iframe_tag {
    my ($class, $u, $moduleid, %opts) = @_;

    return '' if $LJ::DISABLED{embed_module};

    my $journalid = $u->userid;
    $moduleid += 0;

    # parse the contents of the module and try to come up with a guess at the width and height of the content
    my $content = $class->module_content(moduleid => $moduleid, journalid => $journalid, preview => $opts{'preview'});
    my $preview = $opts{preview};
    my $width = 0;
    my $height = 0;
    my $p = HTML::TokeParser->new(\$content);
    my $embedcodes;

    # if the content only contains a whitelisted embedded video
    # then we can skip the placeholders (in some cases)
    my $no_whitelist = 0;
    my $found_embed = 0;

    # we don't need to estimate the dimensions if they are provided in tag attributes
    unless ($opts{width} && $opts{height}) {
        while (my $token = $p->get_token) {
            my $type = $token->[0];
            my $tag  = $token->[1] ? lc $token->[1] : '';
            my $attr = $token->[2];  # hashref

            if ($type eq "S") {
                my ($elewidth, $eleheight);
                if ($attr->{width}) {
                    $elewidth = $attr->{width}+0;
                    $width = $elewidth if $elewidth > $width;
                }
                if ($attr->{height}) {
                    $eleheight = $attr->{height}+0;
                    $height = $eleheight if $eleheight > $height;
                }
                if ($attr->{style}) {
                    if ($attr->{style} =~ /\bwidth:\s*(\d+)px/) {
                        $width = $1 if $1 > $width;
                    }
                    if ($attr->{style} =~ /\bheight:\s*(\d+)px/) {
                        $height = $1 if $1 > $height;
                    }
                }

                my $flashvars = $attr->{flashvars};

                if ($tag eq 'object' || $tag eq 'embed') {
                    my $src;
                    next unless $src = $attr->{src};

                    # we have an object/embed tag with src, make a fake lj-template object
                    my @tags = (
                                ['S', 'lj-template', {
                                    name => 'video',
                                    (defined $elewidth     ? ( width  => $width  ) : ()),
                                    (defined $eleheight    ? ( height => $height ) : ()),
                                    (defined $flashvars ? ( flashvars => $flashvars ) : ()),
                                }],
                                [ 'T', $src, {}],
                                ['E', 'lj-template', {}],
                                );

                    $embedcodes = LJ::run_hook('expand_template_video', \@tags);

                    $found_embed = 1 if $embedcodes;
                    $found_embed &&= $embedcodes !~ /Invalid video/i;

                    $no_whitelist = !$found_embed;
                } elsif ($tag ne 'param') {
                    $no_whitelist = 1;
                }
            }
        }
    }

    # use explicit values if we have them
    $width = $opts{width} if $opts{width};
    $height = $opts{height} if $opts{height};

    $width ||= 480;
    $height ||= 400;

    # some dimension min/maxing
    $width = 50 if $width < 50;
    $width = MAX_WIDTH if $width > MAX_WIDTH;
    $height = 50 if $height < 50;
    $height = MAX_HEIGHT if $height > MAX_HEIGHT;

    # safari caches state of sub-resources aggressively, so give
    # each iframe a unique 'name' attribute
    my $id = qq(name="embed_${journalid}_$moduleid");

    my $remote = LJ::get_remote();
    my %params = (moduleid => $moduleid, journalid => $journalid, preview => $preview,);
    LJ::run_hooks('modify_embed_iframe_params', \%params, $u, $remote);

    my %video_params = $class->embed_video_info($content);
    $params{source} = $video_params{source} if exists $video_params{source};
    $params{vid}    = $video_params{vid}    if exists $video_params{vid};

    my $auth_token = LJ::eurl(LJ::Auth->sessionless_auth_token('embedcontent', %params));
    my $iframe_link = "http://$LJ::EMBED_MODULE_DOMAIN/?auth_token=$auth_token" .
        join('', map { "&amp;$_=" . LJ::eurl($params{$_}) } keys %params);
    my $iframe_tag = qq {<iframe src="$iframe_link" } .
        qq{width="$width" height="$height" frameborder="0" class="lj_embedcontent" $id></iframe>};

    return $iframe_tag unless $remote;
    return $iframe_tag if $opts{edit};

    return $iframe_tag unless $opts{'video_placeholders'};

    # placeholder
    return LJ::placeholder_link(
        placeholder_html   => $iframe_tag,
        width              => $width,
        height             => $height,
        img                => "$LJ::IMGPREFIX/videoplaceholder.png?v=8209",
        link               => $iframe_link,
        remove_video_sizes => $opts{remove_video_sizes},
    );
}

sub module_content {
    my ($class, %opts) = @_;

    my $moduleid  = $opts{moduleid};
    croak "No moduleid" unless defined $moduleid;
    $moduleid += 0;

    my $journalid = $opts{journalid}+0 or croak "No journalid";
    my $journal = LJ::load_userid($journalid) or die "Invalid userid $journalid";
    return '' if ($journal->is_expunged);
    my $preview = $opts{preview};

    # try memcache
    my $memkey = $class->memkey($journalid, $moduleid, $preview);
    my $content = LJ::MemCache::get($memkey);
    my ($dbload, $dbid); # module id from the database
    unless (defined $content) {
        my $table_name = ($preview) ? 'embedcontent_preview' : 'embedcontent';
        ($content, $dbid) = $journal->selectrow_array("SELECT content, moduleid FROM $table_name WHERE " .
                                                      "moduleid=? AND userid=?",
                                                      undef, $moduleid, $journalid);
        die $journal->errstr if $journal->err;
        $dbload = 1;
    }

    $content ||= '';

    LJ::text_uncompress(\$content) if $content =~ s/^C-//;

    # clean js out of content
    unless ($LJ::DISABLED{'embedmodule-cleancontent'}) {
        LJ::CleanHTML::clean(\$content, {
            addbreaks => 0,
            tablecheck => 0,
            mode => 'allow',
            allow => [qw(object embed)],
            deny => [qw(script)],
            remove => [qw(script)],
            ljcut_disable => 1,
            cleancss => 0,
            extractlinks => 0,
            noautolinks => 1,
            extractimages => 0,
            noexpandembedded => 1,
            transform_embed_nocheck => 1,
            journalid => $opts{journalid},
        });
    }

    # if we got stuff out of database
    if ($dbload) {
        # save in memcache
        LJ::MemCache::set($memkey, $content);

        # if we didn't get a moduleid out of the database then this entry is not valid
        return defined $dbid ? $content : "[Invalid lj-embed id $moduleid]";
    }

    # get rid of whitespace around the content
    return LJ::trim($content) || '';
}

sub memkey {
    my ($class, $journalid, $moduleid, $preview) = @_;
    my $pfx = $preview ? 'embedcontpreview' : 'embedcont';
    return [$journalid, "$pfx:$journalid:$moduleid"];
}

# create a tag string from HTML::TokeParser token
sub reconstruct {
    my $class = shift;
    my $token = shift;
    my ($type, $tag, $attr, $attord) = @$token;
    if ($type eq 'S') {
        my $txt = "<$tag";
        my $selfclose;

        # preserve order of attributes. the original order is
        # in element 4 of $token
        foreach my $name (@$attord) {
            if ($name eq '/') {
                $selfclose = 1;
                next;
            }

            ## Remove "data" attribute from <object data="..."> constructs.
            ## Right now attribute is silently dropped.
            ## TODO: pass a flag to outer scope that it was dropped, so that
            ## ljprotocol can notify user by throwing an error.
            if ($tag eq 'object' && $name eq 'data') {
                next;
            }

            my $tribute = " $name=\"" . LJ::ehtml($attr->{$name}) . "\"";

            # FIXME: This fixes problems caused by using ehtml on URLs
            # but not very gracefully. Find a better way to clean URLs
            $tribute =~ s/\&amp;/\&/g
                if ($name =~ /movie|src/ && $attr->{$name} =~ /^http:\/\/.*/);

            $txt .= $tribute;
        }
        $txt .= $selfclose ? " />" : ">";

    } elsif ($type eq 'E') {
        return "</$tag>";
    } else { # C, T, D or PI
        return $tag;
    }
}


1;

