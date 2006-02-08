#!/usr/bin/perl
#
# <LJDEP>
# lib: HTML::TokeParser, cgi-bin/ljconfig.pl, cgi-bin/ljlib.pl
# link: htdocs/userinfo.bml, htdocs/users
# </LJDEP>

use strict;
use HTML::TokeParser ();
use URI ();
use CSS::Cleaner;

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

package LJ;

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
        'eat' => [qw[layer iframe script object embed]],
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

# <LJFUNC>
# name: LJ::CleanHTML::clean
# class: text
# des: Multifaceted HTML parse function
# info:
# args: data, opts
# des-data: A reference to html to parse to output, or HTML if modified in-place.
# des-opts: An hash of options to pass to the parser.
# returns: Nothing.
# </LJFUNC>

sub clean
{
    my $data = shift;
    my $opts = shift;
    my $newdata;

    # remove the auth portion of any see_request.bml links
    $$data =~ s/(see_request\.bml.+?)auth=\w+/$1/ig;

    my $p = HTML::TokeParser->new($data);

    my $wordlength = $opts->{'wordlength'};
    my $addbreaks = $opts->{'addbreaks'};
    my $keepcomments = $opts->{'keepcomments'};
    my $mode = $opts->{'mode'};
    my $cut = $opts->{'cuturl'} || $opts->{'cutpreview'};
    my $ljcut_disable = $opts->{'ljcut_disable'};
    my $s1var = $opts->{'s1var'};
    my $extractlinks = 0 || $opts->{'extractlinks'};
    my $noautolinks = $extractlinks || $opts->{'noautolinks'};

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

    my @attrstrip = qw();
    if ($opts->{'cleancss'}) {
        push @attrstrip, 'id';
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

    my $total_fail = sub {
        my $tag = LJ::ehtml(@_);
        $$data = LJ::ehtml($$data);
        $$data =~ s/\r?\n/<br \/>/g if $addbreaks;
        $$data = "[<b>Error:</b> Irreparable invalid markup ('&lt;$tag&gt;') in entry.  ".
            "Owner must fix manually.  Raw contents below.]<br /><br />" .
            '<div style="width: 95%; overflow: auto">' .
            $$data .
            '</div>';
        return undef;
    };

    my $htmlcleaner = HTMLCleaner->new(valid_stylesheet => \&LJ::valid_stylesheet_url);

  TOKEN:
    while (my $token = $p->get_token)
    {
        my $type = $token->[0];

        # See if this tag should be treated as an alias

        $token->[1] = $tag_substitute{$token->[1]} if defined $tag_substitute{$token->[1]} &&
            ($type eq 'S' || $type eq 'E');

        if ($type eq "S")     # start tag
        {
            my $tag = $token->[1];

            # do some quick checking to see if this is an email address/URL, and if so, just
            # escape it and ignore it
            if ($tag =~ m!(?:\@|://)!) {
                $newdata .= LJ::ehtml("<$tag>");
                next;
            }

            my $slashclose = 0;   # If set to 1, use XML-style empty tag marker
            # for tags like <name/>, pretend it's <name> and reinsert the slash later
            $slashclose = 1 if ($tag =~ s!/$!!);

            return $total_fail->($tag) unless $tag =~ /^\w([\w\-:_]*\w)?$/;

            # for incorrect tags like <name/attrib=val> (note the lack of a space)
            # delete everything after 'name' to prevent a security loophole which happens
            # because IE understands them.
            $tag =~ s!/.+$!!;

            if ($action{$tag} eq "eat") {
                $p->unget_token($token);
                $p->get_tag("/$tag");
                next;
            }

            # try to call HTMLCleaner's element-specific cleaner on this open tag
            my $clean_res = eval {
                my $cleantag = $tag;
                $cleantag =~ s/^.*://s;
                $cleantag =~ s/[^\w]//g;
                no strict 'subs';
                my $meth = "CLEAN_$cleantag";
                my $attr  = $token->[2];  # hashref
                my $seq   = $token->[3];  # attribute names, listref
                my $code = $htmlcleaner->can($meth)
                    or return 1;
                return $code->($htmlcleaner, $seq, $attr);
            };
            next if !$@ && !$clean_res;

            if ($tag eq "lj-cut" && !$ljcut_disable)
            {
                my $attr = $token->[2];
                $cutcount++;
                if ($cut) {
                    my $text = "Read more...";
                    if ($attr->{'text'}) {
                        $text = $attr->{'text'};
                        if ($text =~ /[^\x01-\x7f]/) {
                            $text = pack('C*', unpack('C*', $text));
                        }
                        $text =~ s/</&lt;/g;
                        $text =~ s/>/&gt;/g;
                    }
                    my $url = LJ::ehtml($cut);
                    $newdata .= "<b>(&nbsp;<a href=\"$url#cutid$cutcount\">$text</a>&nbsp;)</b>";
                    $p->get_tag("/lj-cut") unless $opts->{'cutpreview'}
                } else {
                    $newdata .= "<a name=\"cutid$cutcount\"></a>";
                    next;
                }
            }
            elsif ($tag eq "style") {
                my $style = $p->get_text("/style");
                $p->get_tag("/style");
                unless ($LJ::DISABLED{'css_cleaner'}) {
                    my $cleaner = CSS::Cleaner->new;
                    $style = "/* cleaned */\n" . $cleaner->clean($style);
                }
                $newdata .= "\n<style>\n$style</style>\n";
                next;
            }
            elsif ($tag eq "lj")
            {
                my $attr = $token->[2];

                # keep <lj comm> working for backwards compatibility, but pretend
                # it was <lj user> so we don't have to account for it below.
                my $user = $attr->{'user'} = exists $attr->{'user'} ? $attr->{'user'} :
                                             exists $attr->{'comm'} ? $attr->{'comm'} : undef;

                if (length $user) {
                    $user = LJ::canonical_username($user);
                    if ($s1var) {
                        $newdata .= "%%ljuser:$1%%" if $attr->{'user'} =~ /^\%\%([\w\-\']+)\%\%$/;
                    } elsif (length $user) {
                        if ($opts->{'textonly'}) {
                            $newdata .= $user;
                        } else {
                            $newdata .= LJ::ljuser($user);
                        }
                    } else {
                        $newdata .= "<b>[Bad username in LJ tag]</b>";
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
                    if ($attr =~ /^(?:on|dynsrc|data)/) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr =~ /(?:^=)|[\x0b\x0d]/) {
                        # Cleaner attack:  <p ='>' onmouseover="javascript:alert(document/**/.cookie)" >
                        # is returned by HTML::Parser as P_tag("='" => "='") Text( onmouseover...)
                        # which leads to reconstruction of valid HTML.  Clever!
                        # detect this, and fail.
                        return $total_fail->("$tag $attr");
                    }

                    # ignore attributes that do not fit this strict scheme
                    return $total_fail->("$tag " . (%$hash > 1 ? "[...] " : "") . "$attr")
                        unless $attr =~ /^[\w_:-]+$/;

                    $hash->{$attr} =~ s/[\t\n]//g;

                    # IE ignores the null character, so strip it out
                    $hash->{$attr} =~ s/\x0//g;

                    # IE sucks:
                    if ($hash->{$attr} =~ /(j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t|
                                            v\s*b\s*s\s*c\s*r\s*i\s*p\s*t|
                                            a\s*b\s*o\s*u\s*t)\s*:/ix) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr eq 'style' && $opts->{'cleancss'}) {
                        # css2 spec, section 4.1.3
                        # position === p\osition  :(
                        # strip all slashes no matter what.
                        $hash->{$attr} =~ s/\\//g;

                        # and catch the obvious ones ("[" is for things like document["coo"+"kie"]
                        foreach my $css ("/*", "[", qw(absolute fixed expression eval behavior cookie document window javascript -moz-binding)) {
                            if ($hash->{$attr} =~ /\Q$css\E/i) {
                                delete $hash->{$attr};
                                next ATTR;
                            }
                        }

                        # and then run it through a harder CSS cleaner that does a full parse
                        unless ($LJ::DISABLED{'css_cleaner'}) {
                            my $css = CSS::Cleaner->new;
                            $hash->{style} = $css->clean_property($hash->{style});
                        }
                        next ATTR;
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
                }
                if (exists $hash->{href}) {
                    unless ($hash->{href} =~ s/^lj:(?:\/\/)?(.*)$/ExpandLJURL($1)/ei) {
                        $hash->{href} = canonical_url($hash->{href}, 1);
                    }
                }

                if ($tag eq "img")
                {
                    my $img_bad = 0;
                    if (defined $opts->{'maximgwidth'} &&
                        (! defined $hash->{'width'} ||
                         $hash->{'width'} > $opts->{'maximgwidth'})) { $img_bad = 1; }
                    if (defined $opts->{'maximgheight'} &&
                        (! defined $hash->{'height'} ||
                         $hash->{'height'} > $opts->{'maximgheight'})) { $img_bad = 1; }
                    if ($opts->{'extractimages'}) { $img_bad = 1; }

                    $hash->{src} = canonical_url($hash->{src}, 1);

                    if ($img_bad) {
                        $newdata .= "<a class=\"ljimgplaceholder\" href=\"" .
                            LJ::ehtml($hash->{'src'}) . "\">" .
                            LJ::img('placeholder') . '</a>';
                        $alt_output = 1;
                    }
                }

                if ($tag eq "a" && $extractlinks)
                {
                    push @canonical_urls, canonical_url($token->[2]->{href}, 1);
                    $newdata .= "<b>";
                    next;
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
                                ($tag =~ /^(?:tbody|thead|tfoot|tr|td|th)$/ && ! @tablescope) ||

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
                            if ($hash->{$_} =~ /[^\x01-\x7f]/) {
                                # FIXME: this is so ghetto.  make faster.  make generic.
                                # HTML::Parser decodes entities for us (which is good)
                                # but in Perl 5.8 also includes the "poison" SvUTF8
                                # flag on the scalar it returns, thus poisoning the
                                # rest of the content this scalar is appended with.
                                # we need to remove that poison at this point.  *sigh*
                                $hash->{$_} = pack('C*', unpack('C*', $hash->{$_}));
                            }
                            $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\""
                                if exists $hash->{$_};
                        }

                        if ($slashclose) {
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

            my $allow;
            if ($tag eq "lj-raw") {
                $opencount{$tag}--;
                $tablescope[-1]->{$tag}-- if $opts->{'tablecheck'} && @tablescope;
            }
            elsif ($tag eq "lj-cut") {
                if ($opts->{'cutpreview'}) {
                    $newdata .= "<b>&lt;/lj-cut&gt;</b>";
                }
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
                            ($tag =~ /^(?:table|tbody|thead|tfoot|tr|td|th)$/ && ! @tablescope) ||

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

                    } else { $newdata .= "&lt;/$tag&gt;"; }
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
            my $urlcount = 0;

            if ($opencount{'style'} && $LJ::DEBUG{'s1_style_textnode'}) {
                my $r = Apache->request;
                my $uri = $r->uri;
                my $host = $r->header_in("Host");
                warn "Got text node while style elements open.  Shouldn't happen anymore. ($host$uri)\n";
            }

            my $auto_format = $addbreaks &&
                ($opencount{'table'} <= ($opencount{'td'} + $opencount{'th'})) &&
                 ! $opencount{'pre'} &&
                 ! $opencount{'lj-raw'};

            if ($auto_format && ! $noautolinks && ! $opencount{'a'} && ! $opencount{'textarea'}) {
                my $match = sub {
                    my $str = shift;
                    if ($str =~ /^(.*?)(&(#39|quot|lt|gt)(;.*)?)$/) {
                        $url{++$urlcount} = $1;
                        return "&url$urlcount;$1&urlend;$2";
                    } else {
                        $url{++$urlcount} = $str;
                        return "&url$urlcount;$str&urlend;";
                    }
                };
                $token->[1] =~ s!https?://[^\s\'\"\<\>]+[a-zA-Z0-9_/&=\-]! $match->($&); !ge;
            }

            # escape tags in text tokens.  shouldn't belong here!
            # especially because the parser returns things it's
            # confused about (broken, ill-formed HTML) as text.
            $token->[1] =~ s/</&lt;/g;
            $token->[1] =~ s/>/&gt;/g;

            # put <wbr> tags into long words, except inside <pre> and <textarea>.
            if ($wordlength && !$opencount{'pre'} && !$opencount{'textarea'}) {
                $token->[1] =~ s/\S{$wordlength,}/break_word($&,$wordlength)/eg;
            }

            # auto-format things, unless we're in a textarea, when it doesn't make sense
            if ($auto_format && !$opencount{'textarea'}) {
                $token->[1] =~ s/\r?\n/<br \/>/g;
                if (! $opencount{'a'}) {
                    $token->[1] =~ s/&url(\d+);(.*?)&urlend;/<a href=\"$url{$1}\">$2<\/a>/g;
                }
            }

            $newdata .= $token->[1];
        }
        elsif ($type eq "C") {
            # by default, ditch comments
            if ($keepcomments) {
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

    if (ref $opts->{'autoclose'} eq "ARRAY") {
        foreach my $tag (@{$opts->{'autoclose'}}) {
            if ($opencount{$tag}) {
                $newdata .= "</$tag>" x $opencount{$tag};
            }
        }
    }

    # extra-paranoid check
    1 while $newdata =~ s/<script\b//ig;

    $$data = $newdata;
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

my $subject_eat = [qw[head title style layer iframe applet object]];
my $subject_allow = [qw[a b i u em strong cite]];
my $subject_remove = [qw[bgsound embed object caption link font noscript]];
sub clean_subject
{
    my $ref = shift;
    return unless $$ref =~ /[\<\>]/;
    clean($ref, {
        'wordlength' => 40,
        'addbreaks' => 0,
        'eat' => $subject_eat,
        'mode' => 'deny',
        'allow' => $subject_allow,
        'remove' => $subject_remove,
        'autoclose' => $subject_allow,
        'noearlyclose' => 1,
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

my $event_eat = [qw[head title style layer iframe applet object xml]];
my $event_remove = [qw[bgsound embed object link body meta noscript plaintext]];

my @comment_close = qw(
    a sub sup xmp bdo q span
    b i u tt s strike big small font
    abbr acronym cite code dfn em kbd samp strong var del ins
    h1 h2 h3 h4 h5 h6 div blockquote address pre center
    ul ol li dl dt dd
    table tr td th tbody tfoot thead colgroup caption
    marquee area map form textarea blink
);
my @comment_all = (@comment_close, "img", "br", "hr", "p", "col");

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

    # fast path:  no markup or URLs to linkify
    if ($$ref !~ /\<|\>|http/ && ! $opts->{preformatted}) {
        $$ref =~ s/\S{40,}/break_word($&,40)/eg;
        $$ref =~ s/\r?\n/<br \/>/g;
        return;
    }

    # slow path: need to be run it through the cleaner
    clean($ref, {
        'linkify' => 1,
        'wordlength' => 40,
        'addbreaks' => $opts->{'preformatted'} ? 0 : 1,
        'cuturl' => $opts->{'cuturl'},
        'cutpreview' => $opts->{'cutpreview'},
        'eat' => $event_eat,
        'mode' => 'allow',
        'remove' => $event_remove,
        'autoclose' => \@comment_close,
        'cleancss' => 1,
        'maximgwidth' => $opts->{'maximgwidth'},
        'maximgheight' => $opts->{'maximgheight'},
        'ljcut_disable' => $opts->{'ljcut_disable'},
        'noearlyclose' => 1,
        'extractimages' => $opts->{'extractimages'} ? 1 : 0,
    });
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
        $opts = { 'preformatted' => $opts };
    }

    # fast path:  no markup or URLs to linkify
    if ($$ref !~ /\<|\>|http/ && ! $opts->{preformatted}) {
        $$ref =~ s/\S{40,}/break_word($&,40)/eg;
        $$ref =~ s/\r?\n/<br \/>/g;
        return 0;
    }

    # slow path: need to be run it through the cleaner
    return clean($ref, {
        'linkify' => 1,
        'wordlength' => 40,
        'addbreaks' => $opts->{preformatted} ? 0 : 1,
        'eat' => [qw[head title style layer iframe applet object]],
        'mode' => 'deny',
        'allow' => \@comment_all,
        'autoclose' => \@comment_close,
        'cleancss' => 1,
        'extractlinks' => $opts->{'anon_comment'},
        'extractimages' => $opts->{'anon_comment'},
        'noearlyclose' => 1,
        'nocss' => $opts->{'nocss'},
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
            'eat' => [qw[layer iframe script object embed applet]],
            'mode' => 'allow',
            'keepcomments' => 1, # allows CSS to work
            'cleancss' => 1,
            's1var' => $v,
        });
    }

    return Storable::freeze(\%tmpl);
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

    return unless $url;

    unless ($allow_all) {
        # see what protocol they want, default to http
        my $pref = "http";
        $pref = $1 if $url =~ /^(https?|ftp|webcal):/;

        # strip out the protocol section
        $url =~ s!^.*?:/*!!;

        return unless $url;

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
    $word =~ s/((?:$onechar){$at})\B/$1<wbr \/>/g;
    return $word;
}

1;
