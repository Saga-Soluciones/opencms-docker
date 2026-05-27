<?xml version="1.0" encoding="UTF-8" ?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
    <xsl:param name="server_url" select="'http://localhost:8080'" />
    <xsl:output method="xml"
        doctype-system="http://www.opencms.org/dtd/6.0/opencms-sites.dtd"
        indent="yes" />
    <xsl:strip-space elements="*" />

    <xsl:template match="@* | node()">
        <xsl:copy>
            <xsl:apply-templates select="@* | node()" />
        </xsl:copy>
    </xsl:template>

    <xsl:template match="/opencms/sites/workplace-server">
        <workplace-server><xsl:value-of select="$server_url" /></workplace-server>
    </xsl:template>

    <xsl:template match="/opencms/sites/site/@server">
        <xsl:attribute name="server"><xsl:value-of select="$server_url" /></xsl:attribute>
    </xsl:template>
</xsl:stylesheet>
