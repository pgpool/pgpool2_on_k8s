#!/usr/bin/env bash
# -*- coding: utf-8 -*-

DIR="$(cd "$(dirname "${0}")" && pwd)"
PGPOOL_VER=${PGPOOL_VER:-4.4.3}
PGPOOL_IMG=${PGPOOL_IMG:-pgpool/pgpool}

docker image build \
    -f ${DIR}/Dockerfile.pgpool \
    -t ${PGPOOL_IMG}:${PGPOOL_VER} \
    --build-args PGPOOL_VER=${PGPOOL_VER} \
    ${DIR}/

docker image push ${PGPOOL_IMG}:${PGPOOL_VER}
