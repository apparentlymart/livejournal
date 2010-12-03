package LJ::Browse::Parser;

use strict;

## Parsing text for Landing Page
## args:
##      text => Text to parse
##      max_len => Truncate text on max_len chars
## return:
##      hashref
##          text => parsed and cropped text
##          images => arrayref for urls of cropped images
##
sub do_parse {
    my $class = shift;
    my %args = @_;

    my $text = $args{'text'};
    my $char_max = $args{'max_len'};

    my $p = HTML::TokeParser->new(\$text);

    my $ret = '';
    my @open_tags = ();
    my $content_len = 0;
    my $images_crop_cnt = $args{'crop_image'};
    my @images = ();
    my $remove_tags = $args{'remove_tags'};

    while (my $token = $p->get_token) {
        my $type = $token->[0];
        my $tag  = $token->[1];
        my $attr = $token->[2];  # hashref

        if ($type eq "S") {
            my $selfclose;

            if ($tag eq 'img') {
                next unless $images_crop_cnt;
                $images_crop_cnt--;
                my $r = LJ::crop_picture_from_web(
                    source    => $attr->{'src'},
                    size      => '200x200',
                    username  => $LJ::PHOTOS_FEAT_POSTS_FB_USERNAME,
                    password  => $LJ::PHOTOS_FEAT_POSTS_FB_PASSWORD,
                    galleries => [ $LJ::PHOTOS_FEAT_POSTS_FB_GALLERY ],
                );
                push @images, $r->{url} if $r->{url};
                next;
            }

            next if grep { $tag eq $_ } @$remove_tags;

            # start tag
            $ret .= "<$tag";

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
                $ret .= " $attrname=\"" . LJ::ehtml($attr->{$attrname}) . "\"";
            }

            $ret .= $selfclose ? " />" : ">";

            push @open_tags, $tag unless $selfclose;

        } elsif ($type eq 'T' || $type eq 'D') {
            my $content = $token->[1];

            if (length($content) + $content_len > $char_max) {

                # truncate and stop parsing
                $content = LJ::text_trim($content, undef, ($char_max - $content_len));
                $ret .= $content;
                last;
            }

            $content_len += length $content;

            $ret .= $content;

        } elsif ($type eq 'C') {
            # comment, don't care
            $ret .= $token->[1];

        } elsif ($type eq 'E') {
            next if grep { $tag eq $_ } @$remove_tags;

            # end tag
            pop @open_tags;
            $ret .= "</$tag>";
        }
    }

    $ret .= join("\n", map { "</$_>" } reverse @open_tags);

    _after_parse (\$ret);

    return {
        text    => $ret,
        images  => \@images,
    }
}

sub _after_parse {
    my $text = shift;

    ## Remove multiple "br" tags
    $$text =~ s#(\s*<br\s*/?>\s*){2,}# #gi;
}

1;

