#!/usr/bin/perl
#

use strict;
use lib "$ENV{'LJHOME'}/src/s2";
use S2;
use S2::Checker;
use S2::Compiler;
use Storable;
use Apache::Constants ();
use HTMLCleaner;
use POSIX ();

use LJ::S2::RecentPage;
use LJ::S2::YearPage;
use LJ::S2::DayPage;
use LJ::S2::FriendsPage;
use LJ::S2::MonthPage;
use LJ::S2::EntryPage;
use LJ::S2::ReplyPage;
use LJ::Color;

package LJ::S2;

sub make_journal
{
    my ($u, $styleid, $view, $remote, $opts) = @_;

    my $r = $opts->{'r'};
    my $ret;
    $LJ::S2::ret_ref = \$ret;

    my ($entry, $page);
    my $con_opts = {};

    if ($view eq "res") {
        if ($opts->{'pathextra'} =~ m!/(\d+)/stylesheet$!) {
            $styleid = $1;
            $entry = "print_stylesheet()";
            $opts->{'contenttype'} = 'text/css';
            $con_opts->{'use_modtime'} = 1;
        } else {
            $opts->{'handler_return'} = 404;
            return;
        }
    }

    $u->{'_s2styleid'} = $styleid + 0;
    my $ctx = s2_context($r, $styleid, $con_opts);
    unless ($ctx) {
        $opts->{'handler_return'} = Apache::Constants::OK();
        return;
    }

    eval {
        my $lang = 'en';
        LJ::run_hook('set_s2bml_lang', $ctx, \$lang);
        BML::set_language($lang, \&LJ::Lang::get_text);
    };

    # let layouts disable EntryPage / ReplyPage, using the BML version
    # instead.
    if ($ctx->[S2::PROPS]->{'view_entry_disabled'} && ($view eq "entry" || $view eq "reply")) {
        ${$opts->{'handle_with_bml_ref'}} = 1;
        return;
    }

    # make sure capability supports it
    if (($view eq "entry" || $view eq "reply") && ! LJ::get_cap($u, "s2view$view")) {
        ${$opts->{'handle_with_bml_ref'}} = 1;
        return;
    }
    
    escape_context_props($ctx->[S2::PROPS]);
    
    $opts->{'ctx'} = $ctx;

    $ctx->[S2::PROPS]->{'SITEROOT'} = $LJ::SITEROOT;
    $ctx->[S2::PROPS]->{'SITENAME'} = $LJ::SITENAME;
    $ctx->[S2::PROPS]->{'SITENAMESHORT'} = $LJ::SITENAMESHORT;
    $ctx->[S2::PROPS]->{'SITENAMEABBREV'} = $LJ::SITENAMEABBREV;
    $ctx->[S2::PROPS]->{'IMGDIR'} = $LJ::IMGPREFIX;

    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    $u->{'_journalbase'} = LJ::journal_base($u->{'user'}, $opts->{'vhost'});

    if ($view eq "lastn") {
        $entry = "RecentPage::print()";
        $page = RecentPage($u, $remote, $opts);
    } elsif ($view eq "calendar") {
        $entry = "YearPage::print()";
        $page = YearPage($u, $remote, $opts);
    } elsif ($view eq "day") {
        $entry = "DayPage::print()";
        $page = DayPage($u, $remote, $opts);
    } elsif ($view eq "friends" || $view eq "friendsfriends") {
        $entry = "FriendsPage::print()";
        $page = FriendsPage($u, $remote, $opts);
    } elsif ($view eq "month") {
        $entry = "MonthPage::print()";
        $page = MonthPage($u, $remote, $opts);
    } elsif ($view eq "entry") {
        $entry = "EntryPage::print()";
        $page = EntryPage($u, $remote, $opts);
    } elsif ($view eq "reply") {
        $entry = "ReplyPage::print()";
        $page = ReplyPage($u, $remote, $opts);
    }

    return if $opts->{'suspendeduser'};
    return if $opts->{'handler_return'};

    s2_run($r, $ctx, $opts, $entry, $page);
    
    if (ref $opts->{'errors'} eq "ARRAY" && @{$opts->{'errors'}}) {
        return join('', 
                    "Errors occured processing this page:<ul>",
                    map { "<li>$_</li>" } @{$opts->{'errors'}},
                    "</ul>");
    }

    # unload layers that aren't public
    my $pub = get_public_layers();
    my @unload = grep { ! $pub->{$_} } @{$ctx->[S2::LAYERLIST]};
    S2::unregister_layer($_) foreach (@unload);

    return $ret;
}

sub s2_run
{
    my ($r, $ctx, $opts, $entry, $page) = @_;

    my $ctype = $opts->{'contenttype'} || "text/html";
    my $cleaner;
    if ($ctype =~ m!^text/html!) {
        $cleaner = new HTMLCleaner ('output' => sub { $$LJ::S2::ret_ref .= $_[0]; });
    }

    my $send_header = sub {
        my $status = $ctx->[S2::SCRATCH]->{'status'} || 200;
        $r->status($status);
        $r->content_type($ctx->[S2::SCRATCH]->{'ctype'} || $ctype);
        $r->send_http_header();
    };
    
    my $need_flush;
    my $out_straight = sub { 
        # Hacky: forces text flush.  see:
        # http://zilla.livejournal.org/906
        if ($need_flush) {
            $cleaner->parse("<!-- -->");
            $need_flush = 0;
        }
        $$LJ::S2::ret_ref .= $_[0]; 
    };
    my $out_clean = sub { 
        $cleaner->parse($_[0]); 
        $need_flush = 1;
    };
    S2::set_output($out_straight);
    S2::set_output_safe($cleaner ? $out_clean : $out_straight);
          
    $LJ::S2::CURR_PAGE = $page;
    $LJ::S2::RES_MADE = 0;  # standard resources (Image objects) made yet

    eval {
        S2::run_code($ctx, $entry, $page);
    };
    if ($@) { 
        my $error = $@;
        $error =~ s/\n/<br \/>\n/g;
        S2::pout("<b>Error running style:</b> $error");
        return 0;
    }
    $cleaner->eof if $cleaner;  # flush any remaining text/tag not yet spit out
    return 1;    
}

# find existing re-distributed layers that are in the database
# and their styleids.
sub get_public_layers
{
    my $sysid = shift;  # optional system userid (usually not used)
    return $LJ::CACHED_PUBLIC_LAYERS if $LJ::CACHED_PUBLIC_LAYERS;

    my $dbr = LJ::get_db_reader();
    $sysid ||= LJ::get_userid($dbr, "system");
    my $layers = get_layers_of_user($sysid, "is_system");

    return $layers if $LJ::LESS_CACHING;
    $LJ::CACHED_PUBLIC_LAYERS = $layers if $layers;
    return $LJ::CACHED_PUBLIC_LAYERS;
}

