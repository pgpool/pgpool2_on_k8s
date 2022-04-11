#!/bin/bash

# Pgpool-II settings
export PGPOOL_PARAMS_PORT="${PGPOOL_PARAMS_PORT:-9999}"
export PGPOOL_PARAMS_BACKEND_HOSTNAME0="${PGPOOL_PARAMS_BACKEND_HOSTNAME0:-}"
export PGPOOL_PARAMS_BACKEND_PORT0="${PGPOOL_PARAMS_BACKEND_PORT0:-5432}"
export PGPOOL_PARAMS_BACKEND_WEIGHT0="${PGPOOL_PARAMS_BACKEND_WEIGHT0:-1}"
export PGPOOL_PARAMS_BACKEND_FLAG0="${PGPOOL_PARAMS_BACKEND_FLAG0:-ALLOW_TO_FAILOVER}"
export PGPOOL_PARAMS_LISTEN_ADDRESSES="${PGPOOL_PARAMS_LISTEN_ADDRESSES:-*}"
export PGPOOL_PARAMS_SR_CHECK_PERIOD="${PGPOOL_PARAMS_SR_CHECK_PERIOD:-0}"
export PGPOOL_PARAMS_HEALTH_CHECK_PERIOD="${PGPOOL_PARAMS_HEALTH_CHECK_PERIOD:-0}"
export PGPOOL_PARAMS_FAILOVER_ON_BACKEND_ERROR="${PGPOOL_PARAMS_FAILOVER_ON_BACKEND_ERROR:-off}"
export PGPOOL_PARAMS_SOCKET_DIR="/var/run/pgpool"
export PGPOOL_PARAMS_PCP_SOCKET_DIR="/var/run/pgpool"
export PGPOOL_PARAMS_WD_IPC_SOCKET_DIR="/var/run/pgpool"

export PGPOOL_ENABLE_POOL_PASSWD="${PGPOOL_ENABLE_POOL_PASSWD:-true}"
export PGPOOL_PASSWORD_ENCRYPTION_METHOD="${PGPOOL_PASSWORD_ENCRYPTION_METHOD:-scram-sha-256}"
export PGPOOL_SKIP_PASSWORD_ENCRYPTION="${PGPOOL_SKIP_PASSWORD_ENCRYPTION:-false}"
export PGPOOL_PCP_USER="${PGPOOL_PCP_USER:-}"
export PGPOOL_PCP_PASSWORD="${PGPOOL_PCP_PASSWORD:-}"

function env_error_check() {
    if [[ -z ${!1} ]]; then
        echo "ERROR: $1 environment variable is not set, exiting..."
        exit 1
    fi
}

generate_pool_passwd() {

    local cmd=""
    local pgpoolkey_file="${PGPOOL_INSTALL_DIR}/etc/.pgpoolkey"

    touch ${pgpoolkey_file}
    chmod 0600 "${pgpoolkey_file}"

    touch ${PGPOOL_INSTALL_DIR}/etc/pool_passwd
    chmod 0600 ${PGPOOL_INSTALL_DIR}/etc/pool_passwd

    if [[ "${PGPOOL_ENABLE_POOL_PASSWD}" =~ ^(yes|true|on)$ ]]; then
        echo "Generating pool_passwd..."

        if [[ "${PGPOOL_PASSWORD_ENCRYPTION_METHOD}" == "scram-sha-256" ]]; then
            echo $(head -c 20 /dev/urandom | base64) > "${pgpoolkey_file}"
            cmd="pg_enc -k ${pgpoolkey_file}"
        elif [[ "${PGPOOL_PASSWORD_ENCRYPTION_METHOD}" == "md5" ]]; then
            cmd="pg_md5"
        fi
    else
        echo "Skip generating pool_passwd. Use password authentication between client and Pgpool-II and force ssl on all connections in pool_hba.conf."

        export PGPOOL_PASSWORD_ENCRYPTION_METHOD="password"
        echo -e "\n" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
        echo "ssl = 'on'" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
        echo "enable_pool_hba = 'on'" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
        return
    fi

    # Register username and password to pool_passwd
    # All the environment variables defined in format *_USERNAME, *_PASSWORD will be registered.
    ev_usernames=($(printenv | grep -E '.+_USERNAME=.+' | awk -F "_" '{print $1}'))
    for ev_username in "${ev_usernames[@]}"
    do
        username=$(eval "echo \$${ev_username}_USERNAME")
        password=$(eval "echo \$${ev_username}_PASSWORD")

        if [[ -n "${username}" ]]  && [[ -n "${password}" ]]; then
            if [[ "${PGPOOL_SKIP_PASSWORD_ENCRYPTION}" =~ ^(yes|true|on)$ ]]; then
                echo "Skip password encryption. Use the encrypted password."
                echo "${username}:${password}" >> ${PGPOOL_INSTALL_DIR}/etc/pool_passwd
            else
                ${PGPOOL_INSTALL_DIR}/bin/${cmd} -m -f ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf -u ${username} ${password} > /dev/null
            fi
        else
            echo "password for $username user is not defined."
        fi
    done
}

