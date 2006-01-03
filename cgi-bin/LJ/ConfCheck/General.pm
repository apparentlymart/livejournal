#
# This is livejournal.com (ljcom)'s additions to LJ::ConfCheck, for the ljcom instance
# of LiveJournal.
#

package LJ::ConfCheck;

use strict;

add_singletons(qw(
		  @USER_TABLES $PROTOCOL_VER $MAX_DVERSION 
		  $CLEAR_CACHES $BIN $HTDOCS 
		  ));

add_conf('$ADMIN_EMAIL',
	 required => 1,
	 des      => "Email address of the installation's webmaster.",
	 type     => "email",
	 );

add_conf('$BLOCKED_BOT_SUBJECT',
	 required => 0,
	 des      => "Subject/title shown to people suspected to be bots.",
	 type     => "text",
	 );

add_conf('$BLOCKED_BOT_URI',
	 required => 0,
	 des      => "Path (e.g. /bots) at which a informational page about your acceptable bot policies are documented.  This URI is excluded from anti-bot measures, so make sure it's as permissive as possible to allow humans in who may be lazy in their typing.  For example, leave off the trailing slash (/bots instead of /bots/) if your URI is a directory.",
	 type     => "uri",
	 );

add_conf('$BLOCKED_BOT_MESSAGE',
	 required => 0,
	 des      => "Message shown to people suspected to be bots, informing them they've been banned, and where/what the rules are.",
	 type     => "html",
	 );

add_conf('$BML_DENY_CONFIG',
	 required => 0,
	 des      => "Comma-separated list of directories under htdocs which should be served without parsing their _config.bml files.  For example, directories that might be under a lesser-trusted person's control.",
	 validate => qr/^\w+(\s*,\s*\w+)*$/,
	 );

add_conf('$BOGUS_EMAIL',
	 required => 1,
	 des      => "Email address which comments and other notifications come from, but which cannot accept incoming email itself.",
	 type => "email",
	 );

add_conf('$COMMUNITY_EMAIL',
	 required => 0,
	 des      => "Email address which comments and other notifications regarding communities come from.  If unspecified, defaults to \$ADMIN_EMAIL .",
	 type => "email",
	 );

add_conf('$CAPTCHA_AUDIO_PREGEN',
	 required => 0,
	 default => 500,
	 des => "The max number of audio captchas to pre-generate ahead of time.",
	 type => "int",
	 );

add_conf('$CAPTCHA_AUDIO_MAKE',
	 required => 0,
	 des => "The max number of audio captchas to make per-process.  Should be less than CAPTCHA_AUDIO_PREGEN.  Useful for farming out generation of CAPTCHA_AUDIO_PREGEN to lots of machines.",
	 type => "int",
	 STUPID_BECAUSE => "after each generation, processes should just double-check the number available, then we can kill this configuration variable",
	 );

add_conf('$CAPTCHA_IMAGE_PREGEN',	
	 required => 0,
	 default => 1000,
	 des => "The max number of image captchas to pre-generate ahead of time.",
	 type => "int",
	 );

add_conf('$CAPTCHA_MOGILEFS',
	 required => 0,
	 type => "bool",
	 des => "If true, captchas are stored in MogileFS.",
	 STUPID_BECAUSE => "Should just be: if using MogileFS, store them there, else not.",
	 );

add_conf('$COMPRESS_TEXT',
	 required => 0,
	 type => "bool",
	 des => "If set, text is gzip-compressed when put in the database.  When reading from the database, this configuration means nothing, as the code automatically determines to uncompress or not.",
	 );

add_conf('$COOKIE_DOMAIN',
	 required => 1,
	 des => "The 'domain' value set on cookies sent to users.  By default, value is \".\$DOMAIN\".  Note the leading period, which is a wildcard for everything at or under \$DOMAIN.",
	 );

add_conf('$COOKIE_PATH',
	 required => 0,
	 des => "The 'path' value set on cookies sent to users.  By default, value is \"/\", and any other value probably wouldn't work anyway.",
	 STUPID_BECAUSE => "no use, since LJ must be rooted at /.",
	 );

add_conf('@COOKIE_DOMAIN_RESET',
	 required => 0,
	 des => "Array of cookie domain values to send when deleting cookies from users.  Only useful when changing domains, and even then kinda useless.",
	 STUPID_BECAUSE => "ancient hack for one old specific use",
	 );

add_conf('$COPPA_CHECK',
	 required => 0,
	 type => "bool",
	 des => "If set, new users are asked for their birthday for COPPA compliance.",
	 );