sub get_layers_of_user
{
    my ($u, $is_system) = @_;
    my $userid;
    if (ref $u eq "HASH") {
        $userid = $u->{'userid'}+0;
    } else {
        $userid = $u + 0;
        undef $u;
    }
    return undef unless $userid;

    return $u->{'_s2layers'} if $u && $u->{'_s2layers'};

    my %layers;    # id -> {hashref}, uniq -> {same hashref}
    my $dbr = LJ::get_db_reader();

    my $extrainfo = $is_system ? "'redist_uniq', " : "";
    my $sth = $dbr->prepare("SELECT i.infokey, i.value, l.s2lid, l.b2lid, l.type ".
                            "FROM s2layers l, s2info i ".
                            "WHERE l.userid=? AND l.s2lid=i.s2lid AND ".
                            "i.infokey IN ($extrainfo 'type', 'name', 'langcode', ".
                            "'majorversion', '_previews')");
    $sth->execute($userid);
    die $dbr->errstr if $dbr->err;
    while (my ($key, $val, $id, $bid, $type) = $sth->fetchrow_array) {
        $layers{$id}->{'b2lid'} = $bid;
        $layers{$id}->{'s2lid'} = $id;
        $layers{$id}->{'type'} = $type;
        $key = "uniq" if $key eq "redist_uniq";
        $layers{$id}->{$key} = $val;
    }

    foreach (keys %layers) {
        # setup uniq alias.
        if ($layers{$_}->{'uniq'} ne "") {
            $layers{$layers{$_}->{'uniq'}} = $layers{$_};
        }

        # setup children keys
        next unless $layers{$_}->{'b2lid'};
        if ($is_system) {
            my $bid = $layers{$_}->{'b2lid'};
            unless ($layers{$bid}) {
                delete $layers{$layers{$_}->{'uniq'}};
                delete $layers{$_};
                next;
            }
            push @{$layers{$bid}->{'children'}}, $_;
        }
    }

    if ($u) {
        $u->{'_s2layers'} = \%layers;
    }
    return \%layers;
}

# if verify, the $u->{'s2_style'} key is deleted if style isn't found
sub get_style
{
    my ($arg, $verify) = @_;

    my ($styleid, $u);
    if (ref $arg) {
        $u = $arg;
        $styleid = $u->{'s2_style'} + 0;
    } else {
        $styleid = $arg + 0;
    }

    my %style;
    my $have_style = 0;

    if ($verify && $styleid) {
        my $dbr = LJ::get_db_reader();
        my $style = $dbr->selectrow_hashref("SELECT * FROM s2styles WHERE styleid=$styleid");
        if (! $style && $u) {
            delete $u->{'s2_style'};
            $styleid = 0;
        }
    }
    
    if ($styleid) {
        my $stylay = LJ::S2::get_style_layers($styleid);
        while (my ($t, $id) = each %$stylay) { $style{$t} = $id; }
        $have_style = scalar %style;
    }

    unless ($have_style) {
        my $public = get_public_layers();
        while (my ($layer, $name) = each %$LJ::DEFAULT_STYLE) {
            next unless $name ne "";
            next unless $public->{$name};
            my $id = $public->{$name}->{'s2lid'};
            $style{$layer} = $id if $id;
        }
    }

    return %style;
}

sub s2_context
{
    my $r = shift;
    my $styleid = shift;
    my $opts = shift;

    my $dbr = LJ::get_db_reader();

    my %style = get_style($styleid);

    my @layers;
    foreach (qw(core i18nc layout i18n theme user)) {
        push @layers, $style{$_} if $style{$_};
    }

    my $modtime = S2::load_layers_from_db($dbr, @layers);

    # check that all critical layers loaded okay from the database, otherwise
    # fall back to default style.  if i18n/theme/user were deleted, just proceed.
    my $okay = 1;
    foreach (qw(core layout)) {
        next unless $style{$_};
        $okay = 0 unless S2::layer_loaded($style{$_});
    }
    unless ($okay) {
        # load the default style instead, if we just tried to load a real one and failed
        if ($styleid) { return s2_context($r, 0, $opts); }
        
        # were we trying to load the default style?
        $r->content_type("text/html");
        $r->send_http_header();
        $r->print("<b>Error preparing to run:</b> One or more layers required to load the stock style have been deleted.");
        return undef;
    }

    if ($opts->{'use_modtime'})
    {
        my $ims = $r->header_in("If-Modified-Since");
        my $ourtime = LJ::time_to_http($modtime);
        if ($ims eq $ourtime) {
            $r->status_line("304 Not Modified");
            $r->send_http_header();
            return undef;
        } else {
            $r->header_out("Last-Modified", $ourtime);
        }
    }

    my $ctx;
    eval {
        $ctx = S2::make_context(@layers);
    };

    if ($ctx) {
        S2::set_output(sub {});  # printing suppressed
        S2::set_output_safe(sub {}); 
        eval { S2::run_code($ctx, "prop_init()"); };
        return $ctx unless $@;
    }

    my $err = $@;
    $r->content_type("text/html");
    $r->send_http_header();
    $r->print("<b>Error preparing to run:</b> $err");
    return undef;

}

sub clone_layer
{
    my $id = shift;
    return 0 unless $id;

    my $dbh = LJ::get_db_writer();
    my $r;

    $r = $dbh->selectrow_hashref("SELECT * FROM s2layers WHERE s2lid=?", undef, $id);
    return 0 unless $r;
    $dbh->do("INSERT INTO s2layers (b2lid, userid, type) VALUES (?,?,?)",
             undef, $r->{'b2lid'}, $r->{'userid'}, $r->{'type'});
    my $newid = $dbh->{'mysql_insertid'};
    return 0 unless $newid;
    
    foreach my $t (qw(s2compiled s2info s2source)) {
        $r = $dbh->selectrow_hashref("SELECT * FROM $t WHERE s2lid=?", undef, $id);
        next unless $r;
        $r->{'s2lid'} = $newid;

        # kinda hacky:  we have to update the layer id
        if ($t eq "s2compiled") {
            $r->{'compdata'} =~ s/\$_LID = (\d+)/\$_LID = $newid/;
        }

        $dbh->do("INSERT INTO $t (" . join(',', keys %$r) . ") VALUES (".
                 join(',', map { $dbh->quote($_) } values %$r) . ")");
    }

    return $newid;
}

sub create_style
{
    my ($u, $name, $cloneid) = @_;
    
    my $dbh = LJ::get_db_writer();
    my $clone;
    $clone = load_style($cloneid) if $cloneid;

    # can't clone somebody else's style
    return 0 if $clone && $clone->{'userid'} != $u->{'userid'};
    
    # can't create name-less style
    return 0 unless $name =~ /\S/;

    $dbh->do("INSERT INTO s2styles (userid, name, modtime) VALUES (?,?, UNIX_TIMESTAMP())",
             undef, $u->{'userid'}, $name);
    my $styleid = $dbh->{'mysql_insertid'};
    return 0 unless $styleid;

    if ($clone) {
        $clone->{'layer'}->{'user'} = 
            LJ::clone_layer($clone->{'layer'}->{'user'});
        
        my $values;
        foreach my $ly ('core','i18nc','layout','theme','i18n','user') {
            next unless $clone->{'layer'}->{$ly};
            $values .= "," if $values;
            $values .= "($styleid, '$ly', $clone->{'layer'}->{$ly})";
        }
        $dbh->do("REPLACE INTO s2stylelayers (styleid, type, s2lid) ".
                 "VALUES $values") if $values;
    }

    return $styleid;
}

sub load_user_styles
{
    my $u = shift;
    my $opts = shift;
    return undef unless $u;

    my $dbr = LJ::get_db_reader();

    my %styles;
    my $load_using = sub {
        my $db = shift;
        my $sth = $db->prepare("SELECT styleid, name, modtime FROM s2styles WHERE userid=?");
        $sth->execute($u->{'userid'});
        while (my ($id, $name) = $sth->fetchrow_array) {
            $styles{$id} = $name;
        }
    };
    $load_using->($dbr);
    return \%styles if scalar(%styles) || ! $opts->{'create_default'};

    # create a new default one for them, but first check to see if they
    # have one on the master.
    my $dbh = LJ::get_db_writer();
    $load_using->($dbh);
    return \%styles if %styles;

    $dbh->do("INSERT INTO s2styles (userid, name, modtime) VALUES (?,?, UNIX_TIMESTAMP())", undef,
             $u->{'userid'}, $u->{'user'});
    my $styleid = $dbh->{'mysql_insertid'};
    return { $styleid => $u->{'user'} };
}

