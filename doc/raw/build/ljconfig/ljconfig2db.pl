#!/usr/bin/perl
#

use strict;
unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

my $LJHOME = $ENV{'LJHOME'};
require "$LJHOME/doc/raw/build/docbooklib.pl";

my %ljconfig =
(
    'user' => {
        'name' => 'User-Configurable',
        'desc' => "New installations will probably want to set these variables. Some are ".
                  "automatically set by ljdefaults.pl based on your other settings, but it ".
                  "wouldn't hurt to specify them all explicitly.",

        'domain' => {
            'name' => 'Domain Related',
            'sitename' => {
                'desc' => "The name of the site",
            },
            'sitenameshort' => {
                'desc' => "The shortened name of the site, for brevity purposes.",
                'default' => "LiveJournal",
            },
            'sitenameabbrev' => {
                'desc' => "The abbreviated version of the name of the site.",
                'default' => "LJ",
            },
            'siteroot' => {
                'desc' => "The URL prefix to construct canonical pages. This can include the port number, if 80 is not in use.",
                'default' => "http://www.\$DOMAIN:8011/",
            },
            'imgprefix' => {
                'desc' => "The URL prefix of the image directory or subdomain.",
                'default' => '$SITEROOT/img',
            },
            'statprefix' => {
                'desc' => "The URL prefix to the static content directory or subdomain.",
                'default' => '$SITEROOT/stc',
            },
            'userpic_root' => {
                'desc' => "The URL prefix to the userpic directory or subdomain.",
                'default' => '$SITEROOT/userpic',
            },
            'domain' => {
                'desc' => "The minimal domain of the site, excluding the 'www.' prefix if applicable.",
            },
            'domain_web' => {
                'desc' => "Optional. If defined and different from [ljconfig[domain]], any GET requests to [ljconfig[domain]] will be redirected to [ljconfig[domain_web]].",
            },
            'cookie_domain' => {
                'desc' => "Cookie domains should simply be set to .\$domain.com, based on the Netscape Cookie Spec, ".
                          "but some older browsers don't adhere to the specs too well. [ljconfig[cookie_domain]] can ".
                          "be a single string value, or it can be a perl array ref.",
                'example' => '["", ".$DOMAIN"]',
                'default' => ".\$DOMAIN",
            },
            #'cookie_path' => {
            #    'desc' => "According to the RFCs concerning cookies, the cookie path needs to be explicitly set as well. If LiveJournal is installed ".
            #              "underneath a directory other than the top level domain directory, this needs to be set accordingly.",
            #    'default' => "/",
            #},
            'server_name' => {
                'desc' => "Optional. If using db-based web logging, this field is stored in the database in the server column, so you can see later how well each server performed. ".
                          "To share the same ljconfig.pl on each host (say, over NFS), you can put something like this in your ljconfig.pl: It's kinda ugly, but it works. ",
                'example' => 'chomp($SERVER_NAME = `hostname`);',
            },
            'frontpage_journal' => {
                'desc' => "If set, the main page of the site loads the specified journal, not the default index page. ".
                          "Use this if you're running a news site where there's only one journal, or one journal is dominant.",
            },
            'tos_check' => {
                'desc' => "If set, the account creation dialog shows a checkbox, asking users if they agree to the site's Terms of Service, ".
                          "and won't allow them to create an account if they refuse. This depends on a few files being located in the proper directories, ".
                          "namely <filename>tos.bml</filename> and <filename>tos-mini.bml</filename> under <filename><envar>\$LJHOME</envar>/htdocs/legal/</filename>. ".
                          "The account creation dialog can also check for new instances of the Terms of Service if the Terms of Service text is located in a ".
                          "CVS managed include file (<filename><envar>\$LJHOME</envar>/htdocs/inc/legal-tos</filename>), ".
                          "and if the include file includes the following line at the top: <programlisting><![CDATA[<!-- \$Revision\$ -->]]></programlisting>",
            },
            'coppa_check' => {
                'desc' => "If set, the account creation dialog shows a checkbox, asking users if they're under 13 years old and won't let them create an account if they check it.",
            },
        },

        'database' => {
            'name' => "Database Related",
            'dbinfo' => {
                'desc' => "This is a hash that contains the necessary information to connect to your database, as well as ".
                          "the configuration for multiple database clusters, if your installation supports them. ".
                          "Consult [special[dbinfo]] for more details.",
                'type' => "hash",
            },
            'clusters' => {
                'default' => "(1)",
                'desc' => "This  is an array that contains the names of the clusters that your configuration uses.",
                'example' => 'qw(fast slow)',
                'type' => "array",
            },
            'default_cluster' => {
                'desc' => "The default cluster to choose when creating new accounts.",
                'default' => "1",
            },
            'dir_db' => {
                'desc' => "This setting tells the installation which database to read from for directory usage. ".
                          "By default this is left blank, meaning that it will use the main database. This can make larger installations work much slower.",
            },
            'dir_db_host' => {
                'desc' => "The database role to use when connecting to the directory database.",
                'example' => "master",
            },
        },

        'system_tools' => {
            'name' => "System Tools",
            'sendmail' => {
                'desc' => "The system path to the sendmail program, along with any necessary parameters.",
                'example' => '"/usr/bin/sendmail -t"',
            },
            'speller' => {
                'desc' => "The system path to a spell checking binary, along with any necessary parameters.",
                'example' => '"/usr/local/bin/aspell pipe --sug-mode=fast --ignore-case"',
            },
            'smtp_server' => {
                'desc' => "This the recommended system to use for sending email. This requires the perl Net::SMTP module to work properly.",
                'example' => "10.2.0.1",
            },
        },

        'optimizations' => {
            'name' => "Optimization",
            'max_hints_lastn' => {
                'desc' => "Sets how many entries a user can have on their <tt>LASTN</tt> page. A higher value can majorly affect the speed of the installation.",
                'default' => "100",
            },
            'max_scrollback_friends' => {
                'desc' => "Sets how far back someone can go on a user's <tt>FRIENDS</tt> page. A higher value can majorly affect the speed of the installation.",
                'default' => "1000",
            },
            'use_recent_tables' => {
                'desc' => "Only turn this on if you are using MySQL replication between multiple databases and have one or more slaves set to not ".
                          "replicated the logtext and talktext tables. Turning this on makes LJ duplicate all logtext & talktext rows into ".
                          "recent_logtext & recent_talktext which is then replicated. However, a cron job cleans up that table so it's never too big. ".
                          "LJ will try the slaves first, then the master. This is the best method of scaling your LJ installation, as disk seeks on the ".
                          "database for journal text is the slowest part.",
            },
            'do_gzip' => {
                 'desc' => "Boolean setting that when enabled, signals to the installation to use gzip encoding wherever possible. In most cases this is known ".
                           "to cut bandwidth usage in half. Requires the Compress::Zlib perl module.",
            },
            'msg_readonly_user' => {
                'desc' => "Message to send to users if their account becomes readonly during maintenance.",
                'example' => "This journal is in read-only mode right now while database maintenance is being performed. Try again in a few minutes.",
            },
        },
 
        'syndication' => {
            'name' => "Syndicated Account Options",
            'syn_lastn_s1' => {
                'desc' => "When set to an appropriate <tt>LASTN</tt> style, all syndicated accounts on this installation will use this style.",
            },
            'synd_cluster' => {
                'desc' => "Syndicated accounts tend to have more database traffic than normal accounts, so its a good idea to set up a seperate cluster for them.".
                          "If set to a cluster (defined by [ljconfig[clusters]]), all newly created syndicated accounts will reside on that cluster.",
            },
        },

        'debug' => {
            'name' => "Development/Debugging Options",
            'allow_cluster_select' => {
                'desc' => "When set true, the journal creation page will display a drop-down list of clusters (from [ljconfig[clusters]]) along ".
                          "with the old 'cluster 0' which used the old db schema and the user creating an account can choose where they go. ".
                          "In reality, there's no use for this, it's only useful when working on the code.",
            },
            'nodb_msg' => {
                'desc' => "Message to send to users when the database is unavailable",
                'default' => "Database temporarily unavailable. Try again shortly.",
            },
            'server_down' => {
                'desc' => "Set true when performing maintenance that requires user activity to be minimum, such as database defragmentation and cluster movements.",
                'default' => "0",
            },
            'server_down_subject' => {
                'desc' => "While [ljconfig[server_down]] is set true, a message with this subject is displayed for anyone trying to access the LiveJournal installation.",
                'example' => "Maintenance",
            },
            'server_down_message' => {
                'desc' => "While [ljconfig[server_down]] is set true, this message will be displayed for anyone trying to access the LiveJournal installation.",
                'example' => '$SITENAME is down right now while we upgrade. It should be up in a few minutes.',
            },
        },

        'email_addresses' => {
            'name' => "Contact email addresses",
            'admin_email' => {
                'desc' => "Given as the administrative address for functions like changing passwords or information.",
            },
            'support_email' => {
                'desc' => "Used as a contact method for people to report problems with the LiveJournal installation.",
            },
            'bogus_email' => {
                'desc' => "Used for automated notices like comment replies and general support request messages. It should be encouraged <i>not</i> to reply to this address.",
            },
        },

        'caps' => {
            'name' => "Capabilities/User Options",
            'newuser_caps' => {
                'desc' => "The default capability class mask for new users.",
            },
            'cap_def' => {
                'desc' => "The default capability limits, used only when no other class-specific limit below matches.",
                'type' => "hash",
            },
            'cap' => {
                'desc' => "A hash that defines the capability class limits. The keys are bit numbers, from 0 .. 15, and the values ".
                          "are hashrefs with limit names and values. Consult [special[cabalities]] for more information.",
                'type' => "hash",
            },
            'user_email' => {
                'desc' => "Do certain users get a forwarding email address, such as user\@\$DOMAIN?. This requires additional mail system configuration.",
            },
            'user_vhosts' => {
                'desc' => "If enabled, the LiveJournal installation will support username URLs of the form http://username.yoursite.com/",
            },
            'user_domain' => {
                'desc' => "If [ljconfig[user_vhosts]] is enabled, this will is the part of the URL that follows 'username'.",
                'example' => '$DOMAIN',
            },
            'default_style' => {
                'desc' => "A hash that defines the default S2 layers to use for accounts.",
                'default' => "{ 
     'core' => 'core1',
     'layout' => 'generator/layout',
     'i18n' => 'generator/en',
 };",
            },
            'allow_pics_over_quota' => {
                'desc' => "By default, when a user's account expires, their least often used userpics will get marked ".
                          "as inactive and will not be available for use. Turning this boolean setting true will circumvent this behavior.",
            },
        },
        'misc' => {
            'name' => "Miscellaneous settings",
            'helpurls' => {
                'desc' => "A hash of URLs. If defined, little help bubbles appear next to common widgets to the URL you define. ".
                          "Consult [special[helpurls]] for more information.",
                'example' => '%HELPURLS = (
     "accounttype" => "http://www.example.com/doc/faq/",
     "security" => "http://www.example.com/doc/security",
);',
                'type' => "hash",
            },
            'use_acct_codes' => {
                'desc' => "A boolean setting that makes the LiveJournal installation require an invitation code before anyone can create an account.".
                          "Consult [special[invitecodes]] for more information.",
            },
            'disabled' => {
                'desc' => "Boolean hash, signifying that separate parts of this LiveJournal installation are working and are avaiable to use. ".
                          "Consult [special[disabled]] for more information.",
                'type' => "hash",
            },
            'protected_usernames' => {
                'desc' => "This is a list of regular expressions matching usernames that users on this LiveJournal installation can't create on their own.",
                'type' => "array",
                'example' => '("^ex_", "^lj_")', 
            },
            'initial_friends' => {
                'desc' => "This is a list of usernames that will be added to the friends list of all newly created accounts on this installation.",
                'type' => "array",
                'example' => "qw(news)", 
            },
            'testaccts' => {
                'desc' => "A list of usernames used for testing purposes. The password to these accounts cannot be changed through the user interface.",
                'type' => "array",
                'example' => "qw(test test2);",
            },
            'no_password_check' => {
                'desc' => "Set this option true if you are running an installation using ljcom code and if you haven't installed the Crypt::Cracklib perl module.",
            },
            'schemes' => {
                'desc' => "An array of hashes with keys being a BML scheme name and the values being the scheme description. When set, users can change their ".
                          "default BML scheme to the scheme of their choice.",
                'type' => "array",
                'example' => "(
   { scheme => 'bluewhite', title => 'Blue White' },
   { scheme => 'lynx', title => 'Lynx' },
   { scheme => 'opalcat', title => 'Opalcat' },
);",
            },
            'force_empty_friends' => {
                'desc' => "A hash of userids whose friends views should be disabled for performance reasons. This is useful if new accounts are auto-added to ".
                          "another account upon creation (described in [ljconfig[initial_friends]]), as in most situations building a friends view for those ".
                          "accounts would be superflous and taxing on your installation.",
                'type' => "hash",
                'example' => "(
     234 => 1,
     232252 => 1,
);",
            },
            'anti_squatter' => {
                'desc' => "Set true if your installation is a publically available development server and if you would like ".
                          "beta testers to ensure that they understand as such. If left alone your installation might become susceptible to ".
                          "hordes of squatter accounts.",
            },
            's2_trusted' => {
                'desc' => "Allows a specific user's S2 layers to run javascript, something that is considered a potential security risk and is disabled for all accounts. The hash structure is a series of userid => username pairs. Note that the system account is trusted by default, so it is not necessary to add to this hash.",
                'type' => "hash",
                'example' => "( '2' => 'whitaker', '3' => 'test', );",
            },
        },

        'portal' => {
            'name' => "Portal Configuration",
            'portal_cols' => {
                'desc' => 'This is a list that specifies which columns can be used for the portal pages.',
                'type' => 'array',
                'default' => 'qw(main right moz)',
            },
            'portal_uri' => {
                'desc' => "The URI to the portal. Only two options are supported at this time, '/portal/' and '/'.",
                'default' => "/portal/",
            },
            'portal_logged_in' => {
                'desc' => "The default positions for portal boxes that a user will see when they are logged in.",
                'default' => "{'main' => [ 
             [ 'update', 'mode=full'],
             ],
 'right' =>  [ 
             [ 'stats', '', ],
             [ 'bdays', '', ],
             [ 'popfaq', '', ],
 ] };",
            },
            'portal_logged_out' => {
                'desc' => "The default positions for portal boxes that a user will see when they are logged out.",
                'default' => "{'main' => [ 
             [ 'update', 'mode='],
             ],
 'right' =>  [ 
             [ 'login', '', ],
             [ 'stats', '', ],
             [ 'randuser', '', ],
             [ 'popfaq', '', ],
             ],
 'moz' =>    [
             [ 'login', '', ],
             ],
};",
            },
        },
    },
    'auto' => {
        'name' => 'Auto-Configured',
        'desc' => "These <varname>\$LJ::</varname> settings are automatically set in ".
                  "<filename>ljdefaults.pl</filename>. They're only documented here for ".
                  "people interested in extending LiveJournal. Or, you can define them in ".
                  "<filename>ljconfig.pl</filename> ahead of time so you can use them in ".
                  "definitions of future variables. ",

        'directories' => {
            'name' => "Configuration Directories",
            'home' => {
                'desc' => "Set to the same value as [special[ljhome]]",
                'default' => "\$ENV{'LJHOME'}",
            },
            'htdocs' => {
                'desc' => "Points to the htdocs directory under [special[ljhome]]",
                'default' => "\$HOME/htdocs",
            },
            'bin' => {
                'desc' => "Points to the under bin directory under [special[ljhome]]",
                'default' => "\$HOME/bin",
            },
            'temp' => {
                'desc' => "Points to the temp directory under [special[ljhome]]",
                'default' => "\$HOME/temp",
            },
            'var' => {
                'desc' => "Points to the var directory under [special[ljhome]]",
                'default' => "\$HOME/var",
            },
        },

        'i18n' => {
            'name' => "Internationalization",
            'unicode' => {
                'desc' => "Boolean setting that allows UTF-8 support. This is enabled by default.",
            },
        },
    },
);

