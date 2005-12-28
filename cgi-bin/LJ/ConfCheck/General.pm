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


my %bools = (
	     "DONT_LOG_IMAGES" => "Don't log requests for images.",
	     "DONT_TOUCH_STYLES" => "During the upgrade populator, don't touch styles.  That is, consider the local styles the definitive ones, and any differences between the database and the distribution files should mean that the distribution is old, not the database.",
	     "DO_GZIP" => "Compress text content sent to browsers.  Cuts bandwidth by over 50%.",

	     );

foreach my $k (keys %bools) {
    my $val = $bools{$k};
    $val = { des => $val } unless ref $val;
    $val->{type} = "bool",
    $val->{des} = "If set to true, " . lcfirst($val->{des});
    add_conf("\$$k", %$val);
}

1;
