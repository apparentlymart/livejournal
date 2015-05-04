LiveJournal Source Archive
==========================

This is the codebase behind `LiveJournal.com`_, spanning from the creation of the repository
until the official repository was closed to the public by *LiveJournal.com, Inc* in 2014.

Although the official repository is no longer public, the source code until that point remains licensed under the GNU GPL,
with contributions from various different copyright holders.

This history in this codebase spanned three companies (`Danga Interactive`_, Six Apart and `LiveJournal.com, Inc`_) and over
80 different people committed the 21,427 changes reflected here that are dated from June 3, 2001 but actually reflect work from
as far back as 1998. Since LiveJournal development used CVS and Subversion, the converted git history is unable to directly
credit the one-off contributions of a multitude of other authors that did not have commit access, whose additions are merely
noted within the commit messages.

LiveJournal was unusual in that almost all of the code used to run the site was open source, and paid staffers collaborated
with members of the community to maintain and improve the code. This model resulted in a unique community that hasn't yet
been replicated as of this writing, and led to many professional relationships and friendships that persist to this day, both
among those who wrote code and those who contributed in other ways, such as helping other users in the support forum, creating
native desktop clients, and maintaining a multitude of LiveJournal communities to help users get the best out of the site.

This codebase was originally in CVS, was converted to Subversion, and then was finally converted again to Git to create this
archive. In the final conversion to git, authorship information was preserved as much as possible, with an unfortunate weight
towards the early contributors only because the Danga and Six Apart crews have kept in touch over the years.

Authorship detective work was done by Martin Atkins and Abe Hassan, who were both contributors during the Danga and
Six Apart phases of LiveJournal's life. Sorry to those who were missed and who remain identified only by their LJ username
or committer username.

This repository is intended as an archive for posterity and will not be used for any future LiveJournal development. The
closest thing remaining to an open source LiveJournal codebase is Dreamwidth_,
which is a fork from the LiveJournal codebase that did not preserve the commit history.

If you're interested in the LiveJournal source code then you may also be interested in S2_, which was (and still is, at the
time of writing) the templating engine behind LiveJournal, its photo-hosting sibling Fotobilder, Webdrove_ and a few other
codebases that are of little significance at this point.

.. _LiveJournal.com: http://www.livejournal.com/
.. _Danga Interactive: http://danga.com/
.. _LiveJournal.com, Inc: http://livejournalinc.com/
.. _Dreamwidth: https://www.dreamwidth.org/site/opensource
.. _S2: https://github.com/apparentlymart/s2
.. _WebDrove: https://github.com/apparentlymart/webdrove
