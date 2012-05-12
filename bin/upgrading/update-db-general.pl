#
# database schema & data info
#

mark_clustered(@LJ::USER_TABLES);

register_tablecreate('acctcode', <<'EOC');
CREATE TABLE `acctcode` (
  `acid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL,
  `rcptid` int(10) unsigned NOT NULL DEFAULT '0',
  `auth` char(5) NOT NULL,
  PRIMARY KEY (`acid`),
  KEY `userid` (`userid`),
  KEY `rcptid` (`rcptid`)
)
EOC

register_tablecreate('actionhistory', <<'EOC');
CREATE TABLE `actionhistory` (
  `time` int(10) unsigned NOT NULL,
  `clusterid` tinyint(3) unsigned NOT NULL,
  `what` varchar(20) NOT NULL,
  `count` int(10) unsigned NOT NULL DEFAULT '0',
  KEY `time` (`time`)
)
EOC

register_tablecreate('active_user', <<'EOC');
CREATE TABLE `active_user` (
  `year` smallint(6) NOT NULL,
  `month` tinyint(4) NOT NULL,
  `day` tinyint(4) NOT NULL,
  `hour` tinyint(4) NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `type` char(1) NOT NULL,
  PRIMARY KEY (`year`,`month`,`day`,`hour`,`userid`)
)
EOC

register_tablecreate('active_user_summary', <<'EOC');
CREATE TABLE `active_user_summary` (
  `year` smallint(6) NOT NULL,
  `month` tinyint(4) NOT NULL,
  `day` tinyint(4) NOT NULL,
  `hour` tinyint(4) NOT NULL,
  `clusterid` tinyint(3) unsigned NOT NULL,
  `type` char(1) NOT NULL,
  `count` int(10) unsigned NOT NULL DEFAULT '0',
  KEY `year` (`year`,`month`,`day`,`hour`)
)
EOC

register_tablecreate('adopt', <<'EOC');
CREATE TABLE `adopt` (
  `adoptid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `helperid` int(10) unsigned NOT NULL DEFAULT '0',
  `newbieid` int(10) unsigned NOT NULL DEFAULT '0',
  `changetime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`adoptid`),
  KEY `helperid` (`helperid`),
  KEY `newbieid` (`newbieid`)
)
EOC

register_tablecreate('adoptlast', <<'EOC');
CREATE TABLE `adoptlast` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `lastassigned` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `lastadopted` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('antispam', <<'EOC');
CREATE TABLE `antispam` (
  `journalid` int(10) unsigned NOT NULL,
  `itemid` int(10) unsigned NOT NULL DEFAULT '0',
  `type` char(1) NOT NULL,
  `posterid` int(10) unsigned NOT NULL DEFAULT '0',
  `eventtime` date DEFAULT NULL,
  `poster_ip` char(15) DEFAULT NULL,
  `email` char(50) DEFAULT NULL,
  `user_agent` varchar(128) DEFAULT NULL,
  `uniq` char(15) DEFAULT NULL,
  `spam` tinyint(3) unsigned DEFAULT NULL,
  `confidence` float(4,3) unsigned DEFAULT NULL,
  `review` char(1) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`itemid`,`type`),
  KEY `posterid` (`posterid`,`eventtime`),
  KEY `spam` (`spam`),
  KEY `review` (`review`),
  KEY `eventtime` (`eventtime`)
)
EOC

register_tablecreate('authactions', <<'EOC');
CREATE TABLE `authactions` (
  `aaid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `datecreate` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `authcode` varchar(20) DEFAULT NULL,
  `action` varchar(50) DEFAULT NULL,
  `arg1` varchar(255) DEFAULT NULL,
  `used` enum('Y','N') DEFAULT 'N',
  PRIMARY KEY (`aaid`),
  KEY `userid` (`userid`),
  KEY `datecreate` (`datecreate`)
)
EOC

register_tablecreate('backupdirty', <<'EOC');
CREATE TABLE `backupdirty` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `marktime` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('birthdays', <<'EOC');
CREATE TABLE `birthdays` (
  `userid` int(10) unsigned NOT NULL,
  `nextbirthday` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `nextbirthday` (`nextbirthday`)
)
EOC

register_tablecreate('blobcache', <<'EOC');
CREATE TABLE `blobcache` (
  `bckey` varchar(255) NOT NULL,
  `dateupdate` datetime DEFAULT NULL,
  `value` mediumblob,
  PRIMARY KEY (`bckey`)
)
EOC

register_tablecreate('blockwatch_events', <<'EOC');
CREATE TABLE `blockwatch_events` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('captcha_session', <<'EOC');
CREATE TABLE `captcha_session` (
  `sess` char(20) NOT NULL DEFAULT '',
  `sesstime` int(10) unsigned NOT NULL DEFAULT '0',
  `lastcapid` int(11) DEFAULT NULL,
  `trynum` smallint(6) DEFAULT '0',
  PRIMARY KEY (`sess`),
  KEY `sesstime` (`sesstime`)
)
EOC

register_tablecreate('captchas', <<'EOC');
CREATE TABLE `captchas` (
  `capid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `type` enum('image','audio') DEFAULT NULL,
  `location` enum('blob','mogile') DEFAULT NULL,
  `issuetime` int(10) unsigned NOT NULL DEFAULT '0',
  `answer` char(10) DEFAULT NULL,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `anum` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`capid`),
  KEY `type` (`type`,`issuetime`),
  KEY `userid` (`userid`)
)
EOC

# global table for community directory
register_tablecreate('category', <<'EOC');
CREATE TABLE `category` (
  `catid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `pretty_name` varchar(255) NOT NULL,
  `url_path` varchar(120) NOT NULL,
  `parentcatid` int(10) unsigned NOT NULL,
  `vert_id` int(11) NOT NULL,
  PRIMARY KEY (`catid`),
  UNIQUE KEY `url_path` (`url_path`,`parentcatid`,`vert_id`),
  KEY `parentcatid` (`parentcatid`)
)
EOC

register_tablecreate('category_recent_posts', <<'EOC');
CREATE TABLE `category_recent_posts` (
  `jitemid` int(11) NOT NULL DEFAULT '0',
  `timecreate` datetime NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0',
  `pic_orig_url` varchar(255) NOT NULL DEFAULT '',
  `pic_fb_url` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`journalid`,`jitemid`),
  KEY `timecreate` (`timecreate`),
  KEY `journalid` (`journalid`)
)
EOC

# Map journals to categories
register_tablecreate('categoryjournals', <<'EOC');
CREATE TABLE `categoryjournals` (
  `catid` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`catid`,`journalid`),
  KEY `journalid` (`journalid`)
)
EOC

# Moderation of submissions for Community Directory
register_tablecreate('categoryjournals_pending', <<'EOC');
CREATE TABLE `categoryjournals_pending` (
  `pendid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `jid` int(10) unsigned NOT NULL DEFAULT '0',
  `submitid` int(10) unsigned DEFAULT NULL,
  `catid` int(10) unsigned NOT NULL,
  `status` char(1) DEFAULT NULL,
  `lastupdate` int(10) unsigned NOT NULL,
  `modid` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`pendid`),
  KEY `jid` (`jid`),
  KEY `catid` (`catid`)
)
EOC

# Extra properties for categories
register_tablecreate('categoryprop', <<'EOC');
CREATE TABLE `categoryprop` (
  `catid` int(10) unsigned NOT NULL,
  `propid` smallint(5) unsigned NOT NULL,
  `propval` varchar(255) NOT NULL,
  KEY `catid` (`catid`,`propid`)
)
EOC

# Property list for categories
register_tablecreate('categoryproplist', <<'EOC');
CREATE TABLE `categoryproplist` (
  `propid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
)
EOC

# Challenges table (for non-memcache support)
register_tablecreate('challenges', <<'EOC');
CREATE TABLE `challenges` (
  `ctime` int(10) unsigned NOT NULL DEFAULT '0',
  `challenge` char(80) NOT NULL DEFAULT '',
  `count` int(5) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`challenge`)
)
EOC

register_tablecreate('clients', <<'EOC');
CREATE TABLE `clients` (
  `clientid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `client` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`clientid`),
  KEY `client` (`client`)
)
EOC

register_tablecreate('clientusage', <<'EOC');
CREATE TABLE `clientusage` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `clientid` smallint(5) unsigned NOT NULL DEFAULT '0',
  `lastlogin` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`clientid`,`userid`),
  UNIQUE KEY `userid` (`userid`,`clientid`)
)
EOC

register_tablecreate('clustermove', <<'EOC');
CREATE TABLE `clustermove` (
  `cmid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL,
  `sclust` tinyint(3) unsigned NOT NULL,
  `dclust` tinyint(3) unsigned NOT NULL,
  `timestart` int(10) unsigned DEFAULT NULL,
  `timedone` int(10) unsigned DEFAULT NULL,
  `sdeleted` enum('1','0') DEFAULT NULL,
  PRIMARY KEY (`cmid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('clustermove_inprogress', <<'EOC');
CREATE TABLE `clustermove_inprogress` (
  `userid` int(10) unsigned NOT NULL,
  `locktime` int(10) unsigned NOT NULL,
  `dstclust` smallint(5) unsigned NOT NULL,
  `moverhost` int(10) unsigned NOT NULL,
  `moverport` smallint(5) unsigned NOT NULL,
  `moverinstance` char(22) NOT NULL,
  PRIMARY KEY (`userid`)
)
EOC

# tracking where users are active
register_tablecreate('clustertrack2', <<'EOC');
CREATE TABLE `clustertrack2` (
  `userid` int(10) unsigned NOT NULL,
  `timeactive` int(10) unsigned NOT NULL,
  `clusterid` smallint(5) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `timeactive` (`timeactive`,`clusterid`)
)
EOC

register_tablecreate('cmdbuffer', <<'EOC');
CREATE TABLE `cmdbuffer` (
  `cbid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `journalid` int(10) unsigned NOT NULL,
  `cmd` varchar(30) NOT NULL DEFAULT '',
  `instime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `args` text NOT NULL,
  PRIMARY KEY (`cbid`),
  KEY `cmd` (`cmd`),
  KEY `journalid` (`journalid`)
)
EOC

register_tablecreate('codes', <<'EOC');
CREATE TABLE `codes` (
  `type` varchar(10) NOT NULL DEFAULT '',
  `code` varchar(7) NOT NULL DEFAULT '',
  `item` varchar(80) DEFAULT NULL,
  `sortorder` smallint(6) NOT NULL DEFAULT '0',
  PRIMARY KEY (`type`,`code`)
) PACK_KEYS=1
EOC

register_tablecreate('comet_history', <<'EOC');
CREATE TABLE `comet_history` (
  `rec_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `uid` int(10) unsigned NOT NULL,
  `type` varchar(31) DEFAULT NULL,
  `message` text,
  `status` char(1) DEFAULT 'N',
  `added` datetime DEFAULT NULL,
  PRIMARY KEY (`rec_id`),
  KEY `uid` (`uid`)
)
EOC

register_tablecreate('comm_promo_list', <<'EOC');
CREATE TABLE `comm_promo_list` (
  `journalid` int(10) unsigned NOT NULL,
  `r_start` int(10) unsigned NOT NULL,
  `r_end` int(10) unsigned NOT NULL,
  KEY `r_start` (`r_start`)
)
EOC

register_tablecreate('commenturls', <<'EOC');
CREATE TABLE `commenturls` (
  `posterid` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `ip` varchar(15) DEFAULT NULL,
  `jtalkid` int(10) unsigned NOT NULL,
  `timecreate` int(10) unsigned NOT NULL,
  `url` varchar(255) NOT NULL,
  KEY `timecreate` (`timecreate`)
)
EOC

register_tablecreate('comminterests', <<'EOC');
CREATE TABLE `comminterests` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `intid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`intid`),
  KEY `intid` (`intid`)
)
EOC

register_tablecreate('community', <<'EOC');
CREATE TABLE `community` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `membership` enum('open','closed','moderated') NOT NULL DEFAULT 'open',
  `postlevel` enum('members','select','screened') DEFAULT NULL,
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('content_flag', <<'EOC');
CREATE TABLE `content_flag` (
  `flagid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `journalid` int(10) unsigned NOT NULL,
  `typeid` tinyint(3) unsigned NOT NULL,
  `itemid` int(10) unsigned DEFAULT NULL,
  `catid` tinyint(3) unsigned NOT NULL,
  `reporterid` int(10) unsigned NOT NULL,
  `reporteruniq` varchar(15) DEFAULT NULL,
  `instime` int(10) unsigned NOT NULL,
  `modtime` int(10) unsigned NOT NULL,
  `status` char(1) DEFAULT NULL,
  `supportid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`flagid`),
  KEY `journalid` (`journalid`,`typeid`,`itemid`),
  KEY `instime` (`instime`),
  KEY `reporterid` (`reporterid`),
  KEY `status` (`status`)
)
EOC

# user counters
register_tablecreate('counter', <<'EOC');
CREATE TABLE `counter` (
  `journalid` int(10) unsigned NOT NULL,
  `area` char(1) NOT NULL,
  `max` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`journalid`,`area`)
)
EOC

# contextual product prodding history, making sure we don't bug people when
# they don't want it anymore.
#
#   -- firstshowtime:  when it was first highlighted to them (not all the
#                      everything page)
#   -- recentshowtime: a recent showing time.  perhaps not THE most
#                      recent, though.
#   -- acktime:        time the user saw the box.  either by clicking
#                      next/no/more info.
#   -- nothankstime:   also a boolean:  time/if user doesn't want to
#                      see it again
#   -- clickthrutime:  time user clicked for more info
register_tablecreate('cprod', <<'EOC');
CREATE TABLE `cprod` (
  `userid` int(10) unsigned NOT NULL,
  `cprodid` smallint(5) unsigned NOT NULL,
  `firstshowtime` int(10) unsigned DEFAULT NULL,
  `recentshowtime` int(10) unsigned DEFAULT NULL,
  `acktime` int(10) unsigned DEFAULT NULL,
  `nothankstime` int(10) unsigned DEFAULT NULL,
  `clickthrutime` int(10) unsigned DEFAULT NULL,
  `clickthruver` smallint(5) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`,`cprodid`)
)
EOC

# global (contextual product prodding, "hey, you've never used polls, wanna
# learn how?")
register_tablecreate('cprodlist', <<'EOC');
CREATE TABLE `cprodlist` (
  `cprodid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `class` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`cprodid`),
  UNIQUE KEY `class` (`class`)
)
EOC

register_tablecreate('dbinfo', <<'EOC');
CREATE TABLE `dbinfo` (
  `dbid` tinyint(3) unsigned NOT NULL,
  `name` varchar(25) DEFAULT NULL,
  `fdsn` varchar(255) DEFAULT NULL,
  `rootfdsn` varchar(255) DEFAULT NULL,
  `masterid` tinyint(3) unsigned NOT NULL,
  PRIMARY KEY (`dbid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('dbweights', <<'EOC');
CREATE TABLE `dbweights` (
  `dbid` tinyint(3) unsigned NOT NULL,
  `role` varchar(25) NOT NULL,
  `norm` tinyint(3) unsigned NOT NULL,
  `curr` tinyint(3) unsigned NOT NULL,
  PRIMARY KEY (`dbid`,`role`)
)
EOC

register_tablecreate('debug_notifymethod', <<'EOC');
CREATE TABLE `debug_notifymethod` (
  `userid` int(10) unsigned NOT NULL,
  `subid` int(10) unsigned DEFAULT NULL,
  `ntfytime` int(10) unsigned DEFAULT NULL,
  `origntypeid` int(10) unsigned DEFAULT NULL,
  `etypeid` int(10) unsigned DEFAULT NULL,
  `ejournalid` int(10) unsigned DEFAULT NULL,
  `earg1` int(11) DEFAULT NULL,
  `earg2` int(11) DEFAULT NULL,
  `schjobid` varchar(50) DEFAULT NULL
)
EOC

# delayed post Storable object (all props/options)
register_tablecreate('delayedblob2', <<'EOC');
CREATE TABLE `delayedblob2` (
  `journalid` int(10) unsigned NOT NULL,
  `delayedid` int(10) unsigned NOT NULL,
  `request_stor` mediumblob,
  PRIMARY KEY (`journalid`,`delayedid`)
)
EOC

register_tablecreate('delayedlog2', <<'EOC');
CREATE TABLE `delayedlog2` (
  `journalid` int(10) unsigned NOT NULL,
  `delayedid` mediumint(8) unsigned NOT NULL,
  `posterid` int(10) unsigned NOT NULL,
  `subject` char(30) DEFAULT NULL,
  `logtime` datetime DEFAULT NULL,
  `posttime` datetime DEFAULT NULL,
  `security` enum('public','private','usemask') NOT NULL DEFAULT 'public',
  `allowmask` int(10) unsigned NOT NULL DEFAULT '0',
  `year` smallint(6) NOT NULL DEFAULT '0',
  `month` tinyint(4) NOT NULL DEFAULT '0',
  `day` tinyint(4) NOT NULL DEFAULT '0',
  `rlogtime` int(10) unsigned NOT NULL DEFAULT '0',
  `revptime` int(10) unsigned NOT NULL DEFAULT '0',
  `is_sticky` tinyint(1) NOT NULL,
  PRIMARY KEY (`journalid`,`delayedid`),
  KEY `journalid` (`journalid`,`logtime`,`posttime`,`year`,`month`,`day`),
  KEY `rlogtime` (`journalid`,`rlogtime`),
  KEY `revptime` (`journalid`,`revptime`)
)
EOC

register_tablecreate('dirmogsethandles', <<'EOC');
CREATE TABLE `dirmogsethandles` (
  `conskey` char(40) NOT NULL,
  `exptime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`conskey`),
  KEY `exptime` (`exptime`)
)
EOC

register_tablecreate('dirsearchres2', <<'EOC');
CREATE TABLE `dirsearchres2` (
  `qdigest` varchar(32) NOT NULL DEFAULT '',
  `dateins` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `userids` blob,
  PRIMARY KEY (`qdigest`),
  KEY `dateins` (`dateins`)
)
EOC

register_tablecreate('domains', <<'EOC');
CREATE TABLE `domains` (
  `domainid` int(10) unsigned NOT NULL auto_increment,
  `domain` varchar(80) NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `rcptid` int(10) unsigned NOT NULL,
  `type` char(5) default NULL,
  `name` char(80) default NULL,
  PRIMARY KEY  (`domainid`),
  KEY `userid` (`userid`),
  KEY `rcptid` (`userid`)
)
EOC

register_tablecreate('dudata', <<'EOC');
CREATE TABLE `dudata` (
  `userid` int(10) unsigned NOT NULL,
  `area` char(1) NOT NULL,
  `areaid` int(10) unsigned NOT NULL,
  `bytes` mediumint(8) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`area`,`areaid`)
)
EOC

register_tablecreate('duplock', <<'EOC');
CREATE TABLE `duplock` (
  `realm` enum('support','log','comment','payments') NOT NULL DEFAULT 'support',
  `reid` int(10) unsigned NOT NULL DEFAULT '0',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `digest` char(32) NOT NULL DEFAULT '',
  `dupid` int(10) unsigned NOT NULL DEFAULT '0',
  `instime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  KEY `realm` (`realm`,`reid`,`userid`)
)
EOC

register_tablecreate('email', <<'EOC');
CREATE TABLE `email` (
  `userid` int(10) unsigned NOT NULL,
  `email` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `email` (`email`)
)
EOC

register_tablecreate('email_status', <<'EOC');
CREATE TABLE `email_status` (
  `email` varchar(50) NOT NULL DEFAULT '',
  `first_error_time` int(10) unsigned NOT NULL,
  `last_error_time` int(10) unsigned NOT NULL,
  `error_count` tinyint(3) unsigned NOT NULL,
  `disabled` tinyint(3) unsigned NOT NULL,
  PRIMARY KEY (`email`),
  KEY `first_error_time` (`first_error_time`)
)
EOC

register_tablecreate('embedcontent', <<'EOC');
CREATE TABLE `embedcontent` (
  `userid` int(10) unsigned NOT NULL,
  `moduleid` int(10) unsigned NOT NULL,
  `content` text,
  PRIMARY KEY (`userid`,`moduleid`)
)
EOC

register_tablecreate('embedcontent_preview', <<'EOC');
CREATE TABLE `embedcontent_preview` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `moduleid` int(10) NOT NULL DEFAULT '0',
  `content` text,
  PRIMARY KEY (`userid`,`moduleid`)
)
EOC

