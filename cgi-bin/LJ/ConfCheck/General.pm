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

1;
