all: reference.gen testbook.html

reference.gen: to_docbook.xsl xmlrpc.xml
        (xsltproc to_docbook.xsl xmlrpc.xml > reference.gen~) || true
        mv reference.gen~ reference.gen

xmlrpc.xml: xmlrpc.dtd authinfo.ent.xml checkfriends.mode.xml editevent.mode.xml editfriendgroups.mode.xml editfriends.mode.xml friendgroups.ent.xml friendof.mode.xml friendslist.ent.xml getdaycounts.mode.xml getevents.mode.xml getfriendgroups.mode.xml getfriends.mode.xml login.mode.xml moods.ent.xml postevent.mode.xml syncitems.mode.xml usejournal.ent.xml usejournals.ent.xml 

testbook.html: reference.gen testbook.xml
        xsltproc $(LJHOME)/doc/raw/docbook-xsl-1.45/html/docbook.xsl testbook.xml > testbook.html~ || true
        mv testbook.html~ testbook.html

clean:
        rm reference.gen testbook.html
