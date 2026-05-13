<?xml version="1.0" encoding="UTF-8" ?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
    <xsl:output method="xml"
        doctype-system="http://www.opencms.org/dtd/6.0/opencms-system.dtd"
        indent="yes" />

    <xsl:template match="@* | node()">
        <xsl:copy>
            <xsl:apply-templates select="@* | node()" />
        </xsl:copy>
    </xsl:template>

    <!-- Europe/Madrid handles DST correctly (CET/CEST), unlike fixed GMT+01:00 -->
    <xsl:template match="/opencms/system/internationalization/timezone">
        <timezone>Europe/Madrid</timezone>
    </xsl:template>
</xsl:stylesheet>