register_tablecreate('eventrates', <<'EOC');
CREATE TABLE `eventrates` (
  `journalid` int(10) unsigned NOT NULL,
  `itemid` mediumint(8) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `changetime` datetime NOT NULL,
  PRIMARY KEY (`journalid`,`itemid`,`userid`)
)
EOC

register_tablecreate('eventratescounters', <<'EOC');
CREATE TABLE `eventratescounters` (
  `journalid` int(10) unsigned NOT NULL,
  `itemid` mediumint(8) unsigned NOT NULL,
  `count` int(10) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`itemid`)
)
EOC

register_tablecreate('eventtypelist', <<'EOC');
CREATE TABLE `eventtypelist` (
  `etypeid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `class` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`etypeid`),
  UNIQUE KEY `class` (`class`)
)
EOC

register_tablecreate('expunged_users', <<'EOC');
CREATE TABLE `expunged_users` (
  `userid` int(10) unsigned NOT NULL,
  `user` varchar(15) NOT NULL DEFAULT '',
  `expunge_time` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`user`),
  KEY `expunge_time` (`expunge_time`),
  KEY `userid` (`userid`)
)
EOC

# external user mappings
# note: extuser/extuserid are expected to sometimes be NULL, even
# though they are keyed.  (Null values are not taken into account when
# using indexes)
register_tablecreate('extuser', <<'EOC');
CREATE TABLE `extuser` (
  `userid` int(10) unsigned NOT NULL,
  `siteid` int(10) unsigned NOT NULL,
  `extuser` varchar(50) DEFAULT NULL,
  `extuserid` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  UNIQUE KEY `extuser` (`siteid`,`extuser`),
  UNIQUE KEY `extuserid` (`siteid`,`extuserid`)
)
EOC

register_tablecreate('faq', <<'EOC');
CREATE TABLE `faq` (
  `faqid` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `question` text,
  `summary` text,
  `answer` text,
  `sortorder` int(11) DEFAULT NULL,
  `faqcat` varchar(20) DEFAULT NULL,
  `uses` int(11) NOT NULL DEFAULT '0',
  `lastmodtime` datetime DEFAULT NULL,
  `lastmoduserid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`faqid`)
)
EOC

register_tablecreate('faqcat', <<'EOC');
CREATE TABLE `faqcat` (
  `faqcat` varchar(20) NOT NULL DEFAULT '',
  `faqcatname` varchar(100) DEFAULT NULL,
  `catorder` int(11) DEFAULT '50',
  PRIMARY KEY (`faqcat`)
)
EOC

register_tablecreate('faquses', <<'EOC');
CREATE TABLE `faquses` (
  `faqid` mediumint(8) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `dateview` datetime NOT NULL,
  PRIMARY KEY (`userid`,`faqid`),
  KEY `faqid` (`faqid`),
  KEY `dateview` (`dateview`)
)
EOC

register_tablecreate('friendgroup', <<'EOC');
CREATE TABLE `friendgroup` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `groupnum` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `groupname` varchar(60) NOT NULL,
  `sortorder` tinyint(3) unsigned NOT NULL DEFAULT '50',
  `is_public` enum('0','1') NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`groupnum`)
)
EOC

# friendgroup2 -- clustered friend groups
register_tablecreate('friendgroup2', <<'EOC');
CREATE TABLE `friendgroup2` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `groupnum` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `groupname` varchar(90) NOT NULL DEFAULT '',
  `sortorder` tinyint(3) unsigned NOT NULL DEFAULT '50',
  `is_public` enum('0','1') NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`groupnum`)
)
EOC

## Queue of delayed Befriending/Defriending events
register_tablecreate('friending_actions_q', <<'EOC');
CREATE TABLE `friending_actions_q` (
  `rec_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL,
  `friendid` int(10) unsigned NOT NULL,
  `action` char(1) DEFAULT NULL,
  `etime` int(11) DEFAULT NULL,
  `jobid` bigint(20) unsigned DEFAULT NULL,
  PRIMARY KEY (`rec_id`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('friends', <<'EOC');
CREATE TABLE `friends` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `friendid` int(10) unsigned NOT NULL DEFAULT '0',
  `fgcolor` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `bgcolor` mediumint(8) unsigned NOT NULL DEFAULT '16777215',
  `groupmask` int(10) unsigned NOT NULL DEFAULT '1',
  `showbydefault` enum('1','0') NOT NULL DEFAULT '1',
  PRIMARY KEY (`userid`,`friendid`),
  KEY `friendid` (`friendid`)
)
EOC

# partitioned:  ESN subscriptions:  flag on event target (a journal) saying
#               whether there are known listeners out there.
#
# verifytime is unixtime we last checked that this has_subs caching row
# is still accurate and people do in fact still subscribe to this.
# then maintenance tasks can background prune this table and fix
# up verifytimes.
register_tablecreate('has_subs', <<'EOC');
CREATE TABLE `has_subs` (
  `journalid` int(10) unsigned NOT NULL,
  `etypeid` int(10) unsigned NOT NULL,
  `arg1` int(10) unsigned NOT NULL,
  `arg2` int(10) unsigned NOT NULL,
  `verifytime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`etypeid`,`arg1`,`arg2`)
)
EOC

# external identities
#
#   idtype ::=
#      "O" - OpenID
#      "L" - LID (netmesh)
#      "T" - TypeKey
#       ?  - etc
register_tablecreate('identitymap', <<'EOC');
CREATE TABLE `identitymap` (
  `idtype` char(1) NOT NULL,
  `identity` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`idtype`,`identity`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('includetext', <<'EOC');
CREATE TABLE `includetext` (
  `incname` varchar(80) NOT NULL,
  `inctext` mediumtext,
  `updatetime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`incname`),
  KEY `updatetime` (`updatetime`)
)
EOC

register_tablecreate('incoming_email_handle', <<'EOC');
CREATE TABLE `incoming_email_handle` (
  `ieid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timerecv` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`ieid`)
)
EOC

register_tablecreate('infohistory', <<'EOC');
CREATE TABLE `infohistory` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `what` varchar(15) NOT NULL DEFAULT '',
  `timechange` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `oldvalue` varchar(255) DEFAULT NULL,
  `other` varchar(30) DEFAULT NULL,
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('interests', <<'EOC');
CREATE TABLE `interests` (
  `intid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `interest` varchar(255) NOT NULL DEFAULT '',
  `intcount` mediumint(8) unsigned DEFAULT NULL,
  PRIMARY KEY (`intid`),
  UNIQUE KEY `interest` (`interest`)
)
EOC

# inviterecv -- stores community invitations received
register_tablecreate('inviterecv', <<'EOC');
CREATE TABLE `inviterecv` (
  `userid` int(10) unsigned NOT NULL,
  `commid` int(10) unsigned NOT NULL,
  `maintid` int(10) unsigned NOT NULL,
  `recvtime` int(10) unsigned NOT NULL,
  `args` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`commid`)
)
EOC

# invitesent -- stores community invitations sent
register_tablecreate('invitesent', <<'EOC');
CREATE TABLE `invitesent` (
  `commid` int(10) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `maintid` int(10) unsigned NOT NULL,
  `recvtime` int(10) unsigned NOT NULL,
  `status` enum('accepted','rejected','outstanding') NOT NULL,
  `args` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`commid`,`userid`)
)
EOC

register_tablecreate('jabcluster', <<'EOC');
CREATE TABLE `jabcluster` (
  `clusterid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `address` varchar(255) NOT NULL,
  PRIMARY KEY (`clusterid`)
)
EOC

register_tablecreate('jablastseen', <<'EOC');
CREATE TABLE `jablastseen` (
  `userid` int(10) unsigned NOT NULL,
  `presence` blob,
  `time` int(10) unsigned NOT NULL,
  `motd_ver` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('jabpresence', <<'EOC');
CREATE TABLE `jabpresence` (
  `userid` int(10) unsigned NOT NULL,
  `reshash` char(22) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `resource` varchar(255) NOT NULL,
  `client` varchar(255) DEFAULT NULL,
  `clusterid` int(10) unsigned NOT NULL,
  `presence` blob,
  `flags` int(10) unsigned NOT NULL,
  `priority` int(10) unsigned DEFAULT NULL,
  `ctime` int(10) unsigned NOT NULL,
  `mtime` int(10) unsigned NOT NULL,
  `remoteip` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`reshash`)
)
EOC

register_tablecreate('jabroster', <<'EOC');
CREATE TABLE `jabroster` (
  `userid` int(10) unsigned NOT NULL,
  `contactid` int(10) unsigned NOT NULL,
  `name` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `substate` tinyint(3) unsigned NOT NULL,
  `groups` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `ljflags` tinyint(3) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`contactid`)
)
EOC

register_tablecreate('jobstatus', <<'EOC');
CREATE TABLE `jobstatus` (
  `handle` varchar(100) NOT NULL,
  `result` blob,
  `start_time` int(10) unsigned NOT NULL,
  `end_time` int(10) unsigned NOT NULL,
  `status` enum('running','success','error') DEFAULT NULL,
  `userid` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`handle`),
  KEY `end_time` (`end_time`)
)
EOC

register_tablecreate('keywords', <<'EOC');
CREATE TABLE `keywords` (
  `kwid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `keyword` varchar(80) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  PRIMARY KEY (`kwid`),
  UNIQUE KEY `kwidx` (`keyword`)
)
EOC

register_tablecreate('knob', <<'EOC');
CREATE TABLE `knob` (
  `knobname` varchar(255) NOT NULL,
  `val` tinyint(3) unsigned DEFAULT NULL,
  PRIMARY KEY (`knobname`)
)
EOC

register_tablecreate('links', <<'EOC');
CREATE TABLE `links` (
  `journalid` int(10) unsigned NOT NULL DEFAULT '0',
  `ordernum` tinyint(4) unsigned NOT NULL DEFAULT '0',
  `parentnum` tinyint(4) unsigned NOT NULL DEFAULT '0',
  `url` varchar(255) DEFAULT NULL,
  `title` varchar(255) NOT NULL DEFAULT '',
  KEY `journalid` (`journalid`)
)
EOC

register_tablecreate('log2', <<'EOC');
CREATE TABLE `log2` (
  `journalid` int(10) unsigned NOT NULL DEFAULT '0',
  `jitemid` mediumint(8) unsigned NOT NULL,
  `posterid` int(10) unsigned NOT NULL DEFAULT '0',
  `eventtime` datetime DEFAULT NULL,
  `logtime` datetime DEFAULT NULL,
  `compressed` char(1) NOT NULL DEFAULT 'N',
  `anum` tinyint(3) unsigned NOT NULL,
  `security` enum('public','private','usemask') NOT NULL DEFAULT 'public',
  `allowmask` int(10) unsigned NOT NULL DEFAULT '0',
  `replycount` smallint(5) unsigned DEFAULT NULL,
  `year` smallint(6) NOT NULL DEFAULT '0',
  `month` tinyint(4) NOT NULL DEFAULT '0',
  `day` tinyint(4) NOT NULL DEFAULT '0',
  `rlogtime` int(10) unsigned NOT NULL DEFAULT '0',
  `revttime` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`journalid`,`jitemid`),
  KEY `journalid` (`journalid`,`year`,`month`,`day`),
  KEY `rlogtime` (`journalid`,`rlogtime`),
  KEY `revttime` (`journalid`,`revttime`),
  KEY `posterid` (`posterid`,`journalid`)
)
EOC

register_tablecreate('loginlog', <<'EOC');
CREATE TABLE `loginlog` (
  `userid` int(10) unsigned NOT NULL,
  `logintime` int(10) unsigned NOT NULL,
  `sessid` mediumint(8) unsigned NOT NULL,
  `ip` varchar(15) DEFAULT NULL,
  `ua` varchar(100) DEFAULT NULL,
  KEY `userid` (`userid`,`logintime`)
)
EOC

register_tablecreate('loginstall', <<'EOC');
CREATE TABLE `loginstall` (
  `userid` int(10) unsigned NOT NULL,
  `ip` int(10) unsigned NOT NULL,
  `time` int(10) unsigned NOT NULL,
  UNIQUE KEY `userid` (`userid`,`ip`)
)
EOC

# summary counts for security on entry keywords
register_tablecreate('logkwsum', <<'EOC');
CREATE TABLE `logkwsum` (
  `journalid` int(10) unsigned NOT NULL,
  `kwid` int(10) unsigned NOT NULL,
  `security` int(10) unsigned NOT NULL,
  `entryct` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`journalid`,`kwid`,`security`),
  KEY `journalid` (`journalid`,`security`)
)
EOC

register_tablecreate('logprop2', <<'EOC');
CREATE TABLE `logprop2` (
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` mediumint(8) unsigned NOT NULL,
  `propid` tinyint(3) unsigned NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`jitemid`,`propid`)
)
EOC

register_tablecreate('logprop_history', <<'EOC');
CREATE TABLE `logprop_history` (
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` mediumint(8) unsigned NOT NULL,
  `propid` tinyint(3) unsigned NOT NULL,
  `change_time` int(10) unsigned NOT NULL DEFAULT '0',
  `old_value` varchar(255) DEFAULT NULL,
  `new_value` varchar(255) DEFAULT NULL,
  `note` varchar(255) DEFAULT NULL,
  KEY `journalid` (`journalid`,`jitemid`,`propid`)
)
EOC

register_tablecreate('logproplist', <<'EOC');
CREATE TABLE `logproplist` (
  `propid` tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `sortorder` mediumint(8) unsigned DEFAULT NULL,
  `datatype` enum('char','num','bool') NOT NULL DEFAULT 'char',
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('logsec2', <<'EOC');
CREATE TABLE `logsec2` (
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` mediumint(8) unsigned NOT NULL,
  `allowmask` int(10) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`jitemid`)
)
EOC

# mapping of tags applied to an entry
register_tablecreate('logtags', <<'EOC');
CREATE TABLE `logtags` (
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` mediumint(8) unsigned NOT NULL,
  `kwid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`jitemid`,`kwid`),
  KEY `journalid` (`journalid`,`kwid`)
)
EOC

# logtags but only for the most recent 100 tags-to-entry
register_tablecreate('logtagsrecent', <<'EOC');
CREATE TABLE `logtagsrecent` (
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` mediumint(8) unsigned NOT NULL,
  `kwid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`kwid`,`jitemid`)
)
EOC

register_tablecreate('logtext2', <<'EOC');
CREATE TABLE `logtext2` (
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` mediumint(8) unsigned NOT NULL,
  `subject` varchar(255) DEFAULT NULL,
  `event` text,
  PRIMARY KEY (`journalid`,`jitemid`)
) MAX_ROWS=100000000
EOC

register_tablecreate('meme', <<'EOC');
CREATE TABLE `meme` (
  `url` varchar(150) NOT NULL,
  `posterid` int(10) unsigned NOT NULL,
  `ts` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `journalid` int(10) unsigned NOT NULL,
  `itemid` int(10) unsigned NOT NULL,
  UNIQUE KEY `url` (`url`,`posterid`),
  KEY `ts` (`ts`)
)
EOC

register_tablecreate('memkeyword', <<'EOC');
CREATE TABLE `memkeyword` (
  `memid` int(10) unsigned NOT NULL DEFAULT '0',
  `kwid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`memid`,`kwid`)
)
EOC

# memkeyword2 -- clustered memory keyword map
register_tablecreate('memkeyword2', <<'EOC');
CREATE TABLE `memkeyword2` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `memid` int(10) unsigned NOT NULL DEFAULT '0',
  `kwid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`memid`,`kwid`),
  KEY `userid` (`userid`,`kwid`)
)
EOC

register_tablecreate('memorable', <<'EOC');
CREATE TABLE `memorable` (
  `memid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` int(10) unsigned NOT NULL,
  `des` varchar(150) NOT NULL,
  `security` enum('public','friends','private') NOT NULL DEFAULT 'public',
  PRIMARY KEY (`memid`),
  UNIQUE KEY `uniq` (`userid`,`journalid`,`jitemid`),
  KEY `item` (`journalid`,`jitemid`)
)
EOC

# memorable2 -- clustered memories
register_tablecreate('memorable2', <<'EOC');
CREATE TABLE `memorable2` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `memid` int(10) unsigned NOT NULL DEFAULT '0',
  `journalid` int(10) unsigned NOT NULL DEFAULT '0',
  `ditemid` int(10) unsigned NOT NULL DEFAULT '0',
  `des` varchar(150) DEFAULT NULL,
  `security` enum('public','friends','private') NOT NULL DEFAULT 'public',
  PRIMARY KEY (`userid`,`journalid`,`ditemid`),
  UNIQUE KEY `userid` (`userid`,`memid`)
)
EOC

register_tablecreate('ml_domains', <<'EOC');
CREATE TABLE `ml_domains` (
  `dmid` tinyint(3) unsigned NOT NULL,
  `type` varchar(30) NOT NULL,
  `args` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`dmid`),
  UNIQUE KEY `type` (`type`,`args`)
)
EOC

register_tablecreate('ml_items', <<'EOC');
CREATE TABLE `ml_items` (
  `dmid` tinyint(3) unsigned NOT NULL,
  `itid` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `itcode` varchar(80) NOT NULL,
  `notes` mediumtext,
  PRIMARY KEY (`dmid`,`itid`),
  UNIQUE KEY `dmid` (`dmid`,`itcode`)
)
EOC

register_tablecreate('ml_langdomains', <<'EOC');
CREATE TABLE `ml_langdomains` (
  `lnid` smallint(5) unsigned NOT NULL,
  `dmid` tinyint(3) unsigned NOT NULL,
  `dmmaster` enum('0','1') NOT NULL,
  `lastgetnew` datetime DEFAULT NULL,
  `lastpublish` datetime DEFAULT NULL,
  `countokay` smallint(5) unsigned NOT NULL,
  `counttotal` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`lnid`,`dmid`)
)
EOC

register_tablecreate('ml_langs', <<'EOC');
CREATE TABLE `ml_langs` (
  `lnid` smallint(5) unsigned NOT NULL,
  `lncode` varchar(16) NOT NULL,
  `lnname` varchar(60) NOT NULL,
  `parenttype` enum('diff','sim') NOT NULL,
  `parentlnid` smallint(5) unsigned NOT NULL,
  `lastupdate` datetime NOT NULL,
  UNIQUE KEY `lnid` (`lnid`),
  UNIQUE KEY `lncode` (`lncode`)
)
EOC

register_tablecreate('ml_latest', <<'EOC');
CREATE TABLE `ml_latest` (
  `lnid` smallint(5) unsigned NOT NULL,
  `dmid` tinyint(3) unsigned NOT NULL,
  `itid` smallint(5) unsigned NOT NULL,
  `txtid` int(10) unsigned NOT NULL,
  `chgtime` datetime NOT NULL,
  `staleness` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `revid` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`lnid`,`dmid`,`itid`),
  KEY `lnid` (`lnid`,`staleness`),
  KEY `dmid` (`dmid`,`itid`),
  KEY `lnid_2` (`lnid`,`dmid`,`chgtime`),
  KEY `chgtime` (`chgtime`)
)
EOC

register_tablecreate('ml_text', <<'EOC');
CREATE TABLE `ml_text` (
  `dmid` tinyint(3) unsigned NOT NULL,
  `txtid` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `lnid` smallint(5) unsigned NOT NULL,
  `itid` smallint(5) unsigned NOT NULL,
  `text` text NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`dmid`,`txtid`),
  KEY `lnid` (`lnid`,`dmid`,`itid`)
)
EOC

# moderated community post Storable object (all props/options)
register_tablecreate('modblob', <<'EOC');
CREATE TABLE `modblob` (
  `journalid` int(10) unsigned NOT NULL,
  `modid` int(10) unsigned NOT NULL,
  `request_stor` mediumblob,
  PRIMARY KEY (`journalid`,`modid`)
)
EOC