for my $type ( keys %ljconfig )
{
    print "  <section id='lj.install.ljconfig.vars.$type'>\n";
    print "    <title>" . %ljconfig->{$type}->{'name'} . "</title>\n";
    print "    <simpara>" . %ljconfig->{$type}->{'desc'} . "</simpara>\n";
    for my $list ( sort keys %{%ljconfig->{$type}} ) {
        next if ($list eq "name" || $list eq "desc");
        print "    <variablelist>\n";
        print "      <title>" . %ljconfig->{$type}->{$list}->{'name'} . "</title>\n";
        foreach my $var ( sort keys %{%ljconfig->{$type}->{$list}} ) {
            next if $var eq "name";
            my $vartype = '$';
            if (%ljconfig->{$type}->{$list}->{$var}->{'type'} eq "hash") { $vartype = '%'; }
            if (%ljconfig->{$type}->{$list}->{$var}->{'type'} eq "array") { $vartype = '@'; }
            print "      <varlistentry id='ljconfig.$var'>\n";
            print "        <term><varname role='ljconfig.variable'>" . $vartype . "LJ::" . uc($var) . "</varname></term>\n";
            my $des = %ljconfig->{$type}->{$list}->{$var}->{'desc'};
            cleanse(\$des);
            print "        <listitem><simpara>$des</simpara>\n";
            if (%ljconfig->{$type}->{$list}->{$var}->{'example'})
            {
                print "          <para><emphasis>Example:</emphasis> ";
                print "<informalexample><programlisting>";
                print %ljconfig->{$type}->{$list}->{$var}->{'example'};
                print "</programlisting></informalexample></para>\n";
            }
            if (%ljconfig->{$type}->{$list}->{$var}->{'default'})
            {
                print "          <para><emphasis>Default:</emphasis> ";
                print "<informalexample><programlisting>";
                print %ljconfig->{$type}->{$list}->{$var}->{'default'};
                print "</programlisting></informalexample></para>\n";
            }
            print "        </listitem>\n";
            print "      </varlistentry>\n";
        }
        print "    </variablelist>\n";
    }
    print "  </section>\n";
} 

#hooks();
