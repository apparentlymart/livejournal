package LJ::Portal::Box::CProd; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "CProd";
our $_box_description = 'Frank the Goat thinks you might enjoy these features';
our $_box_name = "What else has LJ been hiding from me?";

sub generate_content {
    my $self = shift;

    my $u = $self->{u};

    LJ::need_res('js/httpreq.js');
    LJ::need_res('js/cprod.js');

    my $showclass = LJ::CProd->prod_to_show($u)
        or return "";
    my $version = $showclass->get_version;
    my $content = eval { $showclass->render($u, $version) } || LJ::ehtml($@);

    my $next_button = $showclass->next_button;
    my $clickthru_button = $showclass->clickthru_button($showclass->button_text, $version);
    my $alllink = $showclass->_trackable_link_url("$LJ::SITEROOT/didyouknow/", 0);
    my $e_class = LJ::ehtml($showclass);

    $content = qq {
      <div id="CProd_box">
        <div style='padding: 0 .5em .5em .5em; margin: 0 0 1em 0;'>$content</div>
        <div style='background: #d9e6f2;'>
            <div style='background: #d9e6f2; padding: 0 .5em 0 .5em; width: 90%'>
                <img src='$LJ::IMGPREFIX/frankhead.gif' width='50' height='50' align='absmiddle' style='position: relative; top: -12px;'/>
                <div style='display: inline;'>$clickthru_button $next_button</div>
                <div style='position: relative; top: -1em; margin-left: 55px;'><a href="$alllink">What else has LJ been hiding from me?</a></div>
            </div>
            <div style='display: none;' id='CProd_class'>$e_class</div>
        </div>
      </div>
    };

    return $content;
}

# mark this cprod as having been viewed
sub box_updated {
    my $self = shift;

    my $u = $self->{u};
    my $prod = LJ::CProd->prod_to_show($u);
    LJ::CProd->mark_acked($u, $prod) if $prod;
    return 'CProd.attachNextClickListener();';
}

#######################################

sub box_description { $_box_description; }
sub box_name { $_box_name; }
sub box_class { $_box_class; }
sub can_refresh { 1 }

1;
