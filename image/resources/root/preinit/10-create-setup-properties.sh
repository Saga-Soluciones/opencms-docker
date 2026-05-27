#!/bin/bash

if [ -f /custom-setup.properties ]; then
    echo "Using custom setup properties file:"
    echo "OpenCms Setup: Copying /custom-setup.properties to '$CONFIG_FILE'"
    cp /custom-setup.properties "$CONFIG_FILE"
else
    OCSERVER=${SERVER_URL:-http://localhost}
    HWADDR=$(cat /sys/class/net/eth0/address)

    DB_USER=$DB_USER
    DB_PWD=$(get_secret DB_PASSWD_FILE DB_PASSWD)
    DB_DB=$DB_NAME
    DB_PRODUCT=mysql

    # OpenCms 10.x needs the full URL (DB name + connection params) embedded in
    # db.connection.url because its setup tool uses the value verbatim.
    # OpenCms 19+ expects a bare URL ending with a trailing slash; the setup
    # tool appends db.name and its own params. Mixing the two formats yields a
    # malformed JDBC URL on the 19+ branch (e.g. "?p1=v1?p2=v2").
    if [[ "${OPENCMS_VERSION}" == 10.* ]]; then
        DB_URL="jdbc:mysql://${DB_HOST}:3306/${DB_DB}?useSSL=false&allowPublicKeyRetrieval=true"
    else
        DB_URL="jdbc:mysql://${DB_HOST}:3306/"
    fi
    DB_DRIVER=org.gjt.mm.mysql.Driver

    # Create setup.properties
    echo "OpenCms Setup: Writing configuration to '$CONFIG_FILE'"
    echo "-- Components: $OPENCMS_COMPONENTS"
    PROPERTIES="

    setup.webapp.path=$OPENCMS_HOME
    setup.default.webapp=
    setup.install.components=$OPENCMS_COMPONENTS
    setup.show.progress=true

    db.product=$DB_PRODUCT
    db.provider=$DB_PRODUCT
    db.create.user=$DB_USER
    db.create.pwd=$DB_PWD
    db.worker.user=$DB_USER
    db.worker.pwd=$DB_PWD
    db.connection.url=$DB_URL
    db.name=$DB_DB
    db.create.db=true
    db.create.tables=true
    db.dropDb=true
    db.default.tablespace=
    db.index.tablespace=
    db.jdbc.driver=$DB_DRIVER
    db.template.db=
    db.temporary.tablespace=

    server.url=$OCSERVER
    server.name=OpenCmsServer
    server.ethernet.address=$HWADDR
    server.servlet.mapping=

    "
    echo "$PROPERTIES" > $CONFIG_FILE || { echo "Error: Couldn't write to '$CONFIG_FILE'!" ; exit 1 ; }
fi