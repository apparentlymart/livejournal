#!/usr/bin/perl
#
# BML - Better/Block Markup Language
#       
#

use Compress::Zlib;
use Digest::MD5;
use Getopt::Long;

my $VERSION="1.2.1";

my $opt_code = 0;
exit 1 unless GetOptions('code' => \$opt_code);

# bmlp.pl --code <filename> 
#    prints _CODE sections of given filename as valid
#    perl which can be validated through perl -c
if ($opt_code) {
    if (scalar(@ARGV) != 1) {
        print STDERR "bmlp.pl takes exactly one filename argument after --code.\n";
        exit 1;
    }
    open IN, $ARGV[0] or die "couldn't open $ARGV[0]\n";
    my $bmlsource = "";
    while (<IN>) { $bmlsource .= $_; }
    close IN;
    print "package BMLCodeBlock;\n\n";
    
    # if we were to use bml_decode, we'd have to load definition files,
    # parse all block options, etc. etc. For practical purposes a simple
    # regexp sweep is sufficient. Note that we're using the fact that
    # _CODE blocks can't be nested.
    
    while ($bmlsource =~ m/\(=_CODE(.*?)_CODE=\)/gs) {
        print "sub {\n$1};\n\n";
    }
    exit 0;
}

sub webdie { print "Content-type: text/html\n\n$_[0];\n"; exit; }

#############################################################################
#####                    [ APACHE HOOK SECTION ]                        #####
#############################################################################

require 'bml_client.pl';

srand;

my $SERVE_MAX = 50;
my $SERVE_COUNT = 0;
my $HUP_COUNT = 0;
my $SERVING = 0;
my (%FileModTime, %Config, %FileBlockData, %FileBlockFlags);
my ($time_a, $time_b);

&reset_caches;
$SIG{'HUP'} = sub {
    $HUP_COUNT++;
    reset_caches();
};
$SIG{'TERM'} = sub {
    if ($SERVING) {
	$SERVE_MAX = 0; 
    } else {
	exit 0;
    }
};

sub reset_caches
{
    %FileModTime = ();
    %Config = ();
    %FileBlockData = ();  # $FileBlockData{$file}->{$block} = $def;
    %FileBlockFlags = ();  # $FileBlockFlags{$file}->{$block} = $def;
}

use FCGI;
my $fcgi_req = FCGI::Request();
while(($time_a = time()) && $fcgi_req->Accept() >= 0) 
{
    $SERVING = 1;
    $time_b = time();
    
    my %SAVE_INC = %INC;
    &handle_request;
    %INC = %SAVE_INC;
    &reset_codeblock;	

    $SERVING = 0;
    if (++$SERVE_COUNT >= $SERVE_MAX) { exit 0; }
}

sub reset_codeblock
{
    local $^W = 0;
    my $package = "main::BMLCodeBlock::";
    *stab = *{"main::"};
    while ($package =~ /(\w+?::)/g)
    {
        *stab = ${stab}{$1};
    }
    while (my ($key,$val) = each(%stab)) 
    {
        return if $DB::signal;
        deleteglob ($key, $val);
    }
}

sub deleteglob 
{
    return if $DB::signal;
    my ($key, $val, $all) = @_;
    local(*entry) = $val;
    my $fileno;
    if ($key !~ /^_</ and defined $entry) 
    {
        undef $entry;
    }
    if ($key !~ /^_</ and defined @entry) 
    {
        undef @entry;
    }
    if ($key ne "main::" && $key ne "DB::" && defined %entry
        && $key !~ /::$/
        && $key !~ /^_</ && !($package eq "dumpvar" and $key eq "stab")) 
    {
        undef %entry;
    }
    if (defined ($fileno = fileno(*entry))) {
        # do nothing to filehandles?
    }
    if ($all) {
        if (defined &entry) {
                # do nothing to subs?
        }
    }
}