add_conf('$DB_LOG_HOST',
	 required => 0,
	 type => "hostport",
	 des => "An optional host:port to send UDP packets to with blocking reports.  See LJ::blocking_report(..)",
	 );

add_conf('$DB_TIMEOUT',
	 required => 0,
	 type => "int",
	 des => "Integer number of seconds to wait for database handles before timing out.  By default, zero, which means no timeout.",
	 );

add_conf('$DEFAULT_CLUSTER',
	 required => 0,
	 des => "Integer of a user cluster number or arrayref of cluster numbers, for where new users are assigned after account creation.  In the case of an arrayref, you can weight one particular cluster over another by place it in the arrayref more often.  For instance, [1, 2, 2, 2] would make users go onto cluster #2 75% of the time, and cluster #1 25% of the time.",
	 );

add_conf('$DEFAULT_LANG',
	 required => 0,
	 des => "Default language (code) to show site in, for users that haven't set their langauge.  Defaults to the first item in \@LANGS, which is usually \"en\", for English.",
	 );

add_conf('$DEFAULT_STYLE',
	 required => 0,
	 des => "Hashref describing default S2 style.  Keys are layer types, values being the S2 redist_uniqs.",
	 type => "hashref",
	 allowed_keys => qw(core layout theme i18n i81nc),
	 );

add_conf('$DIRECTORY_SEPARATE',
	 type => 'bool',
	 des => "If true, only use the 'directory' DB role for the directory, and don't also try the 'slave' and 'master' roles.",
	 );

add_conf('$DISABLE_MASTER',
	 type => 'bool',
	 des => "If set to true, access to the 'master' DB role is prevented, by breaking the get_dbh function.  Useful during master database migrations.",
	 );

add_conf('$DISABLE_MEDIA_UPLOADS',
	 type => 'bool',
	 des => "If set to true, all media uploads that would go to MogileFS are disabled.",
	 );

add_conf('$DISCONNECT_DBS',
	 type => 'bool',
	 des => "If set to true, all database connections (except those for logging) are disconnected at the end of each request.  Recommended for high-performance sites with lots of database clusters.  See also: \$DISCONNECT_DB_LOG",
	 );

add_conf('$DISCONNECT_DB_LOG',
	 type => 'bool',
	 des => "If set to true, database connections for logging are disconnected at the end of each request.",
	 );

add_conf('$DISCONNECT_MEMCACHE',
	 type => 'bool',
	 des => "If set to true, memcached connections are disconnected at the end of each request.  Not recommended if your memcached instances are Linux 2.6.",
	 );

add_conf('$DOMAIN',
	 required => 1,
	 des => "The base domain name for your installation.  This value is used to auto-set a bunch of other configuration values.",
	 type => 'hostname,'
	 );

add_conf('$DOMAIN_WEB',
	 required => 0,
	 des => "The preferred domain name for your installation's web root.  For instance, if your \$DOMAIN is 'foo.com', your \$DOMAIN_WEB might be 'www.foo.com', so any user who goes to foo.com will be redirected to www.foo.com.",
	 type => 'hostname,'
	 );

add_conf('$EMAIL_POST_DOMAIN',
	 type => 'hostname',
	 des => "Domain name for incoming emails.  For instance, user 'bob' might post by sending email to 'bob\@post.service.com', where 'post.service.com' is the value of \$EMAIL_POST_DOMAIN",
	 );

add_conf('$FB_DOMAIN',
	 type => 'hostname',
	 des => "Domain name for cooperating Fotobilder (media hosting/cataloging) installation",
	 );

add_conf('$FB_SITEROOT',
	 type => 'url',
	 no_trailing_slash => 1,
	 des => "URL prefix to cooperating Fotobilder installation, without trailing slash.  For instance, http://pics.foo.com",
	 );

add_conf('$HOME',
	 type => 'directory',
	 no_trailing_slash => 1,
	 des => "The root of your LJ installation.  This directory should contain, for example, 'htdocs' and 'cgi-bin', etc.",
	 );

add_conf('$IMGPREFIX',
	 type => 'url',
	 no_trailing_slash => 1,
	 des => "Prefix on (static) image URLs.  By default, it's '\$SITEROOT/img', but your load balancing may dictate another hostname or port for efficiency.  See also: \$IMGPREFIX",
	 );

