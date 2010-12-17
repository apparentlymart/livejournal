package BotCheck;

use strict;
use warnings;

my $crawler_agents = qr{
   (
    sindice-fetcher |                # http://sindice.com/developers/bot
    Yandex |
    bot |
    libwww\-perl |                   # Comes from sup and other bots.
    Apple\-PubSub |
    Yahoo\!\ Slurp |
    Mediapartners\-Google |
    Jakarta\ Commons\-HttpClient |    # comes from independent
    aggregator |                     # robots from spinn3r.com
    crawler |
    Feed |
    Yahoo\ Pipes |
    AppEngine\-Google |
    spider |
    lm114\@nyu\.edu |                 # http://www.nyu.edu; lm114@nyu.edu
    Akregator |
    Rome\ Client |                   # https://rome.dev.java.net/
    RSS |
    Python\-urllib |
    JetBrains\ Omea |
    www\.fetch\.com |		     # www.fetch.com
    Java |
    AppleSyndication |
    Surphace\ Scout |
    DoCoMo |
    PostRank |                      # http://postrank.com   
    NetNewsWire |
    Liferea |
    Incutio\ XML\-RPC |
    Vienna |                         # http://www.vienna-rss.org
    Wget |
    centerim |                      # http://www.centerim.org/index.php/User_Manual#LiveJournal
    Subscribe\.Ru |
    Support\ Search\ Agent |          # This is our own abusebot
    SimplePie |
    NewsFire |
    webcollage |
    lwp\-trivial |                   # Comes from perl module LWP::Simple (script/bot)
    BuzzTracker |                    # http://www.buzztracker.com
    R6\_Primer |
    bestpersons\.ru |
    GreatNews |
    Flexum |                         # Flexum.ru search service
    LucidMedia\ ClickSense |         # comes from amazonaws
    Nutch |                          # http://lucene.apache.org/nutch/about.html
    BlogScope |
    Snarfer |
    Top\-Indexer |	 	     # Top-Indexer; http://www.artlebedev.ru; gregory@artlebedev.ru
    ActiveRefresh |
    relevantnoise\.com |             # http://relevantnoise.com
    Ravelry\.com |
    MailRu\-LJImporter |
    LJpoisk\.ru |                    # RU Search Engine
    Virtual\ Reach\ Newsclip\ Collector | 
    liveinternet\.ru |
    Fever |
    libcurl |
    Netvibes |
    URI\:\:Fetch |
    OutlookConnector |
    Bloglovin |                      # http://www.bloglovin.com/
    LJ\:\:Simple |
    SOAP\:\:Lite |
    LJ\.Rossia\.org |
    Smokeping |                     # http://oss.oetiker.ch/smokeping/
    SharpReader |
    Gregarius |                      # http://devlog.gregarius.net/docs/ua
    blogged\_crawl |                 # Nothing found on Google for this.
    LjSEEK |                         #  http://www.ljseek.com/ or http://ljsearch.net
    WWW\-Mechanize |
    larbin |                        # http://www.webmasterworld.com/forum11/2926.htm    
    PycURL |
    LeapTag |                        # http://leaptag.com/leaptag.php
    Syndic8 |
    online\@monitoring\.ru |
    Python\-httplib |
    gooblog |                        # http://help.goo.ne.jp/contact/
    facebookexternalhit |
    heritrix | 			     # www.kit.edu
    web\.archive\.org |
    Perl\-ljsm |
    Tumblr |
    LWP\:\:Simple |
    Megite |                         # http://www.megite.com/
    WebryReader |
    Snoopy |
    BTWebClient |                   # utorrent.com
    Attensa |
    Amazon\.com\ Blog\ Parser |
    nestreader | 
    Plagger |
    Headline\-Reader |
    Microsoft\ URL\ Control |
    DELCO\ READER |
    NewsLife | 
    CaRP |                           # http://www.geckotribe.com/rss/carp/
    Awasu |
    LJSearch |                       #  http://www.ljseek.com/ or http://ljsearch.net
    ^NIF |                           # http://www.newsisfree.com/robot.php
    StackRambler |                   # Russian Search Engine: http://www.rambler.ru/
    Mail\.ru | 
    ^NewsGator |
    Sphere\ Scout |                  # scout at sphere dot com
    OpenISearch |                    # http://www.openisearch.com/faq.html
    CyberPsy |                       # http://avalon.departament.com/lj-cyberpsy/disclaimer.html
    WWWC |                           # http://www.nakka.com/wwwc/
    Filer\.pro |                     # Nothing found on Google for this.
    Yacy |                           # http://yacy.net/bot.html
    Teleport\ Pro |                  # http://www.tenmax.com/teleport/pro/home.htm
    ShopWiki |                       # http://www.shopwiki.com/wiki/Help:Bot
    pirst
   )
}ixo;

sub is_bot {
	my ($class, $useragent) = @_;
		
	return defined $useragent ? $useragent =~ $crawler_agents ne "" : 0;
}

1;