sub handle_request
{
    $FILE = $ENV{'PATH_TRANSLATED'};
    $most_recent_mod = "";
    %BMLCodeBlock::FORM = ();
    $BMLCodeBlock::FCGI = $fcgi_req;
    %blockdata = ();
    %blockflags = ();
    $CONTENT_TYPE = "text/html";
    %BMLml::ml_used = ();
    $FORM_READ = 0;
    $REQ_LANG = "";
    %GETVARS = ();
    $BML_STOP_FLAG = 0;
    %BMLClient::COOKIE = ();
    &BMLClient::reset();
    @BlockStack = ("");
    %IncludeOpen = ();
    @IncludeStack = ();

    unless (&load_cfg()) {
	print "Content-type: text/html\n\n";
	print "<H1>BML</H1>\n";
	print "<B>Error:</b>: Could not open configuration file.";
	return;
    }
    
    if (-d $FILE) {
	print "Content-type: text/html\n\n";
	print "<H1>Error</H1>\n";
	print "Request file is a directory.";
	return;
    }

    if ($ENV{'REQUEST_URI'} eq "/cgi-bin/bmlp.pl") {
	print "Content-type: text/html\n\n";
	print "<H1>BML</H1>\n";
	print "<H3>Version: $VERSION</H3>\n";
	print "<p>Served: ($SERVE_COUNT/$SERVE_MAX)";
	print "<br>Hupped: ($HUP_COUNT)";
	return
    }

    if ($ENV{'REQUEST_URI'} =~ /cgi-bin/) {
	print "Content-type: text/html\n\n";
	print "<H1>Error</H1>\n";
	print "Cannot serve requests directed at the cgi-bin.";
	return;
    }

    unless ($FILE =~ /\.s?bml$/) {
	print "Content-type: text/html\n\n";
	print "<H1>Error</H1>\n";
	print "Cannot serve non-BML requests.";
	return;
    }

    if ($ENV{'PATH_INFO'} && ! -e $FILE) 
    {
	my $req_path = $ENV{'REQUEST_URI'};
	my $req_args;
	if ($req_path =~ s/\?.*$//) {
	    $req_args = $&;
	}
	$req_path =~ s!/$!!;

	my $errors;
	my $redir = $BMLEnv{'RedirectData'};
	if (! $redir) { $errors .= "<p>No RedirectData file defined = " . join(",", %BMLEnv); }
	elsif (! -e $redir) { $errors .= "<p>RedirectData file not found"; }
	elsif (! -r $redir) { $errors .= "<p>RedirectData cannot be read"; }
	else {
	    open (REDIR, $redir);
	    while (<REDIR>) {
		next unless (/^(\S+)\s+(\S+)/);
		my ($src, $dest) = ($1, $2);
		if ($src eq $req_path) {
		    my $new = $dest . $req_args;
		    print "Status: 301 Moved Permanently\n";
		    print "Location: $new\n";
		    print "Content-type: text/html\n\n";
		    print "This page is now available <A HREF=\"$new\">here</A>.";
		    close REDIR;

		    if ($BMLEnv{'404Log'}) {
			open (FLOG, ">>$BMLEnv{'404Log'}");
			print FLOG join("\t", "redirected", $req_path, $ENV{'HTTP_REFERER'}), "\n";
			close FLOG;
		    }
		    return;
		}
	    }
	    close REDIR;
	}
	print "Content-type: text/html\n\n<H1>Not Found</h1>";
	print "The BML page requested does not exist.<BR><B><TT>reqpath = ($req_path $req_args)</TT></B>$errors";
	if ($BMLEnv{'404Log'}) {
	    open (FLOG, ">>$BMLEnv{'404Log'}");
	    print FLOG join("\t", "missing", $req_path, $ENV{'HTTP_REFERER'}), "\n";
	    close FLOG;
	}
	return;	
    }


    my $starttime = time();

    if ($BMLEnv{'PreLogFile'}) {
	open (LOG, ">>$BMLEnv{'PreLogFile'}");
	print LOG "$$\t$ENV{'REQUEST_URI'}\n";
	close LOG;
    }

    if ($FILE)
    {
	my $query_string = &get_query_string();
	&split_vars(\$query_string, \%GETVARS);

	if (defined $GETVARS{'setscheme'}) {
	    &BMLClient::set_cookie('BMLschemepref', $GETVARS{'setscheme'}, 0, $BMLEnv{'ClientTopPath'});
	    $BMLClient::COOKIE{'BMLschemepref'} = $GETVARS{'setscheme'};
	}

	my $ideal_scheme = "";
	if ($ENV{'HTTP_USER_AGENT'} =~ /^Lynx\//) {
	    $ideal_scheme = "lynx";
	}

	$BMLSCHEME = $BMLEnv{'ForceScheme'} || 
	    $BMLClient::COOKIE{'BMLschemepref'} || 
		$GETVARS{'usescheme'} || 
		    $ideal_scheme ||
			$BMLEnv{'DefaultScheme'};

	if ($BMLEnv{'VarInitScript'}) {
	    my $err;
	    foreach my $is (split(/\s*,\s*/, $BMLEnv{'VarInitScript'})) {
		last unless &load_look_from_initscript($is, \$err);
	    }
	    if ($err) {
		print "Content-type: text/html\n\n";
		print "<b>Error loading VarInitScript:</b><br />\n$err";
		return 0;
	    }
	}

	if ($HOOK{'startup'}) {
	    eval {
		$HOOK{'startup'}->();
	    };
	    if ($@) {
		print "Content-type: text/html\n\n";
                print "<b>Error running startup hook:</b><br />\n$@";
                return 0;
	    }
	}

	&load_look("", "global");
	&load_look($BMLSCHEME, "generic");

	&note_file_mod_time($FILE);

	## begin the multi-lang stuff
	if ($GETVARS{'setlang'})
	{
	    &BMLClient::set_var("langpref", $GETVARS{'setlang'});
	    &BMLClient::set_var("langsettime", time());
	}
	$REQ_LANG = lc($GETVARS{'setlang'} || $GETVARS{'uselang'} || &BMLClient::get_var("langpref"));
	
	# make sure the document says it was changed at least as new as when
	# the user last set their current language, else their browser might
	# show a cached (wrong language) version.
	&note_mod_time(&BMLClient::get_var("langsettime"));

	unless ($REQ_LANG)
	{
	    my %lang_weight = ();
	    my @langs = split(/\s*,\s*/, lc($ENV{'HTTP_ACCEPT_LANGUAGE'}));
	    my $winner_weight = 0.0;
	    foreach (@langs)
	    {
		# do something smarter in future.  for now, ditch country code:
		s/-\w+//;
		
		if (/(.+);q=(.+)/)
		{
		    $lang_weight{$1} = $2;
		}
		else
		{
		    $lang_weight{$_} = 1.0;
		}
		if ($lang_weight{$_} > $winner_weight && 
		    -e "$BMLEnv{'MultiLangRoot'}/$BMLEnv{'LanguageProject'}/lang.$_")
		{
		    $winner_weight = $lang_weight{$_};
		    $REQ_LANG = $_;
		}
	    }
	}
	$REQ_LANG ||= lc($BMLEnv{'DefaultLanguage'}) || "en";

	### read the data to mangle
	my $bmlsource = "";
	open (IN, $FILE);
	while (<IN>) { $bmlsource .= $_; }
	close IN;

	# print on the HTTP header
	my $html;
        &bml_decode(\$bmlsource, \$html, { DO_CODE => $BMLEnv{'AllowCode'} });
	
	# insert all client (per-user, cookie-set) variables
	$html =~ s/%%c\!(\w+)%%/&BMLUtil::ehtml(&BMLClient::get_var($1))/eg;

	# insert all multilang phrases (_ML tags) from the $REQ_LANG
	if (scalar(keys(%BMLml::ml_used)))
	{
	    my $lang_file = "$BMLEnv{'MultiLangRoot'}/$BMLEnv{'LanguageProject'}/lang.$REQ_LANG";
	    if (-e $lang_file)
	    {
		%langprop = ();
		&note_file_mod_time($lang_file);
		open (LANG, $lang_file);
		while (($_ = <LANG>) ne "\n")
		{
		    chomp;
		    my ($key, $value) = ($_ =~ /(.+?)\s*:\s*(.+)/);
		    $langprop{$key} = $value if ($key ne "" && $value ne "");
		}
		
		# read the translate data!
		while (<LANG>)
		{
		    chomp;
		    next unless (/^(?:\*|$BMLEnv{'LanguageSection'})\t(.+?)\t/);
		    next unless defined $BMLml::ml_used{$1};

		    my ($section, $code, $data) = split(/\t/, $_);
		    next unless $BMLml::ml_used{$code};

		    $html =~ s/%%ml\!$code(\?(.+?))?%%/$2 ? &BMLml::interpolate_phrase($data, $2) : $data/eg;
		    undef $BMLml::ml_used{$1};
		}
		close (LANG);
	    }
	    else
	    {
		$html = "<B>Error: </B> Language code <I>$REQ_LANG</I> not defined for this project.";
	    }

	    if (defined $langprop{'Content-type'}) {
		&BML::set_content_type($langprop{'Content-type'});
	    }
	    
	    # replace anything untranslated with an error of sorts
	    $html =~ s!%%ml\!(.+?)%%!<B>[untranslated phrase: </B><I>$1</I><B>]</B>!g;
	    $html .= "\n<!-- $REQ_LANG -->\n";

	    my $rootlang = substr($REQ_LANG, 0, 2);
	    unless ($BMLEnv{'NoHeaders'}) {
		print "Content-Language: $rootlang\n";
	    }
	}

	# TODO: temporary
	#my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
	#$date = sprintf("%04d-%02d-%02d", $year+1900, $mon+1, $mday);
	#open (TLOG, ">>log-$date.txt");
	#print TLOG ($ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'});
	#print TLOG "\t$REQ_LANG\t$ENV{'REQUEST_URI'}\t$date ";
	#print TLOG sprintf("%02d:%02d:%02d\n", $hour, $min, $sec);
	#close TLOG;

	my $modtime = &modified_time;
	my $notmod = 0;

	unless ($BMLEnv{'NoHeaders'}) 
	{
	    if ($ENV{'HTTP_IF_MODIFIED_SINCE'} &&
		! $BMLEnv{'NoCache'} &&
		$ENV{'HTTP_IF_MODIFIED_SINCE'} eq $modtime) 
	    {
		print "Status: 304 Not Modified\n";
		$notmod = 1;
	    }

	    print "Content-type: $CONTENT_TYPE\n";
	    if ($BMLEnv{'NoCache'})
	    {
		#print "Expires: now\n";
		print "Cache-Control: no-cache\n";
	    }
	    if ($BMLEnv{'Static'})
	    {
		print "Last-Modified: $modtime\n";
	    }
	    print "Cache-Control: private, proxy-revalidate\n";
	    print "ETag: ", Digest::MD5::md5_hex($html), "\n";
	    
	}

	unless ($BMLEnv{'NoContent'}) 
	{
	    my $head = ($ENV{'REQUEST_METHOD'} eq "HEAD");
	    if ((! $BMLEnv{'NoHeaders'}) && !$head && 0 && $ENV{'HTTP_ACCEPT_ENCODING'} =~ /gzip/)
	    {
		binmode STDOUT;
		print "Content-Encoding: gzip\n";
		print "\n";
		my $gz = gzopen(\*STDOUT, "wb");
		$gz->gzwrite($html);
		$gz->gzclose;
	    }
	    else
	    {
		unless ($BMLEnv{'NoHeaders'}) {
		    print "Content-length: ", length($html), "\n";
		    print "\n";
		}
		if (! $head) {
		    print $html;
		}
	    }
	}
	
	&BMLClient::save();

	my $duration = time() - $starttime;
	my $fastcgi_wait = $time_b - $time_a;

	if ($BMLEnv{'LogFile'}) {
	    open (LOG, ">>$BMLEnv{'LogFile'}");
	    print LOG "$$\t($fastcgi_wait, $duration)\t$ENV{'REQUEST_URI'}\n";
	    close LOG;
	}
    }
}

