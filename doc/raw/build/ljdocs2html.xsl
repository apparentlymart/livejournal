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

<xsl:param name="chunk.section.depth" select="0"/>

<xsl:param name="local.l10n.xml" select="document('')"/>

<xsl:param name="toc.section.depth">0</xsl:param>

<xsl:param name="navig.showtitles">1</xsl:param>

<xsl:template name="anchor">
  <xsl:param name="node" select="."/>
  <xsl:param name="conditional" select="1"/>
  <xsl:variable name="id">
    <xsl:call-template name="object.id">
      <xsl:with-param name="object" select="$node"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:if test="$conditional = 0 or $node/@id">
    <a class="linkhere" href="#{$id}">&#x00bb;</a> <a name="{$id}"/>
  </xsl:if>
</xsl:template>

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