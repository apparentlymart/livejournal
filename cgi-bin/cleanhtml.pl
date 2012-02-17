#!/usr/bin/perl

use strict;
use Class::Autouse qw(
                      URI
                      HTMLCleaner
                      LJ::CSS::Cleaner
                      HTML::TokeParser
                      LJ::EmbedModule
                      LJ::Config
                      LJ::Maps
                      LJ::UserApps
                      );

LJ::Config->load;

package LJ;

use Encode;
use LJ::EmbedModule;
use HTML::Entities;

# <LJFUNC>
# name: LJ::strip_bad_code
# class: security
# des: Removes malicious/annoying HTML.
# info: This is just a wrapper function around [func[LJ::CleanHTML::clean]].
# args: textref
# des-textref: Scalar reference to text to be cleaned.
# returns: Nothing.
# </LJFUNC>
sub strip_bad_code
{
    my $data = shift;
    LJ::CleanHTML::clean($data, {
        'eat' => [qw[layer script object embed]],
        'mode' => 'allow',
        'keepcomments' => 1, # Allows CSS to work
    });
}

package LJ::CleanHTML;
#     LJ::CleanHTML::clean(\$u->{'bio'}, {
#        'wordlength' => 100, # maximum length of an unbroken "word"
#        'addbreaks' => 1,    # insert <br/> after newlines where appropriate
#        'tablecheck' => 1,   # make sure they aren't closing </td> that weren't opened.
#        'eat' => [qw(head title style layer iframe)],
#        'mode' => 'allow',
#        'deny' => [qw(marquee)],
#        'remove' => [qw()],
#        'maximgwidth' => 100,
#        'maximgheight' => 100,
#        'keepcomments' => 1,
#        'cuturl' => 'http://www.domain.com/full_item_view.ext',
#        'ljcut_disable' => 1, # stops the cleaner from using the lj-cut tag
#        'cleancss' => 1,
#        'extractlinks' => 1, # remove a hrefs; implies noautolinks
#        'noautolinks' => 1, # do not auto linkify
#        'extractimages' => 1, # placeholder images
#        'transform_embed_nocheck' => 1, # do not do checks on object/embed tag transforming
#        'transform_embed_wmode' => <value>, # define a wmode value for videos (usually 'transparent' is the value you want)
#        'blocked_links' => [ qr/evil\.com/, qw/spammer\.com/ ], # list of sites which URL's will be blocked
#        'blocked_link_substitute' => 'http://domain.com/error.html' # blocked links will be replaced by this URL
#        'allowed_img_attrs'  => hashref of allowed img attibutes, other attrs are removed.
#        'remove_all_attribs' => 1, # remove all attributes from html tags
#        'remove_attribs' => [qw/id class style/], # remove specified attributes only
#     });

sub helper_preload
{
    my $p = HTML::TokeParser->new("");
    eval {$p->DESTROY(); };
}


# this treats normal characters and &entities; as single characters
# also treats UTF-8 chars as single characters if $LJ::UNICODE
my $onechar;
{
    my $utf_longchar = '[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xef][\x80-\xbf][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf]';
    my $match;
    if (not $LJ::UNICODE) {
        $match = '[^&\s]|(&\#?\w{1,7};)';
    } else {
        $match = $utf_longchar . '|[^&\s\x80-\xff]|(?:&\#?\w{1,7};)';
    }
    $onechar = qr/$match/o;
}

# Some browsers, such as Internet Explorer, have decided to alllow
# certain HTML tags to be an alias of another.  This has manifested
# itself into a problem, as these aliases act in the browser in the
# same manner as the original tag, but are not treated the same by
# the HTML cleaner.
# 'alias' => 'real'
my %tag_substitute = (
                      'image' => 'img',
                      );

# In XHTML you can close a tag in the same opening tag like <br />,
# but some browsers still will interpret it as an opening only tag.
# This is a list of tags which you can actually close with a trailing
# slash and get the proper behavior from a browser.
my $slashclose_tags = qr/^(?:area|base|basefont|br|col|embed|frame|hr|img|input|isindex|link|meta|param|lj-embed)$/i;