#############################################################################
#####                       [ BML FUNCTIONS ]                           #####
#############################################################################

sub eval_code
{
    my $ret = (eval("{\n package BMLCodeBlock; \n $_[0]\n }\n"))[0];
    if ($@) { return "<B>[Error: $@]</B>"; }
    
    my $newhtml;
    &bml_decode(\$ret, \$newhtml, {});  # no opts on purpose: _CODE can't return _CODE
    return $newhtml;
}

# $type - "THINGER" in the case of (=THINGER Whatever THINGER=)
# $data - "Whatever" in the case of (=THINGER Whatever THINGER=)
# $option_ref - hash ref to %BMLEnv
sub bml_block
{
    my ($type, $data, $option_ref) = @_;
    my $realtype = $type;
    my $previous_block = $BlockStack[-1];

    if (defined $blockdata{"$type/FOLLOW_${previous_block}"}) {
	$realtype = "$type/FOLLOW_${previous_block}";
    }
    
    my $blockflags = $blockflags{$realtype};

    # trim off space from both sides of text data
    $data =~ s/^\s+//;
    $data =~ s/\s+$//;
    
    # executable perl code blocks
    if ($type eq "_CODE")
    {
	if ($option_ref->{'DO_CODE'})
	{
	    &get_form_data unless ($FORM_READ);
	    return &eval_code($data);
	} 
	else
	{
	    return &inline_error("_CODE block failed to execute by permission settings");
	}
    }

    # load in the properties defined in the data
    my %element = ();
    my @elements = ();
    if ($blockflags =~ /F/ || $type eq "_INFO" || $type eq "_INCLUDE")
    {
	&load_elements(\%element, $data, { 'declorder' => \@elements });
    } 
    elsif ($blockflags =~ /P/)
    {
	my @itm = split(/\s*\|\s*/, $data);
	my $ct = 0;
	foreach (@itm) {
	    $ct++;
	    $element{"DATA$ct"} = $_;
	    push @elements, "DATA$ct";
	}
    }
    else
    {
	# single argument block (goes into DATA element)
	$element{'DATA'} = $data;
	push @elements, 'DATA';
    }
    
    # multi-linguality stuff
    if ($type eq "_ML")
    {
	my $pc = $data;
	if ($pc =~ /^(.+?)\?/)
	{
	    $pc = $1;
	}
	# make a note of the phrase requested to translate, to load later
	$BMLml::ml_used{$pc} = 1;
	
	# and put in a marker in page to replace later
	return "%%ml!$data%%";
    }
	
    # an _INFO block contains special internal information, like which
    # look files to include
    if ($type eq "_INFO")
    {
	foreach (split(/\s*\,\s*/, &trim($element{'INCLUDE'})))
	{
	    &load_look($BMLSCHEME, $_);
	}
	if ($element{'NOCACHE'}) { $BMLEnv{'NoCache'} = 1; }
	if ($element{'STATIC'}) { $BMLEnv{'Static'} = 1; }
	if ($element{'NOHEADERS'}) { $BMLEnv{'NoHeaders'} = 1; }
	if ($element{'NOCONTENT'}) { $BMLEnv{'NoContent'} = 1; }
	if ($element{'NOFORMREAD'}) { $FORM_READ = 1; } # don't step on CGI.pm, if used
	if ($element{'LOCALBLOCKS'} && $BMLEnv{'AllowCode'}) {
	    my (%localblock, %localflags);
	    &load_elements(\%localblock, $element{'LOCALBLOCKS'});
	    # look for template types
	    foreach my $k (keys %localblock) {
		if ($localblock{$k} =~ s/^\{([A-Za-z]+)\}//) {
		    $localflags{$k} = $1;
		}
	    }
	    my @expandconstants;
	    foreach my $k (keys %localblock) {
		$blockdata{$k} = $localblock{$k};
		$blockflags{$k} = $localflags{$k};
		if ($localflags{$k} =~ /s/) { push @expandconstants, $k; }
	    }
	    foreach my $k (@expandconstants) {
		$blockdata{$k} =~ s/\(=([A-Z0-9\_]+?)=\)/$blockdata{$1}/g;
	    }
	}
	$BMLEnv{'LanguageSection'} = $element{'MLSECTION'};
	return "";
    }
    
    if ($type eq "_INCLUDE") 
    {
	my $code = 0;
	$code = 1 if ($element{'CODE'});
	foreach my $sec (qw(CODE BML)) {
	    next unless $element{$sec};
	    if (@IncludeStack && ! $IncludeStack[-1]->{$sec}) {
		return &inline_error("Sub-include can't turn on $sec if parent include's $sec was off");
	    }
	}
	unless ($element{'FILE'} =~ /^[a-zA-Z0-9-_\.]{1,255}$/) {
	    return &inline_error("Invalid characters in include file name: $element{'FILE'} (code=$code)");
	}

	if ($IncludeOpen{$element{'FILE'}}++) {
	    return &inline_error("Recursion detected in includes");
	}
	push @IncludeStack, \%element;
	my $isource = "";
	my $file = $BMLEnv{'IncludePath'} . "/" . $element{'FILE'};
	open (INCFILE, $file) || return &inline_error("Could not open include file.");
	while (<INCFILE>) { 
	    $isource .= $_;
	}
	close INCFILE;
	
	if ($element{'BML'}) {
	    my $newhtml;
	    &bml_decode(\$isource, \$newhtml, { DO_CODE => $code });
	    $isource = $newhtml;
	} 
	$IncludeOpen{$element{'FILE'}}--;
	pop @IncludeStack;
	return $isource;
    }
    
    if ($type eq "_COMMENT" || $type eq "_C") {
	return "";
    }

    if ($type eq "_EH") {
	return &BMLUtil::ehtml($element{'DATA'});
    }
    
    if ($type eq "_EB") {
	return &BMLUtil::ebml($element{'DATA'});
    }
    
    if ($type eq "_EU") {
	return &BMLUtil::eurl($element{'DATA'});
    }
    
    if ($type eq "_EA") {
	return &BMLUtil::escapeall($element{'DATA'});
    }
    
    if ($type =~ /^_/) {
	return &inline_error("Unknown core element '$type'");
    }
	
    $BlockStack[-1] = $type;
	
    # traditional BML Block decoding ... properties of data get inserted
    # into the look definition; then get BMLitized again
    if (defined $blockdata{$realtype}) {
	my $preparsed = ($blockflags =~ /p/);
	
	if ($preparsed) {
	    ## does block request pre-parsing of elements?
	    ## this is required for blocks with _CODE and AllowCode set to 0
	    foreach my $k (@elements) {
		my $decoded;
		&bml_decode(\$element{$k}, \$decoded, $option_ref);
		$element{$k} = $decoded;
	    }
	}

	my $expanded = &parsein($blockdata{$realtype}, \%element);

	if ($blockflags =~ /S/) {  # static (don't expand)
	    return $expanded;
	} else {
	    my $out;
	    push @BlockStack, "";
	    my $opts = { %{$option_ref} };
	    if ($preparsed) {
		$opts->{'DO_CODE'} = $BMLEnv{'AllowTemplateCode'};
	    }
	    &bml_decode(\$expanded, \$out, $opts);
	    pop @BlockStack;
	    return $out;
	}
	
    } else {
	return &inline_error("Undefined custom element '$type'");				
    }
}

