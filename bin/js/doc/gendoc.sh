#!/usr/bin/env bash

# launcher script for jsdoc
# Author: Avi Deitcher
#
# This program is released under the MIT License as follows:

# Copyright (c) 2008-2009 Atomic Inc <avi@jsorm.com>
#
#Permission is hereby granted, free of charge, to any person
#obtaining a copy of this software and associated documentation
#files (the "Software"), to deal in the Software without
#restriction, including without limitation the rights to use,
#copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the
#Software is furnished to do so, subject to the following
#conditions:
##
#The above copyright notice and this permission notice shall be
#included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#OTHER DEALINGS IN THE SOFTWARE.
#
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=`dirname "$SCRIPT"`
JSDOCDIR="$SCRIPTPATH/jsdoc-toolkit"
JSDOC="$SCRIPTPATH/../../../htdocs/jsdoc" #we choose relative dir to allow to run script from sshfs
JSDOCTEMPLATEDIR="$JSDOCDIR/templates/jsdoc"
JSDIR="$SCRIPTPATH/../../../htdocs/js"

FILES=`cat docs_source*.txt`
OUTFILES=""

for jsfile in $FILES
do
  OUTFILES="$OUTFILES $JSDIR/$jsfile"
done

_BASEDIR="$JSDOCDIR"
_DOCDIR="-Djsdoc.dir=$JSDOC"
_APPDIR="$JSDOCDIR/app"
_TDIR="-Djsdoc.template.dir=$JSDOCTEMPLATEDIR"

mkdir -p $JSDOCDIR

CMD="java $_DOCDIR $_TDIR -jar $_BASEDIR/jsrun.jar $_APPDIR/run.js -d=$JSDOC --private $OUTFILES"
echo $CMD
$CMD
