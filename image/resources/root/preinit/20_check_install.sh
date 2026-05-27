#!/bin/bash
if [ ! -d ${ARTIFACTS_FOLDER}libs ]; then
    mkdir -v -p ${ARTIFACTS_FOLDER}libs
fi

echo "Writing properties file to contain list of JARs used by the OpenCms core, to be used in later updates."
JAR_NAMES=$( zipinfo -1 ${ARTIFACTS_FOLDER}opencms.war *.jar | tr '\n' ',' )
JAR_NAMES_PROPERTIES="OPENCMS_CORE_LIBS=$JAR_NAMES"
JAR_NAMES_PROPERTIES_FILE=${ARTIFACTS_FOLDER}libs/core-libs.properties
echo "$JAR_NAMES_PROPERTIES" > $JAR_NAMES_PROPERTIES_FILE

if [ -f "${OPENCMS_HOME}/WEB-INF/config/opencms.properties" ] && grep -qE '^[[:space:]]*wizard\.enabled[[:space:]]*=[[:space:]]*false' "${OPENCMS_HOME}/WEB-INF/config/opencms.properties"
then
    echo "OpenCms already installed, updating modules and libs"

    admin_passwd=$(get_secret ADMIN_PASSWD_FILE ADMIN_PASSWD)
    if [ ! -z "$admin_passwd" ]; then
        echo "Changing Admin password for update"
        sed -i -- "s/Admin admin/\"Admin\" \"${admin_passwd}\"/g" /config/update*
    fi

    echo "Extract modules and libs"
    unzip -q -d ${ARTIFACTS_FOLDER}TEMP ${ARTIFACTS_FOLDER}opencms.war
    mv ${ARTIFACTS_FOLDER}TEMP/WEB-INF/packages/modules/* ${ARTIFACTS_FOLDER}

    mv ${ARTIFACTS_FOLDER}TEMP/WEB-INF/lib/* ${ARTIFACTS_FOLDER}libs
    echo "Renaming modules to remove version number"
    for file in ${ARTIFACTS_FOLDER}*.zip
    do
       if [[ $file =~ .*-.*\.zip ]]; then
           mv $file ${file%-*}".zip"
       fi
    done
    echo "Creating backup of opencms-modules.xml at ${OPENCMS_HOME}/WEB-INF/config/backups/opencms-modules-preinst.xml"
    if [ ! -d ${OPENCMS_HOME}/WEB-INF/config/backups ]; then
        mkdir -v -p ${OPENCMS_HOME}/WEB-INF/config/backups
    fi
    cp -f -v ${OPENCMS_HOME}/WEB-INF/config/opencms-modules.xml ${OPENCMS_HOME}/WEB-INF/config/backups/opencms-modules-preinst.xml

    echo "Updating config files with the version from the OpenCms WAR"
    unzip -q -d ${OPENCMS_HOME} ${ARTIFACTS_FOLDER}opencms.war WEB-INF/packages/modules/*.zip WEB-INF/lib/*.jar
    IFS=',' read -r -a FILES <<< "$UPDATE_CONFIG_FILES"
    for FILENAME in "${FILES[@]}"
    do
        if [ -f "${OPENCMS_HOME}/${FILENAME}" ]
        then
            rm -rf "${OPENCMS_HOME}/${FILENAME}"
        fi
        echo "Moving file from \"${ARTIFACTS_FOLDER}TEMP/${FILENAME}\" to \"${OPENCMS_HOME}/${FILENAME}\" ..."
        mv "${ARTIFACTS_FOLDER}TEMP/${FILENAME}" "${OPENCMS_HOME}/${FILENAME}"
    done

    echo "Updating OpenCms core JARs"
    if [ -f ${OPENCMS_HOME}/WEB-INF/lib/core-libs.properties ]; then
        echo "Deleting old JARs first"
        while IFS='=' read -r key value
        do
            key=$(echo $key | tr '.' '_')
            eval ${key}=\${value}
        done < "${OPENCMS_HOME}/WEB-INF/lib/core-libs.properties"

        IFS=',' read -r -a CORE_LIBS <<< "$OPENCMS_CORE_LIBS"
        for CORE_LIB in "${CORE_LIBS[@]}"
        do
            rm -f -v ${OPENCMS_HOME}/${CORE_LIB}
        done
    fi
    echo "Moving new JARs"
    mv ${ARTIFACTS_FOLDER}libs/* ${OPENCMS_HOME}/WEB-INF/lib/

    echo "Update modules core"
    bash /root/execute-opencms-shell.sh /config/update-core-modules.ocsh
else
    echo "OpenCms not installed yet, running setup"
    if [ ! -d ${WEBAPPS_HOME} ]; then
        mkdir -v -p ${WEBAPPS_HOME}
    fi

    if [ ! -d ${OPENCMS_HOME} ]; then
        mkdir -v -p ${OPENCMS_HOME}
    fi

    if [ -f "${OPENCMS_HOME}/WEB-INF/lib/opencms.jar" ]; then
        echo "Detected half-installed OpenCms (wizard still enabled). Wiping ${OPENCMS_HOME} for a clean retry."
        rm -rf ${OPENCMS_HOME}/* ${OPENCMS_HOME}/.[!.]* ${OPENCMS_HOME}/..?* 2>/dev/null || true
    fi

    echo "Unzip the .war"
    unzip -q -d ${OPENCMS_HOME} ${ARTIFACTS_FOLDER}opencms.war
    mv ${ARTIFACTS_FOLDER}libs/core-libs.properties ${OPENCMS_HOME}/WEB-INF/lib
    if [ ! -z "$ADMIN_PASSWD" ]; then
        echo "Changing Admin password for setup"
        sed -i -- "s/login \"Admin\" \"admin\"/login \"Admin\" \"admin\"\nsetPassword \"Admin\" \"$ADMIN_PASSWD\"\nlogin \"Admin\" \"$ADMIN_PASSWD\"/g" "${OPENCMS_HOME}/WEB-INF/setupdata/cmssetup.txt"
    fi

    CLASSPATH="$(shell_classpath)"
    echo "Install OpenCms using org.opencms.setup.CmsAutoSetup with properties \"${CONFIG_FILE}\""
    echo "Classpath: $CLASSPATH"
    # OpenCms 10.x CmsAutoSetup issues DROP DATABASE unconditionally before CREATE.
    # If the DB doesn't exist, the DROP fails fatally. Pre-create an empty schema so
    # both fresh install and re-install (with db.dropDb=true) succeed.
    # On 19+ this is unnecessary — the setup tool handles missing DB cleanly.
    if [[ "${OPENCMS_VERSION}" == 10.* ]]; then
        db_user=$(grep -E '^[[:space:]]*db\.create\.user' "${CONFIG_FILE}" | sed -E 's/.*=[[:space:]]*//')
        db_pwd=$(grep -E '^[[:space:]]*db\.create\.pwd' "${CONFIG_FILE}" | sed -E 's/.*=[[:space:]]*//')
        db_name=$(grep -E '^[[:space:]]*db\.name' "${CONFIG_FILE}" | sed -E 's/.*=[[:space:]]*//')
        echo "Ensuring database '${db_name}' exists on ${DB_HOST}:3306 before running CmsAutoSetup"
        for attempt in 1 2 3 4 5; do
            if mysql -h"${DB_HOST}" -u"${db_user}" -p"${db_pwd}" -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8;" 2>/dev/null; then
                echo "  DB '${db_name}' ready"
                break
            fi
            echo "  DB pre-create attempt ${attempt}/5 failed, sleeping 3s"
            sleep 3
        done
    fi
    SETUP_OK=false
    for attempt in 1 2 3 4 5; do
        echo "CmsAutoSetup attempt ${attempt}/5..."
        if java -classpath "${CLASSPATH}" org.opencms.setup.CmsAutoSetup -path ${CONFIG_FILE}; then
            SETUP_OK=true
            break
        fi
        echo "Setup attempt ${attempt} failed. Waiting 15s before retry..."
        sleep 15
    done
    if [ "${SETUP_OK}" = "false" ]; then
        echo "ERROR: CmsAutoSetup failed after 5 attempts. Check DB connectivity."
        exit 1
    fi

    echo "Deleting no longer  used files"
    rm -rf ${OPENCMS_HOME}/setup
    rm -rf ${OPENCMS_HOME}/WEB-INF/packages/modules/*.zip
fi

echo "Deleting artifacts folder"
rm -rf ${ARTIFACTS_FOLDER}
rm -rf ${OPENCMS_HOME}/setup