sub generic_log
{
    my ($file, $line) = @_;
    open (F, ">>$file");
    print F $line, "\n";
    close F;
}

######## bml_decode
#
# turns BML source into expanded HTML source
#
#   $inref    scalar reference to BML source.  $$inref gets destroyed.
#   $outref   scalar reference to where output is appended.
#   $opts     security flags

sub bml_decode
{
    my ($inref, $outref, $opts) = @_;

    my $block = "";    # what (=BLOCK ... BLOCK=) are we in?
    my $data = "";          # what is (=BLOCK inside BLOCK=) the current block.
    my $depth = 0;     # how many blocks we are deep of the *SAME* type.

  EAT:
    while ($$inref && ! $BML_STOP_FLAG)
    {
	# currently not in a BML tag... looking for one!
	if ($block eq "") {
	    if ($$inref =~ s/^(.*?)\(=([A-Z0-9\_]+)\b//s) {
		$$outref .= $1;
		$block = $2;
		$depth = 1;
		next EAT;
	    }
	    
	    # no BML left? append it all and be done.
	    $$outref .= $$inref;
	    $$inref = "";
	    last EAT;
	}
	
	# now we're in a FOO tag: (=FOO
	# things to look out for:
	#   * Increasing depth:
	#      - some text, then another opening (=FOO, increading our depth
	#          (=FOO bla blah (=FOO
	#   * Decreasing depth: (if depth==0, then we're done)
	#      - immediately closing the tag, empty tag
	#          (=FOO=)
	#      - closing the tag (if depth == 0, then we're done)
	#          (=FOO blah blah FOO=)
	
	if ($$inref =~ s/^=\)//) {
	    $depth--;
	} elsif ($$inref =~ s/^(.+?)((?:\(=$block\b )|(?:\b$block=\)))//s) {
	    $data .= $1;
	    if ($2 eq "(=$block") {
		$data .= $2;
		$depth++;
	    } elsif ($2 eq "$block=)") {
		$depth--;
		if ($depth) { $data .= $2; }
	    }
	} else {
	    $$outref .= &inline_error("BML block '$block' has no close");
	    return;
	}

	# handle finished blocks
	if ($depth == 0) {

	    $$outref .= &bml_block($block, $data, $opts);    
	    $data = "";
	    $block = "";
	}
    }
}

