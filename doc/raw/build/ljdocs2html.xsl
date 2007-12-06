<?xml version="1.0" encoding="iso-8859-1"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                version="1.0">

<xsl:import href="xsl-docbook/html/chunkfast.xsl"/>

<!-- canonical URL support -->
<xsl:param name="use.id.as.filename" select="1"/>

<!-- More inline with perl style docs -->
<xsl:param name="funcsynopsis.style">ansi-nontabular</xsl:param>

<!-- Label sections -->
<xsl:param name="section.autolabel" select="1"/>

<xsl:param name="local.l10n.xml" select="document('')"/>

<xsl:param name="toc.section.depth">2</xsl:param>

<xsl:param name="chunk.section.depth" select="1"/>

<xsl:param name="chunk.first.sections" select="1"/>

<xsl:param name="chunker.output.indent" select="'yes'"></xsl:param>

<xsl:param name="generate.id.attributes" select="1"></xsl:param>

<xsl:param name="chunker.output.doctype-public">-//W3C//DTD HTML 4.01 Transitional//EN</xsl:param>
<xsl:param name="chunker.output.doctype-system">http://www.w3.org/TR/html4/loose.dtd</xsl:param>

<xsl:param name="make.valid.html" select="1"></xsl:param>

<xsl:param name="html.cleanup" select="1"></xsl:param>

<xsl:param name="refentry.generate.title" select="1"/>

<xsl:param name="refentry.generate.name" select="0"/>

<xsl:param name="editedby.enabled">1</xsl:param>

<xsl:param name="glossary.sort" select="1"></xsl:param>
<xsl:param name="glossentry.show.acronym">primary</xsl:param>


<xsl:template match="question">
  <xsl:variable name="deflabel">
    <xsl:choose>
      <xsl:when test="ancestor-or-self::*[@defaultlabel]">
        <xsl:value-of select="(ancestor-or-self::*[@defaultlabel])[last()]
                              /@defaultlabel"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="qanda.defaultlabel"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:variable>

  <tr class="{name(.)}">
    <td align="left" valign="top">
      <xsl:call-template name="anchor">
        <xsl:with-param name="node" select=".."/>
        <xsl:with-param name="conditional" select="0"/>
      </xsl:call-template>
      <!-- Why do they call this twice?
      <xsl:call-template name="anchor">
        <xsl:with-param name="conditional" select="0"/>
      </xsl:call-template> -->

      <b>
        <xsl:apply-templates select="." mode="label.markup"/>
        <xsl:text>. </xsl:text> <!-- FIXME: Hack!!! This should be in the locale! -->
      </b>
    </td>
    <td align="left" valign="top">
      <xsl:choose>
        <xsl:when test="$deflabel = 'none' and not(label)">
          <b><xsl:apply-templates select="*[name(.) != 'label']"/></b>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates select="*[name(.) != 'label']"/>
        </xsl:otherwise>
      </xsl:choose>
    </td>
  </tr>
</xsl:template>

<xsl:template match="ulink" name="ulink">
  <xsl:variable name="link">
    <a>
      <xsl:if test="@id">
        <xsl:attribute name="name">
          <xsl:value-of select="@id"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:attribute name="href"><xsl:value-of select="@url"/></xsl:attribute>
      <xsl:if test="$ulink.target != ''">
        <xsl:attribute name="target">
          <xsl:value-of select="$ulink.target"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:choose>
        <xsl:when test="count(child::node())=0">
          <xsl:value-of select="@url"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates/>
        </xsl:otherwise>
      </xsl:choose>
      <span class="ulink"> <img src="/img/link.png" alt="[o]" title="" /></span>
    </a>
  </xsl:variable>
  <xsl:copy-of select="$link"/>
</xsl:template>

<xsl:template match="chapter[@status = 'prelim']" mode="class.value">
  <xsl:value-of select="'draft-chapter'"/>
</xsl:template>

<xsl:param name="callout.graphics.path">/img/docs/callouts/</xsl:param>
<xsl:param name="img.src.path">/img/docs/</xsl:param>

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

