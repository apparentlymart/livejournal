#!/usr/bin/perl
#
# Stores all global crumbs and builds the crumbs hash

%LJ::CRUMBS = (
               'acctstatus' => ['Account Status', '/accountstatus.bml', 'manage'],
               'addfriend' => ['Add Friend', '', 'userinfo'],
               'addtodo' => ['Add To-Do Item', '', 'todolist'],
               'advcustomize' => ['Customize Advanced S2 Settings', '/customize/advanced/index.bml', 'manage'],
               'advsearch' => ['Advanced Search', '/directorysearch.bml', 'search'],
               'birthdays' => ['Birthdays', '/birthdays.bml', 'friends'],
               'changepass' => ['Change Password', '/changepassword.bml', 'manage'],
               'createcommunity' => ['Create Community', '/community/settings.bml?mode=create', 'managecommunity'],
               'createjournal' => ['Create Journal', '/create.bml', 'home'],
               'customize' => ['Customize S2 Settings', '/customize/index.bml', 'manage'],
               'delcomment' => ['Delete Comment', '/delcomment.bml', 'home'],
               'editentries' => ['Edit Entries', '/editjournal.bml', 'manage'],
               'editentries_do' => ['Edit Entry', '/editjournal_do.bml', 'editentries'],
               'editfriends' => ['Edit Friends', '/friends/edit.bml', 'friends'],
               'editfriendgrps' => ['Edit Friends Groups', '/friends/editgroups.bml', 'friends'],
               'editinfo' => ['Personal Info', '/editinfo.bml', 'manage'],
               'editpics' => ['User Pictures', '/editpics.bml', 'manage'],
               'emailgateway' => ['Email Gateway', '/manage/emailpost.bml', 'manage'],
               'export' => ['Export Journal', '/export.bml', 'home'],
               'faq' => ['Frequently Asked Questions', '/support/faq.bml', 'support'],
               'friends' => ['Friends Tools', '/friends/index.bml', 'manage'],
               'friendsfilter' => ['Friends Filter', '/friends/filter.bml', 'friends'],
               'home' => ['Home', '/', ''],
               'linkslist' => ['Your Links', '/manage/links.bml', 'manage'],
               'login' => ['Login', '/login.bml', 'home'],
               'logout' => ['Logout', '/logout.bml', 'home'],
               'lostinfo' => ['Lost Info', '/lostinfo.bml', 'manage'],
               'manage' => ['Manage Accounts', '/manage/', 'home'],
               'managecommunity' => ['Community Management', '/community/manage.bml', 'manage'],
               'meme' => ['Meme Tracker', '/meme.bml', 'home'],
               'memories' => ['Memorable Posts', '/tools/memories.bml', 'manage'],
               'modify' => ['Journal Settings', '/modify.bml', 'manage'],
               'moodlist' => ['Mood Viewer', '/moodlist.bml', 'manage'],
               'news' => ['News', '/news.bml', 'home'],
               'phonepostsettings' => ['Phone Post', '/manage/phonepost.bml', 'manage'],
               'register' => ['Validate Email', '/register.bml', 'home'],
               'searchinterests' => ['Search By Interest', '/interests.bml', 'search'],
               'searchregion' => ['Search By Region', '/directory.bml', 'search'],
               'setpgpkey' => ['Public Key', '/manage/pubkey.bml', 'manage'],
               'siteopts' => ['Browse Preferences', '/manage/siteopts.bml', 'manage'],
               'stats' => ['Statistics', '/stats.bml', 'about'],
               'support' => ['Support', '/support/index.bml', 'home'],
               'supporthelp' => ['Request Board', '/support/help.bml', 'support'],
               'supportnotify' => ['Notification Settings', '/support/changenotify.bml', 'support'],
               'supportscores' => ['High Scores', '/support/highscores.bml', 'support'],
               'supportsubmit' => ['Submit Request', '/support/submit.bml', 'support'],
               'unsubscribe' => ['Unsubscribe', '/unsubscribe.bml', 'home'],
               'update' => ['Update Journal', '/update.bml', 'home'],
               'utf8convert' => ['UTF-8 Converter', '/utf8convert.bml', 'manage'],
           );

# include the local crumbs info
require "$ENV{'LJHOME'}/cgi-bin/crumbs-local.pl"
    if -e "$ENV{'LJHOME'}/cgi-bin/crumbs-local.pl";

1;