# moderated community post summary info
register_tablecreate('modlog', <<'EOC');
CREATE TABLE `modlog` (
  `journalid` int(10) unsigned NOT NULL,
  `modid` mediumint(8) unsigned NOT NULL,
  `posterid` int(10) unsigned NOT NULL,
  `subject` char(30) DEFAULT NULL,
  `logtime` datetime DEFAULT NULL,
  PRIMARY KEY (`journalid`,`modid`),
  KEY `journalid` (`journalid`,`logtime`)
)
EOC

register_tablecreate('moods', <<'EOC');
CREATE TABLE `moods` (
  `moodid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mood` varchar(40) DEFAULT NULL,
  `parentmood` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`moodid`),
  UNIQUE KEY `mood` (`mood`)
)
EOC

register_tablecreate('moodthemedata', <<'EOC');
CREATE TABLE `moodthemedata` (
  `moodthemeid` int(10) unsigned NOT NULL DEFAULT '0',
  `moodid` int(10) unsigned NOT NULL DEFAULT '0',
  `picurl` varchar(100) DEFAULT NULL,
  `width` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `height` tinyint(3) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`moodthemeid`,`moodid`)
)
EOC

register_tablecreate('moodthemes', <<'EOC');
CREATE TABLE `moodthemes` (
  `moodthemeid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `ownerid` int(10) unsigned NOT NULL DEFAULT '0',
  `name` varchar(50) DEFAULT NULL,
  `des` varchar(100) DEFAULT NULL,
  `is_public` enum('Y','N') NOT NULL DEFAULT 'N',
  PRIMARY KEY (`moodthemeid`),
  KEY `is_public` (`is_public`),
  KEY `ownerid` (`ownerid`)
)
EOC

# tag is lowercase UTF-8
# dest_type:dest is like:
#   PAGE:/partial/path/to/file.bml  (non-SSL)
#   SSL:/pay/foo.bml                (ssl partial path)
#   LJUSER:lj_nifty                 (link to local user account)
#   FAQ:234                         (link to FAQ #234)
register_tablecreate('navtag', <<'EOC');
CREATE TABLE `navtag` (
  `tag` varchar(128) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL,
  `dest_type` varchar(20) NOT NULL,
  `dest` varchar(255) NOT NULL,
  PRIMARY KEY (`tag`,`dest_type`,`dest`)
)
EOC

register_tablecreate('news_sent', <<'EOC');
CREATE TABLE `news_sent` (
  `newsid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `newsnum` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `user` varchar(15) NOT NULL DEFAULT '',
  `datesent` datetime DEFAULT NULL,
  `email` varchar(100) NOT NULL DEFAULT '',
  PRIMARY KEY (`newsid`),
  KEY `newsnum` (`newsnum`),
  KEY `user` (`user`),
  KEY `email` (`email`)
)
EOC

register_tablecreate('noderefs', <<'EOC');
CREATE TABLE `noderefs` (
  `nodetype` char(1) NOT NULL DEFAULT '',
  `nodeid` int(10) unsigned NOT NULL DEFAULT '0',
  `urlmd5` varchar(32) NOT NULL DEFAULT '',
  `url` varchar(120) NOT NULL DEFAULT '',
  PRIMARY KEY (`nodetype`,`nodeid`,`urlmd5`)
)
EOC

register_tablecreate('notifyarchive', <<'EOC');
CREATE TABLE `notifyarchive` (
  `userid` int(10) unsigned NOT NULL,
  `qid` int(10) unsigned NOT NULL,
  `createtime` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `etypeid` smallint(5) unsigned NOT NULL,
  `arg1` int(10) unsigned DEFAULT NULL,
  `arg2` int(10) unsigned DEFAULT NULL,
  `state` char(1) DEFAULT NULL,
  PRIMARY KEY (`userid`,`qid`),
  KEY `userid` (`userid`,`createtime`)
)
EOC

register_tablecreate('notifybookmarks', <<'EOC');
CREATE TABLE `notifybookmarks` (
  `userid` int(10) unsigned NOT NULL,
  `qid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`qid`)
)
EOC

# partitioned:  ESN event queue notification method
register_tablecreate('notifyqueue', <<'EOC');
CREATE TABLE `notifyqueue` (
  `userid` int(10) unsigned NOT NULL,
  `qid` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `etypeid` smallint(5) unsigned NOT NULL,
  `arg1` int(10) unsigned DEFAULT NULL,
  `arg2` int(10) unsigned DEFAULT NULL,
  `state` char(1) NOT NULL DEFAULT 'N',
  `createtime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`qid`),
  KEY `state` (`state`)
)
EOC

register_tablecreate('notifytypelist', <<'EOC');
CREATE TABLE `notifytypelist` (
  `ntypeid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `class` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`ntypeid`),
  UNIQUE KEY `class` (`class`)
)
EOC

register_tablecreate('oldids', <<'EOC');
CREATE TABLE `oldids` (
  `area` char(1) NOT NULL,
  `oldid` int(10) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `newid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`area`,`userid`,`newid`),
  UNIQUE KEY `area` (`area`,`oldid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('openid_endpoint', <<'EOC');
CREATE TABLE `openid_endpoint` (
  `endpoint_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `url` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `last_assert_time` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`endpoint_id`),
  UNIQUE KEY `url` (`url`),
  KEY `last_assert_time` (`last_assert_time`)
)
EOC

register_tablecreate('openid_external', <<'EOC');
CREATE TABLE `openid_external` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `url` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('openid_trust', <<'EOC');
CREATE TABLE `openid_trust` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `endpoint_id` int(10) unsigned NOT NULL DEFAULT '0',
  `trust_time` int(10) unsigned NOT NULL DEFAULT '0',
  `duration` enum('always','once') NOT NULL DEFAULT 'always',
  `last_assert_time` int(10) unsigned DEFAULT NULL,
  `flags` tinyint(3) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`,`endpoint_id`),
  KEY `endpoint_id` (`endpoint_id`)
)
EOC

# track open HTTP proxies
register_tablecreate('openproxy', <<'EOC');
CREATE TABLE `openproxy` (
  `addr` varchar(15) NOT NULL,
  `status` enum('proxy','clear') DEFAULT NULL,
  `asof` int(10) unsigned NOT NULL,
  `src` varchar(80) DEFAULT NULL,
  PRIMARY KEY (`addr`)
)
EOC

register_tablecreate('overrides', <<'EOC');
CREATE TABLE `overrides` (
  `user` varchar(15) NOT NULL DEFAULT '',
  `override` text,
  PRIMARY KEY (`user`)
)
EOC

# partialstats - stores calculation times:
#    jobname = 'calc_country'
#    clusterid = '1'
#    calctime = time()
register_tablecreate('partialstats', <<'EOC');
CREATE TABLE `partialstats` (
  `jobname` varchar(50) NOT NULL,
  `clusterid` mediumint(9) NOT NULL DEFAULT '0',
  `calctime` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`jobname`,`clusterid`)
)
EOC

# partialstatsdata - stores data per cluster:
#    statname = 'country'
#    arg = 'US'
#    clusterid = '1'
#    value = '500'
register_tablecreate('partialstatsdata', <<'EOC');
CREATE TABLE `partialstatsdata` (
  `statname` varchar(50) NOT NULL,
  `arg` varchar(50) NOT NULL,
  `clusterid` int(10) unsigned NOT NULL DEFAULT '0',
  `value` int(11) DEFAULT NULL,
  PRIMARY KEY (`statname`,`arg`,`clusterid`)
)
EOC

register_tablecreate('password', <<'EOC');
CREATE TABLE `password` (
  `userid` int(10) unsigned NOT NULL,
  `password` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('pendcomments', <<'EOC');
CREATE TABLE `pendcomments` (
  `jid` int(10) unsigned NOT NULL,
  `pendcid` int(10) unsigned NOT NULL,
  `data` blob NOT NULL,
  `datesubmit` int(10) unsigned NOT NULL,
  PRIMARY KEY (`pendcid`,`jid`),
  KEY `datesubmit` (`datesubmit`)
)
EOC

register_tablecreate('persistent_queue', <<'EOC');
CREATE TABLE `persistent_queue` (
  `qkey` varchar(255) NOT NULL,
  `idx` int(10) unsigned NOT NULL,
  `value` blob,
  PRIMARY KEY (`qkey`,`idx`)
)
EOC

# PingBack relations
register_tablecreate('pingrel', <<'EOC');
CREATE TABLE `pingrel` (
  `suid` int(10) unsigned NOT NULL,
  `sjid` int(10) unsigned NOT NULL,
  `tuid` int(10) unsigned NOT NULL,
  `tjid` int(10) unsigned NOT NULL,
  UNIQUE KEY `suid` (`suid`,`sjid`,`tuid`,`tjid`)
)
EOC

register_tablecreate('poll', <<'EOC');
CREATE TABLE `poll` (
  `pollid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `itemid` int(10) unsigned NOT NULL DEFAULT '0',
  `journalid` int(10) unsigned NOT NULL DEFAULT '0',
  `posterid` int(10) unsigned NOT NULL DEFAULT '0',
  `whovote` enum('all','friends') NOT NULL DEFAULT 'all',
  `whoview` enum('all','friends','none') NOT NULL DEFAULT 'all',
  `name` varchar(255) DEFAULT NULL,
  `status` char(1) DEFAULT NULL,
  PRIMARY KEY (`pollid`),
  KEY `itemid` (`itemid`),
  KEY `journalid` (`journalid`),
  KEY `posterid` (`posterid`),
  KEY `status` (`status`)
)
EOC

register_tablecreate('poll2', <<'EOC');
CREATE TABLE `poll2` (
  `journalid` int(10) unsigned NOT NULL,
  `pollid` int(10) unsigned NOT NULL,
  `posterid` int(10) unsigned NOT NULL,
  `ditemid` int(10) unsigned NOT NULL,
  `whovote` enum('all','friends','ofentry') NOT NULL DEFAULT 'all',
  `whoview` enum('all','friends','ofentry','none') NOT NULL DEFAULT 'all',
  `name` varchar(255) DEFAULT NULL,
  `status` char(1) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`pollid`),
  KEY `status` (`status`)
)
EOC

register_tablecreate('pollitem', <<'EOC');
CREATE TABLE `pollitem` (
  `pollid` int(10) unsigned NOT NULL DEFAULT '0',
  `pollqid` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `pollitid` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `sortorder` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `item` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`pollid`,`pollqid`,`pollitid`)
)
EOC

register_tablecreate('pollitem2', <<'EOC');
CREATE TABLE `pollitem2` (
  `journalid` int(10) unsigned NOT NULL,
  `pollid` int(10) unsigned NOT NULL,
  `pollqid` tinyint(3) unsigned NOT NULL,
  `pollitid` tinyint(3) unsigned NOT NULL,
  `sortorder` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `item` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`pollid`,`pollqid`,`pollitid`)
)
EOC

# global pollid -> userid map
register_tablecreate('pollowner', <<'EOC');
CREATE TABLE `pollowner` (
  `pollid` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`pollid`),
  KEY `journalid` (`journalid`)
)
EOC

register_tablecreate('pollprop2', <<'EOC');
CREATE TABLE `pollprop2` (
  `journalid` int(10) unsigned NOT NULL,
  `pollid` int(10) unsigned NOT NULL,
  `propid` smallint(5) unsigned NOT NULL,
  `propval` varchar(255) NOT NULL,
  PRIMARY KEY (`journalid`,`pollid`,`propid`)
)
EOC

register_tablecreate('pollproplist2', <<'EOC');
CREATE TABLE `pollproplist2` (
  `propid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('pollquestion', <<'EOC');
CREATE TABLE `pollquestion` (
  `pollid` int(10) unsigned NOT NULL DEFAULT '0',
  `pollqid` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `sortorder` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `type` enum('check','radio','drop','text','scale') DEFAULT NULL,
  `opts` varchar(20) DEFAULT NULL,
  `qtext` text,
  PRIMARY KEY (`pollid`,`pollqid`)
)
EOC

register_tablecreate('pollquestion2', <<'EOC');
CREATE TABLE `pollquestion2` (
  `journalid` int(10) unsigned NOT NULL,
  `pollid` int(10) unsigned NOT NULL,
  `pollqid` tinyint(3) unsigned NOT NULL,
  `sortorder` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `type` enum('check','radio','drop','text','scale') NOT NULL,
  `opts` varchar(20) DEFAULT NULL,
  `qtext` text,
  PRIMARY KEY (`journalid`,`pollid`,`pollqid`)
)
EOC

register_tablecreate('pollresult', <<'EOC');
CREATE TABLE `pollresult` (
  `pollid` int(10) unsigned NOT NULL DEFAULT '0',
  `pollqid` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`pollid`,`pollqid`,`userid`),
  KEY `pollid` (`pollid`,`userid`)
)
EOC

register_tablecreate('pollresult2', <<'EOC');
CREATE TABLE `pollresult2` (
  `journalid` int(10) unsigned NOT NULL,
  `pollid` int(10) unsigned NOT NULL,
  `pollqid` tinyint(3) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`pollid`,`pollqid`,`userid`),
  KEY `userid` (`userid`,`pollid`)
)
EOC

# aggregated results for all questions - answer_variant pairs and
# count of participants
# key may be: '<qid>:<itid>' or 'users'
register_tablecreate('pollresultaggregated2', <<'EOC');
CREATE TABLE `pollresultaggregated2` (
  `journalid` int(10) unsigned NOT NULL,
  `pollid` int(10) unsigned NOT NULL,
  `what` varchar(32) NOT NULL,
  `value` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`journalid`,`pollid`,`what`)
)
EOC

register_tablecreate('pollsubmission', <<'EOC');
CREATE TABLE `pollsubmission` (
  `pollid` int(10) unsigned NOT NULL DEFAULT '0',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `datesubmit` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`pollid`,`userid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('pollsubmission2', <<'EOC');
CREATE TABLE `pollsubmission2` (
  `journalid` int(10) unsigned NOT NULL,
  `pollid` int(10) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `datesubmit` datetime NOT NULL,
  PRIMARY KEY (`journalid`,`pollid`,`userid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('portal', <<'EOC');
CREATE TABLE `portal` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `loc` enum('left','main','right','moz') NOT NULL DEFAULT 'left',
  `pos` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `boxname` varchar(30) DEFAULT NULL,
  `boxargs` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`loc`,`pos`),
  KEY `boxname` (`boxname`)
)
EOC

register_tablecreate('portal_box_prop', <<'EOC');
CREATE TABLE `portal_box_prop` (
  `userid` int(10) unsigned NOT NULL,
  `pboxid` smallint(5) unsigned NOT NULL,
  `ppropid` smallint(5) unsigned NOT NULL,
  `propvalue` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  PRIMARY KEY (`userid`,`pboxid`,`ppropid`)
)
EOC

register_tablecreate('portal_config', <<'EOC');
CREATE TABLE `portal_config` (
  `userid` int(10) unsigned NOT NULL,
  `pboxid` smallint(5) unsigned NOT NULL,
  `col` char(1) DEFAULT NULL,
  `sortorder` smallint(5) unsigned NOT NULL,
  `type` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`pboxid`)
)
EOC

register_tablecreate('portal_typemap', <<'EOC');
CREATE TABLE `portal_typemap` (
  `id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `class_name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `class_name` (`class_name`)
)
EOC

register_tablecreate('priv_list', <<'EOC');
CREATE TABLE `priv_list` (
  `prlid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `privcode` varchar(20) NOT NULL DEFAULT '',
  `privname` varchar(40) DEFAULT NULL,
  `des` varchar(255) DEFAULT NULL,
  `is_public` enum('1','0') NOT NULL DEFAULT '1',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`prlid`),
  UNIQUE KEY `privcode` (`privcode`)
)
EOC

register_tablecreate('priv_map', <<'EOC');
CREATE TABLE `priv_map` (
  `prmid` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `prlid` smallint(5) unsigned NOT NULL DEFAULT '0',
  `arg` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`prmid`),
  KEY `userid` (`userid`),
  KEY `prlid` (`prlid`)
)
EOC

register_tablecreate('priv_packages', <<'EOC');
CREATE TABLE `priv_packages` (
  `pkgid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL DEFAULT '',
  `lastmoduserid` int(10) unsigned NOT NULL DEFAULT '0',
  `lastmodtime` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`pkgid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('priv_packages_content', <<'EOC');
CREATE TABLE `priv_packages_content` (
  `pkgid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `privname` varchar(20) NOT NULL,
  `privarg` varchar(40) NOT NULL DEFAULT '',
  PRIMARY KEY (`pkgid`,`privname`,`privarg`)
)
EOC

register_tablecreate('procnotify', <<'EOC');
CREATE TABLE `procnotify` (
  `nid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `cmd` varchar(50) DEFAULT NULL,
  `args` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`nid`)
)
EOC

register_tablecreate('qotd', <<'EOC');
CREATE TABLE `qotd` (
  `qid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `time_start` int(10) unsigned NOT NULL DEFAULT '0',
  `time_end` int(10) unsigned NOT NULL DEFAULT '0',
  `active` enum('Y','N') NOT NULL DEFAULT 'Y',
  `subject` varchar(255) NOT NULL DEFAULT '',
  `text` text NOT NULL,
  `tags` varchar(255) DEFAULT NULL,
  `from_user` char(15) DEFAULT NULL,
  `img_url` varchar(255) DEFAULT NULL,
  `extra_text` text,
  `cap_mask` smallint(5) unsigned NOT NULL,
  `show_logged_out` enum('Y','N') NOT NULL DEFAULT 'N',
  `countries` varchar(255) DEFAULT NULL,
  `link_url` varchar(255) NOT NULL DEFAULT '',
  `domain` varchar(255) NOT NULL DEFAULT 'homepage',
  `impression_url` varchar(255) DEFAULT NULL,
  `is_special` enum('Y','N') NOT NULL DEFAULT 'N',
  PRIMARY KEY (`qid`),
  KEY `time_start` (`time_start`),
  KEY `time_end` (`time_end`)
)
EOC

register_tablecreate('qotd_imported', <<'EOC');
CREATE TABLE `qotd_imported` (
  `qid` int(10) unsigned NOT NULL,
  `remote_id` int(10) unsigned NOT NULL,
  `provider` char(1) DEFAULT NULL,
  PRIMARY KEY (`qid`,`remote_id`)
)
EOC

register_tablecreate('random_user_set', <<'EOC');
CREATE TABLE `random_user_set` (
  `posttime` int(10) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`posttime`)
)
EOC

register_tablecreate('rateabuse', <<'EOC');
CREATE TABLE `rateabuse` (
  `rlid` tinyint(3) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `evttime` int(10) unsigned NOT NULL,
  `ip` int(10) unsigned NOT NULL,
  `enum` enum('soft','hard') NOT NULL,
  KEY `rlid` (`rlid`,`evttime`),
  KEY `userid` (`userid`),
  KEY `ip` (`ip`)
)
EOC

register_tablecreate('ratelist', <<'EOC');
CREATE TABLE `ratelist` (
  `rlid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  `des` varchar(255) NOT NULL,
  PRIMARY KEY (`rlid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('ratelog', <<'EOC');
CREATE TABLE `ratelog` (
  `userid` int(10) unsigned NOT NULL,
  `rlid` tinyint(3) unsigned NOT NULL,
  `evttime` int(10) unsigned NOT NULL,
  `ip` int(10) unsigned NOT NULL,
  `quantity` smallint(5) unsigned NOT NULL,
  KEY `userid` (`userid`,`rlid`,`evttime`)
)
EOC

register_tablecreate('readonly_user', <<'EOC');
CREATE TABLE `readonly_user` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('recentactions', <<'EOC');
CREATE TABLE `recentactions` (
  `what` varchar(20) NOT NULL
)
EOC

# relationship types:
# 'A' means targetid can administrate userid as a community maintainer
# 'B' means targetid is banned in userid
# 'P' means targetid can post to userid
# 'M' means targetid can moderate the community userid
# 'N' means targetid is preapproved to post to community userid w/o moderation
# 'I' means targetid invited userid to the site
# new types to be added here
register_tablecreate('reluser', <<'EOC');
CREATE TABLE `reluser` (
  `userid` int(10) unsigned NOT NULL,
  `targetid` int(10) unsigned NOT NULL,
  `type` char(1) NOT NULL,
  PRIMARY KEY (`userid`,`type`,`targetid`),
  KEY `targetid` (`targetid`,`type`)
)
EOC

# clustered relationship types are defined in ljlib.pl and ljlib-local.pl in
# the LJ::get_reluser_id function
register_tablecreate('reluser2', <<'EOC');
CREATE TABLE `reluser2` (
  `userid` int(10) unsigned NOT NULL,
  `type` smallint(5) unsigned NOT NULL,
  `targetid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`type`,`targetid`),
  KEY `userid` (`userid`,`targetid`)
)
EOC