# <LJFUNC>
# name: LJ::CleanHTML::clean
# class: text
# des: Multi-faceted HTML parse function
# info:
# args: data, opts
# des-data: A reference to HTML to parse to output, or HTML if modified in-place.
# des-opts: An hash of options to pass to the parser.
# returns: Nothing.
# </LJFUNC>
sub clean
{
    my $data = shift;
    my $opts = shift;
    my $newdata;

    # remove the auth portion of any see_request.bml links
    $$data =~ s/(see_request\.bml\S+?)auth=\w+/$1/ig;

    # decode escapes to get a valid unicode string
    # we encode it back before return
    $$data = Encode::decode_utf8($$data);

    my $p = HTML::TokeParser->new($data);

    my $wordlength = $opts->{'wordlength'};
    my $addbreaks = $opts->{'addbreaks'};
    my $keepcomments = $opts->{'keepcomments'};
    my $mode = $opts->{'mode'};
    my $undefined_tags = $opts->{undefined_tags} || '';
    my $cut = $opts->{'cuturl'} || $opts->{'cutpreview'};
    my $ljcut_disable = $opts->{'ljcut_disable'};
    my $s1var = $opts->{'s1var'};
    my $extractlinks = 0 || $opts->{'extractlinks'};
    my $noautolinks = $extractlinks || $opts->{'noautolinks'};
    my $noexpand_embedded = $opts->{'noexpandembedded'} || $opts->{'textonly'} || 0;
    my $transform_embed_nocheck = $opts->{'transform_embed_nocheck'} || 0;
    my $transform_embed_wmode = $opts->{'transform_embed_wmode'};
    my $remove_colors = $opts->{'remove_colors'} || 0;
    my $remove_sizes = $opts->{'remove_sizes'} || 0;
    my $remove_fonts = $opts->{'remove_fonts'} || 0;
    my $blocked_links = (exists $opts->{'blocked_links'}) ? $opts->{'blocked_links'} : \@LJ::BLOCKED_LINKS;
    my $blocked_link_substitute =
        (exists $opts->{'blocked_link_substitute'}) ? $opts->{'blocked_link_substitute'} :
        ($LJ::BLOCKED_LINK_SUBSTITUTE) ? $LJ::BLOCKED_LINK_SUBSTITUTE : '#';
    my $suspend_msg = $opts->{'suspend_msg'} || 0;
    my $unsuspend_supportid = $opts->{'unsuspend_supportid'} || 0;
    my $remove_all_attribs = $opts->{'remove_all_attribs'} || 0;
    my %remove_attribs = ($opts->{'remove_attribs'}) ?
        (map {$_ => 1} @{ $opts->{'remove_attribs'} }) : ();
    my $remove_positioning = $opts->{'remove_positioning'} || 0;
    my $target = $opts->{'target'} || '';
    my $ljrepost_allowed = ($opts->{ljrepost_allowed} && ! $opts->{'textonly'}) || 0;

    my $poster = LJ::load_userid($opts->{posterid});
    my $put_nofollow = not ($poster and $poster->get_cap('paid'));

    my $viewer_lang = $opts->{'viewer_lang'};
    unless ($viewer_lang) {
        $viewer_lang = LJ::Lang::get_remote_lang();
    }

    # cuturl or entry_url tells about context and texts address,
    # Expand or close lj-cut tag should be switched directly by special flag
    # - expand_cut
    $cut = '' if $opts->{expand_cut};

    my @canonical_urls; # extracted links
    my %action = ();
    my %remove = ();
    if (ref $opts->{'eat'} eq "ARRAY") {
        foreach (@{$opts->{'eat'}}) { $action{$_} = "eat"; }
    }
    if (ref $opts->{'allow'} eq "ARRAY") {
        foreach (@{$opts->{'allow'}}) { $action{$_} = "allow"; }
    }
    if (ref $opts->{'deny'} eq "ARRAY") {
        foreach (@{$opts->{'deny'}}) { $action{$_} = "deny"; }
    }
    if (ref $opts->{'remove'} eq "ARRAY") {
        foreach (@{$opts->{'remove'}}) { $action{$_} = "deny"; $remove{$_} = 1; }
    }

    $action{'script'} = "eat";

    # if removing sizes, remove heading tags
    if ($remove_sizes) {
        foreach my $tag (qw( h1 h2 h3 h4 h5 h6 )) {
            $action{$tag} = "deny";
            $remove{$tag} = 1;
        }
    }

    if ($opts->{'strongcleancss'}) {
        $opts->{'cleancss'} = 1;
    }

    my @attrstrip = qw();
    # cleancss means clean annoying css
    # clean_js_css means clean javascript from css
    if ($opts->{'cleancss'}) {
        push @attrstrip, 'id';
        $opts->{'clean_js_css'} = 1;
    }

    if ($opts->{'nocss'}) {
        push @attrstrip, 'style';
    }

    if (ref $opts->{'attrstrip'} eq "ARRAY") {
        foreach (@{$opts->{'attrstrip'}}) { push @attrstrip, $_; }
    }

    my %opencount = ();
    my @tablescope = ();

    my $cutcount = 0;

    # bytes known good.  set this BEFORE we start parsing any new
    # start tag, where most evil is (because where attributes can be)
    # then, if we have to totally fail, we can cut stuff off after this.
    my $good_until = 0;

    # then, if we decide that part of an entry has invalid content, we'll
    # escape that part and stuff it in here. this lets us finish cleaning
    # the "good" part of the entry (since some tags might not get closed
    # till after $good_until bytes into the text).
    my $extra_text;
    my $total_fail = sub {
        my $tag = LJ::ehtml(@_);

        my $edata = LJ::ehtml($$data);
        $edata =~ s/\r?\n/<br \/>/g if $addbreaks;

        $extra_text = "<div class='ljparseerror'>[<b>Error:</b> Irreparable invalid markup ('&lt;$tag&gt;') in entry.  ".
                      "Owner must fix manually.  Raw contents below.]<br /><br />" .
                      '<div style="width: 95%; overflow: auto">' . $edata . '</div></div>';
    };

    ## We do not need to eat a tag 'iframe' if it enabled here.
    my $htmlcleaner = HTMLCleaner->new(
                                valid_stylesheet => \&LJ::valid_stylesheet_url,
                                enable_iframe    => (grep { $_ eq 'iframe' && $action{$_} == "allow" ? 1 : 0 } keys %action) ? 1 : 0
                      );

    my $eating_ljuser_span = 0;  # bool, if we're eating an ljuser span
    my $ljuser_text_node   = ""; # the last text node we saw while eating ljuser tags
    my @eatuntil = ();  # if non-empty, we're eating everything.  thing at end is thing
                        # we're looking to open again or close again.

    my $capturing_during_eat;  # if we save all tokens that happen inside the eating.
    my @capture = ();  # if so, they go here

    my $form_tag = {
        input => 1,
        select => 1,
        option => 1,
    };

    my $start_capture = sub {
        next if $capturing_during_eat;

        my ($tag, $first_token, $cb) = @_;
        push @eatuntil, $tag;
        @capture = ($first_token);
        $capturing_during_eat = $cb || sub {};
    };

    my $finish_capture = sub {
        @capture = ();
        $capturing_during_eat = undef;
    };

    # this is the stack that holds information about state of parsing
    # <lj-lang> tags; the syntax of these is as follows:
    #
    # <lj-lang-container>
    #      <lj-lang include="en"> English text </lj-lang>
    #      <lj-lang include="de"> German text </lj-lang>
    #      <lj-lang include="en,de"> Text that displays in both
    #                                English and German </lj-lang>
    #      <lj-lang otherwise> In case all above failed, this is
    #                          the text </lj-lang>
    # </lj-lang-container>
    #
    # it is pretty trivial to implement the 'include' versions of
    # tags, and for the 'otherwise' version, we have a state variable
    # indicating that we haven't yet seen an 'include' tag that had
    # its language matching the remote's language. so when we occur
    # an 'otherwise' tag, we figure whether to display its body using
    # this variable.
    #
    # as for the stack, it allows us to make it so that:
    # 1). container tags may be nested
    # 2). lj-lang doesn't actually need to be inside of a container
    #
    # opening <lj-lang-container> unshifts the stack
    # closing <lj-lang-container> shifts it
    # when we need to access a 'variable', $lj_lang_otherwise[0] will do
    #
    # TODO: this comment indicates that the code is less than easy to
    # understand and it would benefit from a refactor, i.e. encapsulating
    # handling specific tags in some set of classes, or something.
    # - ailyin, Nov 15, 2010
    my @lj_lang_otherwise = ( 1 );

    my %vkontakte_like_js;
    my $in_link     = 0;
    my $img_link    = 0;
    my $href_b_link = '';
    my $text_a_link = 0;
    my $text_b_link = 0;

  TOKEN:
    while (my $token = $p->get_token)
    {
        my $type = $token->[0];

        # See if this tag should be treated as an alias

        $token->[1] = $tag_substitute{$token->[1]} if defined $tag_substitute{$token->[1]} &&
            ($type eq 'S' || $type eq 'E');

        if ($type eq "S")     # start tag
        {
            my $tag  = $token->[1];
            my $attr = $token->[2];  # hashref

            $good_until = length $newdata;

            if (LJ::is_enabled('remove_allowscriptaccess')) {
                ## TODO: remove closing </param> tag,
                ## don't strip 'allowscriptaccess' from YouTube and other trusted sites
                if ($tag eq 'param' && $attr->{name} eq 'allowscriptaccess') {
                    next TOKEN;
                }
                if ($tag eq 'embed') {
                    delete $attr->{allowscriptaccess};
                }
            }

            if (@eatuntil) {
                push @capture, $token if $capturing_during_eat;
                if ($tag eq $eatuntil[-1]) {
                    push @eatuntil, $tag;
                }
                next TOKEN;
            }

            if ( $opts->{'img_placeholders'} ) {
                if ( $tag eq 'a' ) {
                    $in_link = 1;
                    $href_b_link = $attr->{href};
                }

                if ( $tag eq 'img' && $in_link ) {
                    $img_link = 1;
                    $newdata .= '</a>';
                }
            }

            if ($tag eq "lj-template" && ! $noexpand_embedded) {
                my $name = $attr->{name} || "";
                $name =~ s/-/_/g;

                my $run_template_hook = sub {
                    # can pass in tokens to override passing the hook the @capture array
                    my ($token, $override_capture) = @_;
                    my $capture = $override_capture ? [$token] : \@capture;
                    # In $expanded we must has valid unicode string.
                    my $expanded = ($name =~ /^\w+$/) ?
                        Encode::decode_utf8(LJ::run_hook("expand_template_$name", $capture)) : "";
                    $newdata .= $expanded || "<b>[Error: unknown template '" . LJ::ehtml($name) . "']</b>";
                };

                if ($attr->{'/'}) {
                    # template is self-closing, no need to do capture
                    $run_template_hook->($token, 1);
                } else {
                    # capture and send content to hook
                    $start_capture->("lj-template", $token, $run_template_hook);
                }
                next TOKEN;
            }

            if ($tag eq "lj-replace") {
                my $name = $attr->{name} || "";
                my $replace = ($name =~ /^\w+$/) ? Encode::decode_utf8(LJ::lj_replace($name, $attr)) : undef;
                $newdata .= defined $replace ? $replace : "<b>[Error: unknown lj-replace key '" . LJ::ehtml($name) . "']</b>";

                next TOKEN;
            }

            if ($tag eq 'lj-map') {
                $newdata .= LJ::Maps->expand_ljmap_tag($attr);
                next TOKEN;
            }


            # lj-repost tag adds button that allows easily post text in remote user's blog.
            #
            # Usage:
            # 1. <lj-repost />
            # 2. <lj-repost button="post this" />
            # 3. <lj-repost>some text</lj-repost>
            # 4. <lj-repost button="re-post to your journal" subject="WOW">
            #       text to repost
            #    </lj-repost>
            #
            if ($tag eq "lj-repost" and $ljrepost_allowed){
                next TOKEN if ref $opencount{$tag}; # no support for nested <lj-repost> tags
                my $button = LJ::ehtml($attr->{button}) || LJ::Lang::ml("repost.default_button");
                if ($attr->{'/'}){
                    # short <lj-repost /> form of tag
                    $newdata .= qq[<form action="http://www.$LJ::DOMAIN/update.bml" method="GET">]
                             .  qq[<input type="hidden" name="repost" value="$opts->{cuturl}" />]
                             .  qq[<input type="hidden" name="repost_type" value="a" />]
                             .  qq[<input type="submit" value="$button" /> ]
                             .  qq[</form>];
                } else {
                    $opencount{$tag} = {
                        button  => $button,
                        subject => $attr->{subject},
                        offset  => length $newdata,
                    };
                }
                next TOKEN;
            }

            ## lj-userpic:
            ##      <lj-userpic> - current journal's default userpic
            ##      <lj-userpic remote> - remote user's default userpic
            ##      <lj-userpic user="test"> - test's default userpic
            if ($tag eq "lj-userpic" and !$opts->{'textonly'} and $action{$tag} ne 'deny') {
                my $u = '';
                if ($attr->{user}){
                    $u = LJ::load_user($attr->{user});
                } elsif ($attr->{remote}){
                    $u = LJ::get_remote();
                } else {
                    my $cur_journal = LJ::Session->domain_journal;
                    $u = LJ::load_user($cur_journal) if $cur_journal;
                }

                my $upic = ref $u ? $u->userpic : '';
                if ($upic){
                    $newdata .= $upic->imgtag;
                } else {
                    $newdata .= qq|<img src="http://wh.livejournal.ru/icons/nouserpic.png" width="100" height="100" class="userpic-img" />|;
                }
                next TOKEN;
            }

            if ($tag eq "lj-wishlist") {
                my $wishid = $attr->{wishid};
                my $userid = $attr->{userid};
                $newdata .= Encode::decode_utf8(LJ::WishElement->check_and_expand_entry($userid, $wishid));
            }

            # Capture object and embed tags to possibly transform them into something else.
            if ($tag eq "object" || $tag eq "embed") {
                if (LJ::are_hooks("transform_embed") && !$noexpand_embedded) {
                    # XHTML style open/close tags done as a singleton shouldn't actually
                    # start a capture loop, because there won't be a close tag.
                    if ($attr->{'/'}) {
                        $newdata .= LJ::run_hook("transform_embed", [$token],
                                                 nocheck => $transform_embed_nocheck, wmode => $transform_embed_wmode, video_placeholders => $opts->{video_placeholders}) || "";
                        next TOKEN;
                    }

                    $start_capture->($tag, $token, sub {
                        my $expanded = LJ::run_hook("transform_embed", \@capture,
                                                    nocheck => $transform_embed_nocheck, wmode => $transform_embed_wmode, video_placeholders => $opts->{video_placeholders});
                        $newdata .= $expanded || "";
                    });
                    next TOKEN;
                }
            }

            if ($tag eq "span" && lc $attr->{class} eq "ljuser" && ! $noexpand_embedded) {
                $eating_ljuser_span = 1;
                $ljuser_text_node = "";
            }

            if ($eating_ljuser_span) {
                next TOKEN;
            }

            if (($tag eq "div" || $tag eq "span") && lc $attr->{class} eq "ljvideo") {
                $start_capture->($tag, $token, sub {
                    my $expanded = LJ::run_hook("expand_template_video", \@capture);
                    $newdata .= $expanded || "<b>[Error: unknown template 'video']</b>";
                });
                next TOKEN;
            }

            # do some quick checking to see if this is an email address/URL, and if so, just
            # escape it and ignore it
            if ($tag =~ m!(?:\@|://)!) {
                $newdata .= LJ::ehtml("<$tag>");
                next;
            }

            if ($form_tag->{$tag}) {
                if (! $opencount{form}) {
                    $newdata .= "&lt;$tag ... &gt;";
                    next;
                }

                if ($tag eq "input") {
                    if ($attr->{type} !~ /^\w+$/ || lc $attr->{type} eq "password") {
                        delete $attr->{type};
                    }
                }
            }

            my $slashclose = 0;   # If set to 1, use XML-style empty tag marker
            # for tags like <name/>, pretend it's <name> and reinsert the slash later
            $slashclose = 1 if ($tag =~ s!/$!!);

            unless ($tag =~ /^\w([\w\-:_]*\w)?$/) {
                $total_fail->($tag);
                last TOKEN;
            }

            # for incorrect tags like <name/attrib=val> (note the lack of a space)
            # delete everything after 'name' to prevent a security loophole which happens
            # because IE understands them.
            $tag =~ s!/.+$!!;

            # Try to execute default action on undefined tags
            next if (!$action{$tag} && $undefined_tags eq "eat");

            if ( $action{$tag} eq "eat" || $tag =~ /^fb|g:/ ) {
                $p->unget_token($token);
                $p->get_tag("/$tag");
                next;
            }

            if ($tag eq 'iframe') {

                ## Allow some iframes from trusted sources (if they are not eaten already)
                ## YouTube (http://apiblog.youtube.com/2010/07/new-way-to-embed-youtube-videos.html),
                ## Vimeo, VKontakte, Google Calendar, Google Docs, VK.com, etc.
                ## see @LJ::EMBED_IFRAME_WHITELIST in lj-disabled-conf
                my $src_allowed = 0;

                if (my $src = $attr->{'src'}) {
                    foreach my $wl ( @LJ::EMBED_IFRAME_WHITELIST ) {
                        if ($src =~ $wl->{re}) {
                            if ($wl->{personal_posts_only}) {
                                last unless $opts->{journalid};
                                my $u = LJ::load_userid($opts->{journalid});
                                last unless $u && $u->is_personal;
                            }
                            $src_allowed = 1;
                            last;
                        }
                    }
                }

                unless ($src_allowed) {
                    ## eat this tag
                    if (!$attr->{'/'}) {
                        ## if not autoclosed tag (<iframe />),
                        ## then skip everything till the closing tag
                        $p->get_tag("/iframe");
                    }
                    next TOKEN;
                }
            }

            # try to call HTMLCleaner's element-specific cleaner on this open tag
            my $clean_res = eval {
                my $cleantag = $tag;
                $cleantag =~ s/^.*://s;
                $cleantag =~ s/[^\w]//g;
                no strict 'subs';
                my $meth = "CLEAN_$cleantag";
                my $seq   = $token->[3];  # attribute names, listref
                my $code = $htmlcleaner->can($meth)
                    or return 1;
                return $code->($htmlcleaner, $seq, $attr);
            };
            next if !$@ && !$clean_res;

            # this is so the rte converts its source to the standard ljuser html
            my $ljuser_div = $tag eq "div" && $attr->{class} eq "ljuser";
            if ($ljuser_div) {

                my $href = $p->get_tag("a");
                my $href_attr = $href->[1]->{"href"};
                my $username = LJ::get_user_by_url ( $href_attr );
                $attr->{'user'} = $username ? $username : '';

                my $ljuser_text = $p->get_text("/b");
                $p->get_tag("/div");
                $ljuser_text =~ s/\[info\]//;
                $tag = "lj";
                $attr->{'title'} = $ljuser_text;

            }
            # stupid hack to remove the class='ljcut' from divs when we're
            # disabling them, so we account for the open div normally later.
            my $ljcut_div = $tag eq "div" && lc $attr->{class} eq "ljcut";
            if ($ljcut_div && $ljcut_disable) {
                $ljcut_div = 0;
            }

            # no cut URL, record the anchor, but then fall through
            if (0 && $ljcut_div && !$cut) {
                $cutcount++;
                $newdata .= "<a name=\"cutid$cutcount\"></a>";
                $ljcut_div = 0;
            }

            if ( $tag eq 'lj-lang' ) {
                # extract a "standard" type of lang here;
                # also, it's a weird way to convert en_LJ -> en
                my $lang = LJ::lang_to_locale($viewer_lang);
                $lang =~ s/_.*//;

                if ($attr->{'include'}) {
                    my @include = split /[,;\s]+/, $attr->{'include'};
                    if ( grep { $_ eq $lang } @include ) {
                        $lj_lang_otherwise[0] = 0;
                        next TOKEN;
                    }
                }

                if ( $attr->{'otherwise'} || $attr->{'default'} ) {
                    next TOKEN if ($lj_lang_otherwise[0]);
                }

                push @eatuntil, $tag;
            }

            if ( $tag eq 'lj-lang-container' ) {
                unshift @lj_lang_otherwise, 1;
            }

            if (($tag eq "lj-cut" || $ljcut_div)) {
                next TOKEN if $ljcut_disable;
                $cutcount++;
                my $link_text = sub {
                    my $text =  BML::ml('fcklang.readmore');
                    $text = Encode::decode_utf8($text) if $text;
                    if ($attr->{'text'}) {
                        $text = $attr->{'text'};
                        $text =~ s/</&lt;/g;
                        $text =~ s/>/&gt;/g;
                    }
                    return $text;
                };
                if ($cut) {
                    my $etext = $link_text->();
                    my $url = LJ::ehtml($cut);
                    $newdata .= "<div>" if $tag eq "div";
                    $newdata .= "<b class=\"ljcut-link\">(&nbsp;<a href=\"$url#cutid$cutcount\">$etext</a>&nbsp;)</b>";
                    $newdata .= "</div>" if $tag eq "div";
                    unless ($opts->{'cutpreview'}) {
                        push @eatuntil, $tag;
                        next TOKEN;
                    }
                } else {
                    $newdata .= "<a name=\"cutid$cutcount\"></a>" unless $opts->{'textonly'};
                    if ($tag eq "div" && !$opts->{'textonly'}) {
                        $opencount{"div"}++;
                        my $etext = $link_text->();
                        $newdata .= "<div class=\"ljcut\" text=\"$etext\">";
                    }
                    next;
                }
            }
            elsif ($tag eq "style") {
                my $style = $p->get_text("/style");
                $p->get_tag("/style");
                unless ($LJ::DISABLED{'css_cleaner'}) {
                    my $cleaner = LJ::CSS::Cleaner->new;
                    $style = $cleaner->clean($style);
                    LJ::run_hook('css_cleaner_transform', \$style);
                    if ($LJ::IS_DEV_SERVER) {
                        $style = "/* cleaned */\n" . $style;
                    }
                }
                $newdata .= "\n<style>\n$style</style>\n";
                next;
            }
            elsif ($tag eq "lj-app")
            {
                next TOKEN if $LJ::DISABLED{'userapps'};
                my %app_attr = map { $_ => Encode::encode_utf8($attr->{$_}) } keys %$attr;
                my $app = LJ::UserApps->get_application( id => delete $app_attr{id}, key => delete $app_attr{key} );
                next TOKEN unless $app && $app->can_show_restricted;

                # Gain all context data
                my %context;
                $context{posterid} = $opts->{posterid} if($opts->{posterid});
                $context{journalid} = $opts->{journalid} if($opts->{journalid});
                if($opts->{entry_url}) {
                    my $entry = LJ::Entry->new_from_url($opts->{entry_url});
                    if ($entry && $entry->valid) {
                        $context{ditemid} = $entry->ditemid;
                    }
                }

                $newdata .= Encode::decode_utf8($app->ljapp_display(viewer => LJ::get_remote(), owner => $poster, attrs => \%app_attr, context => \%context), Encode::FB_QUIET);
                next TOKEN;
            }
            elsif ($tag eq "lj")
            {
                # keep <lj comm> working for backwards compatibility, but pretend
                # it was <lj user> so we don't have to account for it below.
                my $user = $attr->{'user'} = exists $attr->{'user'} ? $attr->{'user'} :
                                             exists $attr->{'comm'} ? $attr->{'comm'} : undef;

                if (length $user) {
                    my $orig_user = $user; # save for later, in case
                    $user = LJ::canonical_username($user);
                    if ($s1var) {
                        $newdata .= "%%ljuser:$1%%" if $attr->{'user'} =~ /^\%\%([\w\-\']+)\%\%$/;
                    } elsif (length $user) {
                        if ($opts->{'textonly'}) {
                            $newdata .= $user;
                        } else {
                            my $title = Encode::encode_utf8($attr->{title});
                            my $ljuser = LJ::ljuser($user, { title => $title, target => $target } );
                            $newdata .= Encode::decode_utf8($ljuser);
                        }
                    } else {
                        $orig_user = LJ::no_utf8_flag($orig_user);
                        $newdata .= "<b>[Bad username: " . LJ::ehtml($orig_user) . "]</b>";
                    }
                } else {
                    $newdata .= "<b>[Unknown LJ tag]</b>";
                }
            }
            elsif ($tag eq "lj-raw")
            {
                # Strip it out, but still register it as being open
                $opencount{$tag}++;
            }

            elsif ( $tag eq 'lj-like' ) {
                next TOKEN if $opts->{'textonly'};

                unless ( exists $opts->{'entry_url'} && $opts->{'entry_url'} )
                {
                    $newdata .= '<b>[lj-like in invalid context]</b>';
                    next TOKEN;
                }

                my $entry_url = $opts->{'entry_url'};
                my $entry = LJ::Entry->new_from_url($entry_url);

                my $meta = { map { $_ => '' } qw( title description image ) };
                if ($entry and $entry->valid) {
                    $meta = $entry->extract_metadata;
                }

                my @buttons = qw(
                    facebook
                    twitter
                    google
                    vkontakte
                    livejournal
                );

                if ( exists $attr->{'buttons'} && $attr->{'buttons'} ) {
                    my $buttons = $attr->{'buttons'};

                    @buttons = ();
                    foreach my $button ( split /,\s*/, $buttons ) {
                        if ( $button =~ /^(?:fb|facebook)$/i ) {
                            push @buttons, 'facebook';
                        }
                        elsif ( $button =~ /^(?:go|google)$/i ) {
                            push @buttons, 'google';
                        }
                        elsif ( $button =~ /^(?:tw|twitter)$/i ) {
                            push @buttons, 'twitter';
                        }
                        elsif ( $button =~ /^(?:vk|vkontakte)$/i ) {
                            push @buttons, 'vkontakte';
                        }
                        elsif ( $button =~ /^(?:lj|livejournal)$/i ) {
                            push @buttons, 'livejournal';
                        }
                    }
                }

                $newdata .= '<div class="lj-like">';
                foreach my $button (@buttons) {
                    if ( $button eq 'facebook' ) {
                        my $language = LJ::Lang::get_remote_lang();
                        my $locale = LJ::lang_to_locale($language);
                        my $entry_url_ehtml = LJ::ehtml($entry_url);

                        $newdata .= qq{<div class="lj-like-item lj-like-item-facebook">}
                                  . qq{<fb:like href="$entry_url_ehtml" send="false" layout="button_count" }
                                  . qq{width="100" show_faces="false" font="" action="recommend">}
                                  . qq{</fb:like></div>};
                    }

                    elsif ( $button eq 'twitter' ) {
                        my $language = LJ::Lang::get_remote_lang();

                        my $locale = LJ::lang_to_locale($language);
                        $locale =~ s/_.*//;

                        my $entry_url_ehtml = LJ::ehtml($entry_url);
                        my $title_ehtml = Encode::decode_utf8( LJ::ehtml( $meta->{'title'} ) );

                        $newdata .= qq{<div class="lj-like-item lj-like-item-twitter">}
                                  . qq{<a href="http://twitter.com/share" class="twitter-share-button" }
                                  . qq{data-url="$entry_url_ehtml" data-text="$title_ehtml" data-count="horizontal" }
                                  . qq{data-lang="$locale">Tweet</a>}
                                  . qq{</div>};
                    }

                    elsif ( $button eq 'google' ) {
                        my $entry_url_ehtml = LJ::ehtml($entry_url);
                        $newdata .= qq{<div class="lj-like-item lj-like-item-google">}
                                  . qq{<g:plusone size="medium" href="$entry_url_ehtml">}
                                  . qq{</g:plusone></div>};
                    }

                    elsif ( $button eq 'vkontakte' ) {
                        unless ( $LJ::VKONTAKTE_CONF ) {
                            $newdata .= qq{<div class="lj-like-item lj-like-item-vkontakte"><b>[vkontakte like]</b></div>};
                            next;
                        }

                        $LJ::REQ_GLOBAL{'ljlike_vkontakte_id'} ||= 1;
                        my $uniqid = int(rand(1_000_000_000));

                        my $widget_opts = {
                            'type'              => 'mini',
                            'verb'              => '1',
                            'pageUrl'           => $entry_url,
                            'pageTitle'         => $meta->{'title'},
                            'pageDescription'   => $meta->{'description'},
                            'pageImage'         => $meta->{'image'},
                        };
                        my $widget_opts_out = Encode::decode_utf8( LJ::JSON->to_json($widget_opts) );

                        $vkontakte_like_js{$uniqid}
                            = qq{<div id="vk_like_$uniqid"></div>}
                            . qq{<script type="text/javascript">}
                            . qq{jQuery.VK.addButton("vk_like_$uniqid",$widget_opts_out);}
                            . qq{</script>};
                        $newdata .= qq{<div class="lj-like-item lj-like-item-vkontakte"><x-vk-like id="$uniqid"></div>};
                    }

                    elsif ( $button eq 'livejournal' ) {
                        my $entry = LJ::Entry->new_from_url($entry_url);
                           $entry = undef unless $entry && $entry->valid;

                        my $give_button = LJ::run_hook("give_button", {
                            'journal' => $entry ? $entry->journal->user : '',
                            'itemid'  => $entry ? $entry->ditemid : 0,
                            'type'    => 'tag',
                        });

                        if ($give_button) {
                            $newdata .= qq{<div class="lj-like-item lj-like-item-livejournal">}
                                      . Encode::decode_utf8($give_button)
                                      . qq{</div>};
                        }
                    }
                }
                $newdata .= '</div>';
            }

            # Don't allow any tag with the "set" attribute
            elsif ($tag =~ m/:set$/) {
                next;
            }
            else
            {
                my $alt_output = 0;

                my $hash  = $token->[2];
                my $attrs = $token->[3]; # attribute names, in original order

                $slashclose = 1 if delete $hash->{'/'};

                foreach (@attrstrip) {
                    # maybe there's a better place for this?
                    next if (lc $tag eq 'lj-embed' && lc $_ eq 'id');
                    delete $hash->{$_};
                }

                if ($tag eq "form") {
                    my $action = lc($hash->{'action'});
                    my $deny = 0;
                    if ($action =~ m!^https?://?([^/]+)!) {
                        my $host = $1;
                        $deny = 1 if
                            $host =~ /[%\@\s]/ ||
                            $LJ::FORM_DOMAIN_BANNED{$host};
                    } else {
                        $deny = 1;
                    }
                    delete $hash->{'action'} if $deny;
                }

              ATTR:
                foreach my $attr (keys %$hash)
                {
                    if ($remove_all_attribs || $remove_attribs{$attr}) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr =~ /^(?:on|dynsrc)/) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr eq "data") {
                        delete $hash->{$attr} unless $tag eq "object";
                        next;
                    }

                    if ($attr eq 'width' || $attr eq 'height' ) {
                        if ($hash->{$attr} > 1024*2) {
                            $hash->{$attr} = 1024*2;
                        }
                    }

                    ## warning: in commets left by anonymous users, <img src="something">
                    ## is replaced by <a href="something"> (see 'extractimages' param)
                    ## If "something" is "data:<script ...", we'll get a vulnerability
                    if (($attr eq "href" || $attr eq 'src') && $hash->{$attr} =~ /^data/) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr =~ /(?:^=)|[\x0b\x0d]/) {
                        # Cleaner attack:  <p ='>' onmouseover="javascript:alert(document/**/.cookie)" >
                        # is returned by HTML::Parser as P_tag("='" => "='") Text( onmouseover...)
                        # which leads to reconstruction of valid HTML.  Clever!
                        # detect this, and fail.
                        $total_fail->("$tag $attr");
                        last TOKEN;
                    }

                    # ignore attributes that do not fit this strict scheme
                    unless ($attr =~ /^[\w_:-]+$/) {
                        $total_fail->("$tag " . (%$hash > 1 ? "[...] " : "") . "$attr");
                        last TOKEN;
                    }

                    $hash->{$attr} =~ s/[\t\n]//g;

                    # IE ignores the null character, so strip it out
                    $hash->{$attr} =~ s/\x0//g;

                    # IE sucks:
                    my $nowhite = $hash->{$attr};
                    $nowhite =~ s/[\s\x0b]+//g;
                    if ($nowhite =~ /(?:jscript|livescript|javascript|vbscript|about):/ix) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr eq 'style') {
                        if ($opts->{'cleancss'}) {
                            # css2 spec, section 4.1.3
                            # position === p\osition  :(
                            # strip all slashes no matter what.
                            $hash->{style} =~ s/\\//g;

                            # and catch the obvious ones ("[" is for things like document["coo"+"kie"]
                            foreach my $css ("/*", "[", qw(absolute fixed expression eval behavior cookie document window javascript -moz-binding)) {
                                if ($hash->{style} =~ /\Q$css\E/i) {
                                    delete $hash->{style};
                                    next ATTR;
                                }
                            }

                            if ($opts->{'strongcleancss'}) {
                                if ($hash->{style} =~ /-moz-|absolute|relative|outline|z-index|(?<!-)(?:top|left|right|bottom)\s*:|filter|-webkit-/io) {
                                    delete $hash->{style};
                                    next ATTR;
                                }
                            }

                            # remove specific CSS definitions
                            if ($remove_colors) {
                                $hash->{style} =~ s/(?:background-)?color:.*?(?:;|$)//gi;
                            }
                            if ($remove_sizes) {
                                $hash->{style} =~ s/font-size:.*?(?:;|$)//gi;
                            }
                            if ($remove_fonts) {
                                $hash->{style} =~ s/font-family:.*?(?:;|$)//gi;
                            }
                            if ($remove_positioning) {
                                $hash->{style} =~ s/margin.*?(?:;|$)//gi;
                                $hash->{style} =~ s/height\s*?:.*?(?:;|$)//gi;
                                # strip excessive padding
                                $hash->{style} =~ s/padding[^:]*?:\D*\d{3,}[^;]*(?:;|$)//gi;
                            }
                        }

                        if ($opts->{'clean_js_css'} && ! $LJ::DISABLED{'css_cleaner'}) {
                            # and then run it through a harder CSS cleaner that does a full parse
                            my $css = LJ::CSS::Cleaner->new;
                            $hash->{style} = $css->clean_property($hash->{style});
                        }
                    }

                    if (
                        lc $tag ne 'lj-embed' &&
                        ( $attr eq 'class' || $attr eq 'id' ) &&
                        $opts->{'strongcleancss'} )
                    {
                        delete $hash->{$attr};
                        next;
                    }

                    # reserve ljs_* ids for divs, etc so users can't override them to replace content
                    if ($attr eq 'id' && $hash->{$attr} =~ /^ljs_/i) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($s1var) {
                        if ($attr =~ /%%/) {
                            delete $hash->{$attr};
                            next ATTR;
                        }

                        my $props = $LJ::S1::PROPS->{$s1var};

                        if ($hash->{$attr} =~ /^%%([\w:]+:)?(\S+?)%%$/ && $props->{$2} =~ /[aud]/) {
                            # don't change it.
                        } elsif ($hash->{$attr} =~ /^%%cons:\w+%%[^\%]*$/) {
                            # a site constant with something appended is also fine.
                        } elsif ($hash->{$attr} =~ /%%/) {
                            my $clean_var = sub {
                                my ($mods, $prop) = @_;
                                # HTML escape and kill line breaks
                                $mods = "attr:$mods" unless
                                    $mods =~ /^(color|cons|siteroot|sitename|img):/ ||
                                    $props->{$prop} =~ /[ud]/;
                                return '%%' . $mods . $prop . '%%';
                            };

                            $hash->{$attr} =~ s/[\n\r]//g;
                            $hash->{$attr} =~ s/%%([\w:]+:)?(\S+?)%%/$clean_var->(lc($1), $2)/eg;

                            if ($attr =~ /^(href|src|lowsrc|style)$/) {
                                $hash->{$attr} = "\%\%[attr[$hash->{$attr}]]\%\%";
                            }
                        }

                    }

                    # remove specific attributes
                    if (($remove_colors && ($attr eq "color" || $attr eq "bgcolor" || $attr eq "fgcolor" || $attr eq "text")) ||
                        ($remove_sizes && $attr eq "size") ||
                        ($remove_fonts && $attr eq "face")) {
                        delete $hash->{$attr};
                        next ATTR;
                    }
                }

                ## attribute lj-sys-message-close is used in SiteMessage's only
                if (exists $hash->{'lj-sys-message-close'}) {
                    delete $hash->{'lj-sys-message-close'};
                    if (my $mid = $opts->{'lj_sys_message_id'}) {
                        $hash->{'onclick'} = "LiveJournal.closeSiteMessage(this, event, $mid)";
                        push @$attrs, 'onclick';
                    }
                }

                if (exists $hash->{href}) {
                    ## links to some resources will be completely blocked
                    ## and replaced by value of 'blocked_link_substitute' param
                    if ($blocked_links) {
                        foreach my $re (@$blocked_links) {
                            if ($hash->{href} =~ $re) {
                                $hash->{href} = sprintf($blocked_link_substitute, LJ::eurl($hash->{href}));
                                last;
                            }
                        }
                    }

                    unless ($hash->{href} =~ s/^lj:(?:\/\/)?(.*)$/ExpandLJURL($1)/ei) {
                        $hash->{href} = canonical_url($hash->{href}, 1);
                    }
                }

                if ($tag eq "img") {
                    my $img_bad = 0;

                    if ($opts->{'remove_img_sizes'}) {
                        delete $hash->{'height'};
                        delete $hash->{'width'};
                    } else {
                        if (defined $opts->{'maximgwidth'} &&
                            (! defined $hash->{'width'} ||
                             $hash->{'width'} > $opts->{'maximgwidth'})) { $img_bad = 1; }

                        if (defined $opts->{'maximgheight'} &&
                            (! defined $hash->{'height'} ||
                             $hash->{'height'} > $opts->{'maximgheight'})) { $img_bad = 1; }
                    }

                    if ($opts->{'extractimages'}) { $img_bad = 1; }

                    if ($opts->{'img_placeholders'}) {
                        $img_bad = 1;
                    }

                    ## Option 'allowed_img_attrs' provides a list of allowed attributes
                    if (my $allowed = $opts->{'allowed_img_attrs'}){
                        while (my ($attr, undef) = each %$hash){
                            delete $hash->{$attr} unless $allowed->{$attr};
                        }
                    }

                    ## TODO: a better check of $hash->{src} is needed,
                    ## known (fixed) vulnerability is src="data:..."
                    $hash->{src} = canonical_url($hash->{src}, 1);

                    ## Ratings can be cheated by commenting a popular post with
                    ## <img src="http://my-journal.livejournal.com/12345.html">
                    if ($hash->{src} =~ m!/\d+\.html$!) {
                        next TOKEN;
                    }

                    ## CDN:
                    ##  http://pics.livejournal.com/<certain-journal>/pic/000fbt9x* -> l-pics.livejournal.com
                    ##  TODO: make it work for communities too
                    if ($hash->{'src'} =~ m!^http://(?:l-)?pics.livejournal.com/(\w+)/pic/(.*)$!i) {
                        my ($journal, $rest) = ($1, $2);
                        my $host = (!$LJ::DISABLED{'pics_via_cdn'} && $LJ::USE_CDN_FOR_PICS{$journal})
                                ? "l-pics.livejournal.com" : "pics.livejournal.com";
                        $hash->{'src'} = "http://$host/$journal/pic/$rest";
                    }

                    if ($img_bad) {
                        $newdata .= qq~<a class="b-mediaplaceholder b-mediaplaceholder-photo" data-href="$href_b_link" href="~ .
                            LJ::ehtml($hash->{'src'}) . '" onclick="return LiveJournal.placeholderClick(this, \'image\')">' .
                            '<span class="b-mediaplaceholder-inner">' .
                            '<i class="b-mediaplaceholder-pic"></i>' .
                            '<span class="b-mediaplaceholder-label b-mediaplaceholder-view">' . LJ::Lang::ml("mediaplaceholder.viewimage") . '</span>'.
                            '<span class="b-mediaplaceholder-label b-mediaplaceholder-loading">' . LJ::Lang::ml("mediaplaceholder.loading") . '</span>'.
                            '</span>' .
                            '</a>';
                        $newdata .= $href_b_link ?
                            '<a href="' . $href_b_link .'" class="b-mediaplaceholder-external" title="' . LJ::Lang::ml("mediaplaceholder.link") . '">' .
                            '<i class="b-mediaplaceholder-bg"></i>' .
                            '<i class="b-mediaplaceholder-pic"></i>' .
                            '<span class="b-mediaplaceholder-inner">' . LJ::Lang::ml("mediaplaceholder.link") . '</span>' .
                            '</a>' : '';
                        $alt_output = 1;
                        $opencount{"img"}++;
                    }
                }

                if ($tag eq "a" && $extractlinks)
                {
                    push @canonical_urls, canonical_url($attr->{href}, 1);
                    $newdata .= "<b>";
                    next;
                }

                if ($tag eq "a" and $hash->{href} and $put_nofollow) {
                    if ($hash->{href} =~ m!^https?://([^/]+?)(/.*)?$!) {
                        my $host = $1;
                        unless ($host =~ /\Q$LJ::DOMAIN\E$/i) {
                            $hash->{rel} = "nofollow";
                            push @$attrs, 'rel';
                        }
                    }
                }

                ## LJSUP-10811: due to security issue only Flash is allowed
                ## LJSV-1995: Embedded video from http://video.yandex.ru doesn't shown
                if ($tag eq 'embed'){
                   $hash->{type} = 'application/x-shockwave-flash';
                   push @$attrs => 'type' unless grep { $_ eq 'type' } @$attrs;
                }
                if ($tag eq 'object' and ($hash->{data} || $hash->{src})){
                   $hash->{type} = 'application/x-shockwave-flash';
                   push @$attrs => 'type' unless grep { $_ eq 'type' } @$attrs;
                }

                # Through the xsl namespace in XML, it is possible to embed scripting lanaguages
                # as elements which will then be executed by the browser.  Combining this with
                # customview.cgi makes it very easy for someone to replace their entire journal
                # in S1 with a page that embeds scripting as well.  An example being an AJAX
                # six degrees tool, while cool it should not be allowed.
                #
                # Example syntax:
                # <xsl:element name="script">
                # <xsl:attribute name="type">text/javascript</xsl:attribute>
                if ($tag eq 'xsl:attribute')
                {
                    $alt_output = 1; # We'll always deal with output for this token

                    my $orig_value = $p->get_text; # Get the value of this element
                    my $value = $orig_value; # Make a copy if this turns out to be alright
                    $value =~ s/\s+//g; # Remove any whitespace

                    # See if they are trying to output scripting, if so eat the xsl:attribute
                    # container and its value
                    if ($value =~ /(javascript|vbscript)/i) {

                        # Remove the closing tag from the tree
                        $p->get_token;

                        # Remove the value itself from the tree
                        $p->get_text;

                    # No harm, no foul...Write back out the original
                    } else {
                        $newdata .= "$token->[4]$orig_value";
                    }
                }

                unless ($alt_output)
                {
                    my $allow;
                    if ($mode eq "allow") {
                        $allow = 1;
                        if ($action{$tag} eq "deny") { $allow = 0; }
                    } else {
                        $allow = 0;
                        if ($action{$tag} eq "allow") { $allow = 1; }
                    }

                    if ($allow && ! $remove{$tag})
                    {
                        if ($opts->{'tablecheck'}) {

                            $allow = 0 if

                                # can't open table elements from outside a table
                                ($tag =~ /^(?:tbody|thead|tfoot|tr|td|th|caption|colgroup|col)$/ && ! @tablescope) ||

                                # can't open td or th if not inside tr
                                ($tag =~ /^(?:td|th)$/ && ! $tablescope[-1]->{'tr'}) ||

                                # can't open a table unless inside a td or th
                                ($tag eq 'table' && @tablescope && ! grep { $tablescope[-1]->{$_} } qw(td th));
                        }

                        if ($allow) { $newdata .= "<$tag"; }
                        else { $newdata .= "&lt;$tag"; }

                        # output attributes in original order, but only those
                        # that are allowed (by still being in %$hash after cleaning)
                        foreach (@$attrs) {
                            $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\""
                                if exists $hash->{$_};
                        }

                        # ignore the effects of slashclose unless we're dealing with a tag that can
                        # actually close itself. Otherwise, a tag like <em /> can pass through as valid
                        # even though some browsers just render it as an opening tag
                        if ($slashclose && $tag =~ $slashclose_tags) {
                            $newdata .= " /";
                            $opencount{$tag}--;
                            $tablescope[-1]->{$tag}-- if $opts->{'tablecheck'} && @tablescope;
                        }
                        if ($allow) {
                            $newdata .= ">";
                            $opencount{$tag}++;

                            # maintain current table scope
                            if ($opts->{'tablecheck'}) {

                                # open table
                                if ($tag eq 'table') {
                                    push @tablescope, {};

                                # new tag within current table
                                } elsif (@tablescope) {
                                    $tablescope[-1]->{$tag}++;
                                }
                            }

                        }
                        else { $newdata .= "&gt;"; }
                    }
                }
            }
        }
        # end tag
        elsif ($type eq "E")
        {
            my $tag = $token->[1];
            next TOKEN if $tag =~ /[^\w\-:]/;
            if (@eatuntil) {
                push @capture, $token if $capturing_during_eat;

                if ($eatuntil[-1] eq $tag) {
                    pop @eatuntil;
                    if (my $cb = $capturing_during_eat) {
                        $cb->();
                        $finish_capture->();
                    }
                    next TOKEN;
                }

                next TOKEN if @eatuntil;
            }

            if ($eating_ljuser_span && $tag eq "span") {
                $eating_ljuser_span = 0;
                $newdata .= $opts->{'textonly'} ? $ljuser_text_node : LJ::ljuser($ljuser_text_node);
                next TOKEN;
            }

            if ( $opts->{'img_placeholders'} ) {
                if ( $tag eq 'a' && $in_link ) {
                    $in_link     = 0;
                    $text_b_link = 0;
                    $text_b_link = 0;
                    $href_b_link = '';
                    $img_link    = 0;
                }
            }

            my $allow;
            if ($tag eq "lj-raw") {
                $opencount{$tag}--;
                $tablescope[-1]->{$tag}-- if $opts->{'tablecheck'} && @tablescope;
            }
            elsif ($tag eq "lj-cut") {
                if ($opts->{'cutpreview'}) {
                    $newdata .= "<b>&lt;/lj-cut&gt;</b>";
                } else {
                    $newdata .= "<a name='cutid$cutcount-end'></a>"
                }
            }
            elsif ($tag eq "lj-repost" and $ljrepost_allowed and ref $opencount{$tag}){
                ## Add repost button
                ## If there is opening <lj-repost> tag than $opencount{$tag} exists.
                ##
                my $button   = LJ::ehtml($opencount{$tag}->{button}) || LJ::Lang::ml("repost.default_button");
                my $subject  = LJ::ehtml($opencount{$tag}->{subject});
                my $captured = substr $newdata => $opencount{$tag}->{offset};

                if ($captured and my $entry = LJ::Entry->new_from_url($opts->{cuturl})){
                    # !!! avoid calling any 'text' methods on $entry,
                    #     it can produce inifinite loop of cleanhtml calls.

                    unless ($subject){
                        $subject = LJ::ehtml($entry->subject_raw || LJ::Lang::ml("repost.default_subject"));
                    }

                    if ($subject && Encode::is_utf8($subject)) {
                        $subject = Encode::encode_utf8($subject);
                    }

                    ## 'posterid' property of a removed (is_valied eq 'false') entry is empty.
                    my $poster_username = $entry->poster
                                            ? $entry->poster->username
                                            : '';

                    LJ::EmbedModule->add_user_to_embed($poster_username, \$captured);
                    $captured = LJ::Lang::ml("repost.wrapper", {
                                                username => $poster_username,
                                                url      => $entry->url,
                                                subject  => $subject,
                                                text     => Encode::encode_utf8($captured),
                                                });

                    $captured = Encode::decode_utf8($captured);
                    $subject  = Encode::decode_utf8($subject) if $subject;
                }
                $captured = LJ::ehtml($captured);

                # add <form> with invisible fields and visible submit button
                if ($captured){
                    $newdata .= qq[<form action="http://www.$LJ::DOMAIN/update.bml" method="POST">
                        <div style="display:none;visible:false">
                        <input type="text" name="subject" value="$subject" />
                        <textarea name="event">$captured</textarea>
                        </div>
                        <input type="submit" value="$button" /></form>];
                } else {
                    ## treat <lj-repost></lj-repost> as <lj-repost />
                    $newdata .= qq[<form action="http://www.$LJ::DOMAIN/update.bml" method="GET">]
                             .  qq[<input type=hidden name="repost" value="$opts->{cuturl}" />]
                             .  qq(<input type="submit" value="$button" /> )
                             .  qq[</form>];
                }

                delete $opencount{$tag};

            } elsif ( $tag eq 'lj-lang' ) {
                # ignore it
            } elsif ( $tag eq 'lj-lang-container' ) {
                shift @lj_lang_otherwise;
            } else {
                if ($mode eq "allow") {
                    $allow = 1;
                    if ($action{$tag} eq "deny") { $allow = 0; }
                } else {
                    $allow = 0;
                    if ($action{$tag} eq "allow") { $allow = 1; }
                }

                if ($extractlinks && $tag eq "a") {
                    if (@canonical_urls) {
                        my $url = LJ::ehtml(pop @canonical_urls);
                        $newdata .= "</b> ($url)";
                        next;
                    }
                }

                if ($allow && ! $remove{$tag})
                {

                    if ($opts->{'tablecheck'}) {

                        $allow = 0 if

                            # can't close table elements from outside a table
                            ($tag =~ /^(?:table|tbody|thead|tfoot|tr|td|th|caption|colgroup|col)$/ && ! @tablescope) ||

                            # can't close td or th unless open tr
                            ($tag =~ /^(?:td|th)$/ && ! $tablescope[-1]->{'tr'});
                    }

                    if ($allow && ! ($opts->{'noearlyclose'} && ! $opencount{$tag})) {

                        # maintain current table scope
                        if ($opts->{'tablecheck'}) {

                            # open table
                            if ($tag eq 'table') {
                                pop @tablescope;

                            # closing tag within current table
                            } elsif (@tablescope) {
                                $tablescope[-1]->{$tag}--;
                            }
                        }

                        $newdata .= "</$tag>";
                        $opencount{$tag}--;
                    } else {
                        $newdata .= "&lt;/$tag&gt;";
                    }
                }
            }
        }
        elsif ($type eq "D") {
            # remove everything past first closing tag
            $token->[1] =~ s/>.+/>/s;
            # kill any opening tag except the starting one
            $token->[1] =~ s/.<//sg;
            $newdata .= $token->[1];
        }
        elsif ($type eq "T") {
            my %url = ();
            my %nofollow;
            my $urlcount = 0;

            if (@eatuntil) {
                push @capture, $token if $capturing_during_eat;
                next TOKEN;
            }

            if ( $opts->{'img_placeholders'} ) {
                if ( $in_link && $img_link ) {
                    $newdata .= qq~<a href="$href_b_link">~
                        . $token->[1]
                        . '</a>';
                    $text_a_link = 1;
                    next TOKEN;
                }
            }

            if ($eating_ljuser_span) {
                $ljuser_text_node = $token->[1];
                next TOKEN;
            }

            if ($opencount{'style'} && $LJ::DEBUG{'s1_style_textnode'}) {
                my $uri = LJ::Request->uri;
                my $host = LJ::Request->header_in("Host");
                warn "Got text node while style elements open.  Shouldn't happen anymore. ($host$uri)\n";
            }

            my $auto_format = $addbreaks &&
                ($opencount{'table'} <= ($opencount{'td'} + $opencount{'th'})) &&
                 ! $opencount{'pre'} &&
                 ! $opencount{'lj-raw'};

            if ($auto_format && ! $noautolinks && ! $opencount{'a'} && ! $opencount{'textarea'}) {
                my $match = sub {
                    my $str = shift;
                    my $end = '';
                    if ($str =~ /^(.*?)(&(#39|quot|lt|gt)(;.*)?)$/) {
                        $url{++$urlcount} = $1;
                        $end = $2;
                    } else {
                        $url{++$urlcount} = $str;
                    }
                    $nofollow{$urlcount} = 0;
                    if ($put_nofollow and $url{$urlcount} =~ m!^https?://([^/]+?)(/.*)?$!) {
                        my $host = $1;
                        unless ($host =~ /\Q$LJ::DOMAIN\E$/i) {
                            $nofollow{$urlcount} = 1;
                        }
                    }
                    return "&url$urlcount;$url{$urlcount}&urlend;$end";
                };
                ## URL is http://anything-here-but-space-and-quotes/and-last-symbol-isn't-space-comma-period-etc
                ## like this (http://example.com) and these: http://foo.bar, http://bar.baz.
                $token->[1] =~ s!(https?://[^\s\'\"\<\>]+[^\s\'\"\<\>\.\,\?\:\)])! $match->($1); !ge;
            }

            # escape tags in text tokens.  shouldn't belong here!
            # especially because the parser returns things it's
            # confused about (broken, ill-formed HTML) as text.
            $token->[1] =~ s/</&lt;/g;
            $token->[1] =~ s/>/&gt;/g;

            # put <wbr> tags into long words, except inside <pre> and <textarea>.
            if ($wordlength && !$opencount{'pre'} && !$opencount{'textarea'}) {
                $token->[1] =~ s/(\S{$wordlength,})/break_word($1,$wordlength)/eg;
            }

            # auto-format things, unless we're in a textarea, when it doesn't make sense
            if ($auto_format && !$opencount{'textarea'}) {
                $token->[1] =~ s/\r?\n/<br \/>/g;
                if (! $opencount{'a'}) {
                    my $tag_a = sub {
                        my ($key, $title) = @_;
                        my $nofollow = $nofollow{$key} ? " rel='nofollow'" : "";
                        return "<a href='$url{$key}'$nofollow>$title</a>";
                    };
                    $token->[1] =~ s|&url(\d+);(.*?)&urlend;|$tag_a->($1,$2)|ge;
                }
            }

            $newdata .= $token->[1];
        }
        elsif ($type eq "C") {

            # probably a malformed tag rather than a comment, so escape it
            # -- ehtml things like "<3", "<--->", "<>", etc
            # -- comments must start with <! to be eaten
            if ($token->[1] =~ /^<[^!]/) {
                $newdata .= LJ::ehtml($token->[1]);

            # by default, ditch comments
            } elsif ($keepcomments) {
                my $com = $token->[1];
                $com =~ s/^<!--\s*//;
                $com =~ s/\s*--!>$//;
                $com =~ s/<!--//;
                $com =~ s/-->//;
                $newdata .= "<!-- $com -->";
            }
        }
        elsif ($type eq "PI") {
            my $tok = $token->[1];
            $tok =~ s/</&lt;/g;
            $tok =~ s/>/&gt;/g;
            $newdata .= "<?$tok>";
        }
        else {
            $newdata .= "<!-- OTHER: " . $type . "-->\n";
        }
    } # end while

    # finish up open links if we're extracting them
    if ($extractlinks && @canonical_urls) {
        while (my $url = LJ::ehtml(pop @canonical_urls)) {
            $newdata .= "</b> ($url)";
            $opencount{'a'}--;
        }
    }

    # close any tags that were opened and not closed
    # don't close tags that don't need a closing tag -- otherwise,
    # we output the closing tags in the wrong place (eg, a </td>
    # after the <table> was closed) causing unnecessary problems
    if (ref $opts->{'autoclose'} eq "ARRAY") {
        foreach my $tag (@{$opts->{'autoclose'}}) {
            next if $tag =~ /^(?:tr|td|th|tbody|thead|tfoot|li)$/;
            if ($opencount{$tag}) {
                $newdata .= "</$tag>" x $opencount{$tag};
            }
        }
    }

    # extra-paranoid check
    1 while $newdata =~ s/<script\b//ig;

    $newdata =~ s/<x-vk-like id="(\d+)">/$vkontakte_like_js{$1}/eg;

    $$data = $newdata;
    $$data .= $extra_text if $extra_text; # invalid markup error

    # encode data back to utf8 before return
    $$data = Encode::encode_utf8($$data);

    if ($suspend_msg) {
        my $msg = qq{<div style="color: #000; font: 12px Verdana, Arial, Sans-Serif; background-color: #ffeeee; background-repeat: repeat-x; border: 1px solid #ff9999; padding: 8px; margin: 5px auto; width: auto; text-align: left; background-image: url('$LJ::IMGPREFIX/message-error.gif?v=4888');">};
        my $link_style = "color: #00c; text-decoration: underline; background: transparent; border: 0;";

        if ($unsuspend_supportid) {
            $msg .= LJ::Lang::ml('cleanhtml.suspend_msg_with_supportid', { aopts => "href='$LJ::SITEROOT/support/see_request.bml?id=$unsuspend_supportid' style='$link_style'" });
        } else {
            $msg .= LJ::Lang::ml('cleanhtml.suspend_msg', { aopts => "href='$LJ::SITEROOT/abuse/report.bml' style='$link_style'" });
        }

        $msg .= "</div>";

        $$data = $msg . $$data;
    }

    return 0;
}


# takes a reference to HTML and a base URL, and modifies HTML in place to use absolute URLs from the given base
sub resolve_relative_urls
{
    my ($data, $base) = @_;
    my $p = HTML::TokeParser->new($data);

    # where we look for relative URLs
    my $rel_source = {
        'a' => {
            'href' => 1,
        },
        'img' => {
            'src' => 1,
        },
    };

    my $global_did_mod = 0;
    my $base_uri = undef;  # until needed
    my $newdata = "";

  TOKEN:
    while (my $token = $p->get_token)
    {
        my $type = $token->[0];

        if ($type eq "S")     # start tag
        {
            my $tag = $token->[1];
            my $hash  = $token->[2]; # attribute hashref
            my $attrs = $token->[3]; # attribute names, in original order

            my $did_mod = 0;
            # see if this is a tag that could contain relative URLs we fix up.
            if (my $relats = $rel_source->{$tag}) {
                while (my $k = each %$relats) {
                    next unless defined $hash->{$k} && $hash->{$k} !~ /^[a-z]+:/;
                    my $rel_url = $hash->{$k};
                    $global_did_mod = $did_mod = 1;

                    $base_uri ||= URI->new($base);
                    $hash->{$k} = URI->new_abs($rel_url, $base_uri)->as_string;
                }
            }

            # if no change was necessary
            unless ($did_mod) {
                $newdata .= $token->[4];
                next TOKEN;
            }

            # otherwise, rebuild the opening tag

            # for tags like <name/>, pretend it's <name> and reinsert the slash later
            my $slashclose = 0;   # If set to 1, use XML-style empty tag marker
            $slashclose = 1 if $tag =~ s!/$!!;
            $slashclose = 1 if delete $hash->{'/'};

            # spit it back out
            $newdata .= "<$tag";
            # output attributes in original order
            foreach (@$attrs) {
                $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\""
                    if exists $hash->{$_};
            }
            $newdata .= " /" if $slashclose;
            $newdata .= ">";
        }
        elsif ($type eq "E") {
            $newdata .= $token->[2];
        }
        elsif ($type eq "D") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "T") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "C") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "PI") {
            $newdata .= $token->[2];
        }
    } # end while

    $$data = $newdata if $global_did_mod;
    return undef;
}