sub showline
{
    my $a = $_[0];
    $a =~ s/\n/ /g;
    return $a;
}

sub split_vars
{
    my ($dataref, $hashref) = @_;
    
    # Split the name-value pairs
    my $pair;
    my @pairs = split(/&/, $$dataref);
    my ($name, $value);
    foreach $pair (@pairs)
    {
	($name, $value) = split(/=/, $pair);
	$value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
	$hashref->{$name} .= defined $hashref->{$name} ? "\0$value" : $value;
    }

}

sub get_query_string
{
    return &BML::get_query_string();
}

# load the FORM data into %%BMLCodeBlock::FORM
sub get_form_data 
{
    my $buffer;
    if ($ENV{'REQUEST_METHOD'} eq 'POST') {
	my $len = $ENV{'CONTENT_LENGTH'};
	if ($len > 5_000_000) { $len = 5_000_000; } # cap at 5 MB
	read(STDIN, $buffer, $len);
    } else {
	$buffer = &BML::get_query_string();
    }

    if ($ENV{'CONTENT_TYPE'} =~ m!^multipart/form-data; boundary=(.+)!)
    {
	# Mime encoding
	# FIXME: do this one day?  steal from CGI.pm?
    } 
    else 
    {
	# Normal URL-style encoding
	&split_vars(\$buffer, \%BMLCodeBlock::FORM);
    }
    
    $FORM_READ = 1;
}