register_tablecreate('s1overrides', <<'EOC');
CREATE TABLE `s1overrides` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `override` text NOT NULL,
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('s1style', <<'EOC');
CREATE TABLE `s1style` (
  `styleid` int(11) NOT NULL AUTO_INCREMENT,
  `userid` int(11) unsigned NOT NULL,
  `styledes` varchar(50) DEFAULT NULL,
  `type` varchar(10) NOT NULL DEFAULT '',
  `formatdata` text,
  `is_public` enum('Y','N') NOT NULL DEFAULT 'N',
  `is_embedded` enum('Y','N') NOT NULL DEFAULT 'N',
  `is_colorfree` enum('Y','N') NOT NULL DEFAULT 'N',
  `opt_cache` enum('Y','N') NOT NULL DEFAULT 'N',
  `has_ads` enum('Y','N') NOT NULL DEFAULT 'N',
  `lastupdate` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`styleid`),
  KEY `userid` (`userid`)
)
EOC

# cache Storable-frozen pre-cleaned style variables
register_tablecreate('s1stylecache', <<'EOC');
CREATE TABLE `s1stylecache` (
  `styleid` int(10) unsigned NOT NULL,
  `cleandate` datetime DEFAULT NULL,
  `type` varchar(10) NOT NULL DEFAULT '',
  `opt_cache` enum('Y','N') NOT NULL DEFAULT 'N',
  `vars_stor` blob,
  `vars_cleanver` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`styleid`)
)
EOC

register_tablecreate('s1stylemap', <<'EOC');
CREATE TABLE `s1stylemap` (
  `styleid` int(10) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`styleid`)
)
EOC

# caches Storable-frozen pre-cleaned overrides & colors
register_tablecreate('s1usercache', <<'EOC');
CREATE TABLE `s1usercache` (
  `userid` int(10) unsigned NOT NULL,
  `override_stor` blob,
  `override_cleanver` smallint(5) unsigned NOT NULL,
  `color_stor` blob,
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('s2checker', <<'EOC');
CREATE TABLE `s2checker` (
  `s2lid` int(10) unsigned NOT NULL,
  `checker` mediumblob,
  PRIMARY KEY (`s2lid`)
)
EOC

# the original global s2compiled table.  see s2compiled2 for new version.
register_tablecreate('s2compiled', <<'EOC');
CREATE TABLE `s2compiled` (
  `s2lid` int(10) unsigned NOT NULL,
  `comptime` int(10) unsigned NOT NULL,
  `compdata` mediumblob,
  PRIMARY KEY (`s2lid`)
)
EOC

# s2compiled2 is only for user S2 layers (not system) and is lazily
# migrated.  new saves go here.  loads try this table first (unless
# system) and if miss, then try the s2compiled table on the global.
register_tablecreate('s2compiled2', <<'EOC');
CREATE TABLE `s2compiled2` (
  `userid` int(10) unsigned NOT NULL,
  `s2lid` int(10) unsigned NOT NULL,
  `comptime` int(10) unsigned NOT NULL,
  `compdata` mediumblob,
  PRIMARY KEY (`userid`,`s2lid`)
)
EOC

register_tablecreate('s2info', <<'EOC');
CREATE TABLE `s2info` (
  `s2lid` int(10) unsigned NOT NULL,
  `infokey` varchar(80) NOT NULL,
  `value` varchar(255) NOT NULL,
  PRIMARY KEY (`s2lid`,`infokey`)
)
EOC

register_tablecreate('s2layers', <<'EOC');
CREATE TABLE `s2layers` (
  `s2lid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `b2lid` int(10) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `type` enum('core','i18nc','layout','theme','i18n','user') NOT NULL,
  PRIMARY KEY (`s2lid`),
  KEY `userid` (`userid`),
  KEY `b2lid` (`b2lid`,`type`)
)
EOC

register_tablecreate('s2source', <<'EOC');
CREATE TABLE `s2source` (
  `s2lid` int(10) unsigned NOT NULL,
  `s2code` mediumblob,
  PRIMARY KEY (`s2lid`)
)
EOC

register_tablecreate('s2source_inno', <<'EOC');
CREATE TABLE `s2source_inno` (
  `s2lid` int(10) unsigned NOT NULL,
  `s2code` mediumblob,
  PRIMARY KEY (`s2lid`)
)
EOC

register_tablecreate('s2stylelayers', <<'EOC');
CREATE TABLE `s2stylelayers` (
  `styleid` int(10) unsigned NOT NULL,
  `type` enum('core','i18nc','layout','theme','i18n','user') NOT NULL,
  `s2lid` int(10) unsigned NOT NULL,
  UNIQUE KEY `styleid` (`styleid`,`type`)
)
EOC

register_tablecreate('s2stylelayers2', <<'EOC');
CREATE TABLE `s2stylelayers2` (
  `userid` int(10) unsigned NOT NULL,
  `styleid` int(10) unsigned NOT NULL,
  `type` enum('core','i18nc','layout','theme','i18n','user') NOT NULL,
  `s2lid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`styleid`,`type`)
)
EOC

register_tablecreate('s2styles', <<'EOC');
CREATE TABLE `s2styles` (
  `styleid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `modtime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`styleid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('sch_error', <<'EOC');
CREATE TABLE `sch_error` (
  `error_time` int(10) unsigned NOT NULL,
  `jobid` bigint(20) unsigned NOT NULL,
  `message` varchar(255) NOT NULL,
  `funcid` int(10) unsigned NOT NULL DEFAULT '0',
  KEY `error_time` (`error_time`),
  KEY `jobid` (`jobid`),
  KEY `funcid` (`funcid`,`error_time`)
)
EOC

register_tablecreate('sch_exitstatus', <<'EOC');
CREATE TABLE `sch_exitstatus` (
  `jobid` bigint(20) unsigned NOT NULL,
  `status` smallint(5) unsigned DEFAULT NULL,
  `completion_time` int(10) unsigned DEFAULT NULL,
  `delete_after` int(10) unsigned DEFAULT NULL,
  `funcid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`jobid`),
  KEY `delete_after` (`delete_after`),
  KEY `funcid` (`funcid`)
)
EOC

register_tablecreate('sch_funcmap', <<'EOC');
CREATE TABLE `sch_funcmap` (
  `funcid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `funcname` varchar(255) NOT NULL,
  PRIMARY KEY (`funcid`),
  UNIQUE KEY `funcname` (`funcname`)
)
EOC

register_tablecreate('sch_job', <<'EOC');
CREATE TABLE `sch_job` (
  `jobid` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `funcid` int(10) unsigned NOT NULL,
  `arg` mediumblob,
  `uniqkey` varchar(255) DEFAULT NULL,
  `insert_time` int(10) unsigned DEFAULT NULL,
  `run_after` int(10) unsigned NOT NULL,
  `grabbed_until` int(10) unsigned DEFAULT NULL,
  `priority` smallint(5) unsigned DEFAULT NULL,
  `coalesce` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`jobid`),
  UNIQUE KEY `funcid_2` (`funcid`,`uniqkey`),
  KEY `funcid` (`funcid`,`run_after`),
  KEY `funcid_3` (`funcid`,`coalesce`)
)
EOC

register_tablecreate('sch_mass_error', <<'EOC');
CREATE TABLE `sch_mass_error` (
  `error_time` int(10) unsigned NOT NULL,
  `jobid` bigint(20) unsigned NOT NULL,
  `message` varchar(255) NOT NULL,
  KEY `error_time` (`error_time`),
  KEY `jobid` (`jobid`)
)
EOC

register_tablecreate('sch_mass_exitstatus', <<'EOC');
CREATE TABLE `sch_mass_exitstatus` (
  `jobid` bigint(20) unsigned NOT NULL,
  `status` smallint(5) unsigned DEFAULT NULL,
  `completion_time` int(10) unsigned DEFAULT NULL,
  `delete_after` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`jobid`),
  KEY `delete_after` (`delete_after`)
)
EOC

register_tablecreate('sch_mass_funcmap', <<'EOC');
CREATE TABLE `sch_mass_funcmap` (
  `funcid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `funcname` varchar(255) NOT NULL,
  PRIMARY KEY (`funcid`),
  UNIQUE KEY `funcname` (`funcname`)
)
EOC

register_tablecreate('sch_mass_job', <<'EOC');
CREATE TABLE `sch_mass_job` (
  `jobid` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `funcid` int(10) unsigned NOT NULL,
  `arg` mediumblob,
  `uniqkey` varchar(255) DEFAULT NULL,
  `insert_time` int(10) unsigned DEFAULT NULL,
  `run_after` int(10) unsigned NOT NULL,
  `grabbed_until` int(10) unsigned DEFAULT NULL,
  `priority` smallint(5) unsigned DEFAULT NULL,
  `coalesce` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`jobid`),
  UNIQUE KEY `funcid_2` (`funcid`,`uniqkey`),
  KEY `funcid` (`funcid`,`run_after`),
  KEY `funcid_3` (`funcid`,`coalesce`)
)
EOC

register_tablecreate('sch_mass_note', <<'EOC');
CREATE TABLE `sch_mass_note` (
  `jobid` bigint(20) unsigned NOT NULL,
  `notekey` varchar(255) NOT NULL DEFAULT '',
  `value` mediumblob,
  PRIMARY KEY (`jobid`,`notekey`)
)
EOC

register_tablecreate('sch_note', <<'EOC');
CREATE TABLE `sch_note` (
  `jobid` bigint(20) unsigned NOT NULL,
  `notekey` varchar(255) NOT NULL DEFAULT '',
  `value` mediumblob,
  PRIMARY KEY (`jobid`,`notekey`)
)
EOC

register_tablecreate('schemacols', <<'EOC');
CREATE TABLE `schemacols` (
  `tablename` varchar(40) NOT NULL DEFAULT '',
  `colname` varchar(40) NOT NULL DEFAULT '',
  `des` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`tablename`,`colname`)
)
EOC

register_tablecreate('schematables', <<'EOC');
CREATE TABLE `schematables` (
  `tablename` varchar(40) NOT NULL DEFAULT '',
  `public_browsable` enum('0','1') NOT NULL DEFAULT '0',
  `redist_mode` enum('off','insert','replace') NOT NULL DEFAULT 'off',
  `redist_where` varchar(255) DEFAULT NULL,
  `des` text,
  PRIMARY KEY (`tablename`)
)
EOC

register_tablecreate('schools', <<'EOC');
CREATE TABLE `schools` (
  `schoolid` int(10) unsigned NOT NULL DEFAULT '0',
  `name` varchar(200) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `country` varchar(4) NOT NULL DEFAULT '',
  `state` varchar(100) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `city` varchar(100) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`schoolid`),
  UNIQUE KEY `country` (`country`,`state`,`city`,`name`)
)
EOC

register_tablecreate('schools_attended', <<'EOC');
CREATE TABLE `schools_attended` (
  `schoolid` int(10) unsigned NOT NULL DEFAULT '0',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `year_start` smallint(5) unsigned DEFAULT NULL,
  `year_end` smallint(5) unsigned DEFAULT NULL,
  PRIMARY KEY (`schoolid`,`userid`)
)
EOC

register_tablecreate('schools_log', <<'EOC');
CREATE TABLE `schools_log` (
  `logid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `action` char(15) NOT NULL DEFAULT '',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `time` int(10) unsigned DEFAULT NULL,
  `schoolid1` int(10) unsigned NOT NULL DEFAULT '0',
  `name1` varchar(255) NOT NULL DEFAULT '',
  `country1` varchar(4) NOT NULL DEFAULT '',
  `state1` varchar(255) DEFAULT NULL,
  `city1` varchar(255) NOT NULL DEFAULT '',
  `url1` varchar(255) DEFAULT NULL,
  `schoolid2` int(10) unsigned NOT NULL DEFAULT '0',
  `name2` varchar(255) NOT NULL DEFAULT '',
  `country2` varchar(4) NOT NULL DEFAULT '',
  `state2` varchar(255) DEFAULT NULL,
  `city2` varchar(255) NOT NULL DEFAULT '',
  `url2` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`logid`),
  KEY `userid` (`userid`),
  KEY `schoolid1` (`schoolid1`),
  KEY `schoolid2` (`schoolid2`),
  KEY `time` (`time`,`action`)
)
EOC

register_tablecreate('schools_pending', <<'EOC');
CREATE TABLE `schools_pending` (
  `pendid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `name` varchar(255) NOT NULL DEFAULT '',
  `country` varchar(4) NOT NULL DEFAULT '',
  `state` varchar(255) DEFAULT NULL,
  `city` varchar(255) NOT NULL DEFAULT '',
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`pendid`),
  KEY `userid` (`userid`),
  KEY `country` (`country`)
)
EOC

register_tablecreate('schools_stats', <<'EOC');
CREATE TABLE `schools_stats` (
  `time` int(11) NOT NULL DEFAULT '0',
  `userid` int(11) NOT NULL DEFAULT '0',
  `action` char(15) NOT NULL DEFAULT '',
  `count_touches` int(11) NOT NULL DEFAULT '0',
  UNIQUE KEY `time` (`time`,`userid`,`action`)
)
EOC

# rotating site secret values
register_tablecreate('secrets', <<'EOC');
CREATE TABLE `secrets` (
  `stime` int(10) unsigned NOT NULL,
  `secret` char(32) NOT NULL,
  PRIMARY KEY (`stime`)
)
EOC

register_tablecreate('send_email_errors', <<'EOC');
CREATE TABLE `send_email_errors` (
  `email` varchar(50) NOT NULL DEFAULT '',
  `time` datetime DEFAULT NULL,
  `message` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`email`),
  KEY `time` (`time`)
)
EOC

# web sessions.  optionally tied to ips and with expiration times.
# whenever a session is okayed, expired ones are deleted, or ones
# created over 30 days ago.  a live session can't change email address
# or password.  digest authentication will be required for that,
# or javascript md5 challenge/response.
register_tablecreate('sessions', <<'EOC');
CREATE TABLE `sessions` (
  `userid` int(10) unsigned NOT NULL,
  `sessid` mediumint(8) unsigned NOT NULL,
  `auth` char(10) NOT NULL,
  `exptype` enum('short','long','once') NOT NULL,
  `timecreate` int(10) unsigned NOT NULL,
  `timeexpire` int(10) unsigned NOT NULL,
  `ipfixed` char(15) DEFAULT NULL,
  PRIMARY KEY (`userid`,`sessid`)
)
EOC

register_tablecreate('sessions_data', <<'EOC');
CREATE TABLE `sessions_data` (
  `userid` mediumint(8) unsigned NOT NULL,
  `sessid` mediumint(8) unsigned NOT NULL,
  `skey` varchar(30) NOT NULL,
  `sval` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`sessid`,`skey`)
)
EOC

register_tablecreate('site_messages', <<'EOC');
CREATE TABLE `site_messages` (
  `mid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `time_start` int(10) unsigned NOT NULL DEFAULT '0',
  `time_end` int(10) unsigned NOT NULL DEFAULT '0',
  `active` enum('Y','N') NOT NULL DEFAULT 'Y',
  `text` text NOT NULL,
  `countries` varchar(255) DEFAULT NULL,
  `accounts` smallint(5) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`mid`),
  KEY `time_start` (`time_start`),
  KEY `time_end` (`time_end`)
)
EOC

register_tablecreate('sms_msg', <<'EOC');
CREATE TABLE `sms_msg` (
  `userid` int(10) unsigned NOT NULL,
  `msgid` mediumint(8) unsigned NOT NULL,
  `timecreate` int(10) unsigned NOT NULL,
  `class_key` varchar(25) NOT NULL DEFAULT 'unknown',
  `type` enum('incoming','outgoing') DEFAULT NULL,
  `status` enum('success','error','ack_wait','unknown') NOT NULL DEFAULT 'unknown',
  `from_number` varchar(15) DEFAULT NULL,
  `to_number` varchar(15) DEFAULT NULL,
  PRIMARY KEY (`userid`,`msgid`),
  KEY `userid` (`userid`,`timecreate`),
  KEY `timecreate` (`timecreate`)
)
EOC

register_tablecreate('sms_msgack', <<'EOC');
CREATE TABLE `sms_msgack` (
  `userid` int(10) unsigned NOT NULL,
  `msgid` mediumint(8) unsigned NOT NULL,
  `type` enum('gateway','smsc','handset','unknown') DEFAULT NULL,
  `timerecv` int(10) unsigned NOT NULL,
  `status_flag` enum('success','error','unknown') DEFAULT NULL,
  `status_code` varchar(25) DEFAULT NULL,
  `status_text` varchar(255) NOT NULL,
  KEY `userid` (`userid`,`msgid`)
)
EOC

register_tablecreate('sms_msgerror', <<'EOC');
CREATE TABLE `sms_msgerror` (
  `userid` int(10) unsigned NOT NULL,
  `msgid` mediumint(8) unsigned NOT NULL,
  `error` text NOT NULL,
  PRIMARY KEY (`userid`,`msgid`)
)
EOC

register_tablecreate('sms_msgprop', <<'EOC');
CREATE TABLE `sms_msgprop` (
  `userid` int(10) unsigned NOT NULL,
  `msgid` mediumint(8) unsigned NOT NULL,
  `propid` smallint(5) unsigned NOT NULL,
  `propval` varchar(255) NOT NULL,
  PRIMARY KEY (`userid`,`msgid`,`propid`)
)
EOC

# unlike most other *proplist tables, this one is auto-populated by app
register_tablecreate('sms_msgproplist', <<'EOC');
CREATE TABLE `sms_msgproplist` (
  `propid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('sms_msgtext', <<'EOC');
CREATE TABLE `sms_msgtext` (
  `userid` int(10) unsigned NOT NULL,
  `msgid` mediumint(8) unsigned NOT NULL,
  `msg_raw` blob NOT NULL,
  `msg_decoded` blob NOT NULL,
  PRIMARY KEY (`userid`,`msgid`)
)
EOC

register_tablecreate('smsuniqmap', <<'EOC');
CREATE TABLE `smsuniqmap` (
  `msg_uniq` varchar(25) NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `msgid` mediumint(8) unsigned NOT NULL,
  PRIMARY KEY (`msg_uniq`)
)
EOC

register_tablecreate('smsusermap', <<'EOC');
CREATE TABLE `smsusermap` (
  `number` varchar(25) NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `verified` enum('Y','N') NOT NULL DEFAULT 'N',
  `instime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`number`),
  UNIQUE KEY `userid` (`userid`)
)
EOC

register_tablecreate('spamreports', <<'EOC');
CREATE TABLE `spamreports` (
  `srid` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `reporttime` int(10) unsigned NOT NULL,
  `posttime` int(10) unsigned NOT NULL,
  `state` enum('open','closed') NOT NULL DEFAULT 'open',
  `ip` varchar(15) DEFAULT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `posterid` int(10) unsigned NOT NULL DEFAULT '0',
  `report_type` enum('entry','comment','message') NOT NULL DEFAULT 'comment',
  `subject` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `body` blob NOT NULL,
  PRIMARY KEY (`srid`),
  KEY `ip` (`ip`),
  KEY `posterid` (`posterid`),
  KEY `reporttime` (`reporttime`,`journalid`)
)
EOC

register_tablecreate('stats', <<'EOC');
CREATE TABLE `stats` (
  `statcat` varchar(30) NOT NULL,
  `statkey` varchar(150) NOT NULL,
  `statval` int(10) unsigned NOT NULL,
  UNIQUE KEY `statcat_2` (`statcat`,`statkey`)
)
EOC

register_tablecreate('statushistory', <<'EOC');
CREATE TABLE `statushistory` (
  `userid` int(10) unsigned NOT NULL,
  `adminid` int(10) unsigned NOT NULL,
  `shtype` varchar(20) NOT NULL,
  `shdate` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `notes` text,
  KEY `userid` (`userid`,`shdate`),
  KEY `adminid` (`adminid`,`shdate`),
  KEY `adminid_2` (`adminid`,`shtype`,`shdate`),
  KEY `shtype` (`shtype`,`shdate`)
)
EOC

register_tablecreate('style', <<'EOC');
CREATE TABLE `style` (
  `styleid` int(11) NOT NULL AUTO_INCREMENT,
  `user` varchar(15) NOT NULL DEFAULT '',
  `styledes` varchar(50) DEFAULT NULL,
  `type` varchar(10) NOT NULL DEFAULT '',
  `formatdata` text,
  `is_public` enum('Y','N') NOT NULL DEFAULT 'N',
  `is_embedded` enum('Y','N') NOT NULL DEFAULT 'N',
  `is_colorfree` enum('Y','N') NOT NULL DEFAULT 'N',
  `opt_cache` enum('Y','N') NOT NULL DEFAULT 'N',
  `has_ads` enum('Y','N') NOT NULL DEFAULT 'N',
  `lastupdate` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`styleid`),
  KEY `user` (`user`),
  KEY `type` (`type`)
) PACK_KEYS=1
EOC

# partitioned:  ESN subscriptions:  details of a user's subscriptions
#  subid: alloc_user_counter
#  is_dirty:  either 1 (indexed) or NULL (not in index).  means we have
#             to go update the target's etypeid
#  userid is OWNER of the subscription,
#  journalid is the journal in which the event took place.
#  ntypeid is the notification type from notifytypelist
#  times are unixtimes
#  expiretime can be 0 to mean "never"
#  flags is a bitmask of flags, where:
#     bit 0 = is digest?  (off means live?)
#     rest undefined for now.
register_tablecreate('subs', <<'EOC');
CREATE TABLE `subs` (
  `userid` int(10) unsigned NOT NULL,
  `subid` int(10) unsigned NOT NULL,
  `is_dirty` tinyint(3) unsigned DEFAULT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `etypeid` smallint(5) unsigned NOT NULL,
  `arg1` int(10) unsigned NOT NULL,
  `arg2` int(10) unsigned NOT NULL,
  `ntypeid` smallint(5) unsigned NOT NULL,
  `createtime` int(10) unsigned NOT NULL,
  `expiretime` int(10) unsigned NOT NULL,
  `flags` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`subid`),
  KEY `is_dirty` (`is_dirty`),
  KEY `etypeid` (`etypeid`,`journalid`,`userid`)
)
EOC

# partitioned:  ESN subscriptions:  metadata on a user's subscriptions
register_tablecreate('subsprop', <<'EOC');
CREATE TABLE `subsprop` (
  `userid` int(10) unsigned NOT NULL,
  `subid` int(10) unsigned NOT NULL,
  `subpropid` smallint(5) unsigned NOT NULL,
  `value` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  PRIMARY KEY (`userid`,`subid`,`subpropid`)
)
EOC

# unlike other *proplist tables, this one is auto-populated by app
register_tablecreate('subsproplist', <<'EOC');
CREATE TABLE `subsproplist` (
  `subpropid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`subpropid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('support', <<'EOC');
CREATE TABLE `support` (
  `spid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `reqtype` enum('user','email') DEFAULT NULL,
  `requserid` int(10) unsigned NOT NULL DEFAULT '0',
  `reqname` varchar(50) DEFAULT NULL,
  `reqemail` varchar(70) DEFAULT NULL,
  `state` enum('open','closed') DEFAULT NULL,
  `authcode` varchar(15) NOT NULL DEFAULT '',
  `spcatid` int(10) unsigned NOT NULL DEFAULT '0',
  `subject` varchar(80) DEFAULT NULL,
  `timecreate` int(10) unsigned DEFAULT NULL,
  `timetouched` int(10) unsigned DEFAULT NULL,
  `timeclosed` int(10) unsigned DEFAULT NULL,
  `timelasthelp` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`spid`),
  KEY `state` (`state`),
  KEY `requserid` (`requserid`),
  KEY `reqemail` (`reqemail`)
)
EOC