sub delete_user_style
{
    my ($u, $styleid) = @_;
    return 1 unless $styleid;
    my $dbh = LJ::get_db_writer();

    my $style = load_style($dbh, $styleid);
    delete_layer($style->{'layer'}->{'user'});

    foreach my $t (qw(s2styles s2stylelayers)) {
        $dbh->do("DELETE FROM $t WHERE styleid=?", undef, $styleid)
    }

    return 1;
}

sub load_style
{
    my $db = ref $_[0] ? shift : undef;
    my $id = shift;
    return undef unless $id;

    $db ||= LJ::get_db_reader();
    my $style = $db->selectrow_hashref("SELECT styleid, userid, name, modtime ".
                                       "FROM s2styles WHERE styleid=?",
                                       undef, $id);
    return undef unless $style;

    $style->{'layer'} = LJ::S2::get_style_layers($id) || {};

    return $style;
}

sub create_layer
{
    my ($userid, $b2lid, $type) = @_;
    $userid = LJ::want_userid($userid);

    return 0 unless $b2lid;  # caller should ensure b2lid exists and is of right type
    return 0 unless 
        $type eq "user" || $type eq "i18n" || $type eq "theme" || 
        $type eq "layout" || $type eq "i18nc" || $type eq "core";

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    $dbh->do("INSERT INTO s2layers (b2lid, userid, type) ".
             "VALUES (?,?,?)", undef, $b2lid, $userid, $type);
    return $dbh->{'mysql_insertid'};
}

sub delete_layer
{
    my $lid = shift;
    return 1 unless $lid;
    my $dbh = LJ::get_db_writer();
    foreach my $t (qw(s2layers s2compiled s2info s2source s2checker)) {
        $dbh->do("DELETE FROM $t WHERE s2lid=?", undef, $lid);
    }
    return 1;
}

sub get_style_layers
{
    my ($styleid, $force) = @_;
    return undef unless $styleid;

    # check memcache unless $force
    my $stylay = undef;
    my $memkey = [$styleid, "s2sl:$styleid"];
    $stylay = LJ::MemCache::get($memkey) unless $force;
    return $stylay if $stylay;

    my $db = LJ::get_db_writer();
    my $sth = $db->prepare("SELECT type, s2lid FROM s2stylelayers " .
                           "WHERE styleid=?");
    $sth->execute($styleid);
    $stylay = {};
    while (my ($type, $s2lid) = $sth->fetchrow_array) {
        $stylay->{$type} = $s2lid;
    }
    return undef unless %$stylay;

    # set in memcache
    LJ::MemCache::set($memkey, $stylay);
    
    return $stylay;
}

sub set_style_layers
{
    my ($u, $styleid, %newlay) = @_;
    my $dbh = LJ::get_db_writer();

    return 0 unless $dbh;
    $dbh->do("REPLACE INTO s2stylelayers (styleid,type,s2lid) VALUES ".
             join(",", map { sprintf("(%d,%s,%d)", $styleid,
                                     $dbh->quote($_), $newlay{$_}) }
                  keys %newlay));
    return 0 if $dbh->err;
    $dbh->do("UPDATE s2styles SET modtime=UNIX_TIMESTAMP() WHERE styleid=?",
             undef, $styleid);

    # delete memcache key
    LJ::MemCache::delete([$styleid, "s2sl:$styleid"]);

    return 1;
}

sub load_layer
{
    my $db = ref $_[0] ? shift : LJ::get_db_reader();
    my $lid = shift;

    return $db->selectrow_hashref("SELECT s2lid, b2lid, userid, type ".
                                  "FROM s2layers WHERE s2lid=?", undef,
                                  $lid);
}

sub escape_context_props
{
    my $obj = shift;
    if (ref $obj eq "HASH") {
        while (my ($k, $v) = each %{$obj}) {
            if (ref $v) {
                escape_context_props($v); 
            } else {
                $obj->{$k} =~ s/</&lt;/g;
                $obj->{$k} =~ s/>/&gt;/g;
                $obj->{$k} =~ s!\n!<br/>!g;
            }
        }
    } elsif (ref $obj eq "ARRAY") {
        foreach (@$obj) {
            if (ref) {
                escape_context_props($_);
            } else {
                s/</&lt;/g;
                s/>/&gt;/g;
                s!\n!<br/>!g;
            }
        }
    }
}

sub layer_compile_user
{
    my ($layer, $overrides) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless ref $layer;
    return 0 unless $layer->{'s2lid'};
    return 1 unless ref $overrides;
    my $id = $layer->{'s2lid'};
    my $s2 = "layerinfo \"type\" = \"user\";\n";
   
    foreach my $name (keys %$overrides) {
        next if $name =~ /\W/;
        my $prop = $overrides->{$name}->[0];
        my $val = $overrides->{$name}->[1];
        if ($prop->{'type'} eq "int") {
            $val = int($val);
        } elsif ($prop->{'type'} eq "bool") {
            $val = $val ? "true" : "false";
        } else {
            $val =~ s/[\\\$\"]/\\$&/g;
            $val = "\"$val\"";
        }
        $s2 .= "set $name = $val;\n";
    }

    my $error;
    return 1 if LJ::S2::layer_compile($layer, \$error, { 's2ref' => \$s2 });
    return LJ::error($error);
}

sub layer_compile
{
    my ($layer, $err_ref, $opts) = @_;
    my $dbh = LJ::get_db_writer();
    
    my $lid;
    if (ref $layer eq "HASH") {
        $lid = $layer->{'s2lid'}+0;
    } else {
        $lid = $layer+0;
        $layer = LJ::S2::load_layer($dbh, $lid) or return 0;
    }
    return 0 unless $lid;
    
    # get checker (cached, or via compiling) for parent layer
    my $checker = get_layer_checker($layer);
    unless ($checker) {
        $$err_ref = "Error compiling parent layer.";
        return undef;
    }

    # do our compile (quickly, since we probably have the cached checker)
    my $s2ref = $opts->{'s2ref'};
    unless ($s2ref) {
        my $s2 = $dbh->selectrow_array("SELECT s2code FROM s2source WHERE s2lid=?", undef, $lid);
        unless ($s2) { $$err_ref = "No source code to compile.";  return undef; }
        $s2ref = \$s2;
    }

    my $untrusted = ! $LJ::S2_TRUSTED{$layer->{'userid'}} &&
                    $layer->{'userid'} != LJ::get_userid("system");

    my $compiled;
    my $cplr = S2::Compiler->new({ 'checker' => $checker });
    eval { 
        $cplr->compile_source({
            'type' => $layer->{'type'},
            'source' => $s2ref,
            'output' => \$compiled,
            'layerid' => $lid,
            'untrusted' => $untrusted,
            'builtinPackage' => "S2::Builtin::LJ",
        });
    };
    if ($@) { $$err_ref = "Compile error: $@"; return undef; }

    # save the source, since it at least compiles
    if ($opts->{'s2ref'}) {
        $dbh->do("REPLACE INTO s2source (s2lid, s2code) VALUES (?,?)",
                 undef, $lid, ${$opts->{'s2ref'}}) or return 0;
    }
    
    # save the checker object for later
    if ($layer->{'type'} eq "core" || $layer->{'type'} eq "layout") {
        $checker->cleanForFreeze();
        my $chk_frz = Storable::freeze($checker);
        $dbh->do("REPLACE INTO s2checker (s2lid, checker) VALUES (?,?)", undef,
                 $lid, $chk_frz) or die;
    }

    # load the compiled layer to test it loads and then get layerinfo/etc from it
    S2::unregister_layer($lid);
    eval $compiled;
    if ($@) { $$err_ref = "Post-compilation error: $@"; return undef; }
    if ($opts->{'redist_uniq'}) {
        # used by update-db loader:
        my $redist_uniq = S2::get_layer_info($lid, "redist_uniq");
        die "redist_uniq value of '$redist_uniq' doesn't match $opts->{'redist_uniq'}\n"
            unless $redist_uniq eq $opts->{'redist_uniq'};
    }
    
    # put layerinfo into s2info
    my %info = S2::get_layer_info($lid);
    my $values;
    my $notin;
    foreach (keys %info) {
        $values .= "," if $values;
        $values .= sprintf("(%d, %s, %s)", $lid,
                           $dbh->quote($_), $dbh->quote($info{$_}));
        $notin .= "," if $notin;
        $notin .= $dbh->quote($_);
    }
    if ($values) {
        $dbh->do("REPLACE INTO s2info (s2lid, infokey, value) VALUES $values") or die;
        $dbh->do("DELETE FROM s2info WHERE s2lid=? AND infokey NOT IN ($notin)", undef, $lid);
    }
    if ($opts->{'layerinfo'}) {
        ${$opts->{'layerinfo'}} = \%info;
    }
    
    # put compiled into database, with its ID number
    $dbh->do("REPLACE INTO s2compiled (s2lid, comptime, compdata) ".
             "VALUES (?, UNIX_TIMESTAMP(), ?)", undef, $lid, $compiled) or die;

    # caller might want the compiled source
    if (ref $opts->{'compiledref'} eq "SCALAR") {
        ${$opts->{'compiledref'}} = $compiled;
    }
    
    S2::unregister_layer($lid);
    return 1;
}

sub get_layer_checker
{
    my $lay = shift;
    my $err_ref = shift;
    return undef unless ref $lay eq "HASH";
    return S2::Checker->new() if $lay->{'type'} eq "core";
    my $parid = $lay->{'b2lid'}+0 or return undef;
    my $dbh = LJ::get_db_writer();

    my $get_cached = sub {
        my $frz = $dbh->selectrow_array("SELECT checker FROM s2checker WHERE s2lid=?", 
                                        undef, $parid) or return undef;
        return Storable::thaw($frz); # can be undef, on failure
    };

    # the good path
    my $checker = $get_cached->();
    return $checker if $checker;

    # no cached checker (or bogus), so we have to [re]compile to get it
    my $parlay = LJ::S2::load_layer($dbh, $parid);
    return undef unless LJ::S2::layer_compile($parlay);
    return $get_cached->();
}

sub load_layer_info
{
    my ($outhash, $listref) = @_;
    return 0 unless ref $listref eq "ARRAY";
    return 1 unless @$listref;
    my $in = join(',', map { $_+0 } @$listref);
    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT s2lid, infokey, value FROM s2info WHERE ".
                            "s2lid IN ($in)");
    $sth->execute;
    while (my ($id, $k, $v) = $sth->fetchrow_array) {
        $outhash->{$id}->{$k} = $v;
    }
    return 1;
}

