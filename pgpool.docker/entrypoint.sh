#!/bin/bash

# Pgpool-II settings
export PGPOOL_PARAMS_PORT=${PGPOOL_PARAMS_PORT:-$PGPOOL_PORT}
export PGPOOL_PARAMS_BACKEND_HOSTNAME0=${PGPOOL_PARAMS_BACKEND_HOSTNAME0:-}
export PGPOOL_PARAMS_BACKEND_PORT0=${PGPOOL_PARAMS_BACKEND_PORT0:-5432}
export PGPOOL_PARAMS_BACKEND_WEIGHT0=${PGPOOL_PARAMS_BACKEND_WEIGHT0:-1}
export PGPOOL_PARAMS_BACKEND_FLAG0="ALWAYS_PRIMARY|DISALLOW_TO_FAILOVER"
export PGPOOL_PARAMS_BACKEND_HOSTNAME1=${PGPOOL_PARAMS_BACKEND_HOSTNAME1:-}
export PGPOOL_PARAMS_BACKEND_PORT1=${PGPOOL_PARAMS_BACKEND_PORT1:-5432}
export PGPOOL_PARAMS_BACKEND_WEIGHT1=${PGPOOL_PARAMS_BACKEND_WEIGHT1:-1}
export PGPOOL_PARAMS_BACKEND_FLAG1=DISALLOW_TO_FAILOVER
export PGPOOL_PARAMS_LISTEN_ADDRESSES=*
export PGPOOL_PARAMS_SR_CHECK_PERIOD=${PGPOOL_PARAMS_SR_CHECK_PERIOD:-0}
export PGPOOL_PARAMS_SR_CHECK_PERIOD=${PGPOOL_PARAMS_HEALTH_CHECK_PERIOD:-0}
export PGPOOL_PARAMS_SOCKET_DIR=/var/run/pgpool
export PGPOOL_PARAMS_PCP_SOCKET_DIR=/var/run/pgpool
export PGPOOL_PARAMS_WD_IPC_SOCKET_DIR=/var/run/pgpool


function env_error_check() {
    if [[ -z ${!1} ]]; then
        echo "$1 environment variable is not set, exiting..."
        exit 1
    fi
}

if [[ -f ${PGPOOL_CONF_VOLUME}/pgpool.conf ]]; then
    echo "Configuring Pgpool-II..."
    echo "Custom pgpool.conf file detected. Use custom configuration files."

    cp ${PGPOOL_CONF_VOLUME}/* ${PGPOOL_INSTALL_DIR}/etc/
else

    echo "Configuring Pgpool-II..."
    echo "No cunstom pgpool.conf detected. Use environment variables and default config."

    cp ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf.sample-stream ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf
    cp ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf.sample ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf
    cp ${PGPOOL_INSTALL_DIR}/etc/pcp.conf.sample ${PGPOOL_INSTALL_DIR}/etc/pcp.conf

    # Error check
    env_error_check "PGPOOL_PARAMS_BACKEND_HOSTNAME0"
    env_error_check "PGPOOL_PARAMS_BACKEND_HOSTNAME1"
    env_error_check "POSTGRES_USERNAME"
    env_error_check "POSTGRES_PASSWORD"

    # Setting pgpool.conf using environment variables with "PGPOOL_PARAMS_*"
    # For example, environment variable "PGPOOL_PARAMS_PORT=9999" is converted to "port = '9999'"
    printenv | sed -nr "s/^PGPOOL_PARAMS_(.*)=(.*)/\L\1 = '\E\2'/p" >> ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf

    # Setting pool_hba.conf
    echo "host    all    all    0.0.0.0/0    md5" >> ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf
fi

# Register username and password to pool_passwd and pcp.conf
# All the environment variables defined in format *_USERNAME, *_PASSWORD will be registered.
ev_usernames=($(printenv | grep -E '.+_USERNAME=.+' | awk -F "_" '{print $1}'))
for ev_username in "${ev_usernames[@]}"
do

    username=$(eval "echo \$${ev_username}_USERNAME")
    password=$(eval "echo \$${ev_username}_PASSWORD")

    if [[ -n "${username}"  && -n "${password}" ]]; then
        ${PGPOOL_INSTALL_DIR}/bin/pg_md5 -m -f ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf -u ${username} ${password}
        echo "${username}:"`${PGPOOL_INSTALL_DIR}/bin/pg_md5 ${password}` >> ${PGPOOL_INSTALL_DIR}/etc/pcp.conf
    else
        echo "password for $username user is not defined."
    fi

done

exec "$@"
