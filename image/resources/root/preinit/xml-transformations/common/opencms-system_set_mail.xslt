<?xml version="1.0" encoding="UTF-8" ?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
    <xsl:output method="xml"
        doctype-system="http://www.opencms.org/dtd/6.0/opencms-system.dtd"
        indent="yes" />
    <xsl:strip-space elements="*" />

    <xsl:template match="@* | node()">
        <xsl:copy>
            <xsl:apply-templates select="@* | node()" />
        </xsl:copy>
    </xsl:template>

    <xsl:template match="/opencms/system/mail">
        <mail>
            <mailfrom>opencms@localhost</mailfrom>
            <mailhost name="mailhog" port="1025" order="10" protocol="smtp"/>
        </mail>
    </xsl:template>
</xsl:stylesheet>