sub ExpandLJURL
{
    my @args = grep { $_ } split(/\//, $_[0]);
    my $mode = shift @args;

    my %modes =
        (
         'faq' => sub {
             my $id = shift()+0;
             if ($id) {
                 return "support/faqbrowse.bml?faqid=$id";
             } else {
                 return "support/faq.bml";
             }
         },
         'memories' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "memories.bml?user=$user";
             } else {
                 return "memories.bml";
             }
         },
         'pubkey' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "pubkey.bml?user=$user";
             } else {
                 return "pubkey.bml";
             }
         },
         'support' => sub {
             my $id = shift()+0;
             if ($id) {
                 return "support/see_request.bml?id=$id";
             } else {
                 return "support/";
             }
         },
         'todo' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "todo/?user=$user";
             } else {
                 return "todo/";
             }
         },
         'user' => sub {
             my $user = LJ::canonical_username(shift);
             return "" if grep { /[\"\'\<\>\n\&]/ } @_;
             return $_[0] eq 'profile' ?
                 "userinfo.bml?user=$user" :
                 "users/$user/" . join("", map { "$_/" } @_ );
         },
         'userinfo' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "userinfo.bml?user=$user";
             } else {
                 return "userinfo.bml";
             }
         },
         'userpics' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "allpics.bml?user=$user";
             } else {
                 return "allpics.bml";
             }
         },
        );

    my $uri = $modes{$mode} ? $modes{$mode}->(@args) : "error:bogus-lj-url";

    return "$LJ::SITEROOT/$uri";
}