add_conf('$JSPREFIX',
	 type => 'url',
	 no_trailing_slash => 1,
	 des => "Prefix on (static) javascript URLs.  By default, it's '\$SITEROOT/js', but your load balancing may dictate another hostname or port for efficiency.  See also: \$IMGPREFIX",
	 );

add_conf('$PALIMGROOT',
	 type => 'url',
	 no_trailing_slash => 1,
	 des => "Prefix on GIF/PNGs with dynamically generated palettes.  By default, it's '\$SITEROOT/palimg\', and there's little reason to change it.  Somewhat related: note that Perlbal has a plugin to handle these before it gets to mod_perl, if you'd like to relieve some load on your backend mod_perls.   But you don't necessarily need this option for using Perlbal to do it.  Depends on your config.",
	 );

add_conf('$MAILLOCK',
	 type => ["hostname", "none", "ddlockd"],
	 des => "Locking method that mailgated.pl should use when processing incoming emails from the Maildir.  You can safely use 'none' if you have a single host processing mail, otherwise 'ddlockd' or 'hostname' is recommended, though 'hostname' means mail that arrived on a host that then crashes won't be processed until it comes back up.  ddlockd is recommended, if you're using multiple mailgated processes.",
	 );

add_conf('$MAX_ATOM_UPLOAD',
	 type => 'int',
	 des => "Max number of bytes that users are allowed to upload via Atom.  Note that this upload path isn't ideal, so the entire upload must fit in memory.  Default is 25MB until path is optimized.",
	 );

add_conf('$MAX_FOAF_FRIENDS',
	 type => 'int',
	 des => "The maximum number of friends that users' FOAF files will show.  Defaults to 1000.  If they have more than the configured amount, some friends will be omitted.",
	 );

add_conf('$MAX_FRIENDOF_LOAD',
	 type => 'int',
	 des => "The maximum number of friend-ofs ('fans'/'followers') to load for a given user.  Defaults to 5000.  Beyond that, a user is just too popular and saying 5,000 is usually sufficient because people aren't actually reading the list.",
	 );

add_conf('$MAX_SCROLLBACK_LASTN',
	 type => 'int',
	 des => "The recent items (lastn view)'s max scrollback depth.  That is, how far you can skip back with the ?skip= URL argument.  Defaults to 100.  After that, the 'previous' links go to day views, which are stable URLs.  ?skip= URLs aren't stable, and there are inefficiencies making this value too large, so you're advised to not go too far above the default of 100.",
	 );

add_conf('$MAX_SCROLLBACK_FRIENDS',
	 type => 'int',
	 des => "The friends page' max scrollback depth.  That is, how far you can skip back with the ?skip= URL argument.  Defaults to 1000.",
	 );

add_conf('$MAX_REPL_LAG',
	 type => 'int',
	 des => "The max number of bytes that a MySQL database slave can be behind in replication and still be considered usable.  Note that slave databases are never used for any 'important' read operations (and especially never writes, because writes only go to the master), so in general MySQL's async replication won't bite you.  This mostly controls how fresh of data a visitor would see, not a content owner.  But in reality, the default of 100k is pretty much real-time, so you can safely ignore this setting.",
	 );

add_conf('$MAX_S2COMPILED_CACHE_SIZE',
	 type => 'int',
	 des => "Threshold (in bytes) under which compiled S2 layers are cached in memcached.  Default is 7500 bytes.  If you have a lot of free memcached memory and a loaded database server with lots of queries to the s2compiled table, turn this up.",
	 );

add_conf('$MAX_USERPIC_KEYWORDS',
	 type => 'int',
	 des => "Max number of keywords allowed per userpic.  Default is 10.",
	 );

add_conf('$MINIMAL_BML_SCHEME',
	 type => "string",
	 des => "The name of the BML scheme that implements the site's 'lite' interface for minimally capable devices such as cellphones/etc.  See also %MINIMAL_USERAGENT.");

add_conf('%MINIMAL_USERAGENT',
	 des => "Set of user-agent prefixes (the part before the slash) that should be considered 'lite' devices and thus be given the site's minimal interface.  Keys are prefixes, value is a boolean.  See also \$MINIMAL_BML_SCHEME.",
	 );

add_conf('$MSG_DB_UNAVAILABLE',
	 type => "html",
	 des => "Message to show users on a database unavailable error.",
	 );

add_conf('$MSG_NO_COMMENT',
	 type => "html",
	 des => "Message to show users when they're not allowed to comment due to either their 'get_comments' or 'leave_comments' capability being disabled, probably by the admin to lower activity after a hardware rotation.",
	 );