generate_pcp_conf() {

    touch ${PGPOOL_INSTALL_DIR}/etc/pcp.conf
    chmod 0600 ${PGPOOL_INSTALL_DIR}/etc/pcp.conf

    if [[ -n "${PGPOOL_PCP_USER}" ]] && [[ -n "${PGPOOL_PCP_PASSWORD}" ]]; then
        echo "Generating pcp.conf..."
        if [[ "${PGPOOL_SKIP_PASSWORD_ENCRYPTION}" =~ ^(yes|true|on)$ ]]; then
            echo "Skip password encryption. Use the encrypted password."
            echo "${PGPOOL_PCP_USER}:${PGPOOL_PCP_PASSWORD}" >> ${PGPOOL_INSTALL_DIR}/etc/pcp.conf
        else
            echo "${PGPOOL_PCP_USER}:"`${PGPOOL_INSTALL_DIR}/bin/pg_md5 ${PGPOOL_PCP_PASSWORD}` >> ${PGPOOL_INSTALL_DIR}/etc/pcp.conf
        fi
    else
        echo "Skip generating pcp.conf. PGPOOL_PCP_USER or PGPOOL_PCP_PASSWORD isn't defined."
    fi
}

generate_pool_hba_conf() {

    if [[ -f ${PGPOOL_CONF_VOLUME}/pool_hba.conf ]]; then

        cp ${PGPOOL_CONF_VOLUME}/pool_hba.conf ${PGPOOL_INSTALL_DIR}/etc/
        grep -E "^hostssl" ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf > /dev/null

        if [[ $? -ne 0 ]] && [[ ! "${PGPOOL_ENABLE_POOL_PASSWD}" =~ ^(yes|true|on)$ ]]; then
            echo "ERROR: If pool_passwd is disabled, password authentication will be used. You must add hostssl lines in pool_hba.conf to secure all connections."
            exit 1
        else
            echo "Custom pool_hba.conf file detected. Use custom pool_hba.conf."
            return;
        fi
     fi

    grep -E "^enable_pool_hba\s*=" ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf | tail -1 | grep -E "^enable_pool_hba\s*=\s*'?on'?" > /dev/null
    if [[ $? -ne 0 ]]; then
        echo "Skip generating pool_hba.conf due to enable_pool_hba = off."
        return;
    fi

    echo "Generating pool_hba.conf..."

    echo "local   all    all        trust" >> ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf

    grep -E "^ssl\s*=" ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf | tail -1 | grep -E "^ssl\s*=\s*'?on'?" > /dev/null

    if [[ $? -eq 0 ]]; then
        echo "Add hostssl entry in pool_hba.conf to enable TLS connections."
        echo "hostssl    all    all    all    ${PGPOOL_PASSWORD_ENCRYPTION_METHOD}" >> ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf
    else
        echo "host    all    all    all    ${PGPOOL_PASSWORD_ENCRYPTION_METHOD}" >> ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf
    fi
}