my $subject_eat = [qw[head title style layer iframe applet object param base]];
my $subject_allow = [qw[a b i u em strong cite]];
my $subject_remove = [qw[bgsound embed object caption link font noscript lj-userpic]];
sub clean_subject
{
    my $ref = shift;
    return unless $$ref =~ /[\<\>]/;
    my $opts = shift || {};

    clean($ref, {
        'wordlength' => 40,
        'addbreaks' => 0,
        'eat' => $subject_eat,
        'mode' => 'deny',
        'allow' => $subject_allow,
        'remove' => $subject_remove,
        'autoclose' => $subject_allow,
        'noearlyclose' => 1,
        'remove_attribs' => [qw/id class style/],
        %$opts,
    });
}

## returns a pure text subject (needed in links, email headers, etc...)
my $subjectall_eat = [qw[head title style layer iframe applet object]];
sub clean_subject_all
{
    my $ref = shift;
    return unless $$ref =~ /[\<\>]/;
    clean($ref, {
        'wordlength' => 40,
        'addbreaks' => 0,
        'eat' => $subjectall_eat,
        'mode' => 'deny',
        'textonly' => 1,
        'autoclose' => $subject_allow,
        'noearlyclose' => 1,
    });
}

# wrapper around clean_subject_all; this also trims the subject to the given length
sub clean_and_trim_subject {
    my $ref = shift;
    my $length = shift || 40;

    LJ::CleanHTML::clean_subject_all($ref);
    $$ref =~ s/\n.*//s;
    $$ref = LJ::text_trim($$ref, 0, $length);
}

