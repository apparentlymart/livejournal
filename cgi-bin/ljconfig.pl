#!/usr/bin/perl
#
# LiveJournal configuration.  This should be the only file you need to change
# to get the LiveJournal code to run on your site.  If not, it's considered
# a bug and you should report it.
#

{
    package LJ;

    $HOME = $ENV{'LJHOME'} || "/home/lj";
    $HTDOCS = "$HOME/htdocs";
    $BIN = "$HOME/bin";
    $TEMP = "$HOME/temp";
    $VAR = "$HOME/var";

    # human readable name of this site
    $SITENAME = "LJ.COM DEV BOX";
    
    ## turn $SERVER_DOWN on while you do any maintenance
    $SERVER_DOWN = 0;
    $SERVER_DOWN_SUBJECT = "Maintenance";
    $SERVER_DOWN_MESSAGE = "$SITENAME is down right now while we upgrade.  It should be up in a few minutes.";

    $DOMAIN = "lj.com";
    $SITEROOT = "http://www.$DOMAIN";   # could add a port number after this, like :8080
    $IMGPREFIX = "$SITEROOT/img";    
    $FTPPREFIX = "ftp://ftp.$DOMAIN"; # leave blank or undefined if you're not running an FTP server
    $DIRURI = "/directory.sbml";

    # path to sendmail-compatible mailer and any necessary options
    $SENDMAIL = "/usr/sbin/sendmail -t";

    # path to spell checker, if you want spell checking
    $SPELLER = "";
    # $SPELLER = "/usr/local/bin/ispell -a";
    # $SPELLER = "/usr/local/bin/aspell pipe --sug-mode=fast --ignore-case";

    # where we set the cookies (note the period before the domain)
    $COOKIE_DOMAIN = ".$DOMAIN";
    $COOKIE_PATH   = "/";

    # email addresses
    $ADMIN_EMAIL = "webmaster\@$DOMAIN";
    $SUPPORT_EMAIL = "support\@$DOMAIN";
    $BOGUS_EMAIL = "lj_dontreply\@$DOMAIN";

    # Support URLs of the form http://username.yoursite.com/ ? 
    # If so, what's the part after "username." ?
    $USER_VHOSTS = 1;
    $USER_DOMAIN = $DOMAIN;
  
    $INTRANET = 1;        # if true, turn off AOL warning, legalese, COPPA stuff, etc
    $EVERYONE_PAID = 1;   # if true, all new accounts get paid feature access
    $EVERYONE_VALID = 1;  # if true, new accounts don't need to be validated

    # performance/load related settings (only necessary on high-traffic installations)
    $BUFFER_QUERIES = 0;

    # Do paid users get email addresses?  username@$USER_DOMAIN ?
    # (requires additional mail system configuration)
    $USER_EMAIL  = 0;

    ## Directory optimizations
    $DIR_DB = "";   # by default, hit the main database (bad for big sites!)

    # database info.
    %DBINFO = (
	       'master' => {
		   'host' => '',
		   'user' => 'lj',
		   'pass' => 'ljpass',
	       },
	       'slavecount' => 0,
	       'slave1' => {
		   'host' => 'slave1host',
		   'user' => 'lj',
		   'pass' => 'ljpass',
	       },
	       );

    ## default portal options

    @PORTAL_COLS = qw(main right moz);  # can also include left, if you want.
    $PORTAL_URI = "/portal/";           # either "/" or "/portal/"    

    $PORTAL_LOGGED_IN = {'main' => [ 
				     [ 'update', 'mode=full'],
				     ],
			 'right' => [ 
				      [ 'goat', '', ],
				      [ 'stats', '', ],
				      [ 'bdays', '', ],
				      ] };
    $PORTAL_LOGGED_OUT = {'main' => [ 
				      [ 'update', 'mode='],
				      ],
			  'right' => [ 
				       [ 'newtolj', '', ],
				       [ 'login', '', ],
				       [ 'stats', '', ],
				       ],
			  'moz' => [
				    [ 'login', '', ],
				    ],
			  };
    
    # HINTS:
    #   how far you can scroll back on lastn page.  big performance
    #   implications if you make these too high.  also, once you lower
    #   them, increasing them won't change anything until there are
    #   new posts numbering the difference you increased it by.
    $MAX_HINTS_LASTN = 100;

}

return 1;
