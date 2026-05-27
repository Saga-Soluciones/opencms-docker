#!/bin/bash

if [ "$SERVLET_CONTAINER" != "tomcat" ]; then
    echo "Skipping $0 because we are not using Tomcat"
    exit
fi

# Tomcat server configuration
# This is ON PURPOSE done in the init / run phase NOT during image installation phase!
# In case you need a special Tomact configuration in a downsteam image, just overwrite this configuration script.
# Or, you can add the configuration as environment variable TOMCAT_OPTS.
if [ -z "${TOMCAT_OPTS}" ]; then
    TOMCAT_OPTS="-Xmx2g -Xms512m -server"
else
    TOMCAT_OPTS="${TOMCAT_OPTS}"
fi

if [ "${DEBUG}" == "true" ]; then
    TOMCAT_OPTS="${TOMCAT_OPTS}  -Xdebug -Xnoagent -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=*:8000 -Djava.compiler=NONE"
fi

# By default Tomcat will overwrite session cookies from multiple webapps on the same IP even different ports are used
# With this little 'sed' magic, each running docker instance will attach the ID of the running container to the session cookie name
echo "Making session cookie name unique and disabling web sockets ..."
sed -i "s/<Context>/<Context sessionCookieName=\"JSESSIONID_$HOSTNAME\" containerSciFilter=\"WsSci\">/" ${TOMCAT_HOME}/conf/context.xml

# Increasing Tomcat webresources cache size
echo "Setting webresources cache size to override defaults"
sed -i "s/<\/Context>/<Resources cachingAllowed=\"true\" cacheMaxSize=\"${WEBRESOURCES_CACHE_SIZE}\" \/><\/Context>/" ${TOMCAT_HOME}/conf/context.xml

# Disabling session persistence and adding JAR scanner filter
#
# OpenCms 10.x ships JSTL as jstl-1.1.2.jar + standard-1.1.2.jar, which do not match
# the upstream tldScan pattern (javax.servlet.jsp.jstl-*.jar). Restricting tldScan on
# 10.x causes "The absolute uri: [http://java.sun.com/jsp/jstl/core] cannot be resolved".
# For 10.x we only skip pluggability scanning (no SCI/web-fragment jars in 10.x lib set)
# and leave TLD scanning at Tomcat defaults.
#
# OpenCms 19+ keeps the original aggressive filter: TLD scan restricted to the JSTL jar.
if [[ "${OPENCMS_VERSION}" == 10.* ]]; then
    SCAN_FILTER='<JarScanner><JarScanFilter pluggabilitySkip=\"\*.jar\"\/><\/JarScanner>'
else
    SCAN_FILTER='<JarScanner><JarScanFilter pluggabilitySkip=\"\*.jar\" tldSkip=\"\*.jar\" tldScan=\"javax.servlet.jsp.jstl-\*.jar\"\/><\/JarScanner>'
fi
echo "Disabling session persistence and adding JAR scanner filter (OpenCms ${OPENCMS_VERSION}) ..."
sed -i "s/<\/Context>/<Manager pathname=\"\" \/>${SCAN_FILTER}<\/Context>/" ${TOMCAT_HOME}/conf/context.xml


echo "Setting java opts for Tomcat to: ${TOMCAT_OPTS}"
echo "JAVA_OPTS=\"-Djava.awt.headless=true -DDISPLAY=:0.0 ${TOMCAT_OPTS}\"" > ${TOMCAT_HOME}/bin/setenv.sh

echo "Using OpenCms optimized server.xml configuration for Tomcat"
mv -v /config/server.xml ${TOMCAT_HOME}/conf/server.xml