my $event_eat = [qw[head title style layer applet object xml param base]];
my $event_remove = [qw[bgsound embed object link body meta noscript plaintext noframes]];

my @comment_close = qw(
    a sub sup xmp bdo q span
    b i u tt s strike big small font
    abbr acronym cite code dfn em kbd samp strong var del ins
    h1 h2 h3 h4 h5 h6 div blockquote address pre center
    ul ol li dl dt dd
    table tr td th tbody tfoot thead colgroup caption
    area map form textarea blink
);
my @comment_all = (@comment_close, "img", "br", "hr", "p", "col", "iframe");

my $userbio_eat = $event_eat;
my $userbio_remove = $event_remove;
my @userbio_close = @comment_close;

sub clean_event
{
    my ($ref, $opts) = @_;

    # old prototype was passing in the ref and preformatted flag.
    # now the second argument is a hashref of options, so convert it to support the old way.
    unless (ref $opts eq "HASH") {
        $opts = { 'preformatted' => $opts };
    }

    my $wordlength = defined $opts->{'wordlength'} ? $opts->{'wordlength'} : 40;

    # fast path:  no markup or URLs to linkify, and no suspend message needed
    if ($$ref !~ /\<|\>|http/ && ! $opts->{preformatted} && !$opts->{suspend_msg}) {
        $$ref =~ s/(\S{$wordlength,})/break_word($1,$wordlength)/eg if $wordlength;
        $$ref =~ s/\r?\n/<br \/>/g;
        return;
    }

    my $cleancss = $opts->{'journalid'} ?
        ! $LJ::STYLE_TRUSTED{ $opts->{'journalid'} } : 0;

    my $strongcleancss = $cleancss;

    my $poster         = LJ::load_userid( $opts->{'posterid'} );
    my $journal        = LJ::load_userid( $opts->{'journalid'} );
    my $active_journal = LJ::get_active_journal();
    if ( $poster &&
        $poster->get_cap('no_strong_clean_css') &&
        $poster->equals($journal) &&
        $poster->equals($active_journal) )
    {
        $strongcleancss = 0;
    }

    # slow path: need to be run it through the cleaner
    clean($ref, {
        'linkify'          => 1,
        'wordlength'       => $wordlength,
        'addbreaks'        => $opts->{'preformatted'} ? 0 : 1,
        'cutpreview'       => $opts->{'cutpreview'},
        'posterid'         => $opts->{'posterid'},
        'eat'              => $event_eat,
        'mode'             => 'allow',
        'remove'           => $event_remove,
        'autoclose'        => \@comment_close,
        'cleancss'         => $cleancss,
        'strongcleancss'   => $strongcleancss,
        'noearlyclose'     => 1,
        'tablecheck'       => 1,
        'ljrepost_allowed' => 1,
        %$opts,
    });
}