add_conf('$MSG_NO_POST',
	 type => "html",
	 des => "Message to show users when they're not allowed to post due to their 'can_post' capability being disabled, probably by the admin to lower activity after a hardware rotation.",
	 );

add_conf('$MSG_READONLY_USER',
	 type => "string",
	 des => "Message to show users when their journal (or a journal they're visting) is in read-only mode due to maintenance.",
	 );

add_conf('$NEWUSER_CAPS',
	 type => 'int',
	 des => "Bitmask of capability classes that new users begin their accounts with.  By default users aren't in any capability classes and get only the default site-wide capabilities.  See also \%CAP.",
	 );

add_conf('$NEW_ENTRY_CLEANUP_HACK',
	 type => "bool",
	 des => "OLD HISTORIC BAGGAGE: Do not use!  There used to be a bug where only parts of entries got deleted, then there was another bug with per-user number allocation.  Together, they forced this option to be made for awhile, where new entries (when this is on) would blow away any old data if part of it was still there but wasn't supposed to be.  This includes deleting comments tied to those old entries.",
	 );

add_conf('$QBUFFERD_DELAY',
	 type => 'int',
	 des => "Time to sleep between runs of qbuffered tasks.  Default is 15 seconds.",
	 );

add_conf('$RATE_COMMENT_AUTH',
	 des => "Arrayref of rate rules to apply incoming comments from authenticated users .  Each rate rule is an arrayref of two items:  number of comments, and period of time.  If user makes more comments in period of time, comment is denied, at least without a captcha.",
	 );

add_conf('$RATE_COMMENT_ANON',
	 des => "Arrayref of rate rules to apply incoming comments from anonymous users .  Each rate rule is an arrayref of two items:  number of comments, and period of time.  If user makes more comments in period of time, comment is denied, at least without a captcha.",
	 );

add_conf('$SCHOOLSMAX',
	 des => "Hashref of journaltype (P, C, I, ..) to maximum number of allowed schools for that journal type.",
	 );


my %bools = (
	     'S2COMPILED_MIGRATION_DONE' => "Don't try to load compiled S2 layers from the global cluster.  Any new installation can enable this safely as a minor optimization.  The option only really makes sense for large, old sites.",
	     "S1_SHORTCOMINGS" => "Use the S2 style named 's1shortcomings' to handle page types that S1 can't handle.  Otherwise, BML is used.  This is off by defalut, but will eventually become on by default, and no longer an option.",
	     "REQUIRE_TALKHASH" => "Require submitted comments to include a signed hidden value provided by the server.  Slows down comment-spammers, at least, in that they have to fetch pages first, instead of just blasting away POSTs.  Defaults to off.",
	     "REQUIRE_TALKHASH_NOTOLD" => "If \$REQUIRE_TALKHASH is on, also make sure that the talkhash provided was issued in the past two hours.  Defaults to off.",
	     "DONT_LOG_IMAGES" => "Don't log requests for images.",
	     "DONT_TOUCH_STYLES" => "During the upgrade populator, don't touch styles.  That is, consider the local styles the definitive ones, and any differences between the database and the distribution files should mean that the distribution is old, not the database.",
	     "DO_GZIP" => "Compress text content sent to browsers.  Cuts bandwidth by over 50%.",
	     "EVERYONE_VALID" => "Users don't need to validate their email addresses.",
	     "FB_QUOTA_NOTIFY" => "Do RPC requests to Fotobilder to inform it of disk quota changes.",
	     "IS_DEV_SERVER" => "This is a development installation only, and not used for production.  A lot of debug info and intentional security holes for convenience are introduced when this is enabled.",
	     "LOG_GTOP" => "Log per-request CPU and memory usage, using gtop libraries.",
	     "NO_PASSWORD_CHECK" => "Don't do strong password checks.  Users can use any old dumb password they'd like.",
	     "OPENID_CONSUMER" => "Accept OpenID identies for logging in and commenting.",
	     "OPENID_SERVER" => "Be an OpenID server.",
	     "OTHER_VHOSTS" => "Let users CNAME their vanity domains to this LiveJournal installation to transparently load their journal.",
	     
	     );

foreach my $k (keys %bools) {
    my $val = $bools{$k};
    $val = { des => $val } unless ref $val;
    $val->{type} = "bool",
    $val->{des} = "If set to true, " . lcfirst($val->{des});
    add_conf("\$$k", %$val);
}

1;
