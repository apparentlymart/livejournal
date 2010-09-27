package LJ::Maps;
use strict;
use URI;

##
## input: attribute hash for <lj-map /> tag (url, width, height)
## outpus: html code
## method is called from html cleaner
##
sub expand_ljmap_tag {
    my $class = shift;
    my $attr = shift;

    if (my $url = $attr->{'url'}) {
        my $uri = URI->new($url);
        if ($uri->can('host')) {
            my $host = $uri->host;
            my %url_params = $uri->query_form;
            my $iframe_url;
            my $width = LJ::ehtml($attr->{'width'}) || 500;
            my $height = LJ::ehtml($attr->{'height'}) || 350;
            if ($host eq 'maps.google.com') {
                $iframe_url = URI->new("http://maps.google.com/");
                $iframe_url->query_form(
                    ll      => $url_params{'ll'},
                    spn     => $url_params{'spn'},
                    z       => $url_params{'z'},
                    output  => "embed"
                );
            } elsif ($host eq 'maps.yandex.ru') {
                $iframe_url = 
                    "http://$LJ::EMBED_MODULE_DOMAIN?mode=lj-map&url=" . LJ::eurl($url) 
                    . "&width=" . LJ::eurl($width) . "&height=" . LJ::eurl($height);
            }
            
            if ($iframe_url) {
                return "<iframe src='$iframe_url' width='$width' height='$height' frameborder='0' style='border: 0;'></iframe>";
            }
        }
    }

    return "[error: invalid lj-map tag]";
}

##
## input: hash of options (url, width, height)
## output: html code for <iframe> with Yandex Map
## method is called from htdocs/tools/embedcontent.bml
## 
sub get_iframe_source {
    my $class = shift;
    my %opts = @_;
    
    ## http://maps.yandex.ru/?ll=37.580238%2C55.749544&spn=0.010504%2C0.00311&z=17&l=map
    my $uri = URI->new($opts{'url'});
    if ($uri->can('host') && $uri->host eq 'maps.yandex.ru') {
        my $key;
        {
            my @domains = split /\./, LJ::Request->header_in("Host");
            if (@domains>=2) {
                my $subdomain = "$domains[-2].$domains[-1]";
                warn $subdomain;
                $key = $LJ::YANDEX_MAPS_API_KEYS{$subdomain};
            }
        }
        return "[error: no Yandex Map API key found]"
            unless $key;

        my %url_params = $uri->query_form;
        my ($x, $y) = split /,/, $url_params{'ll'};
        my $zoom    = $url_params{'z'};
        $x =~ s/[^\d\.\-\+]//g; $y =~ s/[^\d\.\-\+]//g;
        $zoom =~ s/[^\d\.\-\+]//g;
        my $width   = LJ::ehtml($opts{'width'});
        my $height  = LJ::ehtml($opts{'height'});
        #my $width   = LJ::ehtml($opts{'width'} - 20);
        #my $height  = LJ::ehtml($opts{'height'} - 20);
        
        return <<"HTML";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <script src="http://api-maps.yandex.ru/1.1/index.xml?key=$key" type="text/javascript"></script>
        <script type="text/javascript">
            YMaps.jQuery(function () {
                var map = new YMaps.Map(YMaps.jQuery("#YMapsID")[0]);
                map.setCenter(new YMaps.GeoPoint($x, $y), $zoom);
                map.addControl(new YMaps.ToolBar());
                map.addControl(new YMaps.Zoom());
                map.addControl(new YMaps.ScaleLine());
            });
        </script>
<style type="text/css">
* {padding: 0; margin: 0;  }
</style>
</head>
<body >
    <div id="YMapsID" style="width:${width}px;height:${height}px"></div>
</body>
</html>
HTML
     }
    return "[error: invalid Yandex Map url]";
}

1;

