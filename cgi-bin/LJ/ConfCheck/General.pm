#
# This is livejournal.com (ljcom)'s additions to LJ::ConfCheck, for the ljcom instance
# of LiveJournal.
#

package LJ::ConfCheck;

use strict;

add_singletons(qw(
		  @USER_TABLES $PROTOCOL_VER $MAX_DVERSION 
		  $CLEAR_CACHES
		  ));

add_conf('$ADMIN_EMAIL',
	 required => 1,
	 des      => "Email address of the installation's webmaster.",
	 type     => "email",
	 );


1;