sub pre_clean_event_for_entryform
{
    my $ref = shift;

    ## fast path - no html tags
    return unless $$ref =~ /</;

    ## slow path
    my $data = Encode::decode_utf8($$ref);
    my $p = HTML::TokeParser->new(\$data);
    my $newdata = '';

    TOKEN:
    while (my $token = $p->get_token) {
        my $type = $token->[0];
        if ($type eq 'S') {
            ## start tag
            my $tag  = $token->[1];
            my $hash = $token->[2];  # attributes
            my $attrs = $token->[3]; # attribute names, in original order

            ## check the tag
            if ($tag eq 'script') {
                $p->get_tag("/$tag");
                next TOKEN;
            }
            if ($tag =~ /:set$/) {
                next TOKEN;
            }
            unless ($tag =~ /^\w([\w\-:_]*\w)?\/?$/) {
                next TOKEN;
            }
            ## check attributes
            my $autoclose = delete $hash->{'/'};
            foreach my $attr (keys %$hash) {
                if ($attr =~ /^(?:on|dynsrc)/) {
                    delete $hash->{$attr};
                    next;
                } elsif ($attr eq 'href' || $attr eq 'src') {
                    if ($hash->{$attr} =~ /^data/) {
                        delete $hash->{$attr};
                        next;
                    }
                }
                if ($attr =~ /(?:^=)|[\x0b\x0d]/) {
                    next TOKEN;
                }
                unless ($attr =~ /^[\w_:-]+$/) {
                    delete $hash->{$attr};
                    next;
                }
                my $tmp = $hash->{$attr};
                $tmp =~ s/[\t\n\0]//g;
                if ($tmp =~ /(?:jscript|livescript|javascript|vbscript|about):/ix) {
                    delete $hash->{$attr};
                    next;
                }
                ## TODO: css & xslt js expressions
            }
            ## reconstruct the tag
            $newdata .= "<$tag";
            foreach (@$attrs) {
                $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\"" if exists $hash->{$_};
            }
            $newdata .= ($autoclose) ? " />" : ">";
        } elsif ($type eq 'E' or $type eq 'PI') {
            ## close (end) tags and processing instructions
            $newdata .= $token->[2];
        } else {
            $newdata .= $token->[1];
        }
    }

    # extra-paranoid check
    1 while $newdata =~ s/<script\b//ig;

    $$ref = Encode::encode_utf8($newdata);
}

