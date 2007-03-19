<?xml version="1.0" encoding="iso-8859-1"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                version="1.0">

<xsl:template match="abstract" mode="titlepage.mode">
  <div class="{name(.)}">
    <h3>Abstract</h3>
    <p><xsl:apply-templates mode="titlepage.mode"/></p>
  </div>
</xsl:template>

<xsl:template match="authorgroup" mode="titlepage.mode">
  <div class="{name(.)}">
    <h3>Authors</h3>
    <p>
    <xsl:apply-templates mode="titlepage.mode"/>
    </p>
  </div>
</xsl:template>

<xsl:template match="author" mode="titlepage.mode">
  <b class="{name(.)}"><xsl:call-template name="person.name"/></b>
  <xsl:apply-templates mode="titlepage.mode" select="./contrib"/>
  <xsl:apply-templates mode="titlepage.mode" select="./affiliation"/>
  <br />
</xsl:template>

<xsl:template match="editor" mode="titlepage.mode">
  <b class="{name(.)}">Editor: <xsl:call-template name="person.name"/></b>
  <xsl:apply-templates mode="titlepage.mode" select="./contrib"/>
  <xsl:apply-templates mode="titlepage.mode" select="./affiliation"/>
  <br />
</xsl:template>

<xsl:template match="address" mode="titlepage.mode">
  <xsl:param name="suppress-numbers" select="'0'"/>

  <xsl:variable name="rtf">
    <xsl:apply-templates mode="titlepage.mode"/>
  </xsl:variable>

  <xsl:choose>
    <xsl:when test="$suppress-numbers = '0'
                    and @linenumbering = 'numbered'
                    and $use.extensions != '0'
                    and $linenumbering.extension != '0'">
      <div class="{name(.)}">
        <p>
          <xsl:call-template name="number.rtf.lines">
            <xsl:with-param name="rtf" select="$rtf"/>
          </xsl:call-template>
        </p>
      </div>
    </xsl:when>

    <xsl:otherwise>
      <xsl:apply-templates mode="titlepage.mode"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="affiliation" mode="titlepage.mode">
  <xsl:apply-templates mode="titlepage.mode"/>
</xsl:template>

</xsl:stylesheet>