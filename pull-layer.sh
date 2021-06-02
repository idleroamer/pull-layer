#!/bin/bash

set -eu

reg="registry.hub.docker.com"
repo="gliderlabs"
image="alpine"
name="${repo}/${image}"
tag="latest"
parallel=4

INFO="\033[1;32m"
WARN="\033[0;33m"
FATAL="\033[0;31m"
CLEAR='\033[0m'

info() {
    if [ -n "${QUIET:-}" ]; then
        return
    fi

    printf "* ${INFO}${1}${CLEAR}\n"
}

warn() {
    printf "! ${WARN}${1}${CLEAR}\n"
}

fatal() {
    printf "!! ${FATAL}${1}${CLEAR}\n"
    exit 1
}

# Get auth token
token=$( curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${name}:pull" | jq -r .token )

# Get manifest
curl -s -H "Authorization: Bearer $token" "https://${reg}/v2/${name}/manifests/${tag}" &> manifest.json 
# Get layers
resp=$(curl -s -H "Authorization: Bearer $token" "https://${reg}/v2/${name}/manifests/${tag}" | jq -r .fsLayers[].blobSum )
layers=( $( echo $resp | tr ' ' '\n' | sort -u ) )

prun() {
    while (( "$#" )); do
        for (( i=0; i<$parallel; i++ )); do
            if [ -n "${1:-}" ]; then
                layer=${1##sha256:}
                if [ -f "${layer}" ]; then
                    checksum=$( shasum -a 256 $layer | awk '{ print $1 }' )
                    if [ "$checksum" != "$layer" ]; then
                        warn "File exist checksum doesn't match, download again: $layer"
                        curl -s -o $layer -L -H "Authorization: Bearer $token" "https://${reg}/v2/${name}/blobs/${1}" &
                    else
                       info "Skip file: $layer"
                    fi
                else
                    info "Download: $layer"
                    curl -s -o $layer -L -H "Authorization: Bearer $token" "https://${reg}/v2/${name}/blobs/${1}" &
                fi
                shift
            fi
        done
        wait
    done
}

prun ${layers[@]}

# Run twice in-case of failure
QUIET="true"
prun ${layers[@]}