sub get_layout_langs
{
    my $src = shift;
    my $layid = shift;
    my %lang;
    foreach (keys %$src) {
        next unless /^\d+$/;
        my $v = $src->{$_};
        next unless $v->{'langcode'};
        $lang{$v->{'langcode'}} = $src->{$_} 
            if ($v->{'type'} eq "i18nc" ||
                ($v->{'type'} eq "i18n" && $layid && $v->{'b2lid'} == $layid));
    }
    return map { $_, $lang{$_}->{'name'} } sort keys %lang;
}

# returns array of hashrefs
sub get_layout_themes
{
    my $src = shift; $src = [ $src ] unless ref $src eq "ARRAY";
    my $layid = shift;
    my @themes;
    foreach my $src (@$src) {
        foreach (sort { $src->{$a}->{'name'} cmp $src->{$b}->{'name'} } keys %$src) {
            next unless /^\d+$/;
            my $v = $src->{$_};
            push @themes, $v if
                ($v->{'type'} eq "theme" && $layid && $v->{'b2lid'} == $layid);
        }
    }
    return @themes;
}

sub get_layout_themes_select
{
    my @sel;
    my $last_uid;
    foreach my $t (get_layout_themes(@_)) {
        if ($last_uid && $t->{'userid'} != $last_uid) {
            push @sel, 0, '---';  # divider between system & user
        }
        $last_uid = $t->{'userid'};
        push @sel, $t->{'s2lid'}, $t->{'name'};
    }
    return @sel;
}

sub get_policy
{
    return $LJ::S2::CACHE_POLICY if $LJ::S2::CACHE_POLICY;
    my $policy = {};

    foreach my $infix ("", "-local") {
        my $file = "$LJ::HOME/bin/upgrading/s2layers/policy${infix}.dat";
        my $layer = undef;
        open (P, $file) or next;
        while (<P>) {
            s/\#.*//;
            next unless /\S/;
            if (/^\s*layer\s*:\s*(\S+)\s*$/) {
                $layer = $1;
                next;
            }
            next unless $layer;
            s/^\s+//; s/\s+$//;
            my @words = split(/\s+/, $_);
            next unless $words[-1] eq "allow" || $words[-1] eq "deny";
            my $allow = $words[-1] eq "allow" ? 1 : 0;
            if ($words[0] eq "use" && @words == 2) {
                $policy->{$layer}->{'use'} = $allow;
            }
            if ($words[0] eq "props" && @words == 2) {
                $policy->{$layer}->{'props'} = $allow;
            }
            if ($words[0] eq "prop" && @words == 3) {
                $policy->{$layer}->{'prop'}->{$words[1]} = $allow;
            }
        }
    }

    return $LJ::S2::CACHE_POLICY = $policy;
}

sub can_use_layer
{
    my ($u, $uniq) = @_;  # $uniq = redist_uniq value
    return 1 if LJ::get_cap($u, "s2styles");
    my $pol = get_policy();
    my $can = 0;
    foreach ('*', $uniq) {
        next unless defined $pol->{$_};
        next unless defined $pol->{$_}->{'use'};
        $can = $pol->{$_}->{'use'};
    }
    return $can;
}

sub can_use_prop
{
    my ($u, $uniq, $prop) = @_;  # $uniq = redist_uniq value
    return 1 if LJ::get_cap($u, "s2styles");
    my $pol = get_policy();
    my $can = 0;
    my @layers = ('*');
    my $pub = get_public_layers();
    if ($pub->{$uniq} && $pub->{$uniq}->{'type'} eq "layout") {
        my $cid = $pub->{$uniq}->{'b2lid'};
        push @layers, $pub->{$cid}->{'uniq'} if $pub->{$cid};
    }
    push @layers, $uniq;
    foreach my $lay (@layers) {
        foreach my $it ('props', 'prop') {
            if ($it eq "props" && defined $pol->{$lay}->{'props'}) {
                $can = $pol->{$lay}->{'props'};
            }
            if ($it eq "prop" && defined $pol->{$lay}->{'prop'}->{$prop}) {
                $can = $pol->{$lay}->{'prop'}->{$prop};
            }
        }
    }
    return $can;
}

sub get_journal_day_counts
{
    my ($s2page) = @_;
    return $s2page->{'_day_counts'} if defined $s2page->{'_day_counts'};
    
    my $u = $s2page->{'_u'};
    my $counts = {};
    
    my $remote = LJ::get_remote();
    my $days = LJ::get_daycounts($u, $remote) or return {};
    foreach my $day (@$days) {
        $counts->{$day->[0]}->{$day->[1]}->{$day->[2]} = $day->[3];
    }
    
    return $s2page->{'_day_counts'} = $counts;
}

## S2 object constructors

sub CommentInfo
{
    my $opts = shift;
    $opts->{'_type'} = "CommentInfo";
    $opts->{'count'} += 0;
    return $opts;
}

sub Date
{
    my @parts = @_;
    my $dt = { '_type' => 'Date' };
    $dt->{'year'} = $parts[0]+0;
    $dt->{'month'} = $parts[1]+0;
    $dt->{'day'} = $parts[2]+0;
    $dt->{'_dayofweek'} = $parts[3];
    die "S2 Builtin Date() takes day of week 1-7, not 0-6"
        if defined $parts[3] && $parts[3] == 0;
    return $dt;
}

