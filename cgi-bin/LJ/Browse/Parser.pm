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
    my $is_removed_video = 0;
    my $images_crop_cnt = $args{'crop_image'};
    my @images = ();
    my $remove_tags = $args{'remove_tags'};
    my $is_text_trimmed = 0;

    while (my $token = $p->get_token) {
        my $type = $token->[0];
        my $tag  = $token->[1];
        my $attr = $token->[2];  # hashref

        if ($type eq "S") {
            my $selfclose = 0;

            ## resize and crop first image from post if exist
            if ($tag eq 'img') {
                my $r = $images_crop_cnt ? LJ::crop_picture_from_web(
                    source      => $attr->{'src'},
                    size        => '200x200',
                    cancel_size => '200x0',
                    username    => $LJ::PHOTOS_FEAT_POSTS_FB_USERNAME,
                    password    => $LJ::PHOTOS_FEAT_POSTS_FB_PASSWORD,
                    galleries   => [ $LJ::PHOTOS_FEAT_POSTS_FB_GALLERY ],
                ) : {};
                if ($images_crop_cnt && $r && ($r->{'status'} ne 'small') && $r->{'url'}) {
                    $images_crop_cnt--;
                    push @images, $r->{url};
                    next;
                } elsif ($r && $r->{'status'} ne 'small') {
                    next;
                }
            }

            if (grep { $tag eq $_ } @$remove_tags) {
                ## adding space to the text do not stick together
                $ret .= " ";
                next;
            }

            if ($tag =~ /^lj-poll/) {
                ## no need to insert poll
                $ret .= " ";
            } elsif ($tag =~ /^lj-embed/) {
                ## nothing to do. remove all embed content
                $is_removed_video = 1;
                $ret .= " ";
            } elsif ($tag =~ /^lj-cut/) {
                ## remove all text from lj-cut
                $ret .= " ";
            } elsif ($tag eq 'lj') {
                foreach my $attrname (keys %$attr) {
                    if ($attrname =~ /user|comm/) {
                        $ret .= LJ::ljuser($attr->{$attrname});
                    }
                }
                $selfclose = 1;
            } else {
                $ret .= "<$tag";

                # assume tags are properly self-closed
                $selfclose = 1 if lc $tag eq 'input' || lc $tag eq 'br' || lc $tag eq 'img';

                # preserve order of attributes. the original order is
                # in element 4 of $token
                foreach my $attrname (@{$token->[3]}) {
                    if ($attrname eq '/') {
                        next;
                    }

                    # FIXME: ultra ghetto.
                    $attr->{$attrname} = LJ::no_utf8_flag($attr->{$attrname});
                    $ret .= " $attrname=\"" . LJ::ehtml($attr->{$attrname}) . "\"";
                }

                $ret .= $selfclose ? " />" : ">";
            }

            push @open_tags, $tag unless $selfclose;

        } elsif ($type eq 'T' || $type eq 'D') {
            my $content = $token->[1];

            if (length($content) + $content_len > $char_max) {

                # truncate and stop parsing
                $content = LJ::trim_at_word($content, ($char_max - $content_len));
                $ret .= $content;
                $is_text_trimmed = 1;
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
        text             => $ret,
        images           => \@images,
        is_removed_video => $is_removed_video,
        is_text_trimmed  => $is_text_trimmed,
    }
}

sub _after_parse {
    my $text = shift;

    ## Remove multiple "br" tags
    $$text =~ s#(\s*</?br\s*/?>\s*){2,}#<br/>#gi;

    ## Remove <a><img><br>-type html (imgs had been deleted early)
    $$text =~ s#(<a[^>]*?></a></?br\s*/?>\s*){2,}#<br/>#gi;

    ## Remove all content of 'script' tag
    $$text =~ s#<script.*?/script># #gis;
}

1;

