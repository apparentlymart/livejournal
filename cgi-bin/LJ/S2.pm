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

use LJ::S2::RecentPage;
use LJ::S2::ArchiveYearPage;
use LJ::S2::DayPage;
use LJ::S2::FriendsPage;

package LJ::S2;

sub make_journal
{
    my ($u, $styleid, $view, $remote, $opts) = @_;

    my $r = $opts->{'r'};
    my $ret;
    $LJ::S2::ret_ref = \$ret;

    my ($entry, $page);

    my $run_opts = {
        'content_type' => 'text/html',
    };

    if ($view eq "res") {
        if ($opts->{'pathextra'} =~ m!/(\d+)/stylesheet$!) {
            $styleid = $1;
            $entry = "print_stylesheet()";
            $run_opts->{'content_type'} = 'text/css';
        } else {
            $opts->{'handler_return'} = 404;
            return;
        }
    }

    $u->{'_s2styleid'} = $styleid + 0;
    my $ctx = s2_context($r, $styleid);
    unless ($ctx) {
        $opts->{'handler_return'} = Apache::Constants::OK();
        return;
    }
    
    escape_context_props($ctx);
    
    $opts->{'ctx'} = $ctx;

    $ctx->[S2::PROPS]->{'SITEROOT'} = $LJ::SITEROOT;
    $ctx->[S2::PROPS]->{'SITENAME'} = $LJ::SITENAME;
    $ctx->[S2::PROPS]->{'IMGDIR'} = $LJ::IMGPREFIX;
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    $u->{'_journalbase'} = LJ::journal_base($u->{'user'}, $opts->{'vhost'});

    if ($view eq "lastn") {
        $entry = "RecentPage::print()";
        $page = RecentPage($u, $remote, $opts);
    } elsif ($view eq "calendar") {
        $entry = "ArchiveYearPage::print()";
        $page = ArchiveYearPage($u, $remote, $opts);
    } elsif ($view eq "day") {
        $entry = "DayPage::print()";
        $page = DayPage($u, $remote, $opts);
    } elsif ($view eq "friends" || $view eq "friendsfriends") {
        $entry = "FriendsPage::print()";
        $page = FriendsPage($u, $remote, $opts);
    }

    s2_run($r, $ctx, $run_opts, $entry, $page);
    
    if (ref $opts->{'errors'} eq "ARRAY" && @{$opts->{'errors'}}) {
        return join('', 
                    "Errors occured processing this page:<ul>" .
                    map { "<li>$_</li>" } @{$opts->{'errors'}},
                    "</ul>");
    }
    
    return $ret;
}

sub s2_run
{
    my ($r, $ctx, $opts, $entry, $page) = @_;

    my $ctype = $opts->{'content_type'} || "text/html";
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
    
    if ($entry eq "prop_init()") {
        S2::set_output(sub {});
        S2::set_output_safe(sub {});
    } else {
        my $out_straight = sub { $$LJ::S2::ret_ref .= $_[0]; };
        my $out_clean = sub { $cleaner->parse($_[0]); };
        S2::set_output($out_straight);
        S2::set_output_safe($out_straight);
        S2::set_output_safe($out_clean) if $cleaner;
    }
          
    $LJ::S2::CURR_PAGE = $page;
    $LJ::S2::RES_MADE = 0;  # standard resources (Image objects) made yet

    eval {
        S2::run_code($ctx, $entry, $page);
    };
    if ($@) { 
        my $error = $@;
        $error =~ s/\n/<br>\n/g;
        S2::pout("<b>Error running style:</b> $error");
        return 0;
    }
    S2::pout(undef);  # send the HTTP header, if it hasn't been already
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
    
    my %existing;  # uniq -> id
    my $sth = $dbr->prepare("SELECT i.infokey, i.value, l.s2lid, l.b2lid, l.type ".
                            "FROM s2layers l, s2info i ".
                            "WHERE l.userid=$sysid AND l.s2lid=i.s2lid AND ".
                            "i.infokey IN ('redist_uniq', 'name', 'langcode', '_previews')");
    $sth->execute;
    die $dbr->errstr if $dbr->err;
    while (my ($key, $val, $id, $bid, $type) = $sth->fetchrow_array) {
        $existing{$id}->{'b2lid'} = $bid;
        $existing{$id}->{'s2lid'} = $id;
        $existing{$id}->{'type'} = $type;
        $key = "uniq" if $key eq "redist_uniq";
        $existing{$id}->{$key} = $val;
    }

    foreach (keys %existing) {
        # setup uniq alias.
        $existing{$existing{$_}->{'uniq'}} = $existing{$_};

        # setup children keys
        next unless $existing{$_}->{'b2lid'};
        my $bid = $existing{$_}->{'b2lid'};
        unless ($existing{$bid}) {
            delete $existing{$existing{$_}->{'uniq'}};
            delete $existing{$_};
            next;
        }
        push @{$existing{$bid}->{'children'}}, $_;
    }

    return \%existing if $LJ::LESS_CACHING;
    $LJ::CACHED_PUBLIC_LAYERS = \%existing if %existing;
    return $LJ::CACHED_PUBLIC_LAYERS;
}