sub DateTime_unix
{
    my $time = shift;
    my @gmtime = gmtime($time);
    my $dt = { '_type' => 'DateTime' };
    $dt->{'year'} = $gmtime[5]+1900;
    $dt->{'month'} = $gmtime[4]+1;
    $dt->{'day'} = $gmtime[3];
    $dt->{'hour'} = $gmtime[2];
    $dt->{'min'} = $gmtime[1];
    $dt->{'sec'} = $gmtime[0];
    $dt->{'_dayofweek'} = $gmtime[6] + 1;
    return $dt;
}

sub DateTime_parts
{
    my @parts = split(/\s+/, shift);
    my $dt = { '_type' => 'DateTime' };
    $dt->{'year'} = $parts[0]+0;
    $dt->{'month'} = $parts[1]+0;
    $dt->{'day'} = $parts[2]+0;
    $dt->{'hour'} = $parts[3]+0;
    $dt->{'min'} = $parts[4]+0;
    $dt->{'sec'} = $parts[5]+0;
    # the parts string comes from MySQL which has range 0-6,
    # but internally and to S2 we use 1-7.
    $dt->{'_dayofweek'} = $parts[6] + 1 if defined $parts[6];
    return $dt;
}

sub Entry
{
    my ($u, $arg) = @_;
    my $e = {
        '_type' => 'Entry',
        'link_keyseq' => [ 'edit_entry' ],
        'metadata' => {},
    };
    foreach (qw(subject _rawsubject text journal poster new_day end_day
                comments userpic permalink_url itemid)) {
        $e->{$_} = $arg->{$_};
    }

    $e->{'time'} = DateTime_parts($arg->{'dateparts'});
    $e->{'depth'} = 0;  # Entries are always depth 0.  Comments are 1+.
    
    my $link_keyseq = $e->{'link_keyseq'};
    push @$link_keyseq, 'mem_add' unless $LJ::DISABLED{'memories'};
    push @$link_keyseq, 'tell_friend' unless $LJ::DISABLED{'tellafriend'};
    # Note: nav_prev and nav_next are not included in the keyseq anticipating
    #      that their placement relative to the others will vary depending on
    #      layout.

    if ($arg->{'security'} eq "public") {
        # do nothing.
    } elsif ($arg->{'security'} eq "usemask") {
        $e->{'security'} = "protected";
        $e->{'security_icon'} = Image_std("security-protected");
    } elsif ($arg->{'security'} eq "private") {
        $e->{'security'} = "private";
        $e->{'security_icon'} = Image_std("security-private");
    }

    my $p = $arg->{'props'};
    if ($p->{'current_music'}) {
        $e->{'metadata'}->{'music'} = $p->{'current_music'};
        LJ::CleanHTML::clean_subject(\$e->{'metadata'}->{'music'});
    }
    if (my $mid = $p->{'current_moodid'}) {
        my $theme = defined $arg->{'moodthemeid'} ? $arg->{'moodthemeid'} : $u->{'moodthemeid'};
        my %pic;
        $e->{'mood_icon'} = Image($pic{'pic'}, $pic{'w'}, $pic{'h'})
            if LJ::get_mood_picture($theme, $mid, \%pic);
        if (my $mood = LJ::mood_name($mid)) {
            $e->{'metadata'}->{'mood'} = $mood;
        }
    }
    if ($p->{'current_mood'}) {
        $e->{'metadata'}->{'mood'} = $p->{'current_mood'};
        LJ::CleanHTML::clean_subject(\$e->{'metadata'}->{'mood'});
    }

    return $e;
}

sub Friend
{
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'} = "Friend";
    $o->{'bgcolor'} = S2::Builtin::LJ::Color__Color($u->{'bgcolor'});
    $o->{'fgcolor'} = S2::Builtin::LJ::Color__Color($u->{'fgcolor'});
    return $o;
}

sub Null
{   
    my $type = shift;
    return {
        '_type' => $type,
        '_isnull' => 1,
    };
}

sub Page
{
    my ($u, $opts) = @_;
    my $styleid = $u->{'_s2styleid'} + 0;
    my $base_url = $u->{'_journalbase'};

    my $get = $opts->{'getargs'};
    my %args;
    foreach my $k (keys %$get) {
        my $v = $get->{$k};
        next unless $k =~ s/^\.//;
        $args{$k} = $v;
    }

    # get MAX(modtime of style layers)
    my $stylemodtime = S2::get_style_modtime($opts->{'ctx'});
    my $style = load_style($u->{'s2_style'});
    $stylemodtime = $style->{'modtime'} if $style->{'modtime'} > $stylemodtime;

    my $linkobj = LJ::Links::load_linkobj($u);
    my $linklist = [ map { UserLink($_) } @$linkobj ];

    my $p = {
        '_type' => 'Page',
        '_u' => $u,
        'view' => '',
        'args' => \%args,
        'journal' => User($u),
        'journal_type' => $u->{'journaltype'},
        'time' => DateTime_unix(time),
        'base_url' => $base_url,
        'stylesheet_url' => "$base_url/res/$styleid/stylesheet?$stylemodtime",
        'view_url' => {
            'recent' => "$base_url/",
            'userinfo' => "$LJ::SITEROOT/userinfo.bml?user=$u->{'user'}",
            'archive' => "$base_url/calendar",
            'friends' => "$base_url/friends",
        },
        'linklist' => $linklist,
        'views_order' => [ 'recent', 'archive', 'friends', 'userinfo' ],
        'global_title' =>  LJ::ehtml($u->{'journaltitle'} || $u->{'name'}),
        'global_subtitle' => LJ::ehtml($u->{'journalsubtitle'}),
        'head_content' => '',
    };
    if ($LJ::UNICODE && $opts) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\" />\n";
        # "Automatic Discovery of RSS feeds"
        $p->{'head_content'} .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$p->{'base_url'}/data/rss" />\n};
    }

    return $p;
}

sub Image
{
    my ($url, $w, $h) = @_;
    return {
        '_type' => 'Image',
        'url' => $url,
        'width' => $w,
        'height' => $h,
    };
}

sub Image_std
{
    my $name = shift;
    unless ($LJ::S2::RES_MADE++) {
        $LJ::S2::RES_CACHE = {
            'security-protected' => Image("$LJ::IMGPREFIX/icon_protected.gif", 14, 15),
            'security-private' => Image("$LJ::IMGPREFIX/icon_private.gif", 16, 16),
        };
    }
    return $LJ::S2::RES_CACHE->{$name};
}

sub Image_userpic
{
    my ($u, $picid, $kw) = @_;

    $picid ||= LJ::get_picid_from_keyword($u, $kw);

    my $pi = LJ::get_userpic_info($u);
    my $p = $pi->{'pic'}->{$picid};

    return Null("Image") unless $p;
    return {
        '_type' => "Image",
        'url' => "$LJ::USERPIC_ROOT/$picid/$u->{'userid'}",
        'width' => $p->{'width'},
        'height' => $p->{'height'},
    };
}

sub ItemRange_fromopts
{
    my $opts = shift;
    my $ir = {};

    my $items = $opts->{'items'};
    my $page_size = ($opts->{'pagesize'}+0) || 25;
    my $page = $opts->{'page'}+0 || 1;
    my $num_items = scalar @$items;

    my $pages = POSIX::ceil($num_items / $page_size);
    if ($page > $pages) { $page = $pages; }

    splice(@$items, 0, ($page-1)*$page_size) if $page > 1;
    splice(@$items, $page_size) if @$items > $page_size;
    
    $ir->{'current'} = $page;
    $ir->{'total'} = $pages;
    $ir->{'total_subitems'} = $num_items;
    $ir->{'from_subitem'} = ($page-1) * $page_size + 1;
    $ir->{'num_subitems_displayed'} = @$items;
    $ir->{'to_subitem'} = $ir->{'from_subitem'} + $ir->{'num_subitems_displayed'} - 1;
    $ir->{'all_subitems_displayed'} = ($pages == 1);
    $ir->{'_url_of'} = $opts->{'url_of'};
    return ItemRange($ir);
}