# opens bmlp.cfg file and loads in options for current document
sub load_cfg
{
    my ($currentpath, $line, $var, $val);

    my $modtime;
    if ($BMLEnv{'CacheUntilHUP'} && $FileModTime{"bmlp.cfg"}) {
	$modtime = $FileModTime{"bmlp.cfg"};
    } else {
	$modtime = (stat("bmlp.cfg"))[9];
    }
    if ($modtime > $FileModTime{"bmlp.cfg"}) 
    {
	%Config = ();

	$FileModTime{"bmlp.cfg"} = $modtime;

	open (CFG, "bmlp.cfg") or return 0;
	while ($line = <CFG>)
	{
	    chomp $line;
	    next if ($line =~ /^\#/);
	    if (($var, $val) = ($line =~ /^(\w+):?\s*(.*)/))
	    {
		if ($var eq "Location")
		{
		    $currentpath = $val;
		}
		else
		{
		    # expand environment variables
		    $val =~ s/\$(\w+)/$ENV{$1}/g;

		    $Config{$currentpath}->{$var} = $val;
		}
	    }
	}
	close CFG;

	grep { $Config{$_}->{'_size'} = length($_);  } keys %Config;
    }

    %BMLEnv = ();
    my @dirs = sort { $Config{$a}->{'_size'} <=> $Config{$b}->{'_size'} } keys %Config;
    foreach my $dir (@dirs)
    {
	if ($ENV{'PATH_INFO'} =~ /^$dir/)
	{
	    foreach (keys %{$Config{$dir}})
	    {
		$BMLEnv{$_} = $Config{$dir}->{$_};
	    }
	}
    }

    return 1;    
}

# given a block of data, loads elements found into 
sub load_elements
{
    my ($hashref, $data, $opts) = @_;
    my $ol = $opts->{'declorder'};
    my @data = split(/\n/, $data);
    my $curitem = "";
    my $depth;
    
    foreach (@data)
    {
	$_ .= "\n";
	if ($curitem eq "" && /^([A-Z0-9\_\/]+)=>(.*)/)
	{
	    $hashref->{$1} = $2;
	    push @$ol, $1;
	}
	elsif (/^([A-Z0-9\_\/]+)<=\s*$/)
	{
	    if ($curitem eq "")
	    {
		$curitem = $1;
		$depth = 1;
		$hashref->{$curitem} = "";
		push @$ol, $curitem;
	    }
	    else
	    {
		if ($curitem eq $1)
		{
		    $depth++;
		}
		$hashref->{$curitem} .= $_;
	    }
	}
	elsif ($curitem && /^<=$curitem\s*$/)
	{
	    $depth--;
	    if ($depth == 0)
	    {
		$curitem = "";
	    } 
	    else
	    {
		$hashref->{$curitem} .= $_;
	    }
	}
	else
	{
	    $hashref->{$curitem} .= $_ if $curitem;
	}
    }
}

sub load_look_from_initscript
{
    my $file = shift;
    my $errref = shift;
    my $dummy;
    $errref ||= \$dummy;
    unless (-e $file) {
	$$errref = "Can't find VarInitScript: $file";
	return 0;
    }
    return 0 unless (-e $file);

    my $modtime;
    if ($BMLEnv{'CacheUntilHUP'} && $FileModTime{$file}) {
        $modtime = $FileModTime{$file};
    } else {
        $modtime = (stat($file))[9];
    }
    &note_mod_time($modtime);
    if ($modtime > $FileModTime{$file})
    {
	my $init;
	open (IS, $file);
	while (<IS>) {
	    $init .= $_;
	}
	close IS;

	$FileBlockData{$file} = {};
	$FileBlockFlags{$file} = {};
	&BML::register_block_setup({ 'data' => $FileBlockData{$file},
				     'flags' => $FileBlockFlags{$file}, });
	eval($init);
	if ($@) {
	    $$errref = $@;
	    return 0;
	}

	$FileModTime{$file} = $modtime;
    } 
    
    my @expandconstants;
    foreach my $k (keys %{$FileBlockData{$file}}) {
	$blockdata{$k} = $FileBlockData{$file}->{$k};
	$blockflags{$k} = $FileBlockFlags{$file}->{$k};
	if ($blockflags{$k} =~ /s/) { push @expandconstants, $k; }
    }
    foreach my $k (@expandconstants) {
	$blockdata{$k} =~ s/\(=([A-Z0-9\_]+?)=\)/$blockdata{$1}/g;
    }
    
    return 1;
}

# given the name of a look file, loads definitions into %look
sub load_look
{
    my ($scheme, $file) = @_;
    return 0 if $scheme =~ /[^a-zA-Z0-9_\-]/;
    return 0 if $file =~ /[^a-zA-Z0-9_\-]/;
    
    $file = $scheme ? $BMLEnv{'LookRoot'} . "/$scheme/$file.look" : $BMLEnv{'LookRoot'} . "/$file.look";
    return 0 unless (-e $file);
    
    my $modtime;
    if ($BMLEnv{'CacheUntilHUP'} && $FileModTime{$file}) {
	$modtime = $FileModTime{$file};
    } else {
	$modtime = (stat($file))[9];
    }
    &note_mod_time($modtime);
    if ($modtime > $FileModTime{$file}) 
    {
	my $look;
	open (LOOK, $file);
	while (<LOOK>) {
	    $look .= $_;
	}
	close LOOK;
	    
	$FileBlockData{$file} = {};
	&load_elements($FileBlockData{$file}, $look);  
	$FileModTime{$file} = $modtime;

	# look for template types
	foreach my $k (keys %{$FileBlockData{$file}}) {
	    if ($FileBlockData{$file}->{$k} =~ s/^\{([A-Za-z]+)\}//) {
		$FileBlockFlags{$file}->{$k} = $1;
	    }
	}
    } 
    
    my @expandconstants;
    foreach my $k (keys %{$FileBlockData{$file}}) {
	$blockdata{$k} = $FileBlockData{$file}->{$k};
	$blockflags{$k} = $FileBlockFlags{$file}->{$k};
	if ($blockflags{$k} =~ /s/) { push @expandconstants, $k; }
    }
    foreach my $k (@expandconstants) {
	$blockdata{$k} =~ s/\(=([A-Z0-9\_]+?)=\)/$blockdata{$1}/g;
    }
    
    return 1;
}

# given a file it returns an HTTP Last-modified header in the correct 
# formatting
sub modified_time
{
    my $file = $_[0];
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($most_recent_mod);
    my @day = qw{Sun Mon Tue Wed Thu Fri Sat};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};
    
    if ($year < 1900) { $year += 1900; }
    
    return sprintf("$day[$wday], %02d $month[$mon] $year %02d:%02d:%02d GMT",
		   $mday, $hour, $min, $sec);
}

