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


1;