sub ItemRange
{
    my $h = shift;  # _url_of = sub($n)
    $h->{'_type'} = "ItemRange";

    my $url_of = ref $h->{'_url_of'} eq "CODE" ? $h->{'_url_of'} : sub {"";};

    $h->{'url_next'} = $url_of->($h->{'current'} + 1)
        unless $h->{'current'} >= $h->{'total'};
    $h->{'url_prev'} = $url_of->($h->{'current'} - 1)
        unless $h->{'current'} <= 1;
    $h->{'url_first'} = $url_of->(1)
        unless $h->{'current'} == 1;
    $h->{'url_last'} = $url_of->($h->{'total'})
        unless $h->{'current'} == $h->{'total'};

    return $h;
}

sub User
{
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'} = "User";
    $o->{'default_pic'} = Image_userpic($u, $u->{'defaultpicid'});
    $o->{'website_url'} = LJ::ehtml($u->{'url'});
    $o->{'website_name'} = LJ::ehtml($u->{'urlname'});
    return $o;
}

sub UserLink
{
    my $link = shift; # hashref

    # a dash means pass to s2 as blank so it will just insert a blank line
    $link->{'title'} = '' if $link->{'title'} eq "-";

    return {
        '_type' => 'UserLink',
        'is_heading' => $link->{'url'} ? 0 : 1,
        'url' => LJ::ehtml($link->{'url'}),
        'title' => LJ::ehtml($link->{'title'}),
        'children' => $link->{'children'} || [], # TODO: implement parent-child relationships
    };
}

sub UserLite
{
    my ($u) = @_;
    my $o = {
        '_type' => 'UserLite',
        'username' => $u->{'user'},
        'name' => LJ::ehtml($u->{'name'}),
        'journal_type' => $u->{'journaltype'},
    };
    return $o;
}


###############

package S2::Builtin::LJ;
use strict;

sub AUTOLOAD { 
    no strict;
    if ($AUTOLOAD =~ /::(\w+)$/) {
        my $real = \&{"S2::Builtin::$1"};
        *{$AUTOLOAD} = $real;
        return $real->(@_);
    }
    die "No such builtin: $AUTOLOAD";
}

sub ehtml
{
    my ($ctx, $text) = @_;
    return LJ::ehtml($text);
}

sub eurl
{
    my ($ctx, $text) = @_;
    return LJ::eurl($text);
}

# escape tags only
sub etags {
    my ($ctx, $text) = @_;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

sub get_page
{
    return $LJ::S2::CURR_PAGE;
}

sub get_plural_phrase
{
    my ($ctx, $n, $prop) = @_;
    my $form = S2::run_function($ctx, "lang_map_plural(int)", $n);
    my $a = $ctx->[S2::PROPS]->{"_plurals_$prop"};
    unless (ref $a eq "ARRAY") {
        $a = $ctx->[S2::PROPS]->{"_plurals_$prop"} = [ split(m!\s*//\s*!, $ctx->[S2::PROPS]->{$prop}) ];
    }
    my $text = $a->[$form];

    # this fixes missing plural forms for russians (who have 2 plural forms)
    # using languages like english with 1 plural form
    $text = $a->[-1] unless defined $text;

    $text =~ s/\#/$n/;
    return LJ::ehtml($text);
}

sub get_url
{
    my ($ctx, $obj, $view) = @_;
    my $dir = "users";
    if (ref $obj eq "HASH" && $obj->{'journal_type'} eq "C") {
        $dir = "community";
    }
    my $user = ref $obj ? $obj->{'username'} : $obj;
    $view = "info" if $view eq "userinfo";
    $view = "calendar" if $view eq "archive";
    $view = "" if $view eq "recent";
    return "$LJ::SITEROOT/$dir/$user/$view";
}

sub htmlattr
{
    my ($ctx, $name, $value) = @_;
    return "" if $value eq "";
    $name = lc($name);
    return "" if $name =~ /[^a-z]/;
    return " $name=\"" . LJ::ehtml($value) . "\"";
}

sub rand
{
    my ($ctx, $aa, $bb) = @_;
    my ($low, $high);
    if (ref $aa eq "ARRAY") {
        ($low, $high) = (0, @$aa - 1);
    } elsif (! defined $bb) {
        ($low, $high) = (1, $aa);
    } else {
        ($low, $high) = ($aa, $bb);
    }
    return int(rand($high - $low + 1)) + $low;
}

sub viewer_logged_in
{
    my ($ctx) = @_;
    my $remote = LJ::get_remote();
    return defined $remote;
}

sub viewer_is_owner
{
    my ($ctx) = @_;
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return $remote->{'userid'} == $LJ::S2::CURR_PAGE->{'_u'}->{'userid'};
}

sub weekdays
{
    my ($ctx) = @_;
    return [ 1..7 ];  # FIXME: make this conditionally monday first: [ 2..7, 1 ]
}

sub zeropad
{
    my ($ctx, $num, $digits) = @_;
    $num += 0;
    $digits += 0;
    return sprintf("%0${digits}d", $num);
}
*int__zeropad = \&zeropad;

sub Color__update_hsl
{
    my ($this, $force) = @_;
    return if $this->{'_hslset'}++;
    ($this->{'_h'}, $this->{'_s'}, $this->{'_l'}) =
        LJ::Color::rgb_to_hsl($this->{'r'}, $this->{'g'}, $this->{'b'});
    $this->{$_} = int($this->{$_} * 255 + 0.5) foreach qw(_h _s _l);
}

sub Color__update_rgb
{
    my ($this) = @_;

    ($this->{'r'}, $this->{'g'}, $this->{'b'}) = 
        LJ::Color::hsl_to_rgb( map { $this->{$_} / 255 } qw(_h _s _l) );
    Color__make_string($this);
}

sub Color__make_string
{
    my ($this) = @_;
    $this->{'as_string'} = sprintf("\#%02x%02x%02x",
				  $this->{'r'},
				  $this->{'g'},
				  $this->{'b'});
}

# public functions
sub Color__Color
{
    my ($s) = @_;
    $s =~ s/^\#//;
    return if $s =~ /[^a-fA-F0-9]/ || length($s) != 6;

    my $this = { '_type' => 'Color' };
    $this->{'r'} = hex(substr($s, 0, 2));
    $this->{'g'} = hex(substr($s, 2, 2));
    $this->{'b'} = hex(substr($s, 4, 2));
    $this->{$_} = $this->{$_} % 256 foreach qw(r g b);

    Color__make_string($this);
    return $this;
}

sub Color__clone
{
    my ($ctx, $this) = @_;
    return { %$this };
}

sub Color__set_hsl
{
    my ($this, $h, $s, $l) = @_;
    $this->{'_h'} = $h % 256;
    $this->{'_s'} = $s % 256;
    $this->{'_l'} = $l % 256;
    $this->{'_hslset'} = 1;
    Color__update_rgb($this);
}

sub Color__red {
    my ($ctx, $this, $r) = @_;
    if (defined $r) { 
        $this->{'r'} = $r % 256;
        delete $this->{'_hslset'};
        Color__make_string($this); 
    }
    $this->{'r'};
}

sub Color__green {
    my ($ctx, $this, $g) = @_;
    if (defined $g) {
        $this->{'g'} = $g % 256;
        delete $this->{'_hslset'};
        Color__make_string($this);
    }
    $this->{'g'};
}

sub Color__blue {
    my ($ctx, $this, $b) = @_;
    if (defined $b) {
        $this->{'b'} = $b % 256;
        delete $this->{'_hslset'};
        Color__make_string($this);
    }
    $this->{'b'};
}

sub Color__hue {
    my ($ctx, $this, $h) = @_;

    if (defined $h) {
        $this->{'_h'} = $h % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }
    $this->{'_h'};
}

sub Color__saturation {
    my ($ctx, $this, $s) = @_;
    if (defined $s) { 
        $this->{'_s'} = $s % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }
    $this->{'_s'};
}

sub Color__lightness {
    my ($ctx, $this, $l) = @_;

    if (defined $l) {
        $this->{'_l'} = $l % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }

    $this->{'_l'};
}

sub Color__inverse {
    my ($ctx, $this) = @_;
    my $new = {
        '_type' => 'Color',
        'r' => 255 - $this->{'r'},
        'g' => 255 - $this->{'g'},
        'b' => 255 - $this->{'b'},
    };
    Color__make_string($new);
    return $new;
}

sub Color__average {
    my ($ctx, $this, $other) = @_;
    my $new = {
        '_type' => 'Color',
        'r' => int(($this->{'r'} + $other->{'r'}) / 2 + .5),
        'g' => int(($this->{'g'} + $other->{'g'}) / 2 + .5),
        'b' => int(($this->{'b'} + $other->{'b'}) / 2 + .5),
    };
    Color__make_string($new);
    return $new;
}

sub Color__lighter {
    my ($ctx, $this, $amt) = @_;
    $amt = defined $amt ? $amt : 30;

    Color__update_hsl($this);

    my $new = {
        '_type' => 'Color',
        '_hslset' => 1,
        '_h' => $this->{'_h'},
        '_s' => $this->{'_s'},
        '_l' => ($this->{'_l'} + $amt > 255 ? 255 : $this->{'_l'} + $amt),
    };

    Color__update_rgb($new);
    return $new;
}

sub Color__darker {
    my ($ctx, $this, $amt) = @_;
    $amt = defined $amt ? $amt : 30;

    Color__update_hsl($this);

    my $new = {
        '_type' => 'Color',
        '_hslset' => 1,
        '_h' => $this->{'_h'},
        '_s' => $this->{'_s'},
        '_l' => ($this->{'_l'} - $amt < 0 ? 0 : $this->{'_l'} - $amt),
    };

    Color__update_rgb($new);
    return $new;
}

sub Comment__get_link
{
    my ($ctx, $this, $key) = @_;
    
    if ($key eq "delete_comment" || $key eq "unscreen_comment" || $key eq "screen_comment") {
        my $page = get_page();
        my $u = $page->{'_u'};
        my $post_user = $page->{'entry'} ? $page->{'entry'}->{'poster'}->{'username'} : undef;
        my $com_user = $this->{'poster'} ? $this->{'poster'}->{'username'} : undef;
        my $remote = LJ::get_remote();
        if ($key eq "delete_comment") {
            return undef unless LJ::Talk::can_delete($remote, $u, $post_user, $com_user);
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/delcomment.bml?journal=$u->{'user'}&amp;id=$this->{'talkid'}",
                'caption' => $ctx->[S2::PROPS]->{"text_multiform_opt_delete"},
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_del.gif", 22, 20),
            };
        }
        if ($key eq "screen_comment") {
            return undef if $this->{'screened'};
            return undef unless LJ::Talk::can_screen($remote, $u, $post_user, $com_user);
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/talkscreen.bml?mode=screen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
                'caption' => $ctx->[S2::PROPS]->{"text_multiform_opt_screen"},
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_scr.gif", 22, 20),
            };
        }
        if ($key eq "unscreen_comment") {
            return undef unless $this->{'screened'};
            return undef unless LJ::Talk::can_unscreen($remote, $u, $post_user, $com_user);
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/talkscreen.bml?mode=unscreen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
                'caption' => $ctx->[S2::PROPS]->{"text_multiform_opt_unscreen"},
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_unscr.gif", 22, 20),
            };
        }
    }
}

