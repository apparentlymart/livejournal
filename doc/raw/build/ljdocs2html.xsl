<?xml version="1.0" encoding="iso-8859-1"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                version="1.0">

<xsl:import href="xsl-docbook/html/chunk.xsl"/>

<xsl:include href="titlepage.xsl"/>

<!-- canonical URL support -->
<xsl:param name="use.id.as.filename" select="1"/>

<!-- More inline with perl style docs -->
<xsl:param name="funcsynopsis.style" select="ansi"/>

<!-- Label sections -->
<xsl:param name="section.autolabel" select="1"/>

<!-- DocBook XSL adds extra navigation links which
     basically add 500 lines of unnecessary kludge.
     Turning this off saves on bandwidth and speed. -->
<xsl:param name="html.extra.head.links" select="0"/>

<xsl:param name="local.l10n.xml" select="document('')"/>

<l:i18n xmlns:l="http://docbook.sourceforge.net/xmlns/l10n/1.0">
  <l:l10n language="en">
    <l:context name="xref">
      <l:template name="chapter" text="Chapter %n: %t"/>
    </l:context>
    <l:context name="section-xref-numbered">
      <l:template name="section" text="Section %n: %t"/>
    </l:context>
  </l:l10n>
</l:i18n> 

</xsl:stylesheet>