sub get_okay_comment_tags
{
    return @comment_all;
}


# ref: scalarref of text to clean, gets cleaned in-place
# opts:  either a hashref of opts:
#         - preformatted:  if true, don't insert breaks and auto-linkify
#         - anon_comment:  don't linkify things, and prevent <a> tags
#       or, opts can just be a boolean scalar, which implies the performatted tag
sub clean_comment
{
    my ($ref, $opts) = @_;

    unless (ref $opts) {
        $opts = { 'preformatted' => $opts,
                  'nocss'        => 1 };
    }

    # fast path:  no markup or URLs to linkify
    if ($$ref !~ /\<|\>|http/ && ! $opts->{preformatted}) {
        $$ref =~ s/(\S{40,})/break_word($1,40)/eg;
        $$ref =~ s/\r?\n/<br \/>/g;
        return 0;
    }

    # slow path: need to be run it through the cleaner
    return clean($ref, {
        'linkify'            => 1,
        'wordlength'         => 40,
        'addbreaks'          => $opts->{preformatted} ? 0 : 1,
        'eat'                => [qw[head title style layer applet object]],
        'mode'               => 'deny',
        'allow'              => \@comment_all,
        'autoclose'          => \@comment_close,
        'cleancss'           => 1,
        'strongcleancss'     => 1,
        'extractlinks'       => $opts->{'anon_comment'},
        'extractimages'      => $opts->{'anon_comment'},
        'noearlyclose'       => 1,
        'tablecheck'         => 1,
        'nocss'              => $opts->{'nocss'},
        'textonly'           => $opts->{'textonly'} ? 1 : 0,
        'remove_positioning' => 1,
        'posterid'           => $opts->{'posterid'},
        'img_placeholders'   => $opts->{'img_placeholders'},
        'video_placeholders' => $opts->{'video_placeholders'},
    });
}