sub Comment__print_multiform_check
{
    my ($ctx, $this) = @_;
    my $tid = $this->{'talkid'} >> 8;
    $S2::pout->("<input type='checkbox' name='selected_$tid' class='ljcomsel' id='ljcomsel_$this->{'talkid'}' />");
}

# class 'date'
sub Date__day_of_week
{
    my ($ctx, $dt) = @_;
    return $dt->{'_dayofweek'} if defined $dt->{'_dayofweek'};
    return $dt->{'_dayofweek'} = LJ::day_of_week($dt->{'year'}, $dt->{'month'}, $dt->{'day'}) + 1;
}
*DateTime__day_of_week = \&Date__day_of_week;

my %dt_vars = (
               'm' => "\$time->{month}",
               'mm' => "sprintf('%02d', \$time->{month})",
               'd' => "\$time->{day}",
               'dd' => "sprintf('%02d', \$time->{day})",
               'yy' => "sprintf('%02d', \$time->{year} % 100)",
               'yyyy' => "\$time->{year}",
               'mon' => "\$ctx->[S2::PROPS]->{lang_monthname_short}->[\$time->{month}]",
               'month' => "\$ctx->[S2::PROPS]->{lang_monthname_long}->[\$time->{month}]",
               'da' => "\$ctx->[S2::PROPS]->{lang_dayname_short}->[Date__day_of_week(\$ctx, \$time)]",
               'day' => "\$ctx->[S2::PROPS]->{lang_dayname_long}->[Date__day_of_week(\$ctx, \$time)]",
               'dayord' => "S2::run_function(\$ctx, \"lang_ordinal(int)\", \$time->{day})",
               'H' => "\$time->{hour}",
               'HH' => "sprintf('%02d', \$time->{hour})",
               'h' => "(\$time->{hour} % 12 || 12)",
               'hh' => "sprintf('%02d', (\$time->{hour} % 12 || 12))",
               'min' => "sprintf('%02d', \$time->{min})",
               'sec' => "sprintf('%02d', \$time->{sec})",
               'a' => "(\$time->{hour} < 12 ? 'a' : 'p')",
               'A' => "(\$time->{hour} < 12 ? 'A' : 'P')",
            );

sub Date__date_format
{
    my ($ctx, $this, $fmt) = @_;
    $fmt ||= "short";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_datefmt'}->{$fmt};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_datefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"};
    }
    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join('',";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { $code .= $dt_vars{$_} . ","; }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}
*DateTime__date_format = \&Date__date_format;

sub DateTime__time_format
{
    my ($ctx, $this, $fmt) = @_;
    $fmt ||= "short";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_timefmt'}->{$fmt};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_timefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"};
    }
    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join('',";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { $code .= $dt_vars{$_} . ","; }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}

sub EntryLite__get_link
{
    my ($ctx, $this, $key) = @_;
    return undef;
}

sub EntryLite__get_plain_subject
{
    my ($ctx, $this) = @_;
    return $this->{'_plainsubject'} if $this->{'_plainsubject'};
    return $this->{'subject'} unless $this->{'_rawsubject'};
    my $subj = $this->{'subject'};
    LJ::CleanHTML::clean_subject_all(\$subj);
    return $this->{'_plainsubject'} = $subj;
}
*Entry__get_plain_subject = \&EntryLite__get_plain_subject;

sub Entry__get_link
{
    my ($ctx, $this, $key) = @_;
    if ($key eq "nav_prev" || $key eq "edit_entry" || $key eq "mem_add" || 
        $key eq "tell_friend" || $key eq "nav_next")
    {
        my $journal = $this->{'journal'}->{'username'};
        my $poster = $this->{'poster'}->{'username'};
        my $remote = LJ::get_remote();

        if ($key eq "edit_entry") {
            return undef unless $remote && ($remote->{'user'} eq $journal ||
                                            $remote->{'user'} eq $poster || 
                                            LJ::check_rel(LJ::load_user($journal), $remote, 'A'));
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/editjournal_do.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                'caption' => "Edit Entry",
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_edit.gif", 22, 20),
            }
        }
        if ($key eq "tell_friend") {
            return undef if $LJ::DISABLED{'tellafriend'};
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/tools/tellafriend.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                'caption' => "Tell A Friend",
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_tellfriend.gif", 22, 20),
            };
        }
        if ($key eq "mem_add") {
            return undef if $LJ::DISABLED{'memories'};
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/tools/memadd.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                'caption' => "Add to Memories",
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_memories.gif", 22, 20),
            };
        }
        if ($key eq "nav_prev") {
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/go.bml?journal=$journal&amp;itemid=$this->{'itemid'}&amp;dir=prev",
                'caption' => "Previous Entry",
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_prev.gif", 22, 20),
            };
        }
        if ($key eq "nav_next") {
            return {
                '_type' => "Link",
                'url' => "$LJ::SITEROOT/go.bml?journal=$journal&amp;itemid=$this->{'itemid'}&amp;dir=next",
                'caption' => "Next Entry",
                'icon' => LJ::S2::Image("$LJ::IMGPREFIX/btn_next.gif", 22, 20),
            };
        }
    }
}
    