# given a file, checks it's modification time and sees if it's
# newer than anything else that compiles into what is the document
sub note_file_mod_time
{
    my $file = shift;
    &note_mod_time((stat($file))[9]);
}

sub note_mod_time
{
    my $mod_time = shift;
    if ($mod_time > $most_recent_mod) { $most_recent_mod = $mod_time; }
}

# takes a scalar with %%FIELDS%% mixed in and replaces
# them with their correct values from an anonymous hash, given
# by the second argument to this call
sub parsein
{
    my ($data, $hashref) = @_;
    $data =~ s/%%(\w+)%%/$hashref->{$1}/eg;
    return $data;
}

sub inline_error
{
    return "[Error: <B>@_</B>]";
}

# returns lower-cased, trimmed string
sub trim
{
    my $a = $_[0];
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;
}

package BML;

sub register_block_setup
{
    my $opts = shift;
    $BML::InitData = $opts->{'data'};
    $BML::InitFlags = $opts->{'flags'};
    return 1;
}

sub register_block
{
    my ($type, $flags, $def) = @_;
    $type = uc($type);

    my $datahash = $BML::InitData;
    my $flaghash = $BML::InitFlags;
    $datahash->{$type} = $def;
    $flaghash->{$type} = $flags;
    return 1;
}

sub register_hook
{
    my ($name, $code) = @_;
    $main::HOOK{$name} = $code;
}

