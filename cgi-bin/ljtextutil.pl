package LJ;
use strict;
no warnings 'uninitialized';

use Class::Autouse qw(
                      LJ::ConvUTF8
                      HTML::TokeParser
                      HTML::Parser
                      LJ::Text
                      );
# <LJFUNC>
# name: LJ::trim
# class: text
# des: Removes whitespace from left and right side of a string.
# args: string
# des-string: string to be trimmed
# returns: trimmed string
# </LJFUNC>
sub trim
{
    my $a = $_[0];
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;
}

# <LJFUNC>
# name: LJ::decode_url_string
# class: web
# des: Parse URL-style arg/value pairs into a hash.
# args: buffer, hashref
# des-buffer: Scalar or scalarref of buffer to parse.
# des-hashref: Hashref to populate.
# returns: boolean; true.
# </LJFUNC>
sub decode_url_string
{
    my $a = shift;
    my $buffer = ref $a ? $a : \$a;
    my $hashref = shift;  # output hash
    my $keyref  = shift;  # array of keys as they were found

    my $pair;
    my @pairs = split(/&/, $$buffer);
    @$keyref = @pairs;
    my ($name, $value);
    foreach $pair (@pairs)
    {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $hashref->{$name} .= $hashref->{$name} ? "\0$value" : $value;
    }
    return 1;
}

# args: hashref of key/values
#       arrayref of keys in order (optional)
# returns: urlencoded string
sub encode_url_string {
    my ($hashref, $keyref) = @_;

    return join('&', map { LJ::eurl($_) . '=' . LJ::eurl($hashref->{$_}) }
                (ref $keyref ? @$keyref : keys %$hashref));
}

# <LJFUNC>
# name: LJ::eurl
# class: text
# des: Escapes a value before it can be put in a URL.  See also [func[LJ::durl]].
# args: string
# des-string: string to be escaped
# returns: string escaped
# </LJFUNC>
sub eurl
{
    return LJ::Text->eurl(@_);
}

# <LJFUNC>
# name: LJ::durl
# class: text
# des: Decodes a value that's URL-escaped.  See also [func[LJ::eurl]].
# args: string
# des-string: string to be decoded
# returns: string decoded
# </LJFUNC>
sub durl
{
    return LJ::Text->durl(@_);
}

