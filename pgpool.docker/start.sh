#!/bin/bash

# Start Pgpool-II
echo "Starting Pgpool-II..."
${PGPOOL_INSTALL_DIR}/bin/pgpool -n \
    -f ${PGPOOL_INSTALL_DIR}/etc/pgpool.conf \
    -F ${PGPOOL_INSTALL_DIR}/etc/pcp.conf \
    -a ${PGPOOL_INSTALL_DIR}/etc/pool_hba.conf \
    -k ${PGPOOL_INSTALL_DIR}/etc/.pgpoolkey