sub get_query_string
{
    my $q = $ENV{'QUERY_STRING'} || $ENV{'REDIRECT_QUERY_STRING'};
    if ($q eq "" && $ENV{'REQUEST_URI'} =~ /\?(.+)/) {
	$q = $1;
    }
    return $q;
}

sub finish_suppress_all
{
    finish();
    suppress_headers();
    suppress_content();
}

sub suppress_headers
{
    $main::BMLEnv{'NoHeaders'} = 1;
}

sub suppress_content
{
    $main::BMLEnv{'NoContent'} = 1;
}

sub finish
{
    $main::BML_STOP_FLAG = 1;
}

sub set_content_type
{
    $main::CONTENT_TYPE = $_[0] if $_[0];
}

sub eall
{
    my $a = $_[0];
    return &ebml(&ehtml($a));
}


# escape html
sub ehtml
{
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;	
}

sub ebml
{
    my $a = $_[0];
    $a =~ s/\(=/\(&#0061;/g;
    $a =~ s/=\)/&#0061;\)/g;
    return $a;
}

package BMLUtil;

# escape html
sub ehtml
{
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;	
}

sub ebml
{
    return BML::ebml($_[0]);
}

sub escapeall
{
    return &eall($_[0]);
}

sub eall
{
    my $a = $_[0];
    return &ebml(&ehtml($a));
}

sub eurl
{
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

sub durl
{
    my ($a) = @_;
    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}

sub randlist
{
    my @rlist = @_;
    my $size = scalar(@rlist);
    
    my $i;
    for ($i=0; $i<$size; $i++)
    {
	unshift @rlist, splice(@rlist, $i+int(rand()*($size-$i)), 1);
    }
    return @rlist;
}

sub page_newurl
{
    my $page = $_[0];
    my @pair = ();
    foreach (sort grep { $_ ne "page" } keys %BMLCodeBlock::FORM)
    {
	push @pair, (&eurl($_) . "=" . &eurl($BMLCodeBlock::FORM{$_}));
    }
    push @pair, "page=$page";
    return ($ENV{'PATH_INFO'} . "?" . join("&", @pair));
}

sub paging
{
    my ($listref, $page, $pagesize) = @_;
    $page = 1 unless ($page && $page==int($page));
    my %self;
    
    $self{'itemcount'} = scalar(@{$listref});
    
    $self{'page'} = $page;
    
    $self{'pages'} = $self{'itemcount'} / $pagesize;
    $self{'pages'} = $self{'pages'}==int($self{'pages'}) ? $self{'pages'} : (int($self{'pages'})+1);
    
    $self{'itemfirst'} = $pagesize * ($page-1) + 1;
    $self{'itemlast'} = $self{'pages'}==$page ? $self{'itemcount'} : ($pagesize * $page);
    
    $self{'items'} = [ @{$listref}[($self{'itemfirst'}-1)..($self{'itemlast'}-1)] ];
    
    unless ($page==1) { $self{'backlink'} = "<A HREF=\"" . &page_newurl($page-1) . "\">&lt;&lt;&lt;</A>"; }
    unless ($page==$self{'pages'}) { $self{'nextlink'} = "<A HREF=\"" . &page_newurl($page+1) . "\">&gt;&gt;&gt;</A>"; }
    
    return %self;
}

package BMLml;

sub get_language
{
    return $main::REQ_LANG;
}

sub set_language
{
    $main::REQ_LANG = $_[0];
}

sub make_ml_block
{
    my ($pc, $arghashref) = @_;
    my $ret = "(=_ML $pc?";
    foreach (keys %{$arghashref})
    {
        $ret .= "$_=" . &BMLUtil::eurl($arghashref->{$_}) . "&";
    }
    chop $ret;  # return last ampersand, or the question mark if no args
    $ret .= " _ML=)";
    return $ret;
}

sub interpolate_phrase
{
    my ($data, $args) = @_;
    my %vars = ();

    my $pair;
    my @pairs = split(/&/, $args);
    my ($name, $value);
    foreach $pair (@pairs)
    {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $vars{$name} = $value;
    }
    $data =~ s/\[\[(.+?)\]\]/$vars{$1}/g;
    return $data;
}

package main;