register_tablecreate('support_answers', <<'EOC');
CREATE TABLE `support_answers` (
  `ansid` int(10) unsigned NOT NULL,
  `spcatid` int(10) unsigned NOT NULL,
  `lastmodtime` int(10) unsigned NOT NULL,
  `lastmoduserid` int(10) unsigned NOT NULL,
  `subject` varchar(255) DEFAULT NULL,
  `body` text,
  PRIMARY KEY (`ansid`),
  KEY `spcatid` (`spcatid`)
)
EOC

register_tablecreate('support_youreplied', <<'EOC');
CREATE TABLE `support_youreplied` (
  `userid` int(10) unsigned NOT NULL,
  `spid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`spid`)
)
EOC

register_tablecreate('supportcat', <<'EOC');
CREATE TABLE `supportcat` (
  `spcatid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `catkey` varchar(25) NOT NULL,
  `catname` varchar(80) DEFAULT NULL,
  `sortorder` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `basepoints` tinyint(3) unsigned NOT NULL DEFAULT '1',
  `is_selectable` enum('1','0') NOT NULL DEFAULT '1',
  `public_read` enum('1','0') NOT NULL DEFAULT '1',
  `public_help` enum('1','0') NOT NULL DEFAULT '1',
  `allow_screened` enum('1','0') NOT NULL DEFAULT '0',
  `hide_helpers` enum('1','0') NOT NULL DEFAULT '0',
  `user_closeable` enum('1','0') NOT NULL DEFAULT '1',
  `replyaddress` varchar(50) DEFAULT NULL,
  `no_autoreply` enum('1','0') NOT NULL DEFAULT '0',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`spcatid`),
  UNIQUE KEY `catkey` (`catkey`)
)
EOC

register_tablecreate('supportlog', <<'EOC');
CREATE TABLE `supportlog` (
  `splid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `spid` int(10) unsigned NOT NULL DEFAULT '0',
  `timelogged` int(10) unsigned NOT NULL DEFAULT '0',
  `type` enum('req','answer','comment','internal','screened') NOT NULL,
  `faqid` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `message` text,
  `tier` tinyint(3) unsigned DEFAULT NULL,
  PRIMARY KEY (`splid`),
  KEY `spid` (`spid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('supportnotify', <<'EOC');
CREATE TABLE `supportnotify` (
  `spcatid` int(10) unsigned NOT NULL DEFAULT '0',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `level` enum('all','new') DEFAULT NULL,
  PRIMARY KEY (`spcatid`,`userid`),
  KEY `spcatid` (`spcatid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('supportpoints', <<'EOC');
CREATE TABLE `supportpoints` (
  `spid` int(10) unsigned NOT NULL DEFAULT '0',
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `points` tinyint(3) unsigned DEFAULT NULL,
  KEY `spid` (`spid`),
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('supportpointsum', <<'EOC');
CREATE TABLE `supportpointsum` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `totpoints` mediumint(8) unsigned DEFAULT '0',
  `lastupdate` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`),
  KEY `totpoints` (`totpoints`,`lastupdate`),
  KEY `lastupdate` (`lastupdate`)
)
EOC

register_tablecreate('supportprop', <<'EOC');
CREATE TABLE `supportprop` (
  `spid` int(10) unsigned NOT NULL DEFAULT '0',
  `prop` varchar(30) NOT NULL,
  `value` varchar(255) NOT NULL,
  PRIMARY KEY (`spid`,`prop`)
)
EOC

# see also: LJ::Support::Request::Tag
register_tablecreate('supporttag', <<'EOC');
CREATE TABLE `supporttag` (
  `sptagid` int(11) NOT NULL AUTO_INCREMENT,
  `spcatid` int(11) NOT NULL DEFAULT '0',
  `name` char(50) NOT NULL DEFAULT '',
  PRIMARY KEY (`sptagid`),
  KEY `name` (`name`)
)
EOC

# see also: LJ::Support::Request::Tag
register_tablecreate('supporttagmap', <<'EOC');
CREATE TABLE `supporttagmap` (
  `sptagid` int(11) NOT NULL DEFAULT '0',
  `spid` int(11) NOT NULL DEFAULT '0',
  UNIQUE KEY `uniq` (`sptagid`,`spid`),
  KEY `sptagid` (`sptagid`),
  KEY `spid` (`spid`)
)
EOC

register_tablecreate('syndicated', <<'EOC');
CREATE TABLE `syndicated` (
  `userid` int(10) unsigned NOT NULL,
  `synurl` varchar(255) DEFAULT NULL,
  `checknext` datetime NOT NULL,
  `lastcheck` datetime DEFAULT NULL,
  `lastmod` int(10) unsigned DEFAULT NULL,
  `etag` varchar(80) DEFAULT NULL,
  `laststatus` varchar(80) DEFAULT NULL,
  `lastnew` datetime DEFAULT NULL,
  `oldest_ourdate` datetime DEFAULT NULL,
  `numreaders` mediumint(9) DEFAULT NULL,
  PRIMARY KEY (`userid`),
  UNIQUE KEY `synurl` (`synurl`),
  KEY `checknext` (`checknext`),
  KEY `numreaders` (`numreaders`)
)
EOC

register_tablecreate('synitem', <<'EOC');
CREATE TABLE `synitem` (
  `userid` int(10) unsigned NOT NULL,
  `item` char(22) DEFAULT NULL,
  `dateadd` datetime NOT NULL,
  KEY `userid` (`userid`,`item`(3)),
  KEY `userid_2` (`userid`,`dateadd`)
)
EOC

# what:  ip, email, ljuser, ua, emailnopay
# emailnopay means don't allow payments from that email
register_tablecreate('sysban', <<'EOC');
CREATE TABLE `sysban` (
  `banid` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `status` enum('active','expired') NOT NULL DEFAULT 'active',
  `bandate` datetime DEFAULT NULL,
  `banuntil` datetime DEFAULT NULL,
  `what` varchar(20) NOT NULL,
  `value` varchar(80) DEFAULT NULL,
  `note` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`banid`),
  KEY `status` (`status`)
)
EOC

register_tablecreate('talk2', <<'EOC');
CREATE TABLE `talk2` (
  `journalid` int(10) unsigned NOT NULL,
  `jtalkid` int(10) unsigned NOT NULL,
  `nodetype` char(1) NOT NULL DEFAULT '',
  `nodeid` int(10) unsigned NOT NULL DEFAULT '0',
  `parenttalkid` int(10) unsigned NOT NULL,
  `posterid` int(10) unsigned NOT NULL DEFAULT '0',
  `datepost` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `state` char(1) DEFAULT 'A',
  PRIMARY KEY (`journalid`,`jtalkid`),
  KEY `nodetype` (`nodetype`,`journalid`,`nodeid`),
  KEY `journalid` (`journalid`,`state`,`nodetype`),
  KEY `posterid` (`posterid`)
)
EOC

register_tablecreate('talkleft', <<'EOC');
CREATE TABLE `talkleft` (
  `userid` int(10) unsigned NOT NULL,
  `posttime` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `nodetype` char(1) NOT NULL,
  `nodeid` int(10) unsigned NOT NULL,
  `jtalkid` int(10) unsigned NOT NULL,
  `publicitem` enum('1','0') NOT NULL DEFAULT '1',
  KEY `userid` (`userid`,`posttime`),
  KEY `journalid` (`journalid`,`nodetype`,`nodeid`)
)
EOC

register_tablecreate('talkleft_xfp', <<'EOC');
CREATE TABLE `talkleft_xfp` (
  `userid` int(10) unsigned NOT NULL,
  `posttime` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `nodetype` char(1) NOT NULL,
  `nodeid` int(10) unsigned NOT NULL,
  `jtalkid` int(10) unsigned NOT NULL,
  `publicitem` enum('1','0') NOT NULL DEFAULT '1',
  KEY `userid` (`userid`,`posttime`),
  KEY `journalid` (`journalid`,`nodetype`,`nodeid`)
)
EOC

register_tablecreate('talkprop2', <<'EOC');
CREATE TABLE `talkprop2` (
  `journalid` int(10) unsigned NOT NULL,
  `jtalkid` int(10) unsigned NOT NULL,
  `tpropid` tinyint(3) unsigned NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`jtalkid`,`tpropid`)
)
EOC

register_tablecreate('talkproplist', <<'EOC');
CREATE TABLE `talkproplist` (
  `tpropid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `datatype` enum('char','num','bool') NOT NULL DEFAULT 'char',
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`tpropid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('talktext2', <<'EOC');
CREATE TABLE `talktext2` (
  `journalid` int(10) unsigned NOT NULL,
  `jtalkid` int(10) unsigned NOT NULL,
  `subject` varchar(100) DEFAULT NULL,
  `body` text,
  PRIMARY KEY (`journalid`,`jtalkid`)
) MAX_ROWS=100000000
EOC

register_tablecreate('tempanonips', <<'EOC');
CREATE TABLE `tempanonips` (
  `reporttime` int(10) unsigned NOT NULL,
  `ip` varchar(15) NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `jtalkid` mediumint(8) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`jtalkid`),
  KEY `reporttime` (`reporttime`)
)
EOC

register_tablecreate('themecustom', <<'EOC');
CREATE TABLE `themecustom` (
  `user` varchar(15) NOT NULL DEFAULT '',
  `coltype` varchar(30) DEFAULT NULL,
  `color` varchar(30) DEFAULT NULL,
  KEY `user` (`user`)
)
EOC

register_tablecreate('themedata', <<'EOC');
CREATE TABLE `themedata` (
  `themeid` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `coltype` varchar(30) NOT NULL,
  `color` varchar(30) DEFAULT NULL,
  UNIQUE KEY `thuniq` (`themeid`,`coltype`)
) PACK_KEYS=1
EOC

register_tablecreate('themelist', <<'EOC');
CREATE TABLE `themelist` (
  `themeid` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL DEFAULT '',
  PRIMARY KEY (`themeid`)
)
EOC

register_tablecreate('todo', <<'EOC');
CREATE TABLE `todo` (
  `todoid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `journalid` int(10) unsigned NOT NULL DEFAULT '0',
  `posterid` int(10) unsigned NOT NULL DEFAULT '0',
  `ownerid` int(10) unsigned NOT NULL DEFAULT '0',
  `statusline` varchar(40) DEFAULT NULL,
  `security` enum('public','private','friends') NOT NULL DEFAULT 'public',
  `subject` varchar(100) DEFAULT NULL,
  `des` varchar(255) DEFAULT NULL,
  `priority` enum('1','2','3','4','5') NOT NULL DEFAULT '3',
  `datecreate` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `dateupdate` datetime DEFAULT NULL,
  `datedue` datetime DEFAULT NULL,
  `dateclosed` datetime DEFAULT NULL,
  `progress` tinyint(3) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`todoid`),
  KEY `journalid` (`journalid`),
  KEY `posterid` (`posterid`),
  KEY `ownerid` (`ownerid`)
)
EOC

register_tablecreate('tododep', <<'EOC');
CREATE TABLE `tododep` (
  `todoid` int(10) unsigned NOT NULL DEFAULT '0',
  `depid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`todoid`,`depid`),
  KEY `depid` (`depid`)
)
EOC

register_tablecreate('todokeyword', <<'EOC');
CREATE TABLE `todokeyword` (
  `todoid` int(10) unsigned NOT NULL DEFAULT '0',
  `kwid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`todoid`,`kwid`)
)
EOC

register_tablecreate('txtmsg', <<'EOC');
CREATE TABLE `txtmsg` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `provider` varchar(25) DEFAULT NULL,
  `number` varchar(60) DEFAULT NULL,
  `security` enum('all','reg','friends') NOT NULL DEFAULT 'all',
  PRIMARY KEY (`userid`)
)
EOC

register_tablecreate('underage', <<'EOC');
CREATE TABLE `underage` (
  `uniq` char(15) NOT NULL,
  `timeof` int(10) NOT NULL,
  PRIMARY KEY (`uniq`),
  KEY `timeof` (`timeof`)
)
EOC

register_tablecreate('uniqmap', <<'EOC');
CREATE TABLE `uniqmap` (
  `uniq` varchar(15) NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `modtime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`uniq`),
  KEY `userid` (`userid`,`modtime`),
  KEY `uniq` (`uniq`,`modtime`)
)
EOC

register_tablecreate('urimap', <<'EOC');
CREATE TABLE `urimap` (
  `journalid` int(10) unsigned NOT NULL,
  `uri` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL,
  `nodetype` char(1) NOT NULL,
  `nodeid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`uri`),
  KEY `journalid` (`journalid`,`nodetype`,`nodeid`)
)
EOC

register_tablecreate('user', <<'EOC');
CREATE TABLE `user` (
  `userid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user` char(15) DEFAULT NULL,
  `caps` bigint(20) unsigned NOT NULL DEFAULT '0',
  `clusterid` tinyint(3) unsigned NOT NULL,
  `dversion` tinyint(3) unsigned NOT NULL,
  `packed_props` bigint(20) unsigned NOT NULL DEFAULT '0',
  `status` char(1) NOT NULL DEFAULT 'N',
  `statusvis` char(1) NOT NULL DEFAULT 'V',
  `statusvisdate` datetime DEFAULT NULL,
  `name` char(80) NOT NULL,
  `bdate` date DEFAULT NULL,
  `themeid` int(11) NOT NULL DEFAULT '1',
  `moodthemeid` int(10) unsigned NOT NULL DEFAULT '1',
  `opt_forcemoodtheme` enum('Y','N') NOT NULL DEFAULT 'N',
  `allow_infoshow` char(1) NOT NULL DEFAULT 'Y',
  `allow_contactshow` char(1) NOT NULL DEFAULT 'Y',
  `allow_getljnews` char(1) NOT NULL DEFAULT 'N',
  `opt_showtalklinks` char(1) NOT NULL DEFAULT 'Y',
  `opt_whocanreply` enum('all','reg','friends') NOT NULL DEFAULT 'all',
  `opt_gettalkemail` char(1) NOT NULL DEFAULT 'Y',
  `opt_htmlemail` enum('Y','N') NOT NULL DEFAULT 'Y',
  `opt_mangleemail` char(1) NOT NULL DEFAULT 'N',
  `useoverrides` char(1) NOT NULL DEFAULT 'N',
  `defaultpicid` int(10) unsigned DEFAULT NULL,
  `has_bio` enum('Y','N') NOT NULL DEFAULT 'N',
  `txtmsg_status` enum('none','on','off') NOT NULL DEFAULT 'none',
  `is_system` enum('Y','N') NOT NULL DEFAULT 'N',
  `journaltype` char(1) NOT NULL DEFAULT 'P',
  `lang` char(2) NOT NULL DEFAULT 'EN',
  `oldenc` tinyint(4) NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`),
  UNIQUE KEY `user` (`user`),
  KEY `status` (`status`),
  KEY `statusvis` (`statusvis`),
  KEY `idxcluster` (`clusterid`),
  KEY `idxversion` (`dversion`)
) PACK_KEYS=1
EOC

register_tablecreate('user_schools', <<'EOC');
CREATE TABLE `user_schools` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `schoolid` int(10) unsigned NOT NULL DEFAULT '0',
  `year_start` smallint(5) unsigned DEFAULT NULL,
  `year_end` smallint(5) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`,`schoolid`)
)
EOC

register_tablecreate('userbio', <<'EOC');
CREATE TABLE `userbio` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `bio` text,
  PRIMARY KEY (`userid`)
)
EOC

# - blobids aren't necessarily unique between domains;
# global userpicids may collide with the counter used for the rest.
# so type must be in the key.
# - domain ids are set up in ljconfig.pl.
# - NULL length indicates the data is external-- we need another
# table for more data for that.
register_tablecreate('userblob', <<'EOC');
CREATE TABLE `userblob` (
  `journalid` int(10) unsigned NOT NULL,
  `domain` tinyint(3) unsigned NOT NULL,
  `blobid` int(10) unsigned NOT NULL,
  `length` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`journalid`,`domain`,`blobid`),
  KEY `domain` (`domain`)
)
EOC

register_tablecreate('userblobcache', <<'EOC');
CREATE TABLE `userblobcache` (
  `userid` int(10) unsigned NOT NULL,
  `bckey` varchar(60) NOT NULL,
  `timeexpire` int(10) unsigned NOT NULL,
  `value` mediumblob,
  PRIMARY KEY (`userid`,`bckey`),
  KEY `timeexpire` (`timeexpire`)
)
EOC

# user counters on the global (contrary to the name)
register_tablecreate('usercounter', <<'EOC');
CREATE TABLE `usercounter` (
  `journalid` int(10) unsigned NOT NULL,
  `area` char(1) NOT NULL,
  `max` int(10) unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`area`)
)
EOC

register_tablecreate('useridmap', <<'EOC');
CREATE TABLE `useridmap` (
  `userid` int(10) unsigned NOT NULL,
  `user` char(15) NOT NULL,
  PRIMARY KEY (`userid`),
  UNIQUE KEY `user` (`user`)
)
EOC

register_tablecreate('userinterests', <<'EOC');
CREATE TABLE `userinterests` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `intid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`intid`),
  KEY `intid` (`intid`)
)
EOC