# ref: scalarref of text to clean, gets cleaned in-place
sub clean_message
{
    my ($ref, $opts) = @_;

    # slow path: need to be run it through the cleaner
    return clean($ref, {
        'linkify' => 1,
        'wordlength' => 40,
        'addbreaks' => 0,
        'eat' => [qw[head title style layer applet object]],
        'mode' => 'deny',
        'allow' => \@comment_all,
        'autoclose' => \@comment_close,
        'cleancss' => 1,
        'strongcleancss' => 1,
        'noearlyclose' => 1,
        'tablecheck' => 1,
        'nocss' => $opts->{'nocss'},
        'textonly' => $opts->{'textonly'} ? 1 : 0,
        'remove_positioning' => 1,
    });
}

sub clean_userbio {
    my $ref = shift;
    return undef unless ref $ref;

    clean($ref, {
        'wordlength' => 100,
        'addbreaks' => 1,
        'attrstrip' => [qw[style]],
        'mode' => 'allow',
        'noearlyclose' => 1,
        'tablecheck' => 1,
        'eat' => $userbio_eat,
        'remove' => $userbio_remove,
        'autoclose' => \@userbio_close,
        'cleancss' => 1,
    });
}

sub clean_s1_style
{
    my $s1 = shift;
    my $clean;

    my %tmpl;
    LJ::parse_vars(\$s1, \%tmpl);
    foreach my $v (keys %tmpl) {
        clean(\$tmpl{$v}, {
            'eat' => [qw[layer script object embed applet]],
            'mode' => 'allow',
            'keepcomments' => 1, # allows CSS to work
            'clean_js_css' => 1,
            's1var' => $v,
        });
    }

    return Storable::nfreeze(\%tmpl);
}

sub s1_attribute_clean {
    my $a = $_[0];
    $a =~ s/[\t\n]//g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;

    # IE sucks:
    if ($a =~ /((?:(?:v\s*b)|(?:j\s*a\s*v\s*a))\s*s\s*c\s*r\s*i\s*p\s*t|
                a\s*b\s*o\s*u\s*t)\s*:/ix) { return ""; }
    return $a;
}

sub canonical_url {
    my $url = shift;
    my $allow_all = shift;

    # strip leading and trailing spaces
    $url =~ s/^\s*//;
    $url =~ s/\s*$//;

    return '' unless $url;

    unless ($allow_all) {
        # see what protocol they want, default to http
        my $pref = "http";
        $pref = $1 if $url =~ /^(https?|ftp|webcal):/;

        # strip out the protocol section
        $url =~ s!^.*?:/*!!;

        return '' unless $url;

        # rebuild safe url
        $url = "$pref://$url";
    }

    if ($LJ::DEBUG{'aol_http_to_ftp'}) {
        # aol blocks http referred from lj, but ftp has no referer header.
        if ($url =~ m!^http://(?:www\.)?(?:members|hometown|users)\.aol\.com/!) {
            $url =~ s!^http!ftp!;
        }
    }

    return $url;
}

sub break_word {
    my ($word, $at) = @_;
    return $word unless $at;

    $word =~ s/((?:$onechar){$at})\B/$1<wbr \/>/g;
    return $word;
}


sub clean_friends
{
    my $ref = shift;

    my @tags_remove = qw(bgsound embed object link body meta noscript plaintext noframes);
    my @tags_allow = qw(lj);

    LJ::CleanHTML::clean($ref, {
        'linkify' => 1,
        'wordlength' => 160,
        'undefined_tags' => 'eat',
        'allow' => \@tags_allow,
        'remove' => \@tags_remove,
        'cleancss' => 1,
        'noearlyclose' => 1,
        'tablecheck' => 1,
        'textonly' => 1,
    });

    # Trim function must be a part of cleanHTML::clean method,
    # but now this method is too complicated to do this right way.
    # Now just cut off last breaked tag.

    # trim text
    my $trunc = LJ::text_trim($$ref, 640, 320);
    if ($$ref ne $trunc) {
        $trunc =~ s/(\W+\w+)$//; # cut off last space and chars right from it.

        # cut off last unclosed tag
        if ($trunc =~ m!\</?([^>]+)$!) {        # ... <tag or ... </tag
            my $tag = $1;
            $trunc =~ s!</?\Q$tag\E>?.*?$!!;
        }

        # add '...' to the tail
        $$ref = $trunc . ' ...';
    }
}

1;