# <LJFUNC>
# name: LJ::exml
# class: text
# des: Escapes a value before it can be put in XML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub exml
{
    # fast path for the commmon case:
    return $_[0] unless $_[0] =~ /[&\"\'<>\x00-\x08\x0B\x0C\x0E-\x1F]/;
    # what are those character ranges? XML 1.0 allows:
    # #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]

    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    $a =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    return $a;
}

# <LJFUNC>
# name: LJ::ehtml
# class: text
# des: Escapes a value before it can be put in HTML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub ehtml
{
    # fast path for the commmon case:
    return $_[0] unless $_[0] =~ /[&\"\'<>]/;

    # this is faster than doing one substitution with a map:
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}
*eall = \&ehtml;  # old BML syntax required eall to also escape BML.  not anymore.

# <LJFUNC>
# name: LJ::dhtml
# class: text
# des: Remove HTML-escaping
# args: string
# des-string: string to be un-escaped
# returns: string with HTML
# </LJFUNC>
sub dhtml
{
    my $a = $_[0];
    $a =~ s/&quot;/"/g;
    $a =~ s/&\#39;/'/g;
    $a =~ s/&apos;/'/g;
    $a =~ s/&lt;/</g;
    $a =~ s/&gt;/>/g;
    $a =~ s/&amp;/&/g;
    return $a;
}

# <LJFUNC>
# name: LJ::etags
# class: text
# des: Escapes < and > from a string
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub etags
{
    # fast path for the commmon case:
    return $_[0] unless $_[0] =~ /[<>]/;

    my $a = $_[0];
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

# <LJFUNC>
# name: LJ::ejs
# class: text
# des: Escapes a string value before it can be put in JavaScript.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub ejs
{
    my $a = $_[0];
    $a =~ s/[\"\'\\]/\\$&/g;
    $a =~ s/&quot;/\\&quot;/g;
    $a =~ s/\r?\n/\\n/gs;
    $a =~ s/\r//gs;
    return $a;
}

# given a string, makes it into a string you can put into javascript,
# including protecting against closing </script> tags in the entry.
# does the double quotes for ya.
sub ejs_string {
    my $str = ejs($_[0]);
    $str =~ s!</script!</scri\" + \"pt!gi;
    return "\"" . $str . "\"";
}

# changes every char in a string to %XX where XX is the hex value
# this is useful for passing strings to javascript through HTML, because
# javascript's "unescape" function expects strings in this format
sub ejs_all
{
    my $a = $_[0];
    $a =~ s/(.)/uc sprintf("%%%02x",ord($1))/eg;
    return $a;
}


# strip all HTML tags from a string
sub strip_html {
    my $str = shift;
    my $opts = shift || {};
=head
    $str =~ s/\<lj user\=['"]?([\w-]+)['"]?\>/$1/g;   # "
    if ($opts->{use_space}) {
        $str =~ s/\<([^\<])+\>/ /g;
    } else {
        $str =~ s/\<([^\<])+\>//g;
    }
    return $str;
=cut
    my $p = HTML::Parser->new(api_version => 3,
                handlers => {
                    text  => [sub { $_[0]->{res} .= $_[1] }, 'self, text'], # concat plain text
                    # handle tags
                    start => [sub { 
                                    my ($self, $tag, $attrs) = @_;
                                    if ($tag =~ /lj/i){
                                        $self->{res} .= $attrs->{user} || $attrs->{comm};  # <lj user="username" title=".."> -> username
                                    } else {
                                        $self->{res} .= ' ' if $opts->{use_space}; # for other tags add spaces if needed.
                                    }
                                   },
                                   'self, tagname, attr, text'
                               ],
                },
            );
    $p->parse($str);
    $p->eof; 

    return $p->{res};
}

# <LJFUNC>
# name: LJ::is_ascii
# des: checks if text is pure ASCII.
# args: text
# des-text: text to check for being pure 7-bit ASCII text.
# returns: 1 if text is indeed pure 7-bit, 0 otherwise.
# </LJFUNC>
sub is_ascii {
    my $text = shift;
    return ($text !~ m/[^\x01-\x7f]/);
}

# <LJFUNC>
# name: LJ::is_utf8
# des: check text for UTF-8 validity.
# args: text
# des-text: text to check for UTF-8 validity
# returns: 1 if text is a valid UTF-8 stream, 0 otherwise.
# </LJFUNC>
sub is_utf8 {
    my $text = shift;

    if (LJ::are_hooks("is_utf8")) {
        return LJ::run_hook("is_utf8", $text);
    }

    require Unicode::CheckUTF8;
    {
        no strict;
        local $^W = 0;
        *stab = *{"main::LJ::"};
        undef $stab{is_utf8};
    }
    *LJ::is_utf8 = \&Unicode::CheckUTF8::is_utf8;
    return Unicode::CheckUTF8::is_utf8($text);
}

# <LJFUNC>
# name: LJ::text_out
# des: force outgoing text into valid UTF-8.
# args: text
# des-text: reference to text to pass to output. Text if modified in-place.
# returns: nothing.
# </LJFUNC>
sub text_out
{
    my $rtext = shift;

    # if we're not Unicode, do nothing
    return unless $LJ::UNICODE;

    # is this valid UTF-8 already?
    return if LJ::is_utf8($$rtext);

    # no. Blot out all non-ASCII chars
    $$rtext =~ s/[\x00\x80-\xff]/\?/g;
    return;
}

# <LJFUNC>
# name: LJ::text_in
# des: do appropriate checks on input text. Should be called on all
#      user-generated text.
# args: text
# des-text: text to check
# returns: 1 if the text is valid, 0 if not.
# </LJFUNC>
sub text_in
{
    my $text = shift;
    return 1 unless $LJ::UNICODE;
    if (ref ($text) eq "HASH") {
        return ! (grep { !LJ::is_utf8($_) } values %{$text});
    }
    if (ref ($text) eq "ARRAY") {
        return ! (grep { !LJ::is_utf8($_) } @{$text});
    }
    return LJ::is_utf8($text);
}

# <LJFUNC>
# name: LJ::text_convert
# des: convert old entries/comments to UTF-8 using user's default encoding.
# args: dbs?, text, u, error
# des-dbs: optional. Deprecated; a master/slave set of database handles.
# des-text: old possibly non-ASCII text to convert
# des-u: user hashref of the journal's owner
# des-error: ref to a scalar variable which is set to 1 on error
#            (when user has no default encoding defined, but
#            text needs to be translated).
# returns: converted text or undef on error
# </LJFUNC>
sub text_convert
{
    &nodb;
    my ($text, $u, $error) = @_;

    # maybe it's pure ASCII?
    return $text if LJ::is_ascii($text);

    # load encoding id->name mapping if it's not loaded yet
    LJ::load_codes({ "encoding" => \%LJ::CACHE_ENCODINGS } )
        unless %LJ::CACHE_ENCODINGS;

    if ($u->{'oldenc'} == 0 ||
        not defined $LJ::CACHE_ENCODINGS{$u->{'oldenc'}}) {
        $$error = 1;
        return undef;
    };

    # convert!
    my $name = $LJ::CACHE_ENCODINGS{$u->{'oldenc'}};
    unless (LJ::ConvUTF8->supported_charset($name)) {
        $$error = 1;
        return undef;
    }

    return LJ::ConvUTF8->to_utf8($name, $text);
}


# <LJFUNC>
# name: LJ::text_length
# des: returns both byte length and character length of a string. In a non-Unicode
#      environment, this means byte length twice. In a Unicode environment,
#      the function assumes that its argument is a valid UTF-8 string.
# args: text
# des-text: the string to measure
# returns: a list of two values, (byte_length, char_length).
# </LJFUNC>

sub text_length
{
    my $text = shift;
    my $bl = length($text);
    unless ($LJ::UNICODE) {
        return ($bl, $bl);
    }
    my $cl = 0;
    my $utf_char = "([\x00-\x7f]|[\xc0-\xdf].|[\xe0-\xef]..|[\xf0-\xf7]...)";

    while ($text =~ m/$utf_char/go) { $cl++; }
    return ($bl, $cl);
}

# <LJFUNC>
# name: LJ::text_trim
# des: truncate string according to requirements on byte length, char
#      length, or both. "char length" means number of UTF-8 characters if
#      [ljconfig[unicode]] is set, or the same thing as byte length otherwise.
# args: text, byte_max, char_max
# des-text: the string to trim
# des-byte_max: maximum allowed length in bytes; if 0, there's no restriction
# des-char_max: maximum allowed length in chars; if 0, there's no restriction
# returns: the truncated string.
# </LJFUNC>
sub text_trim
{
    my ($text, $byte_max, $char_max) = @_;
    return $text unless $byte_max or $char_max;
    if (!$LJ::UNICODE) {
        $byte_max = $char_max if $char_max and $char_max < $byte_max;
        $byte_max = $char_max unless $byte_max;
        return substr($text, 0, $byte_max);
    }
    my $cur = 0;
    my $utf_char = "([\x00-\x7f]|[\xc0-\xdf].|[\xe0-\xef]..|[\xf0-\xf7]...)";

    # if we don't have a character limit, assume it's the same as the byte limit.
    # we will never have more characters than bytes, but we might have more bytes
    # than characters, so we can't inherit the other way.
    $char_max ||= $byte_max;
    $byte_max ||= ($char_max + 0) * 4;

    while ($text =~ m/$utf_char/gco) {
    last unless $char_max;
        last if $cur + length($1) > $byte_max and $byte_max;
        $cur += length($1);
        $char_max--;
    }
    return substr($text,0,$cur);
}

# trim string, but not truncate in middle of the word
sub trim_at_word
{
    my ($text, $char_max) = @_;

    return $text if length($text) <= $char_max;

    $char_max -= 3; # space for '...'
   
    my $short_text = text_trim($text, undef, $char_max);
    my $short_len  = length($short_text);
    my $full_len   = length($text);

    if ($short_len < $full_len) { # really trimmed
        # need correct last word and add '...'
        my $last_char = substr($short_text, -1, 1);
        my $first_char = substr($text, $short_len, 1);
        if ($last_char ne ' ' and $first_char ne ' ') { 
            my $space_idx = rindex($short_text, ' ');
            my $dot_idx   = rindex($short_text, '.');
            my $comma_idx = rindex($short_text, ',');
            my $semi_idx  = rindex($short_text, ';');
            my $colon_idx = rindex($short_text, ':');
            
            my $max = (sort {$b <=> $a} $space_idx, $dot_idx, $comma_idx, $semi_idx, $colon_idx)[0];
            $short_text = substr($text, 0, $max);

            # attention: &#2116; must not lose ';' sign
            if ($max == $semi_idx) {
                my $one_char_longer = substr($text, 0, $max + 1);
                if ($one_char_longer =~ /&.+;$/) { # entity in any form
                    $short_text = $one_char_longer; # we must keep in whole
                }
            }

            # seconde attempt to reduce text to the end of phrase
            return $short_text . '...' if $short_text =~ s/([.;:!?])[^\\1]{1,5}$//;
        }
    }

    return $short_text . '...';
}

# <LJFUNC>
# name: LJ::html_trim_4gadgets
# des: truncate string according to requirements on char length.
# args: text, char_max
# des-text: the string to trim
# des-char_max: maximum allowed length in chars; if 0, there's no restriction
# returns: the truncated string.
# </LJFUNC>

# internal subs

sub _html_trim_4gadgets_count_chars
{
    my ($l, $text_out_len, $max_len) = @_;

    if ($$text_out_len + $l > $max_len) {
        return 0;
    } else {
        $$text_out_len += $l;
        return $l;
    }
}

my %_html_trim_4gadgets_autoclose = map { $_ => $_ } qw(p li ol ul a strike);

# Subroutine itself
sub html_trim_4gadgets
{
    my $text = shift;
    my $max_len = shift;
    my $link = shift;

    my $text_out = '';
    my $text_out_len = 0;
    my $finish = 0;

    my @tags2autoclose = ();
    my $text_before_table = '';

    # collapse all white spaces to one space.
    $text =~ s/\s{2,}/ /g;

    # remove <lj-cut> ... </lj-cut>
    $text =~ s/\(\&nbsp;<a href="http:\/\/.+?\.html\?#cutid.+?<\/a>\&nbsp;\)//g;

    my $clean_tag = sub {
        my ($type, $tag, $attr, $protected) = @_;
        my $ret = '';

        $ret = "<$tag />" if 'S' eq $type && $attr->{'/'};

        if ('S' eq $type) {
            my $added_attrs = '';
            if ($protected) {
                foreach my $k (keys %$attr) {
                    delete $attr->{$k} unless $protected->{lc $k};
                }
                $added_attrs = join(' ', map { $attr->{$_} . "=\"$_\"" } keys %$attr);
            }
            $ret = "<$tag$added_attrs>";
            push @tags2autoclose, $tag if exists $_html_trim_4gadgets_autoclose{lc $tag};
        } else {
            warn "broken nested tags sequence\n" if $tag ne pop @tags2autoclose;
            $ret = "</$tag>";
        }

        return $ret;
    };

    my $clean_table_tag = sub { $clean_tag->(@_, { map { $_ => $_ } qw(rowspan colspan) } ) };

    my $clean_hn_tag = sub {
        my ($type, $tag, $attr) = @_;
        my $ret = '';

        $ret = "<p /><strong />" if 'S' eq $type && $attr->{'/'};

        if ('S' eq $type) {
            $ret = "<p><strong>";
        } else {
            $ret = "</p></strong>";
        }

        return $ret;
    };

    my %reconstruct = (
        img => sub {
            my ($type, $tag, $attr) = @_;

            if ('S' eq $type && $attr->{'src'}) {
                # <img ...> tag count as 50 chars
                if (_html_trim_4gadgets_count_chars(50, \$text_out_len, $max_len)) {
                    return "<img src=\"".$attr->{'src'}."\" border=\"0\" />";
                } else {
                    $finish = 1;
                }
            }
            return '';
        },

        a => sub {
            my ($type, $tag, $attr) = @_;

            if ('S' eq $type && $attr->{'href'}) {
                push @tags2autoclose, $tag;
                return "<$tag href=\"".$attr->{'href'}."\" target=\"_blank\">";
            }
            if ('E' eq $type) {
                warn "broken nested tags sequence\n" if $tag ne pop @tags2autoclose;
                return "</$tag>";
            }
            return '';
        },

        p       => $clean_tag,
        br      => $clean_tag,
        wbr     => $clean_tag,
        li      => $clean_tag,
        ol      => $clean_tag,
        ul      => $clean_tag,
        s       => $clean_tag,
        strike  => $clean_tag,

        table   => sub {
            my ($type, $tag, $attr) = @_;

            if ('S' eq $type && $attr->{'href'}) {
                $text_before_table = $text_out unless $text_before_table;
                push @tags2autoclose, $tag;
                return "<$tag cellpadding=\"5\" cellspacing=\"5\" border=\"0\">"
            }
            if ('E' eq $type) {
                warn "broken nested tags sequence\n" if $tag ne pop @tags2autoclose;
                $text_before_table = '' unless grep { /table/i } @tags2autoclose;
                return "</$tag>";
            }
            return '';
        },

        th      => $clean_table_tag,
        tr      => $clean_table_tag,
        td      => $clean_table_tag,

        h1      => $clean_hn_tag,
        h2      => $clean_hn_tag,
        h3      => $clean_hn_tag,
        h4      => $clean_hn_tag,
        h5      => $clean_hn_tag,
        h6      => $clean_hn_tag,

        'lj-embed'  => sub {
            my ($type, $tag, $attr) = @_;

            if ('S' eq $type && $attr->{'id'}) {
                return "<$tag id=\"".$attr->{'id'}."\" />";
            }

            return '';
        },

    );

    my $p = HTML::TokeParser->new(\$text);

    while (my $token = $p->get_token) {
        my ($type, $tag, $attr) = @$token;

        if ('T' eq $type) {
            if(_html_trim_4gadgets_count_chars(length($tag),\$text_out_len,$max_len)) {
                $text_out .= $tag;
            } else {
                # Try to cut $tag and add some words, not whole text.
                $text_out .= LJ::trim_at_word($tag, $max_len - $text_out_len);
                $text_out =~ s/\.\.\.$//; # remove last '...' added by LJ::trim_at_word()
                $finish = 1;
            }
            next;
        }

        if (exists($reconstruct{lc $tag})) {
            $text_out .= $reconstruct{$tag}->($type, $tag, $attr);
        }

        # <lj-poll-n>
        if ($tag =~ m/^lj-poll-(\d+)$/g && 'S' eq $type) {
           my $pollid = $1;
           my $name = LJ::Poll->new($pollid)->name;
           if ($name) {
               LJ::Poll->clean_poll(\$name);
           } else {
               $name = "#$pollid";
           }

           $text_out .= "<a href=\"$LJ::SITEROOT/poll/?id=$pollid\" target=\"_blank\" >View Poll: $name.</a>";
        }

        last if $finish;
    }

    # Close all open tags.
    if ($finish && @tags2autoclose) {
        while ($_ = pop @tags2autoclose) {
            if ('table' eq lc $_) {
                $text_out = $text_before_table;
                last;
            }
            $text_out .= "</$_>";
        }
    }

    return $text_out . ($finish && $link ? "<a href=\"$link\">...</a>" : '');
}

# <LJFUNC>
# name: LJ::text_compress
# des: Compresses a chunk of text, to gzip, if configured for site.  Can compress
#      a scalarref in place, or return a compressed copy.  Won't compress if
#      value is too small, already compressed, or size would grow by compressing.
# args: text
# des-text: either a scalar or scalarref
# returns: nothing if given a scalarref (to compress in-place), or original/compressed value,
#          depending on site config.
# </LJFUNC>
sub text_compress
{
    my $text = shift;
    my $ref = ref $text;
    return $ref ? undef : $text unless $LJ::COMPRESS_TEXT;
    die "Invalid reference" if $ref && $ref ne "SCALAR";

    my $tref = $ref ? $text : \$text;
    my $pre_len = length($$tref);
    unless (substr($$tref,0,2) eq "\037\213" || $pre_len < 100) {
        my $gz = Compress::Zlib::memGzip($$tref);
        if (length($gz) < $pre_len) {
            $$tref = $gz;
        }
    }

    return $ref ? undef : $$tref;
}

# <LJFUNC>
# name: LJ::text_uncompress
# des: Uncompresses a chunk of text, from gzip, if configured for site.  Can uncompress
#      a scalarref in place, or return a compressed copy.  Won't uncompress unless
#      it finds the gzip magic number at the beginning of the text.
# args: text
# des-text: either a scalar or scalarref.
# returns: nothing if given a scalarref (to uncompress in-place), or original/uncompressed value,
#          depending on if test was compressed or not
# </LJFUNC>
sub text_uncompress
{
    my $text = shift;
    my $ref = ref $text;
    die "Invalid reference" if $ref && $ref ne "SCALAR";
    my $tref = $ref ? $text : \$text;

    # check for gzip's magic number
    if (substr($$tref,0,2) eq "\037\213") {
        $$tref = Compress::Zlib::memGunzip($$tref);
    }

    return $ref ? undef : $$tref;
}

# trimm text for small widgets(myspace, yandexbar, facebook and etc.)
# args:
# text =>
# length =>
# img_length =>
# return: trimmed text
sub trim_widgets {
     my %args = @_;
     my $max_length = $args{length};
     my $img_length = $args{img_length} || 50;
     my @allow_tags = qw(img p li ol ul a br s strike table th tr td h1 h2 h3 h4 h5 h6 lj);
     my @close_tags = qw(li ol ul a s strike h1 h2 h3 h4 h5 h6);
     
     my $event = '';
     my $event_length = 0;
     my $table_tags = 0;
     my $buff = '';
     my $buff_length = 0;
     my @tags_stack;
     my @parts = split /(<[^>]*>)/, $args{text};
     while (defined(my $slice = shift @parts)){
         if( my ($close_tag, $tag, $attrib) = ($slice =~ m#<(/?)\s*(\w+)(\s+[^>]*)?>#) ){
             next unless grep {$tag eq $_} @allow_tags;
             if( $close_tag ){
                 my $j;
                 for $j( 0 .. @tags_stack ){
                     last if $tags_stack[$j] eq $tag;
                 }
                 splice(@tags_stack, $j, 1);
                 $table_tags-- if ($tag eq 'table') && $table_tags;
             } else {
                 if( $tag eq 'img' ){
                    if ($buff_length + $event_length > $max_length - $img_length){
                        push @parts, $slice;
                        last;
                    };
                    $attrib =~ s#.*(src=['"][^'"]*['"])$#$1 /#; 
                    $buff_length += $img_length;                        
                 } elsif( $tag eq 'a' ) {
                    $attrib =~ s#.*(href=['"][^'"]*['"]).*$#$1#; 
                    $attrib = 'target="_blank" ' . $attrib;
                 } elsif( $tag eq 'table' ){
                    $attrib = 'cellpadding="5" cellspacing="5" border="0"';
                    $table_tags++;
                 } elsif( $tag =~ /t[hdr]/ ){
                    $attrib = join(' ', grep {$_ =~ /^(col|row)span/} 
                        split /\s+/, $attrib);
                 }

                 unshift @tags_stack, $tag
                    if grep {$tag eq $_} @close_tags;
                         
                 $slice = "<$tag" . ($attrib?" $attrib>":'>');
             }
             $slice = $close_tag?'</strong></p>':'<p><strong>' if $tag =~ /h\d/;
         } else {
            my $slice_length = LJ::text_length($slice);
            if ($event_length + $buff_length > $max_length - $slice_length) {
                if ($table_tags){
                    push @parts, $slice;
                    last; 
                }
                my @words = split /([\n\s]+)/, $slice;
                for my $w (@words){
                    my $word_length = LJ::text_length($w);
                    if ($event_length + $word_length > $max_length){
                        push @parts, $slice;
                        last;
                    }
                    $event_length += $word_length;
                    $event .= $w;
                }
                last;
            } 
            $buff_length += $slice_length;
         }

         $buff .= $slice;
         unless( $table_tags ){
             $event_length += $buff_length;
             $event .= $buff;
             $buff_length = 0;
             $buff = '';                     
         }
     }

     $event = $event . "</$_>" for @tags_stack;
     $event = $event . $args{'read_more'} if @parts;
     return $event;   
}

# event => text
# embed_url => url
sub convert_lj_tags_to_links {
    my %args = @_;
    while ($args{event} =~ /<lj-poll-(\d+)>/g) {
       my $pollid = $1;
       my $name = LJ::Poll->new($pollid)->name;
       if ($name) {
           LJ::Poll->clean_poll(\$name);
       } else {
           $name = "#$pollid";
       }
       $args{event} =~ s#<lj-poll-$pollid>#<a href="$LJ::SITEROOT/poll/?id=$pollid" target="_blank" >View Poll: $name.</a>#g;
    }
    
    $args{event} =~ s#<lj\-embed[^>]+/>#<a href="$args{embed_url}">View movie.</a>#g;
    while ( $args{event} =~ /<lj\s+user="([^>"]+)"\s*\/?>/g ){
        # follow the documentation - no about communites, openid or syndicated, just user
        my $user = LJ::load_user($1); 
        my $name = $user->username;
        my $html = '<a href="' . $user->profile_url . '" target="_blank"><img src="' 
        . $LJ::IMGPREFIX . '/userinfo.gif" alt=""></a><a href="'
        . $user->journal_base . '" target="_blank">' . $name . '</a>';
        $args{event} =~ s#<lj\s+user="$name"\s*\/?>#$html#g;
    }
    $args{event} =~ s#</?lj-cut[^>]*>##g;
    
    return $args{event};
}

# function to trim a string containing HTML.  this will auto-close any
# html tags that were still open when the string was truncated
sub html_trim {
    my ($text, $char_max) = @_;

    return $text unless $char_max;

    my $p = HTML::TokeParser->new(\$text);
    my @open_tags; # keep track of what tags are open
    my $out = '';
    my $content_len = 0;

  TOKEN:
    while (my $token = $p->get_token) {
        my $type = $token->[0];
        my $tag  = $token->[1];
        my $attr = $token->[2];  # hashref

        if ($type eq "S") {
            my $selfclose;

            # start tag
            $out .= "<$tag";

            # assume tags are properly self-closed
            $selfclose = 1 if lc $tag eq 'input' || lc $tag eq 'br' || lc $tag eq 'img';

            # preserve order of attributes. the original order is
            # in element 4 of $token
            foreach my $attrname (@{$token->[3]}) {
                if ($attrname eq '/') {
                    $selfclose = 1;
                    next;
                }

                # FIXME: ultra ghetto.
                $attr->{$attrname} = LJ::no_utf8_flag($attr->{$attrname});
                $out .= " $attrname=\"" . LJ::ehtml($attr->{$attrname}) . "\"";
            }

            $out .= $selfclose ? " />" : ">";

            push @open_tags, $tag unless $selfclose;

        } elsif ($type eq 'T' || $type eq 'D') {
            my $content = $token->[1];

            if (length($content) + $content_len > $char_max) {

                # truncate and stop parsing
                $content = LJ::text_trim($content, undef, ($char_max - $content_len));
                $out .= $content;
                last;
            }

            $content_len += length $content;

            $out .= $content;

        } elsif ($type eq 'C') {
            # comment, don't care
            $out .= $token->[1];

        } elsif ($type eq 'E') {
            # end tag
            pop @open_tags;
            $out .= "</$tag>";
        }
    }

    $out .= join("\n", map { "</$_>" } reverse @open_tags);

    return $out;
}

# takes a number, inserts commas where needed
sub commafy {
    my $number = shift;
    return $number unless $number =~ /^\d+$/;

    my $punc = LJ::Lang::ml('number.punctuation') || ",";
    $number =~ s/(?<=\d)(?=(\d\d\d)+(?!\d))/$punc/g;
    return $number;
}

# <LJFUNC>
# name: LJ::html_newlines
# des: Replace newlines with HTML break tags.
# args: text
# returns: text, possibly including HTML break tags.
# </LJFUNC>
sub html_newlines
{
    my $text = shift;
    $text =~ s/\n/<br \/>/gm;

    return $text;
}

# given HTML, returns an arrayref of URLs to images that are in the HTML
sub html_get_img_urls {
    my $htmlref = shift;
    my %opts = @_;

    my $exclude_site_imgs = $opts{exclude_site_imgs} || 0;

    my @image_urls;
    my $p = HTML::TokeParser->new($htmlref);

    while (my $token = $p->get_token) {
        if ($token->[1] eq "img") {
            my $attrs = $token->[2];
            foreach my $attr (keys %$attrs) {
                push @image_urls, $attrs->{$attr} if
                    $attr eq "src" &&
                    ($exclude_site_imgs ? $attrs->{$attr} !~ /^$LJ::IMGPREFIX/ : 1);
            }
        }
    }

    return \@image_urls;
}

# given HTML, returns an arrayref of link URLs that are in the HTML
sub html_get_link_urls {
    my $htmlref = shift;
    my %opts = @_;

    my @link_urls;
    my $p = HTML::TokeParser->new($htmlref);

    while (my $token = $p->get_token) {
        if ($token->[0] eq "S" && $token->[1] eq "a") {
            my $attrs = $token->[2];
            foreach my $attr (keys %$attrs) {
                push @link_urls, $attrs->{$attr} if $attr eq "href";
            }
        }
    }

    return \@link_urls;
}

1;