# userkeywords -- clustered keywords
register_tablecreate('userkeywords', <<'EOC');
CREATE TABLE `userkeywords` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `kwid` int(10) unsigned NOT NULL DEFAULT '0',
  `keyword` varchar(80) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL,
  PRIMARY KEY (`userid`,`kwid`),
  UNIQUE KEY `userid` (`userid`,`keyword`)
)
EOC

register_tablecreate('userlog', <<'EOC');
CREATE TABLE `userlog` (
  `userid` int(10) unsigned NOT NULL,
  `logtime` int(10) unsigned NOT NULL,
  `action` varchar(30) NOT NULL,
  `actiontarget` int(10) unsigned DEFAULT NULL,
  `remoteid` int(10) unsigned DEFAULT NULL,
  `ip` varchar(15) DEFAULT NULL,
  `uniq` varchar(15) DEFAULT NULL,
  `extra` varchar(255) DEFAULT NULL,
  KEY `userid` (`userid`)
)
EOC

register_tablecreate('usermsg', <<'EOC');
CREATE TABLE `usermsg` (
  `journalid` int(10) unsigned NOT NULL,
  `msgid` int(10) unsigned NOT NULL,
  `type` enum('in','out') NOT NULL,
  `parent_msgid` int(10) unsigned DEFAULT NULL,
  `otherid` int(10) unsigned NOT NULL,
  `timesent` int(10) unsigned DEFAULT NULL,
  `state` char(1) DEFAULT 'A',
  PRIMARY KEY (`journalid`,`msgid`),
  KEY `journalid` (`journalid`,`type`,`otherid`),
  KEY `journalid_2` (`journalid`,`timesent`)
)
EOC

register_tablecreate('usermsgprop', <<'EOC');
CREATE TABLE `usermsgprop` (
  `journalid` int(10) unsigned NOT NULL,
  `msgid` int(10) unsigned NOT NULL,
  `propid` smallint(5) unsigned NOT NULL,
  `propval` varchar(255) NOT NULL,
  PRIMARY KEY (`journalid`,`msgid`,`propid`)
)
EOC

register_tablecreate('usermsgproplist', <<'EOC');
CREATE TABLE `usermsgproplist` (
  `propid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate('usermsgtext', <<'EOC');
CREATE TABLE `usermsgtext` (
  `journalid` int(10) unsigned NOT NULL,
  `msgid` int(10) unsigned NOT NULL,
  `subject` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `body` blob NOT NULL,
  PRIMARY KEY (`journalid`,`msgid`)
)
EOC

register_tablecreate('userpic', <<'EOC');
CREATE TABLE `userpic` (
  `picid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `contenttype` char(25) DEFAULT NULL,
  `width` smallint(6) NOT NULL DEFAULT '0',
  `height` smallint(6) NOT NULL DEFAULT '0',
  `state` char(1) NOT NULL DEFAULT 'N',
  `picdate` datetime DEFAULT NULL,
  `md5base64` char(22) NOT NULL DEFAULT '',
  PRIMARY KEY (`picid`),
  KEY `userid` (`userid`),
  KEY `state` (`state`)
)
EOC

register_tablecreate('userpic2', <<'EOC');
CREATE TABLE `userpic2` (
  `picid` int(10) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `fmt` char(1) DEFAULT NULL,
  `width` smallint(6) NOT NULL DEFAULT '0',
  `height` smallint(6) NOT NULL DEFAULT '0',
  `state` char(1) NOT NULL DEFAULT 'N',
  `picdate` datetime DEFAULT NULL,
  `md5base64` char(22) NOT NULL DEFAULT '',
  `comment` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `flags` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `location` enum('blob','disk','mogile') DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`picid`)
)
EOC

register_tablecreate('userpicblob2', <<'EOC');
CREATE TABLE `userpicblob2` (
  `userid` int(10) unsigned NOT NULL,
  `picid` int(10) unsigned NOT NULL,
  `imagedata` blob,
  PRIMARY KEY (`userid`,`picid`)
) MAX_ROWS=10000000
EOC

register_tablecreate('userpicmap', <<'EOC');
CREATE TABLE `userpicmap` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `kwid` int(10) unsigned NOT NULL DEFAULT '0',
  `picid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`kwid`)
)
EOC

register_tablecreate('userpicmap2', <<'EOC');
CREATE TABLE `userpicmap2` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `kwid` int(10) unsigned NOT NULL DEFAULT '0',
  `picid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`kwid`)
)
EOC

# global, indexed
register_tablecreate('userprop', <<'EOC');
CREATE TABLE `userprop` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `upropid` smallint(5) unsigned NOT NULL DEFAULT '0',
  `value` varchar(60) DEFAULT NULL,
  PRIMARY KEY (`userid`,`upropid`),
  KEY `upropid` (`upropid`,`value`)
)
EOC

register_tablecreate('userpropblob', <<'EOC');
CREATE TABLE `userpropblob` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `upropid` smallint(5) unsigned NOT NULL DEFAULT '0',
  `value` blob,
  PRIMARY KEY (`userid`,`upropid`)
)
EOC

register_tablecreate('userproplist', <<'EOC');
CREATE TABLE `userproplist` (
  `upropid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `indexed` enum('1','0') NOT NULL DEFAULT '1',
  `cldversion` tinyint(3) unsigned NOT NULL,
  `multihomed` enum('1','0') NOT NULL DEFAULT '0',
  `prettyname` varchar(60) DEFAULT NULL,
  `datatype` enum('char','num','bool','blobchar') NOT NULL DEFAULT 'char',
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`upropid`),
  UNIQUE KEY `name` (`name`)
)
EOC

# global, not indexed
register_tablecreate('userproplite', <<'EOC');
CREATE TABLE `userproplite` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `upropid` smallint(5) unsigned NOT NULL DEFAULT '0',
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`upropid`),
  KEY `upropid` (`upropid`)
)
EOC

# clustered, not indexed
register_tablecreate('userproplite2', <<'EOC');
CREATE TABLE `userproplite2` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `upropid` smallint(5) unsigned NOT NULL DEFAULT '0',
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`upropid`),
  KEY `upropid` (`upropid`)
)
EOC

register_tablecreate('usersearch_packdata', <<'EOC');
CREATE TABLE `usersearch_packdata` (
  `userid` int(10) unsigned NOT NULL,
  `packed` char(8) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `mtime` int(10) unsigned NOT NULL,
  `good_until` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `mtime` (`mtime`),
  KEY `good_until` (`good_until`)
)
EOC

# table showing what tags a user has; parentkwid can be null
register_tablecreate('usertags', <<'EOC');
CREATE TABLE `usertags` (
  `journalid` int(10) unsigned NOT NULL,
  `kwid` int(10) unsigned NOT NULL,
  `parentkwid` int(10) unsigned DEFAULT NULL,
  `display` enum('0','1') NOT NULL DEFAULT '1',
  PRIMARY KEY (`journalid`,`kwid`)
)
EOC

register_tablecreate('usertrans', <<'EOC');
CREATE TABLE `usertrans` (
  `userid` int(10) unsigned NOT NULL DEFAULT '0',
  `time` int(10) unsigned NOT NULL DEFAULT '0',
  `what` varchar(25) NOT NULL DEFAULT '',
  `before` varchar(25) NOT NULL DEFAULT '',
  `after` varchar(25) NOT NULL DEFAULT '',
  KEY `userid` (`userid`),
  KEY `time` (`time`)
)
EOC

register_tablecreate('userusage', <<'EOC');
CREATE TABLE `userusage` (
  `userid` int(10) unsigned NOT NULL,
  `timecreate` datetime NOT NULL,
  `timeupdate` datetime DEFAULT NULL,
  `timecheck` datetime DEFAULT NULL,
  `lastitemid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`),
  KEY `timeupdate` (`timeupdate`)
)
EOC

register_tablecreate('vertical', <<'EOC');
CREATE TABLE `vertical` (
  `vertid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `createtime` int(10) unsigned NOT NULL,
  `lastfetch` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`vertid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=latin1
EOC

register_tablecreate('vertical2', <<'EOC');
CREATE TABLE `vertical2` (
  `vert_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `url` varchar(20) NOT NULL,
  `name` varchar(50) NOT NULL,
  `createtime` int(10) unsigned NOT NULL DEFAULT '0',
  `journal` varchar(16) DEFAULT '',
  `show_entries` int(11) NOT NULL,
  `not_deleted` int(11) NOT NULL,
  `remove_after` int(11) NOT NULL,
  PRIMARY KEY (`vert_id`)
)
EOC

register_tablecreate('vertical_comms', <<'EOC');
CREATE TABLE `vertical_comms` (
  `vert_id` int(11) NOT NULL,
  `journalid` int(11) NOT NULL,
  `timecreate` datetime NOT NULL,
  `timeadded` datetime NOT NULL,
  `is_deleted` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`vert_id`,`journalid`),
  KEY `journalid` (`journalid`),
  KEY `timecreate` (`timecreate`)
)
EOC

register_tablecreate('vertical_editorials', <<'EOC');
CREATE TABLE `vertical_editorials` (
  `edid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vertid` int(10) unsigned NOT NULL DEFAULT '0',
  `adminid` int(10) unsigned NOT NULL DEFAULT '0',
  `time_start` int(10) unsigned NOT NULL DEFAULT '0',
  `time_end` int(10) unsigned NOT NULL DEFAULT '0',
  `title` varchar(255) NOT NULL DEFAULT '',
  `editor` varchar(255) DEFAULT NULL,
  `img_url` text,
  `img_width` int(5) unsigned DEFAULT NULL,
  `img_height` int(5) unsigned DEFAULT NULL,
  `img_link_url` varchar(255) DEFAULT NULL,
  `submitter` varchar(255) DEFAULT NULL,
  `block_1_title` varchar(255) NOT NULL DEFAULT '',
  `block_1_text` text NOT NULL,
  `block_2_title` varchar(255) DEFAULT NULL,
  `block_2_text` text,
  `block_3_title` varchar(255) DEFAULT NULL,
  `block_3_text` text,
  `block_4_title` varchar(255) DEFAULT NULL,
  `block_4_text` text,
  PRIMARY KEY (`edid`),
  KEY `vertid` (`vertid`),
  KEY `time_start` (`time_start`),
  KEY `time_end` (`time_end`)
)
EOC