sub get_style
{
    my $styleid = shift;

    my %style;
    my $have_style = 0;

    if ($styleid) {
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT type, s2lid FROM s2stylelayers ".
                                "WHERE styleid=?");
        $sth->execute($styleid);
        while (my ($t, $id) = $sth->fetchrow_array) { $style{$t} = $id; }
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
        my $ourtime = LJ::date_unix_to_http($opts->{'modtime'});
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

    $dbh->do("INSERT INTO s2styles (userid, name) VALUES (?,?)", undef,
             $u->{'userid'}, $name);
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
        my $sth = $db->prepare("SELECT styleid, name FROM s2styles WHERE userid=?");
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

    $dbh->do("INSERT INTO s2styles (userid, name) VALUES (?,?)", undef,
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
    my $style = $db->selectrow_hashref("SELECT styleid, userid, name ".
                                       "FROM s2styles WHERE styleid=?",
                                       undef, $id);
    return undef unless $style;

    $style->{'layer'} = {};
    my $sth = $db->prepare("SELECT type, s2lid FROM s2stylelayers ".
                           "WHERE styleid=?");
    $sth->execute($id);
    while (my ($type, $s2lid) = $sth->fetchrow_array) {
        $style->{'layer'}->{$type} = $s2lid;
    }
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
    my $ctx = shift;
    while (my ($k, $v) = each %{$ctx->[S2::PROPS]}) {
        $v =~ s/</&lt;/g;
        $v =~ s/>/&gt;/g;
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
        $layer = LJ::load_layer($dbh, $lid) or return 0;
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

    my $untrusted = $layer->{'userid'} != LJ::get_userid($dbh, "system");

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
    my $parlay = LJ::load_layer($dbh, $parid);
    return undef unless LJ::layer_compile($parlay);
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
            push @sel, 0, '';  # divider between system & user
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
    return 1 if LJ::get_cap($u, "s2everything");
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
    return 1 if LJ::get_cap($u, "s2everything");
    my $pol = get_policy();
    my $can = 0;
    foreach my $lay ('*', $uniq) {
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
    $dt->{'_dayofweek'} = $parts[6];
    return $dt;
}

sub Entry
{
    my ($u, $arg) = @_;
    my $e = {
        '_type' => 'Entry',
        'links' => {}, # TODO: finish
        'metadata' => {},
    };
    foreach (qw(subject text journal poster new_day end_day comments 
                userpic permalink_url itemid)) {
        $e->{$_} = $arg->{$_};
    }

    $e->{'time'} = DateTime_parts($arg->{'dateparts'});
    
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
        $e->{'metadata'}->{'music'} = LJ::ehtml($p->{'current_music'});
    }
    if (my $mid = $p->{'current_moodid'}) {
        my $theme = $u->{'moodthemeid'};
        LJ::load_mood_theme(undef, $theme);
        my %pic;
        $e->{'mood_icon'} = Image($pic{'pic'}, $pic{'w'}, $pic{'h'})
            if LJ::get_mood_picture($theme, $mid, \%pic);
        $e->{'metadata'}->{'mood'} = $LJ::CACHE_MOODS{$mid}->{'name'};
    }
    if ($p->{'current_mood'}) {
        $e->{'metadata'}->{'mood'} = LJ::ehtml($p->{'current_mood'});
    }

    return $e;
}

sub Friend
{
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'} = "Friend";
    $o->{'bgcolor'} = S2::Builtin::Color__Color($u->{'bgcolor'});
    $o->{'fgcolor'} = S2::Builtin::Color__Color($u->{'fgcolor'});
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
    my ($u) = @_;
    my $styleid = $u->{'_s2styleid'} + 0;
    my $base_url = $u->{'_journalbase'};
    my $p = {
        '_type' => 'Page',
        'view' => '',
        'journal' => User($u),
        'journal_type' => $u->{'journaltype'},
        'base_url' => $base_url,
        'stylesheet_url' => "$base_url/res/$styleid/stylesheet",
        'view_url' => {
            'recent' => "$base_url/",
            'userinfo' => "$LJ::SITEROOT/userinfo.bml?user=$u->{'user'}",
            'archive' => "$base_url/calendar",
            'friends' => "$base_url/friends",
        },
        'views_order' => [ 'recent', 'archive', 'friends', 'userinfo' ],
        'global_title' => '',
        'head_content' => '',
    };
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
    unless ($u->{'_userpics'}) {
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT picid, width, height FROM userpic ".
                                "WHERE userid=?");
        $sth->execute($u->{'userid'});
        while (my ($id, $w, $h) = $sth->fetchrow_array) {
            $u->{'_userpics'}->{$id} = [ $w, $h ];
        }
        $sth = $dbr->prepare("SELECT m.picid, k.keyword FROM userpicmap m, keywords k ".
                             "WHERE m.userid=? AND m.kwid=k.kwid");
        $sth->execute($u->{'userid'});
        while (my ($id, $kw) = $sth->fetchrow_array) {
            $u->{'_userpics'}->{'kw'}->{$kw} = $id;
        }
    }

    unless ($picid) {
        $picid = $kw ? $u->{'_userpics'}->{'kw'}->{$kw} : $u->{'defaultpicid'};
    }

    return Null("Image") unless defined $u->{'_userpics'}->{$picid};
    my $p = $u->{'_userpics'}->{$picid};
    return {
        '_type' => "Image",
        'url' => "$LJ::USERPIC_ROOT/$picid/$u->{'userid'}",
        'width' => $p->[0],
        'height' => $p->[1],
    };
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

sub UserLite
{
    my ($u) = @_;
    my $o = {
        '_type' => 'UserLite',
        'username' => $u->{'user'},
        'name' => $u->{'name'},
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
    $text =~ s/\#/$n/;
    return LJ::ehtml($text);
}

sub get_url
{
    my ($ctx, $obj, $view) = @_;
    my $user = ref $obj ? $obj->{'username'} : $obj;
    $view = "info" if $view eq "userinfo";
    $view = "" if $view eq "recent";
    return "$LJ::SITEROOT/$user/$view";
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

sub Date__day_of_week
{
    my ($ctx, $dt) = @_;
    return $dt->{'_dayofweek'} if defined $dt->{'_dayofweek'};
    return $dt->{'_dayofweek'} = LJ::day_of_week($dt->{'year'}, $dt->{'month'}, $dt->{'day'});
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
               'mm' => "sprintf('%02d', \$time->{min})",
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
    my $code = "\$\$c = sub { my \$time = shift; return join(";
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
    my $code = "\$\$c = sub { my \$time = shift; return join(";
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

sub ArchiveYearMonth__month_format
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
    my $code = "\$\$c = sub { my \$time = shift; return join(";
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


1;
