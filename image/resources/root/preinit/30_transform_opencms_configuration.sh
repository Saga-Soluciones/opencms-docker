#!/bin/bash

CONFIG_FOLDER="${OPENCMS_HOME}/WEB-INF/config/"
XSLT_BASE="/root/preinit/xml-transformations"
COMMON_DIR="${XSLT_BASE}/common"
VERSION_DIR="${XSLT_BASE}/${OPENCMS_VERSION}"

echo "Executing XSL transformations of OpenCms config files."

apply_xslts() {
    local dir="$1"
    if [ ! -d "${dir}" ]; then
        echo "XSLT directory ${dir} not found, skipping."
        return
    fi
    for XSLT in "${dir}"/*.xslt; do
        [ -f "${XSLT}" ] || continue

        XSLT_NAME="${XSLT##*/}"

        # Skip JSONAPI XSLT for OpenCms versions before 11 (module not available)
        if [[ "${XSLT_NAME}" == *"_activate_jsonapi"* ]]; then
            MAJOR=$(echo "${OPENCMS_VERSION}" | cut -d'.' -f1)
            if [ -n "${MAJOR}" ] && [ "${MAJOR}" -lt 11 ] 2>/dev/null; then
                echo "Skipping JSONAPI XSLT for OpenCms ${OPENCMS_VERSION} (requires OpenCms 11+)"
                continue
            fi
        fi

        CONFIG_NAME=$(echo "${XSLT_NAME}" | cut -d'_' -f 1)
        if [[ "${CONFIG_NAME}" == "solr-schema" ]]; then
            XML_CONFIG_FILE="${OPENCMS_HOME}/WEB-INF/solr/configsets/default/conf/schema.xml"
        else
            XML_CONFIG_FILE="${CONFIG_FOLDER}${CONFIG_NAME}.xml"
        fi

        PARAM_FILE="${XSLT/%.xslt/.params}"

        echo "."
        echo "Executing XSL transformation: ${XSLT}"
        echo "---------------------------------------------------"
        if [ -f "${XML_CONFIG_FILE}" ]; then
            if [ -f "${PARAM_FILE}" ]; then
                extraparams=$(cat "${PARAM_FILE}")
                extraparams=$(eval echo $extraparams)
                cat "${XSLT}" | xsltproc --novalid --nonet $extraparams --output "${XML_CONFIG_FILE}" - "${XML_CONFIG_FILE}"
                xslt_exit=$?
                if [ ${xslt_exit} -eq 0 ]; then
                    echo "Applied: ${XSLT_NAME} → ${XML_CONFIG_FILE}"
                else
                    echo "ERROR: XSLT transformation failed for ${XSLT_NAME} (exit code ${xslt_exit})"
                fi
            else
                cat "${XSLT}" | xsltproc --novalid --nonet --output "${XML_CONFIG_FILE}" - "${XML_CONFIG_FILE}"
                xslt_exit=$?
                if [ ${xslt_exit} -eq 0 ]; then
                    echo "Applied: ${XSLT_NAME} → ${XML_CONFIG_FILE}"
                else
                    echo "ERROR: XSLT transformation failed for ${XSLT_NAME} (exit code ${xslt_exit})"
                fi
            fi
        else
            echo "XML config file ${XML_CONFIG_FILE} does not exist, skipping"
        fi
        echo "---------------------------------------------------"
    done
}

apply_xslts "${COMMON_DIR}"
apply_xslts "${VERSION_DIR}"
