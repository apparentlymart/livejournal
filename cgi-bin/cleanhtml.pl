#!/usr/bin/perl
#
# <LJDEP>
# lib: HTML::TokeParser, cgi-bin/ljconfig.pl, cgi-bin/ljlib.pl
# link: htdocs/userinfo.bml, htdocs/users
# </LJDEP>

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

use strict;
use HTML::TokeParser ();

#     &LJ::CleanHTML::clean(\$u->{'bio'}, { 
#	 'wordlength' => 100, # maximum length of an unbroken "word"
#	 'addbreaks' => 1,    # insert <br/> after newlines where appropriate
#	 'tablecheck' => 1,   # make sure they aren't closing </td> that weren't opened.
#	 'eat' => [qw(head title style layer iframe)],
#	 'mode' => 'allow',
#	 'deny' => [qw(marquee)],
#        'remove' => [qw()],
#        'maximgwidth' => 100,
#        'maximgheight' => 100,
#        'keepcomments' => 1,
#        'cuturl' => 'http://www.domain.com/full_item_view.ext',
#        'cleancss' => 1
#     });

package LJ::CleanHTML;

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
 
    my $p = HTML::TokeParser->new($data);

    my $wordlength = $opts->{'wordlength'};
    my $addbreaks = $opts->{'addbreaks'};
    my $keepcomments = $opts->{'keepcomments'};
    my $mode = $opts->{'mode'};
    my $cut = $opts->{'cuturl'} || $opts->{'cutpreview'};
    my $s1var = $opts->{'s1var'};

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

    if (ref $opts->{'attrstrip'} eq "ARRAY") {
        foreach (@{$opts->{'attrstrip'}}) { push @attrstrip, $_; }
    }

    my %opencount = ();

    my $cutcount = 0;

  TOKEN:
    while (my $token = $p->get_token)
    {
        my $type = $token->[0];

        if ($type eq "S")     # start tag
        {
            my $tag = $token->[1];
            my $slashclose = 0;   # If set to 1, use XML-style empty tag marker
            
            # for tags like <name/>, pretend it's <name> and reinsert the slash later
            $slashclose = 1 if ($tag =~ s!/$!!); 

            # for incorrect tags like <name/attrib=val> (note the lack of a space) 
            # delete everything after 'name' to prevent a security loophole which happens
            # because IE understands them.
            $tag =~ s!/.+$!!;

            if ($action{$tag} eq "eat") {
                $p->unget_token($token);
                $p->get_tag("/$tag");
            } 
            elsif ($tag eq "lj-cut") 
            {
                my $attr = $token->[2];
                $cutcount++;
                if ($cut) {
                    my $text = "Read more...";
                    if ($attr->{'text'}) {
                        $text = $attr->{'text'};
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
            elsif ($tag eq "lj") 
            {
                my $attr = $token->[2];
                if ($attr->{'user'} || $attr->{'comm'}) {
                    my $user = LJ::canonical_username($attr->{'user'} || $attr->{'comm'});
                    if ($s1var) {
                        if ($attr->{'user'} =~ /^\%\%([\w\-\']+)\%\%$/) {
                            $newdata .= "%%ljuser:$1%%";
                        } elsif ($attr->{'comm'} =~ /^\%\%([\w\-\']+)\%\%$/) {
                            $newdata .= "%%ljcomm:$1%%";
                        }
                    } elsif ($user) {
                        if ($opts->{'textonly'}) {
                            $newdata .= $user;
                        } else {
                            $newdata .= LJ::ljuser($user, { 
                                'type' => $attr->{'user'} ? "" : "C"
                                });
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
            else 
            {
                my $alt_output = 0;

                my $hash = $token->[2];
                
                $slashclose = 1 if delete $hash->{'/'};

                foreach (@attrstrip) {
                    delete $hash->{$_};
                }

                foreach my $attr (keys %$hash)
                {
                    delete $hash->{$attr} if $attr =~ /^(on|dynsrc|data)/;

                    $hash->{$attr} =~ s/[\t\n]//g;
                    # IE sucks:
                    if ($hash->{$attr} =~ /(j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t|
                                            v\s*b\s*s\s*c\s*r\s*i\s*p\s*t|
                                            a\s*b\s*o\s*u\s*t)\s*:/ix) { 
                        delete $hash->{$attr}; 
                    }

                    if ($attr eq 'style' && $opts->{'cleancss'}) {
                        my $attr = $hash->{$attr};
                        # css2 spec, section 4.1.3
                        # position === p\osition  :(
                        $attr =~ s/\\//g;
                        foreach my $css (qw(absolute relative fixed)) {
                            if ($hash->{$attr} =~ /$css/i) {
                                delete $hash->{$attr};
                                last;
                            }
                        }
                    }
                        
                    if ($s1var) {
                        if ($attr =~ /%%/) {
                            delete $hash->{$attr};
                            next;
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
                foreach my $attr (qw(href)) {
                    $hash->{$attr} =~ s/^lj:(?:\/\/)?(.*)$/ExpandLJURL($1)/ei
                        if exists $hash->{$attr};
                }
                if ($hash->{'style'} =~ /expression/i) {
                    delete $hash->{'style'};
                }

                if ($tag eq "img") 
                {
                    my $img_bad = 0;
                    if ($opts->{'maximgwidth'} &&
                        (! defined $hash->{'width'} ||
                         $hash->{'width'} > $opts->{'maximgwidth'})) { $img_bad = 1; }
                    if ($opts->{'maximgheight'} &&
                        (! defined $hash->{'height'} ||
                         $hash->{'height'} > $opts->{'maximgheight'})) { $img_bad = 1; }

                    if ($img_bad) {
                        $newdata .= "<a href=\"$hash->{'src'}\"><b>(Image Link)</b></a>";
                        $alt_output = 1;
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
			    if (($tag eq 'td' || $tag eq 'th') && ! $opencount{'tr'}) { $allow = 0; }
			    elsif ($tag eq 'tr' && ! $opencount{'table'}) { $allow = 0; }
			}

                        if ($allow) { $newdata .= "<$tag"; }
                        else { $newdata .= "&lt;$tag"; }
                        foreach (keys %$hash) {
                            $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\"";
                        }
                        if ($slashclose) {
                            $newdata .= " /";
                            $opencount{$tag}--;
                        }
                        if ($allow) { 
			    $newdata .= ">"; 
			    $opencount{$tag}++;
			}
                        else { $newdata .= "&gt;"; }
                    }
                }
            }
        }
        elsif ($type eq "E") 
        {
            my $tag = $token->[1];

            my $allow;
            if ($tag eq "lj-raw") {
                $opencount{$tag}--;
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

                if ($allow && ! $remove{$tag})
                {
                    if ($allow && ! ($opts->{'noearlyclose'} && ! $opencount{$tag})) {
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

            if ($opencount{'style'}) {
                # remove anything that might run javascript/vbscript code
                $token->[1] =~ s/j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*://g;
                $token->[1] =~ s/v\s*b\s*s\s*c\s*r\s*i\s*p\s*t\s*://g;
                $token->[1] =~ s/a\s*b\s*o\s*u\s*t\s*://g;
                $token->[1] =~ s/expression//g;
                $token->[1] =~ s/<!--/[COMS]/g;
                $token->[1] =~ s/-->/[COME]/g;
            }
            my $auto_format = $addbreaks && 
                ($opencount{'table'} <= ($opencount{'td'} + $opencount{'th'})) &&
                 ! $opencount{'pre'} &&
                 ! $opencount{'lj-raw'};
            
            if ($auto_format && ! $opencount{'a'}) {
                my $match = sub {
                    my $str = shift;
                    if ($str =~ /^(.*?)(&(#39|quot|lt|gt)(;.*)?)$/) {
                        $url{++$urlcount} = $1;
                        return "&url$urlcount;$2";
                    } else {
                        $url{++$urlcount} = $str;
                        return "&url$urlcount;";
                    }
                };
                $token->[1] =~ s!https?://[^\s\'\"\<\>]+[a-zA-Z0-9_/&=\-]! $match->($&); !ge;
            }

            # escape tags in text tokens.  shouldn't belong here!
            # especially because the parser returns things it's
            # confused about (broken, ill-formed HTML) as text.
            $token->[1] =~ s/</&lt;/g;
            unless ($opencount{'style'}) {
                # don't escape this, because that breaks a CSS construct
                $token->[1] =~ s/>/&gt;/g;
            }
            if ($opencount{'style'}) {
                $token->[1] =~ s/\[COMS\]/<!--/g;
                $token->[1] =~ s/\[COME\]/-->/g;
            }

            # put <wbr> tags into long words, except inside <pre>.
            if ($wordlength && !$opencount{'pre'}) {
                # this treats normal characters and &entities; as single characters
                # also treats UTF-8 chars as single characters if $LJ::UNICODE
                my $utf_longchar = '[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xef][\x80-\xbf][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf]';
                my $match;
                if (not $LJ::UNICODE) {
                    $match = '[^&\s]|(&\#?\w{1,7};)';
                } else {
                    $match = $utf_longchar . '|[^&\s\x80-\xff]|(&\#?\w{1,7};)';
                }
                my $onechar = qr/$match/o;
                $token->[1] =~ s/(($onechar){$wordlength})\B/$1<wbr \/>/g;
            } 

            if ($auto_format) {
                $token->[1] =~ s/(\r)?\n/<br \/>/g;
                if (! $opencount{'a'}) {
                    $token->[1] =~ s/&url(\d+);/<a href=\"$url{$1}\">$url{$1}<\/a>/g;
                }
            }

            $newdata .= $token->[1];
        } 
        elsif ($type eq "C") {
            # by default, ditch comments
            if ($keepcomments) {
                $newdata .= $token->[1];
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
    return undef;
}

sub ExpandLJURL 
{
    my @args = grep { $_ } split(/\//, $_[0]);
    my $mode = shift @args;

    if ($mode eq 'user')
    {
        my $url;
        my $user = shift @args;
        $user = LJ::canonical_username($user);
        if ($args[0] eq "profile") {
            $url = "$LJ::SITEROOT/userinfo.bml?user=$user";
        } else {
            $url = "$LJ::SITEROOT/users/$user/";
            foreach (@args) {
                $url .= "$_/";
            }
        }
        return $url;
    }
    
    if ($mode eq 'support') 
    {
        if ($args[0]) {
            my $id = $args[0]+0;
            return "$LJ::SITEROOT/support/see_request.bml?id=$id";
        } else {
            return "$LJ::SITEROOT/support/";
        }
    }

    if ($mode eq 'faq') 
    {
        if ($args[0]) {
            my $id = $args[0]+0;
            return "$LJ::SITEROOT/support/faqbrowse.bml?faqid=$id";
        } else {
            return "$LJ::SITEROOT/support/faq.bml";
        }
    }

    return "$LJ::SITEROOT/";
}

my $subject_eat = [qw[head title style layer iframe applet object]];
my $subject_allow = [qw[a b i u em strong cite]];
my $subject_remove = [qw[bgsound embed object caption link font]];
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
    });
}

my $event_eat = [qw[head title style layer iframe applet object]];
my $event_remove = [qw[bgsound embed object link body meta]];

my @comment_close = qw(
    a sub sup xmp bdo q span
    b i u tt s strike big small font
    abbr acronym cite code dfn em kbd samp strong var del ins
    h1 h2 h3 h4 h5 h6 div blockquote address pre center
    ul ol li dl dt dd
    table tr td th tbody tfoot thead colgroup caption
    marquee area map 
);
my @comment_all = (@comment_close, "img", "br", "hr", "p", "col");

sub clean_event
{
    my $ref = shift;
    my $opts = shift;

    # old prototype was passing in the ref and preformatted flag.
    # now the second argument is a hashref of options, so convert it to support the old way.
    unless (ref $opts eq "HASH") {
        $opts = { 'preformatted' => $opts };
    }

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
    });
}

sub get_okay_comment_tags
{
    return @comment_all;
}

sub clean_comment
{
    my $ref = shift;
    my $preformatted = shift;

    clean($ref, {
        'linkify' => 1,
        'wordlength' => 40,
        'addbreaks' => $preformatted ? 0 : 1,
        'eat' => [qw[head title style layer iframe applet object]],
        'mode' => 'deny',
        'allow' => \@comment_all,
        'autoclose' => \@comment_close,
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
            'eat' => [qw[layer iframe script object embed]],
            'mode' => 'allow',
            'keepcomments' => 1, # allows CSS to work
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