function generate_certs() {

    if [[ -f "${PGPOOL_CONF_VOLUME}/tls/tls.key" ]] && [[ -f "${PGPOOL_CONF_VOLUME}/tls/tls.crt" ]]; then

        echo "Custom certificate detected. Use custom certificate."
        mkdir ${PGPOOL_INSTALL_DIR}/tls
        cp ${PGPOOL_CONF_VOLUME}/tls/* ${PGPOOL_INSTALL_DIR}/tls/

        echo -e "\n" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
        echo "ssl = 'on'" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
    else

        grep -E "^ssl\s*=" ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf | tail -1 | grep -E "^ssl\s*=\s*'?on'?" > /dev/null

        if [[ $? -ne 0 ]]; then
            return
        fi

        echo "Generating self-signed certificate..."

        mkdir ${PGPOOL_INSTALL_DIR}/tls

        /usr/bin/openssl req -nodes -new -x509 -days 1825 -subj /CN=$(hostname) \
            -keyout ${PGPOOL_INSTALL_DIR}/tls/tls.key \
            -out ${PGPOOL_INSTALL_DIR}/tls/tls.crt > /dev/null 2>&1

        if [[ $? -ne 0 ]]; then
            echo "ERROR: failed to generate private key and certificate."
            exit 1
        fi
    fi

    echo -e "\n" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
    echo "ssl_key = '${PGPOOL_INSTALL_DIR}/tls/tls.key'" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
    echo "ssl_cert = '${PGPOOL_INSTALL_DIR}/tls/tls.crt'" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
}

validate_pgpool_settings() {
    local sr_check_period=0
    local health_check_period=0
    local sr_check_user=""
    local sr_check_password=""
    local health_check_user=""
    local health_check_password=""
    local backend_hostname0=""
    local pgpool_conf="${PGPOOL_INSTALL_DIR}/etc/pgpool.conf"

    # Validate sr_check_*
    sr_check_user=$(grep -E "^sr_check_user\s*=" ${pgpool_conf} | tail -1 | sed -e "s/^sr_check_user\s*=\s*'\(.*\)'/\1/g")
    sr_check_password=$(grep -E "^sr_check_password\s*=" ${pgpool_conf} | tail -1 | sed -e "s/^sr_check_password\s*=\s*'\(.*\)'/\1/g")
    grep -E "^sr_check_period\s*=" ${pgpool_conf} | tail -1 | grep -E "^sr_check_period\s*=\s*'?0'?" > /dev/null

    if [[ $? -ne 0 ]]; then
        if [[ -z "${sr_check_user}" ]]; then
            echo "ERROR: sr_check_user is not set, exiting..."
            exit 1
        fi

        grep -E "^${sr_check_user}:.+" ${PGPOOL_INSTALL_DIR}/etc/pool_passwd > /dev/null

        if [[ $? -ne 0 ]] && [[ -z ${sr_check_password} ]]; then
            echo "ERROR: password of sr_check_user is not set. Set sr_check_password or environment variable. exiting..."
            exit 1
        fi
    fi

    # Validate health_check_*
    health_check_user=$(grep -E "^health_check_user\s*=" ${pgpool_conf} | tail -1 | sed -e "s/^health_check_user\s*=\s*'\(.*\)'/\1/g")
    health_check_password=$(grep -E "^health_check_password\s*=" ${pgpool_conf} | tail -1 | sed -e "s/^health_check_password\s*=\s*'\(.*\)'/\1/g")
    health_check_period=$(grep -E "^health_check_period\s*=" ${pgpool_conf} | tail -1 | sed -e "s/^health_check_period\s*=\s*'\?\([0-9]\+\)'\?[^0-9]*/\1/g")

    if [[ "${health_check_period}" -gt 0 ]]; then
        if [[ -z "${health_check_user}" ]]; then
            echo "ERROR: health_check_user is not set, exiting..."
            exit 1
        fi

        grep -E "^${health_check_user}:.+" ${PGPOOL_INSTALL_DIR}/etc/pool_passwd > /dev/null

        if [[ $? -ne 0 ]] && [[ -z ${health_check_password} ]]; then
            echo "ERROR: password of health_check_user is not set. Set health_check_password or environment variable. exiting..."
            exit 1
        fi
    fi

    # Validate backend_hostname0
    backend_hostname0=$(grep -E "^backend_hostname0\s*=" ${pgpool_conf} | tail -1 | sed -e "s/^backend_hostname0\s*=\s*'\(.*\)'/\1/g")

    if [[ -z "${backend_hostname0}" ]]; then
        echo "ERROR: backend_hostname0 is not set, exiting..."
        exit 1
    fi

    # Validate failover_on_backend_error
    # If "failover_on_backend_error = on" isn't specified, turn it off.
    grep -E "^failover_on_backend_error\s*=" ${pgpool_conf} | tail -1 | grep -E "^failover_on_backend_error\s*=\s*'?on'?" > /dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "\n" >> ${pgpool_conf}
        echo "failover_on_backend_error = 'off'" >> ${pgpool_conf}
    fi
}

if [[ -f ${PGPOOL_CONF_VOLUME}/pgpool.conf ]]; then
    echo "Configuring Pgpool-II..."
    echo "Custom pgpool.conf file detected. Use custom configuration files."

    cp ${PGPOOL_CONF_VOLUME}/pgpool.conf ${PGPOOL_INSTALL_DIR}/etc/

else
    echo "Configuring Pgpool-II..."
    echo "No custom pgpool.conf detected. Use environment variables and default config."

    cp ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf.sample ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf

    # Error check
    env_error_check "PGPOOL_PARAMS_BACKEND_HOSTNAME0"

    # Setting pgpool.conf using environment variables with "PGPOOL_PARAMS_*"
    # For example, environment variable "PGPOOL_PARAMS_PORT=9999" is converted to "port = '9999'"
    printenv | sed -nr "s/^PGPOOL_PARAMS_(.*)=(.*)/\L\1 = '\E\2'/p" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
fi

generate_pool_passwd
generate_pcp_conf
generate_pool_hba_conf
generate_certs
validate_pgpool_settings

exec "$@"