sub Entry__plain_subject
{
    my ($ctx, $this) = @_;
    return $this->{'_subject_plain'} if defined $this->{'_subject_plain'};
    $this->{'_subject_plain'} = $this->{'subject'};
    LJ::CleanHTML::clean_subject_all(\$this->{'_subject_plain'});
    return $this->{'_subject_plain'};
}

sub EntryPage__print_multiform_actionline
{
    my ($ctx, $this) = @_;
    return unless $this->{'multiform_on'};
    my $pr = $ctx->[S2::PROPS];
    $S2::pout->($pr->{'text_multiform_des'} . "\n" .
                LJ::html_select({'name' => 'mode' },
                                "" => "",
                                map { $_ => $pr->{"text_multiform_opt_$_"} }
                                qw(unscreen screen delete)) . "\n" .
                LJ::html_submit('', $pr->{'text_multiform_btn'},
                                { "onclick" => "return (document.multiform.mode.value != \"delete\") " .
                                      "|| confirm(\"" . LJ::ejs($pr->{'text_multiform_conf_delete'}) . "\");" }));
}

sub EntryPage__print_multiform_end
{
    my ($ctx, $this) = @_;
    return unless $this->{'multiform_on'};
    $S2::pout->("</form>");
}

sub EntryPage__print_multiform_start
{
    my ($ctx, $this) = @_;
    return unless $this->{'multiform_on'};
    $S2::pout->("<form style='display: inline' method='post' action='$LJ::SITEROOT/talkmulti.bml' name='multiform'>\n" .
                LJ::html_hidden("ditemid", $this->{'entry'}->{'itemid'},
                                "journal", $this->{'entry'}->{'journal'}->{'username'}) . "\n");
}

sub Page__get_latest_month
{
    my ($ctx, $this) = @_;
    return $this->{'_latest_month'} if defined $this->{'_latest_month'};
    my $counts = LJ::S2::get_journal_day_counts($this);
    my ($year, $month);
    my @years = sort { $a <=> $b } keys %$counts;
    if (@years) {
        # year/month of last post
        $year = $years[-1];
        $month = (sort { $a <=> $b } keys %{$counts->{$year}})[-1];
    } else {
        # year/month of current date, if no posts
        my @now = gmtime(time);
        ($year, $month) = ($now[5]+1900, $now[4]+1);
    }
    return $this->{'_latest_month'} = LJ::S2::YearMonth($this, {
        'year' => $year,
        'month' => $month,
    });
}
*RecentPage__get_latest_month = \&Page__get_latest_month;
*DayPage__get_latest_month = \&Page__get_latest_month;
*MonthPage__get_latest_month = \&Page__get_latest_month;
*YearPage__get_latest_month = \&Page__get_latest_month;
*FriendsPage__get_latest_month = \&Page__get_latest_month;
*EntryPage__get_latest_month = \&Page__get_latest_month;
*ReplyPage__get_latest_month = \&Page__get_latest_month;

sub palimg_modify
{
    my ($ctx, $filename, $items) = @_;
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::SITEROOT/palimg/$filename";
    return $url unless $items && @$items;
    return undef if @$items > 7;
    $url .= "/p";
    foreach my $pi (@$items) {
        die "Can't modify a palette index greater than 15 with palimg_modify\n" if
            $pi->{'index'} > 15;
        $url .= sprintf("%1x%02x%02x%02x", 
                        $pi->{'index'},
                        $pi->{'color'}->{'r'},
                        $pi->{'color'}->{'g'},
                        $pi->{'color'}->{'b'});
    }
    return $url;
}

sub palimg_tint
{
    my ($ctx, $filename, $bcol, $dcol) = @_;  # bright color, dark color [opt]
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::SITEROOT/palimg/$filename";
    $url .= "/pt";
    foreach my $col ($bcol, $dcol) {
        next unless $col;
        $url .= sprintf("%02x%02x%02x", 
                        $col->{'r'}, $col->{'g'}, $col->{'b'});
    }
    return $url;
}

sub palimg_gradient
{
    my ($ctx, $filename, $start, $end) = @_;
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::SITEROOT/palimg/$filename";
    $url .= "/pg";
    foreach my $pi ($start, $end) {
        next unless $pi;
        $url .= sprintf("%02x%02x%02x%02x", 
                        $pi->{'index'},
                        $pi->{'color'}->{'r'},
                        $pi->{'color'}->{'g'},
                        $pi->{'color'}->{'b'});
    }
    return $url;
}

sub PalItem
{
    my ($ctx, $idx, $color) = @_;
    return undef unless $color && $color->{'_type'} eq "Color";
    return undef unless $idx >= 0 && $idx <= 255;
    return {
        '_type' => 'PalItem',
        'color' => $color,
        'index' => $idx+0,
    };
}

sub YearMonth__month_format
{
    my ($ctx, $this, $fmt) = @_;
    $fmt ||= "long";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_monthfmt'}->{$fmt};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_timefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_month_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_month_$fmt"};
    }
    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join('',";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { $code .= $dt_vars{$_} . ","; }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}

sub Image__set_url {
    my ($ctx, $img, $newurl) = @_;
    $img->{'url'} = LJ::eurl($newurl);
}

sub ItemRange__url_of
{
    my ($ctx, $this, $n) = @_;
    return "" unless ref $this->{'_url_of'} eq "CODE";
    return $this->{'_url_of'}->($n+0);
}


sub string__substr
{
    my ($ctx, $this, $start, $length) = @_;
    use utf8;
    return substr($this, $start, $length);
}

sub string__length
{
    use utf8;
    my ($ctx, $this) = @_;
    return length($this);
}

sub string__lower
{
    use utf8;
    my ($ctx, $this) = @_;
    return lc($this);
}

sub string__upper
{
    use utf8;
    my ($ctx, $this) = @_;
    return uc($this);
}

sub string__upperfirst
{
    use utf8;
    my ($ctx, $this) = @_;
    return ucfirst($this);
}

sub string__starts_with
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /^\Q$str\E/;
}

sub string__ends_with
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /\Q$str\E$/;
}

sub string__contains
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /\Q$str\E/;
}

sub string__repeat
{
    use utf8;
    my ($ctx, $this, $num) = @_;
    $num += 0;
    my $size = length($this) * $num;
    return "[too large]" if $size > 5000;
    return $this x $num;
}

1;