register_tablecreate('vertical_entries', <<'EOC');
CREATE TABLE `vertical_entries` (
  `vertid` int(10) unsigned NOT NULL,
  `instime` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` int(10) unsigned NOT NULL,
  PRIMARY KEY (`vertid`,`journalid`,`jitemid`),
  KEY `vertid` (`vertid`,`instime`)
)
EOC

register_tablecreate('vertical_keymap', <<'EOC');
CREATE TABLE `vertical_keymap` (
  `journalid` int(11) NOT NULL,
  `jitemid` int(11) NOT NULL,
  `vert_id` int(11) NOT NULL,
  `kw_id` int(11) NOT NULL,
  PRIMARY KEY (`journalid`,`jitemid`,`vert_id`,`kw_id`),
  KEY `kw_id` (`kw_id`),
  KEY `vert_id` (`vert_id`)
)
EOC

register_tablecreate('vertical_keywords', <<'EOC');
CREATE TABLE `vertical_keywords` (
  `keyword` varchar(80) NOT NULL,
  `kw_id` int(11) NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`kw_id`),
  UNIQUE KEY `keyword` (`keyword`)
)
EOC

register_tablecreate('vertical_posts', <<'EOC');
CREATE TABLE `vertical_posts` (
  `vert_id` int(10) unsigned NOT NULL,
  `journalid` int(10) unsigned NOT NULL,
  `jitemid` int(10) unsigned NOT NULL,
  `timecreate` datetime NOT NULL,
  `timeadded` datetime NOT NULL,
  `is_deleted` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`journalid`,`jitemid`),
  KEY `timecreate` (`timecreate`),
  KEY `journalid` (`journalid`),
  KEY `vert_id` (`vert_id`)
)
EOC

register_tablecreate('vertical_rules', <<'EOC');
CREATE TABLE `vertical_rules` (
  `vertid` int(10) unsigned NOT NULL,
  `rules` blob,
  PRIMARY KEY (`vertid`)
)
EOC

# wknum - number of weeks past unix epoch time
# ubefore - units before next week (unit = 10 seconds)
# uafter - units after this week (unit = 10 seconds)
register_tablecreate('weekuserusage', <<'EOC');
CREATE TABLE `weekuserusage` (
  `wknum` smallint(5) unsigned NOT NULL,
  `userid` int(10) unsigned NOT NULL,
  `ubefore` smallint(5) unsigned NOT NULL,
  `uafter` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`wknum`,`userid`)
)
EOC

register_tablecreate('zip', <<'EOC');
CREATE TABLE `zip` (
  `zip` varchar(5) NOT NULL DEFAULT '',
  `state` char(2) NOT NULL DEFAULT '',
  `city` varchar(100) NOT NULL DEFAULT '',
  PRIMARY KEY (`zip`),
  KEY `state` (`state`)
) PACK_KEYS=1
EOC

register_tablecreate('zips', <<'EOC');
CREATE TABLE `zips` (
  `FIPS` char(2) DEFAULT NULL,
  `zip` varchar(5) NOT NULL DEFAULT '',
  `State` char(2) NOT NULL DEFAULT '',
  `Name` varchar(30) NOT NULL DEFAULT '',
  `alloc` float(9,7) NOT NULL DEFAULT '0.0000000',
  `pop1990` int(11) NOT NULL DEFAULT '0',
  `lon` float(10,7) NOT NULL DEFAULT '0.0000000',
  `lat` float(10,7) NOT NULL DEFAULT '0.0000000',
  PRIMARY KEY (`zip`)
)
EOC

register_tablecreate('repost2', <<'EOC');
CREATE TABLE `repost2` (
    `journalid` int(10) NOT NULL,
    `jitemid` int(11) NOT NULL,
    `reposterid` int(10) NOT NULL,
    `reposted_jitemid` int(11) NOT NULL,
    PRIMARY KEY ( `journalid`, `reposterid`, `jitemid` ),
    KEY `jitemid` ( `journalid`, `jitemid` )
)
EOC

post_create("clients",
            "sqltry" => "INSERT INTO clients (client) SELECT DISTINCT client FROM logins",
            );

post_create("clientusage",
            "sqltry" => "INSERT INTO clientusage SELECT u.userid, c.clientid, l.lastlogin FROM user u, clients c, logins l WHERE u.user=l.user AND l.client=c.client",
            );

post_create("supportpointsum",
            "sqltry" => "INSERT IGNORE INTO supportpointsum (userid, totpoints, lastupdate) " .
            "SELECT userid, SUM(points), 0 FROM supportpoints GROUP BY userid",
            );


post_create("useridmap",
            "sqltry" => "REPLACE INTO useridmap (userid, user) SELECT userid, user FROM user",
            );

post_create("userusage",
            "sqltry" => "INSERT IGNORE INTO userusage (userid, timecreate, timeupdate, timecheck, lastitemid) SELECT userid, timecreate, timeupdate, timecheck, lastitemid FROM user",
            "sqltry" => "ALTER TABLE user DROP timecreate, DROP timeupdate, DROP timecheck, DROP lastitemid",
            );

post_create("reluser",
            "sqltry" => "INSERT IGNORE INTO reluser (userid, targetid, type) SELECT userid, banneduserid, 'B' FROM ban",
            "sqltry" => "INSERT IGNORE INTO reluser (userid, targetid, type) SELECT u.userid, p.userid, 'A' FROM priv_map p, priv_list l, user u WHERE l.privcode='sharedjournal' AND l.prlid=p.prlid AND p.arg=u.user AND p.arg<>'all'",
            "code" => sub {

                # logaccess has been dead for a long time.  In fact, its table
                # definition has been removed from this file.  No need to try
                # and upgrade if the source table doesn't even exist.
                unless (column_type('logaccess', 'userid')) {
                    print "# No logaccess source table found, skipping...\n";
                    return;
                }

                my $dbh = shift;
                print "# Converting logaccess rows to reluser...\n";
                my $sth = $dbh->prepare("SELECT MAX(userid) FROM user");
                $sth->execute;
                my ($maxid) = $sth->fetchrow_array;
                return unless $maxid;

                my $from = 1; my $to = $from + 10000 - 1;
                while ($from <= $maxid) {
                    printf "#  logaccess status: (%0.1f%%)\n", ($from * 100 / $maxid);
                    do_sql("INSERT IGNORE INTO reluser (userid, targetid, type) ".
                           "SELECT ownerid, posterid, 'P' ".
                           "FROM logaccess ".
                           "WHERE ownerid BETWEEN $from AND $to");
                    $from += 10000;
                    $to += 10000;
                }
                print "# Finished converting logaccess.\n";
            },
            );

post_create("comminterests",
            "code" => sub {
                my $dbh = shift;
                print "# Populating community interests...\n";

                my $BLOCK = 1_000;

                my @ids = @{ $dbh->selectcol_arrayref("SELECT userid FROM community") || [] };
                my $total = @ids;

                while (@ids) {
                    my @set = grep { $_ } splice(@ids, 0, $BLOCK);

                    printf ("# community interests status: (%0.1f%%)\n",
                            ((($total - @ids) / $total) * 100)) if $total > $BLOCK;

                    local $" = ",";
                    do_sql("INSERT IGNORE INTO comminterests (userid, intid) ".
                           "SELECT userid, intid FROM userinterests " .
                           "WHERE userid IN (@set)");
                }

                print "# Finished converting community interests.\n";
            },
            );

register_tabledrop("ibill_codes");
register_tabledrop("paycredit");
register_tabledrop("payments");
register_tabledrop("tmp_contributed");
register_tabledrop("transferinfo");
register_tabledrop("contest1");
register_tabledrop("contest1data");
register_tabledrop("logins");
register_tabledrop("hintfriendsview");
register_tabledrop("hintlastnview");
register_tabledrop("batchdelete");
register_tabledrop("ftpusers");
register_tabledrop("ipban");
register_tabledrop("ban");
register_tabledrop("logaccess");
register_tabledrop("fvcache");
register_tabledrop("userpic_comment");
register_tabledrop("events");
register_tabledrop("randomuserset");

### changes

register_alter(sub {

    my $dbh = shift;
    my $runsql = shift;

    if (column_type("content_flag", "reporteruniq") eq "")
    {
        do_alter("content_flag",
                 "ALTER TABLE content_flag ADD reporteruniq VARCHAR(15) AFTER reporterid");

    }
    if (column_type("supportcat", "is_selectable") eq "")
    {
        do_alter("supportcat",
                 "ALTER TABLE supportcat ADD is_selectable ENUM('1','0') ".
                 "NOT NULL DEFAULT '1', ADD public_read  ENUM('1','0') NOT ".
                 "NULL DEFAULT '1', ADD public_help ENUM('1','0') NOT NULL ".
                 "DEFAULT '1', ADD allow_screened ENUM('1','0') NOT NULL ".
                 "DEFAULT '0', ADD replyaddress VARCHAR(50), ADD hide_helpers ".
                 "ENUM('1','0') NOT NULL DEFAULT '0' AFTER allow_screened");

    }
    if (column_type("supportlog", "type") =~ /faqref/)
    {
        do_alter("supportlog",
                 "ALTER TABLE supportlog MODIFY type ENUM('req', 'answer', ".
                 "'custom', 'faqref', 'comment', 'internal', 'screened') ".
                 "NOT NULL");
        do_sql("UPDATE supportlog SET type='answer' WHERE type='custom'");
        do_sql("UPDATE supportlog SET type='answer' WHERE type='faqref'");
        do_alter("supportlog",
                 "ALTER TABLE supportlog MODIFY type ENUM('req', 'answer', ".
                 "'comment', 'internal', 'screened') NOT NULL");

    }
    if (table_relevant("supportcat") && column_type("supportcat", "catkey") eq "")
    {
        do_alter("supportcat",
                 "ALTER TABLE supportcat ADD catkey VARCHAR(25) AFTER spcatid");
        do_sql("UPDATE supportcat SET catkey=spcatid WHERE catkey IS NULL");
        do_alter("supportcat",
                 "ALTER TABLE supportcat MODIFY catkey VARCHAR(25) NOT NULL");
    }
    if (column_type("supportcat", "no_autoreply") eq "")
    {
        do_alter("supportcat",
                 "ALTER TABLE supportcat ADD no_autoreply ENUM('1', '0') ".
                 "NOT NULL DEFAULT '0'");
    }

    if (column_type("support", "timelasthelp") eq "")
    {
        do_alter("supportlog",
                 "ALTER TABLE supportlog ADD INDEX (userid)");
        do_alter("support",
                 "ALTER TABLE support ADD timelasthelp INT UNSIGNED");
    }

    if (column_type("duplock", "realm") !~ /payments/)
    {
        do_alter("duplock",
                 "ALTER TABLE duplock MODIFY realm ENUM('support','log',".
                 "'comment','payments') NOT NULL default 'support'");
    }

    if (column_type("schematables", "redist_where") eq "")
    {
        do_alter("schematables",
                 "ALTER TABLE schematables ADD ".
                 "redist_where varchar(255) AFTER redist_mode");
    }

    # upgrade people to the new capabilities system.  if they're
    # using the the paidfeatures column already, we'll assign them
    # the same capability bits that ljcom will be using.
    if (table_relevant("user") && !column_type("user", "caps"))
    {
        do_alter("user",
                 "ALTER TABLE user ADD ".
                 "caps SMALLINT UNSIGNED NOT NULL DEFAULT 0 AFTER user");
        try_sql("UPDATE user SET caps=16|8|2 WHERE paidfeatures='on'");
        try_sql("UPDATE user SET caps=8|2    WHERE paidfeatures='paid'");
        try_sql("UPDATE user SET caps=4|2    WHERE paidfeatures='early'");
        try_sql("UPDATE user SET caps=2      WHERE paidfeatures='off'");
    }

    if ( table_relevant('user') &&
        column_type( 'user', 'caps' ) =~ /smallint/i )
    {
        do_alter('user', qq{
            ALTER TABLE user
                DROP COLUMN email,
                DROP COLUMN password,
                MODIFY COLUMN caps BIGINT UNSIGNED NOT NULL DEFAULT 0,
                ADD COLUMN packed_props BIGINT UNSIGNED NOT NULL DEFAULT 0
        });
    }

    # axe this column (and its two related ones) if it exists.
    if (column_type("user", "paidfeatures"))
    {
        try_sql("REPLACE INTO paiduser (userid, paiduntil, paidreminder) ".
                "SELECT userid, paiduntil, paidreminder FROM user WHERE paidfeatures='paid'");
        try_sql("REPLACE INTO paiduser (userid, paiduntil, paidreminder) ".
                "SELECT userid, COALESCE(paiduntil,'0000-00-00'), NULL FROM user WHERE paidfeatures='on'");
        do_alter("user",
                 "ALTER TABLE user DROP paidfeatures, DROP paiduntil, DROP paidreminder");
    }

    # move S1 _style ids to userprop table!
    if (column_type("user", "lastn_style")) {

        # be paranoid and insert these in case they don't exist:
        try_sql("INSERT INTO userproplist VALUES (null, 's1_lastn_style', 0, 'Recent View StyleID', 'num', 'The style ID# of the S1 style for the recent entries view.')");
        try_sql("INSERT INTO userproplist VALUES (null, 's1_calendar_style', 0, 'Calendar View StyleID', 'num', 'The style ID# of the S1 style for the calendar view.')");
        try_sql("INSERT INTO userproplist VALUES (null, 's1_day_style', 0, 'Day View StyleID', 'num', 'The style ID# of the S1 style for the day view.')");
        try_sql("INSERT INTO userproplist VALUES (null, 's1_friends_style', 0, 'Friends View StyleID', 'num', 'The style ID# of the S1 style for the friends view.')");

        foreach my $v (qw(lastn day calendar friends)) {
            do_sql("INSERT INTO userproplite SELECT u.userid, upl.upropid, u.${v}_style FROM user u, userproplist upl WHERE upl.name='s1_${v}_style'");
        }

        do_alter("user",
                 "ALTER TABLE user DROP lastn_style, DROP calendar_style, DROP search_style, DROP searchres_style, DROP day_style, DROP friends_style");
    }

    # add scope columns to proplist tables
    if (column_type("userproplist", "scope") eq "") {
        do_alter("userproplist",
                 "ALTER TABLE userproplist ADD scope ENUM('general', 'local') ".
                 "DEFAULT 'general' NOT NULL");
    }

    if (column_type("logproplist", "scope") eq "") {
        do_alter("logproplist",
                 "ALTER TABLE logproplist ADD scope ENUM('general', 'local') ".
                 "DEFAULT 'general' NOT NULL");
    }

    if (column_type("talkproplist", "scope") eq "") {
        do_alter("talkproplist",
                 "ALTER TABLE talkproplist ADD scope ENUM('general', 'local') ".
                 "DEFAULT 'general' NOT NULL");
    }

    if (column_type("priv_list", "scope") eq "") {
        do_alter("priv_list",
                 "ALTER TABLE priv_list ADD scope ENUM('general', 'local') ".
                 "DEFAULT 'general' NOT NULL");
    }

    # change size of stats table to accomodate meme data, and shrink statcat,
    # since it's way too big
    if (column_type("stats", "statcat") eq "varchar(100)") {
        do_alter("stats",
                 "ALTER TABLE stats ".
                 "MODIFY statcat VARCHAR(30) NOT NULL, ".
                 "MODIFY statkey VARCHAR(150) NOT NULL, ".
                 "MODIFY statval INT UNSIGNED NOT NULL, ".
                 "DROP INDEX statcat");
    }

    if (column_type("priv_list", "is_public") eq "") {
        do_alter("priv_list",
                 "ALTER TABLE priv_list ".
                 "ADD is_public ENUM('1', '0') DEFAULT '1' NOT NULL");
    }

    # cluster stuff!
    if (column_type("meme", "journalid") eq "") {
        do_alter("meme",
                 "ALTER TABLE meme ADD journalid INT UNSIGNED NOT NULL AFTER ts");
    }

    if (column_type("memorable", "jitemid") eq "") {
        do_alter("memorable", "ALTER TABLE memorable ".
                 "DROP INDEX userid, DROP INDEX itemid, ".
                 "CHANGE itemid jitemid INT UNSIGNED NOT NULL, ".
                 "ADD journalid INT UNSIGNED NOT NULL AFTER userid, ".
                 "ADD UNIQUE uniq (userid, journalid, jitemid), ".
                 "ADD KEY item (journalid, jitemid)");
    }

    if (column_type("user", "clusterid") eq "") {
        do_alter("user", "ALTER TABLE user ".
                 "ADD clusterid TINYINT UNSIGNED NOT NULL AFTER caps, ".
                 "ADD dversion TINYINT UNSIGNED NOT NULL AFTER clusterid, ".
                 "ADD INDEX idxcluster (clusterid), ".
                 "ADD INDEX idxversion (dversion)");
    }

    if (column_type("friends", "bgcolor") eq "char(7)") {
        do_alter("friends", "ALTER TABLE friends ".
                 "MODIFY bgcolor CHAR(8) NOT NULL DEFAULT '16777215', ".
                 "MODIFY fgcolor CHAR(8) NOT NULL DEFAULT '0'");
        do_sql("UPDATE friends SET ".
               "bgcolor=CONV(RIGHT(bgcolor,6),16,10), ".
               "fgcolor=CONV(RIGHT(fgcolor,6),16,10)")
            unless skip_opt() eq "colorconv";
    }

    return if skip_opt() eq "colorconv";

    if (column_type("friends", "bgcolor") eq "char(8)") {
        do_alter("friends", "ALTER TABLE friends ".
                 "MODIFY bgcolor MEDIUMINT UNSIGNED NOT NULL DEFAULT 16777215, ".
                 "MODIFY fgcolor MEDIUMINT UNSIGNED NOT NULL DEFAULT 0");
    }

    # add the default encoding field, for recoding older pre-Unicode stuff

    if (column_type("user", "oldenc") eq "") {
        do_alter("user", "ALTER TABLE user ".
                 "ADD oldenc TINYINT DEFAULT 0 NOT NULL, ".
                 "MODIFY name CHAR(80) NOT NULL");
    }

    if (column_type("user", "allow_getpromos") ne "") {
        do_alter("user", "ALTER TABLE user DROP allow_getpromos");
    }

    # widen columns to accomodate larger Unicode names
    if (column_type("friendgroup", "groupname") eq "varchar(30)") {
        do_alter("friendgroup",
                 "ALTER TABLE friendgroup ".
                 "MODIFY groupname VARCHAR(60) NOT NULL");
    }
    if (column_type("todo", "statusline") eq "varchar(15)") {
        do_alter("todo",
                 "ALTER TABLE todo ".
                 "MODIFY statusline VARCHAR(40) NOT NULL, " .
                 "MODIFY subject VARCHAR(100) NOT NULL, " .
                 "MODIFY des VARCHAR(255) NOT NULL");
    }
    if (column_type("memorable", "des") eq "varchar(60)") {
        do_alter("memorable",
                 "ALTER TABLE memorable ".
                 "MODIFY des VARCHAR(150) NOT NULL");
    }
    if (column_type("keywords", "keyword") eq "varchar(40) binary") {
        do_alter("keywords",
                 "ALTER TABLE keywords ".
                 "MODIFY keyword VARCHAR(80) BINARY NOT NULL");
    }

    # change interest.interest key to being unique, if it's not already
    if (table_exists("interests")) {
        my $sth = $dbh->prepare("SHOW INDEX FROM interests");
        $sth->execute;
        while (my $i = $sth->fetchrow_hashref) {
            if ($i->{'Key_name'} eq "interest" && $i->{'Non_unique'}) {
                do_alter("interests", "ALTER IGNORE TABLE interests ".
                         "DROP INDEX interest, ADD UNIQUE interest (interest)");
                last;
            }
        }
    }

    if (column_type("supportcat", "scope") eq "")
    {
        do_alter("supportcat",
                 "ALTER IGNORE TABLE supportcat ADD scope ENUM('general', 'local') ".
                 "NOT NULL DEFAULT 'general', ADD UNIQUE (catkey)");
    }

    # convert 'all' arguments to '*'
    if (table_relevant("priv_map") && !check_dbnote("privcode_all_to_*")) {

        # arg isn't keyed, but this table is only a couple thousand rows
        do_sql("UPDATE priv_map SET arg='*' WHERE arg='all'");

        set_dbnote("privcode_all_to_*", 1);
    }

    # convert 'wizard' s2 styles to 'wizard-uniq'
    if (table_relevant("s2styles") && !check_dbnote("s2style-wizard-update")) {

        # set_dbnote will return true if $opt_sql is set and it sets
        # the note successfully.  only then do we run the wizard updater
        set_dbnote("s2style-wizard-update", 1) &&
            system("$ENV{'LJHOME'}/bin/upgrading/s2style-wizard-update.pl");
    }

    # this never ended up being useful, and just freaked people out unnecessarily.
    if (column_type("user", "track")) {
        do_alter("user", "ALTER TABLE user DROP track");
    }

    # need more choices (like "Y" for sYndicated journals)
    if (column_type("user", "journaltype") =~ /enum/i) {
        do_alter("user", "ALTER TABLE user MODIFY journaltype CHAR(1) NOT NULL DEFAULT 'P'");
    }

    unless (column_type("syndicated", "laststatus")) {
        do_alter("syndicated",
                 "ALTER TABLE syndicated ADD laststatus VARCHAR(80), ADD lastnew DATETIME");
    }

    # change themedata. key to being unique, if it's not already
    unless (index_name("themedata", "UNIQUE:themeid-coltype")) {
        do_alter("themedata", "ALTER IGNORE TABLE themedata ".
                 "DROP KEY themeid, MODIFY coltype VARCHAR(30) NOT NULL, ".
                 "ADD UNIQUE `thuniq` (themeid, coltype)");
    }

    unless (column_type("syndicated", "numreaders")) {
        do_alter("syndicated",
                 "ALTER TABLE syndicated ".
                 "ADD numreaders MEDIUMINT, ADD INDEX (numreaders)");
    }

    if (column_type("community", "ownerid"))
    {
        do_alter("community",
                 "ALTER TABLE community DROP ownerid");
    }

    # if it exists, but it's the old way, just kill it.
    if (column_type("weekuserusage", "ubefore") && ! column_type("weekuserusage", "uafter")) {
        do_sql("DROP TABLE weekuserusage");
        create_table("weekuserusage");
    }

    unless (column_type("userproplist", "cldversion")) {
        do_alter("userproplist",
                 "ALTER TABLE userproplist ADD cldversion TINYINT UNSIGNED NOT NULL AFTER indexed");
    }

    unless (column_type("authactions", "used") &&
            index_name("authactions", "INDEX:userid") &&
            index_name("authactions", "INDEX:datecreate")) {

        do_alter("authactions",
                 "ALTER TABLE authactions " .
                 "ADD used enum('Y', 'N') DEFAULT 'N' AFTER arg1, " .
                 "ADD INDEX(userid), ADD INDEX(datecreate)");
    }

    unless (column_type("s2styles", "modtime")) {
        do_alter("s2styles",
                 "ALTER TABLE s2styles ADD modtime INT UNSIGNED NOT NULL AFTER name");
    }

    if (column_type("acctinvite", "reason") eq "varchar(20)") {
        do_alter("acctinvite",
                 "ALTER TABLE acctinvite MODIFY reason VARCHAR(40)");
    }

    # Add BLOB flag to proplist
    unless (column_type("userproplist", "datatype") =~ /blobchar/) {
        if (column_type("userproplist", "is_blob")) {
            do_alter("userproplist",
                     "ALTER TABLE userproplist DROP is_blob");
        }
        do_alter("userproplist",
                 "ALTER TABLE userproplist MODIFY datatype ENUM('char','num','bool','blobchar') NOT NULL DEFAULT 'char'");
    }

    if (column_type("challenges", "count") eq "")
    {
        do_alter("challenges",
                 "ALTER TABLE challenges ADD ".
                 "count int(5) UNSIGNED NOT NULL DEFAULT 0 AFTER challenge");
    }

    if (column_type("userblob", "length") =~ /mediumint/)
    {
        do_alter("userblob", "ALTER TABLE userblob MODIFY length INT UNSIGNED");
    }

    unless (index_name("support", "INDEX:requserid")) {
        do_alter("support", "ALTER IGNORE TABLE support ADD INDEX (requserid), ADD INDEX (reqemail)");
    }

    unless (column_type("community", "membership") =~ /moderated/i) {
        do_alter("community", "ALTER TABLE community MODIFY COLUMN " .
                 "membership ENUM('open','closed','moderated') DEFAULT 'open' NOT NULL");
    }

    if (column_type("userproplist", "multihomed") eq '') {
        do_alter("userproplist", "ALTER TABLE userproplist " .
                 "ADD multihomed ENUM('1', '0') NOT NULL DEFAULT '0' AFTER cldversion");
    }

    if (index_name("moodthemedata", "INDEX:moodthemeid")) {
        do_alter("moodthemedata", "ALTER IGNORE TABLE moodthemedata DROP KEY moodthemeid");
    }

    if (column_type("userpic2", "flags") eq '') {
        do_alter("userpic2", "ALTER TABLE userpic2 " .
                 "ADD flags tinyint(1) unsigned NOT NULL default 0 AFTER comment, " .
                 "ADD location enum('blob','disk','mogile') default NULL AFTER flags");
    }

    if (column_type("userblob", "blobid") =~ /mediumint/) {
        do_alter("userblob", "ALTER TABLE userblob MODIFY blobid INT UNSIGNED NOT NULL");
    }

    if (column_type("counter", "max") =~ /mediumint/) {
        do_alter("counter", "ALTER TABLE counter MODIFY max INT UNSIGNED NOT NULL DEFAULT 0");
    }

    if (column_type("userpic2", "url") eq '') {
        do_alter("userpic2", "ALTER TABLE userpic2 " .
                 "ADD url VARCHAR(255) default NULL AFTER location");
    }

    unless (column_type("spamreports", "posttime") ne '') {
        do_alter("spamreports", "ALTER TABLE spamreports ADD COLUMN posttime INT(10) UNSIGNED " .
                 "NOT NULL AFTER reporttime, ADD COLUMN state ENUM('open', 'closed') DEFAULT 'open' " .
                 "NOT NULL AFTER posttime");
    }

    if (column_type("captchas", "location") eq '') {
        do_alter("captchas", "ALTER TABLE captchas " .
                 "ADD location ENUM('blob','mogile') DEFAULT NULL AFTER type");
    }

    if (column_type("spamreports", "report_type") eq '') {
        do_alter("spamreports", "ALTER TABLE spamreports " .
                "ADD report_type ENUM('entry','comment') NOT NULL DEFAULT 'comment' " .
                "AFTER posterid");
    }

    if (column_type("commenturls", "ip") eq '') {
        do_alter("commenturls",
                "ALTER TABLE commenturls " .
                "ADD ip VARCHAR(15) DEFAULT NULL " .
                "AFTER journalid");
    }

    if (column_type("sessions", "exptype") !~ /once/) {
        do_alter("sessions",
                "ALTER TABLE sessions CHANGE COLUMN exptype ".
                "exptype ENUM('short', 'long', 'once') NOT NULL");
    }

    if (column_type("ml_items", "itid") =~ /auto_increment/) {
        do_alter("ml_items",
                "ALTER TABLE ml_items MODIFY COLUMN " .
                "itid MEDIUMINT UNSIGNED NOT NULL DEFAULT 0");
    }

    if (column_type("ml_text", "txtid") =~ /auto_increment/) {
        do_alter("ml_text",
                "ALTER TABLE ml_text MODIFY COLUMN " .
                "txtid MEDIUMINT UNSIGNED NOT NULL DEFAULT 0");
    }

    unless (column_type("syndicated", "oldest_ourdate")) {
        do_alter("syndicated",
                 "ALTER TABLE syndicated ADD oldest_ourdate DATETIME AFTER lastnew");
    }

    if (column_type("sessions", "userid") =~ /mediumint/) {
        do_alter("sessions",
                "ALTER TABLE sessions MODIFY COLUMN userid INT UNSIGNED NOT NULL");
    }

    if (column_type("faq", "summary") eq '') {
        do_alter("faq",
                 "ALTER TABLE faq ADD summary TEXT AFTER question");
    }
    
    if (!column_type("faq", "uses")) {
        do_alter("faq",
                 "ALTER TABLE faq ADD uses int(11) NOT NULL default 0");
    }


    if (column_type("spamreports", "srid") eq '') {
        do_alter("spamreports",
                 "ALTER TABLE spamreports DROP PRIMARY KEY");

        do_alter("spamreports",
                 "ALTER TABLE spamreports ADD srid MEDIUMINT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT FIRST");

        do_alter("spamreports",
                 "ALTER TABLE spamreports ADD INDEX (reporttime, journalid)");
    }

    if (column_type("includetext", "inctext") !~ /mediumtext/) {
        do_alter("includetext",
                 "ALTER TABLE includetext MODIFY COLUMN inctext MEDIUMTEXT");
    }
    if (column_type("portal_config", "userid") !~ /unsigned/i) {
        do_alter("portal_config",
                 "ALTER TABLE portal_config MODIFY COLUMN userid INT UNSIGNED NOT NULL, MODIFY COLUMN pboxid SMALLINT UNSIGNED NOT NULL, MODIFY COLUMN sortorder SMALLINT UNSIGNED NOT NULL, MODIFY COLUMN type INT UNSIGNED NOT NULL");
    }
    if (column_type("portal_box_prop", "userid") !~ /unsigned/i) {
                 do_alter("portal_box_prop",
                          "ALTER TABLE portal_box_prop MODIFY COLUMN userid INT UNSIGNED NOT NULL, MODIFY COLUMN pboxid SMALLINT UNSIGNED NOT NULL, MODIFY COLUMN ppropid SMALLINT UNSIGNED NOT NULL");
    }

    # These table are both livejournal tables, although could have ljcom values
    # that we need to update.  Not trying to be lazy, but running the updates in
    # update-db-local.pl would cause us to have to do a select on the table everytime
    # to see if it still has old values, which is lame.  The updates also can't run
    # before the alter so and if on if the alter has happened also isn't really
    # useful.  So here they live. :-\
    foreach my $table (qw(recentactions actionhistory)) {

        if (column_type($table, "what") =~ /^char/i) {
            do_alter($table,
                     "ALTER TABLE $table MODIFY COLUMN what VARCHAR(20) NOT NULL");

            next if $table eq 'recentactions';

            # Since actionhistory is updated nightly, is alright to do updates now
            do_sql("UPDATE actionhistory SET what='post' WHERE what='P'");
            do_sql("UPDATE actionhistory SET what='phonepost' WHERE what='_F'");
            do_sql("UPDATE actionhistory SET what='phonepost_mp3' WHERE what='_M'");
        }
    }

    # table format totally changed, we'll just truncate and modify
    # all of the columns since the data is just summary anyway
    if (index_name("active_user", "INDEX:time")) {
        do_sql("TRUNCATE TABLE active_user");
        do_alter("active_user",
                 "ALTER TABLE active_user " .
                 "DROP time, DROP KEY userid, " .
                 "ADD year SMALLINT NOT NULL FIRST, " .
                 "ADD month TINYINT NOT NULL AFTER year, " .
                 "ADD day TINYINT NOT NULL AFTER month, " .
                 "ADD hour TINYINT NOT NULL AFTER day, " .
                 "ADD PRIMARY KEY (year, month, day, hour, userid)");
    }

    if (index_name("active_user_summary", "UNIQUE:year-month-day-hour-clusterid-type")) {
        do_alter("active_user_summary",
                 "ALTER TABLE active_user_summary DROP PRIMARY KEY, " .
                 "ADD INDEX (year, month, day, hour)");
    }

    if (column_type("blobcache", "bckey") =~ /40/) {
        do_alter("blobcache",
                 "ALTER TABLE blobcache MODIFY bckey VARCHAR(255) NOT NULL");
    }

    if (column_type("eventtypelist", "eventtypeid")) {
        do_alter("eventtypelist",
                 "ALTER TABLE eventtypelist CHANGE eventtypeid etypeid SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT");
    }

    unless (column_type("sms_msg", "status")) {
        do_alter("sms_msg",
                 "ALTER TABLE sms_msg ADD status ENUM('success', 'error', 'unknown') NOT NULL DEFAULT 'unknown' AFTER type");
    }

    unless (column_type("sms_msg", "status") =~ /ack_wait/) {
        do_alter("sms_msg",
                 "ALTER TABLE sms_msg MODIFY status ENUM('success', 'error', 'ack_wait', 'unknown') NOT NULL DEFAULT 'unknown'");
    }

    if (column_type("sms_msg", "msg_raw")) {
        do_alter("sms_msg",
                 "ALTER TABLE sms_msg DROP msg_raw");
    }

    # add index on journalid, etypeid to subs
    unless (index_name("subs", "INDEX:etypeid-journalid") || index_name("subs", "INDEX:etypeid-journalid-userid")) {
        # This one is deprecated by the one below, which adds a userid
        # at the end.  hence the double if above.
        do_alter("subs", "ALTER TABLE subs ".
                 "ADD INDEX (etypeid, journalid)");
    }

    unless (column_type("sch_error", "funcid")) {
        do_alter("sch_error", "alter table sch_error add funcid int(10) unsigned NOT NULL default 0, add index (funcid, error_time)");
    }

    unless (column_type("sch_exitstatus", "funcid")) {
        do_alter("sch_exitstatus", "alter table sch_exitstatus add funcid INT UNSIGNED NOT NULL DEFAULT 0, add index (funcid)");
    }

    # make userid unique
    if (index_name("smsusermap", "INDEX:userid")) {
        # iterate over the table and delete dupes
        my $sth = $dbh->prepare("SELECT userid, number FROM smsusermap");
        $sth->execute();

        my %map = ();
        while (my $row = $sth->fetchrow_hashref) {
            my $uid = $row->{userid};
            my $num = $row->{number};

            if ($map{$uid}) {
                # dupe, delete
                $dbh->do("DELETE FROM smsusermap WHERE userid=? AND number=?",
                         undef, $uid, $num);
            }

            $map{$uid} = 1;
        }

        do_alter("smsusermap", "ALTER IGNORE TABLE smsusermap ".
                 "DROP KEY userid, ADD UNIQUE (userid)");
    }

    # add index to sms_msg
    unless (index_name("sms_msg", "INDEX:userid-timecreate")) {
        do_alter("sms_msg", "ALTER TABLE sms_msg ADD INDEX(userid, timecreate)");
    }

    # add typekey to sms_msg
    unless (column_type("sms_msg", "class_key")) {
        do_alter("sms_msg", "ALTER TABLE sms_msg " .
                 "ADD class_key VARCHAR(25) NOT NULL default 'unknown' AFTER timecreate");
    }

    # add index on just timecreate for time-bound stats
    unless (index_name("sms_msg", "INDEX:timecreate")) {
        do_alter("sms_msg", "ALTER TABLE sms_msg ADD INDEX(timecreate)");
    }

    # add verified/instime columns to smsusermap
    unless (column_type("smsusermap", "verified")) {
        do_alter("smsusermap", "ALTER TABLE smsusermap " .
                 "ADD verified ENUM('Y','N') NOT NULL DEFAULT 'N', " .
                 "ADD instime INT UNSIGNED NOT NULL");
    }

    # add an index
    unless (index_name("subs", "INDEX:etypeid-journalid-userid")) {
        do_alter("subs",
                 "ALTER TABLE subs DROP INDEX etypeid, ADD INDEX etypeid (etypeid, journalid, userid)");
    }

    # add a column
    unless (column_type("qotd", "tags")) {
        do_alter("qotd",
                 "ALTER TABLE qotd ADD tags VARCHAR(255) DEFAULT NULL AFTER text");
    }

    # fix primary key
    unless (index_name("pollresult2", "UNIQUE:journalid-pollid-pollqid-userid")) {
        do_alter("pollresult2",
                 "ALTER TABLE pollresult2 DROP PRIMARY KEY, ADD PRIMARY KEY (journalid,pollid,pollqid,userid)");
    }

    # fix primary key
    unless (index_name("pollsubmission2", "UNIQUE:journalid-pollid-userid")) {
        do_alter("pollsubmission2",
                 "ALTER TABLE pollsubmission2 DROP PRIMARY KEY, ADD PRIMARY KEY (journalid,pollid,userid)");
    }

    # add an indexed 'userid' column
    unless (column_type("expunged_users", "userid")) {
        do_alter("expunged_users",
                 "ALTER TABLE expunged_users ADD userid INT UNSIGNED NOT NULL FIRST, " .
                 "ADD INDEX (userid)");
    }

    # add a column
    unless (column_type("qotd", "extra_text")) {
        do_alter("qotd",
                 "ALTER TABLE qotd ADD extra_text TEXT DEFAULT NULL");
    }

    # add a column
    unless (column_type("qotd", "subject")) {
        do_alter("qotd",
                 "ALTER TABLE qotd " .
                 "ADD subject VARCHAR(255) NOT NULL DEFAULT '' AFTER active, " .
                 "ADD from_user CHAR(15) DEFAULT NULL AFTER tags");
    }

    unless (column_type("usermsgproplist", "scope")) {
        do_alter("usermsgproplist",
                 "ALTER TABLE usermsgproplist ADD scope ENUM('general', 'local') "
                 . "DEFAULT 'general' NOT NULL");
    }

    unless (column_type("qotd", "cap_mask")) {
        do_alter("qotd",
                 "ALTER TABLE qotd " .
                 # bitmask representation of cap classes that this question applies to
                 "ADD cap_mask SMALLINT UNSIGNED NOT NULL, " .
                 # show to logged out users or not
                 "ADD show_logged_out ENUM('Y','N') NOT NULL DEFAULT 'N', " .
                 "ADD countries VARCHAR(255)");

        # set all current questions to be shown to all classes and logged out users
        if (table_relevant("qotd")) {
            my $mask = LJ::mask_from_bits(keys %LJ::CAP);
            do_sql("UPDATE qotd SET cap_mask=$mask, show_logged_out='Y'");
        }
    }

    unless (column_type("qotd", "link_url")) {
        do_alter("qotd",
                 "ALTER TABLE qotd " .
                 "ADD link_url VARCHAR(255) NOT NULL DEFAULT ''");
    }

    if (table_relevant("spamreports") && column_type("spamreports", "report_type") !~ /message/) {
        # cache table by running select
        do_sql("SELECT COUNT(*) FROM spamreports");
        # add 'message' enum
        do_alter("spamreports", "ALTER TABLE spamreports " .
                 "CHANGE COLUMN report_type report_type " .
                 "ENUM('entry','comment','message') NOT NULL DEFAULT 'comment'");
    }

    if (column_type("supportcat", "user_closeable") eq "") {
        do_alter("supportcat",
                 "ALTER TABLE supportcat ADD " .
                 "user_closeable ENUM('1', '0') NOT NULL DEFAULT '1' " .
                 "AFTER hide_helpers");
    }

    unless (column_type("content_flag", "supportid")) {
        do_alter("content_flag",
                 "ALTER TABLE content_flag " .
                 "ADD supportid INT(10) UNSIGNED NOT NULL DEFAULT '0'");
    }

    if (keys %LJ::VERTICAL_TREE && table_relevant("vertical")) {
        my @vertical_names = keys %LJ::VERTICAL_TREE;


        # get all of the verticals currently in the db
        my $verts = $dbh->selectcol_arrayref("SELECT name FROM vertical");


        # remove any verticals from the db that aren't in the config hash
        my @verts_to_remove;
        foreach my $name (@$verts) {
            push @verts_to_remove, $name unless $LJ::VERTICAL_TREE{$name};
        }

        if (@verts_to_remove) {
            my @string_verts = map { "'$_'" } @verts_to_remove;
            my $vert_sql = join(',', @string_verts);
            do_sql("DELETE FROM vertical WHERE name IN ($vert_sql)");
        }


        # add any verticals to the db that are in the config hash (and aren't there already)
        my %verts_in_db = map { $_ => 1 } @$verts;

        my %verts_to_add;
        foreach my $name (@vertical_names) {
            $verts_to_add{$name} = 1 unless $verts_in_db{$name};
        }

        if (keys %verts_to_add) {
            my @vert_sql_values;
            foreach my $vert (keys %verts_to_add) {
                push @vert_sql_values, "('$vert',UNIX_TIMESTAMP())";
            }
            my $vert_sql = join(',', @vert_sql_values);
            do_sql("INSERT INTO vertical (name, createtime) VALUES $vert_sql");
        }
    }

    unless (column_type("vertical_editorials", "img_width")) {
        do_alter("vertical_editorials",
                 "ALTER TABLE vertical_editorials " .
                 "ADD img_width INT(5) UNSIGNED DEFAULT NULL AFTER img_url, " .
                 "ADD img_height INT(5) UNSIGNED DEFAULT NULL AFTER img_width");
    }

    unless (column_type("vertical_editorials", "img_link_url")) {
        do_alter("vertical_editorials",
                 "ALTER TABLE vertical_editorials " .
                 "ADD img_link_url VARCHAR(255) DEFAULT NULL AFTER img_height");
    }

    # add a status column to polls
    unless (column_type("poll", "status")) {
        do_alter("poll",
                 "ALTER TABLE poll ADD status CHAR(1) AFTER name, " .
                 "ADD INDEX (status)");
    }
    unless (column_type("poll2", "status")) {
        do_alter("poll2",
                 "ALTER TABLE poll2 ADD status CHAR(1) AFTER name, " .
                 "ADD INDEX (status)");
    }

    unless (column_type("qotd", "domain")) {
        do_alter("qotd",
                 "ALTER TABLE qotd " .
                 "ADD domain VARCHAR(255) NOT NULL DEFAULT 'homepage'");
    }

    unless (column_type("qotd", "impression_url")) {
        do_alter("qotd",
                 "ALTER TABLE qotd " .
                 "ADD impression_url VARCHAR(255) DEFAULT NULL");
    }

    unless (column_type("qotd", "is_special")) {
        do_alter("qotd",
                 "ALTER TABLE qotd " .
                 "ADD is_special ENUM('Y','N') NOT NULL DEFAULT 'N'");
    }

    unless (column_type("jobstatus", "userid")) {
        do_alter("jobstatus",
                 "ALTER TABLE jobstatus " .
                 "ADD userid INT UNSIGNED DEFAULT NULL"); # yes, we allow userid to be NULL - it means no userid checking
    }

    unless (column_type("supportlog", "tier")) {
        do_alter("supportlog",
                 "ALTER TABLE supportlog " .
                 "ADD tier TINYINT UNSIGNED DEFAULT NULL");
    }
    
    if (column_type("talk2", "jtalkid") =~ /mediumint/) {
        do_alter("talk2",
                 "ALTER TABLE talk2 " .
                 "MODIFY jtalkid INT UNSIGNED NOT NULL");
    }
    
    if (column_type("talk2", "parenttalkid") =~ /mediumint/) {
        do_alter("talk2",
                 "ALTER TABLE talk2 " .
                 "MODIFY parenttalkid INT UNSIGNED NOT NULL");
    }
    
    if (column_type("talkprop2", "jtalkid") =~ /mediumint/) {
        do_alter("talkprop2",
                 "ALTER TABLE talkprop2 " .
                 "MODIFY jtalkid INT UNSIGNED NOT NULL");
    }
    
    if (column_type("talktext2", "jtalkid") =~ /mediumint/) {
        do_alter("talktext2",
                 "ALTER TABLE talktext2 " .
                 "MODIFY jtalkid INT UNSIGNED NOT NULL");
    }

    if (column_type("talkleft", "jtalkid") =~ /mediumint/) {
        do_alter("talkleft",
                 "ALTER TABLE talkleft " .
                 "MODIFY jtalkid INT UNSIGNED NOT NULL");
    }

    if (column_type("talkleft_xfp", "jtalkid") =~ /mediumint/) {
        do_alter("talkleft_xfp",
                 "ALTER TABLE talkleft_xfp " .
                 "MODIFY jtalkid INT UNSIGNED NOT NULL");
    }

    if (column_type("commenturls", "jtalkid") =~ /mediumint/) {
        do_alter("commenturls",
                 "ALTER TABLE commenturls " .
                 "MODIFY jtalkid INT UNSIGNED NOT NULL");
    }

    # add an index on 'country' column
    unless (index_name("schools_pending", "INDEX:country")) {
        do_alter("schools_pending",
                 "ALTER TABLE schools_pending ADD INDEX(country)");
    }

    unless (column_type("comet_history", "status")) {
        do_alter("comet_history",
                 "ALTER TABLE comet_history " .
                 "ADD status char(1) default 'N' after message");
    }

    unless (column_type("ml_latest", "revid")) {
        do_alter("ml_latest",
                 "ALTER TABLE ml_latest " .
                 "ADD revid int unsigned default null");
    }

    unless (column_type("antispam", "eventtime") eq 'date') {
        do_alter("antispam",
                 "ALTER TABLE antispam " .
                 "MODIFY eventtime DATE DEFAULT NULL");
        do_alter("antispam",
                 "ALTER TABLE antispam ADD INDEX(eventtime)");
    }

    unless (column_type("site_messages", "countries")) {
        do_alter("site_messages",
                 "ALTER TABLE site_messages " .
                 "ADD countries varchar(255) default NULL, " .
                 "ADD accounts smallint(5) unsigned NOT NULL default '0'");
    }

    if (column_type("ratelist", "rlid") =~ /tinyint/i) {
        do_alter("ratelist",
                 "ALTER TABLE ratelist " .
                 "MODIFY rlid INT UNSIGNED NOT NULL AUTO_INCREMENT");
    }

    unless (column_type("category", "vert_id")) {
        do_alter("category",
                 "ALTER TABLE category " .
                 "ADD vert_id INT(11) NOT NULL");
    }

    unless (column_type("vertical2", "show_entries")) {
        do_alter("vertical2",
                "ALTER TABLE vertical2 
                    ADD show_entries INT NOT NULL, 
                    ADD not_deleted INT NOT NULL, 
                    ADD remove_after INT NOT NULL");
    }

    unless (column_type("vertical_keywords", "kw_id")) {
        do_alter("vertical_keywords",
            "ALTER TABLE vertical_keywords DROP PRIMARY KEY, DROP INDEX vert_id, DROP INDEX keyword, DROP journalid, DROP jitemid, DROP vert_id, DROP is_seo, ADD kw_id INT NOT NULL");
        do_alter("vertical_keywords",
            "ALTER TABLE vertical_keywords ADD PRIMARY KEY(kw_id), ADD UNIQUE(keyword), MODIFY kw_id INT NOT NULL AUTO_INCREMENT");
    }
    
    ## category may have the same path in different verticals
    unless (index_name("category", "UNIQUE:url_path-parentcatid-vert_id")) {
        do_alter("category", "ALTER IGNORE TABLE category ".
                 "DROP KEY `url_path`, ".
                 "ADD UNIQUE `url_path` (url_path, parentcatid, vert_id)");
    }

    if (column_null("category", "parentcatid") eq 'YES') {
        do_alter("category", "ALTER TABLE category MODIFY parentcatid INT UNSIGNED NOT NULL");
    }

    unless (column_type("category_recent_posts", "pic_orig_url")) {
        do_alter("category_recent_posts",
            "ALTER TABLE category_recent_posts
                ADD pic_orig_url VARCHAR(255) NOT NULL DEFAULT '',
                ADD pic_fb_url VARCHAR(255) NOT NULL DEFAULT ''
        ");
    }

    unless (column_type("domains", "domainid")) {
            do_alter("domains", "ALTER TABLE domains DROP PRIMARY KEY");
            do_alter("domains", "ALTER TABLE domains ADD COLUMN domainid int(10) unsigned NOT NULL AUTO_INCREMENT KEY");
            do_alter("domains", "ALTER TABLE domains ADD COLUMN rcptid int(10) unsigned NOT NULL");
            do_alter("domains", "ALTER TABLE domains ADD COLUMN type char(5)");
            do_alter("domains", "ALTER TABLE domains ADD COLUMN name char(80)");
    }
});

register_alter(sub {

    my $dbh = shift;
    my $runsql = shift;

    unless (column_type("eventrates", "itemid")) {
        do_alter("eventrates",
                 "ALTER TABLE eventrates " .
                 "CHANGE COLUMN jitemid itemid MEDIUMINT UNSIGNED NOT NULL");
    }

    unless (column_type("eventratescounters", "itemid")) {
        do_alter("eventratescounters",
                 "ALTER TABLE eventratescounters " .
                 "CHANGE COLUMN jitemid itemid MEDIUMINT UNSIGNED NOT NULL");
    }
});

register_alter(sub {

    my $dbh = shift;
    my $runsql = shift;

    unless (column_type("send_email_errors", "message")) {
        do_alter("send_email_errors",
                 "ALTER TABLE send_email_errors " .
                 "ADD message VARCHAR(255) DEFAULT NULL");
    }

    unless (index_name("send_email_errors", "INDEX:time")) {
        do_alter("send_email_errors",
                "ALTER TABLE send_email_errors " .
                "ADD INDEX(time)");
    }

    unless (column_type("delayedlog2", "is_sticky")) {
        do_alter("delayedlog2",
                 "ALTER TABLE delayedlog2 " .
                 "ADD is_sticky BOOLEAN NOT NULL");
    }

});

1; # return true
