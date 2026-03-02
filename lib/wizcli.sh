#!/bin/bash

WIZCLI_IMAGE="public-registry.wiz.io/wiz-app/wizcli:1"
WIZCLI_LOCAL_TAG="wizcli:latest"

setupWizCli() {
    echo "--- :wiz: Setting up Wiz CLI"

    if [[ -z "${WIZ_DIR:-}" ]]; then
        echo "WIZ_DIR is not set"
        return 1
    fi

    mkdir -p "$WIZ_DIR"

    if ! docker pull "$WIZCLI_IMAGE"; then
        echo "Failed to pull Wiz CLI image"
        return 1
    fi

    docker tag "$WIZCLI_IMAGE" "$WIZCLI_LOCAL_TAG"

    echo "Verifying Wiz CLI version:"
    docker run --rm "$WIZCLI_LOCAL_TAG" version

    WIZ_API_DETAILS="$(aws secretsmanager get-secret-value --secret-id global/buildkite/wiz-cli-credentials --query "SecretString" --output text)"
    if [[ -z "$WIZ_API_DETAILS" ]]; then
        echo "Failed to retrieve Wiz API credentials from Secrets Manager"
        return 1
    fi

    WIZ_CLIENT_ID="$(jq -r '.client_id' <<<"$WIZ_API_DETAILS")"
    WIZ_CLIENT_SECRET="$(jq -r '.client_secret' <<<"$WIZ_API_DETAILS")"

    if [[ -z "$WIZ_CLIENT_ID" || "$WIZ_CLIENT_ID" == "null" || -z "$WIZ_CLIENT_SECRET" || "$WIZ_CLIENT_SECRET" == "null" ]]; then
        echo "Failed to parse client_id or client_secret from Wiz API credentials"
        return 1
    fi
}

dirScan() {
    SCAN_PATH="${BUILDKITE_PLUGIN_WIZ_PATH:-}"
    if [[ -z "${SCAN_PATH}" ]]; then
        echo "Missing path. Directory scans require a path to the directory to scan."
        return 1
    fi

    echo "--- :wiz: Running Wiz CLI directory scan on ${SCAN_PATH}"
    docker run \
        --rm \
        --mount type=bind,src="$PWD",dst=/scan \
        "$WIZCLI_LOCAL_TAG" \
        scan dir "/scan/${SCAN_PATH}" \
        --client-id "$WIZ_CLIENT_ID" \
        --client-secret "$WIZ_CLIENT_SECRET" \
        --by-policy-hits=BLOCK \
        --stdout=human \
        --human-output-file=/scan/dir-scan-result
    exit_code="$?"

    if [[ "${WIZ_ANNOTATIONS:-false}" == "false" ]]; then
        return 0
    fi

    case $exit_code in
    0)
        if [[ -n "${BUILDKITE_PLUGIN_WIZ_ANNOTATE_SUCCESS:-}" ]]; then
            buildAnnotation "dir" "$SCAN_PATH" true "$PWD/dir-scan-result" | buildkite-agent annotate --append --style 'success' --context 'ctx-wiz-dir-success'
        fi
        return 0
        ;;
    *)
        buildAnnotation "dir" "$SCAN_PATH" false "$PWD/dir-scan-result" | buildkite-agent annotate --append --context 'ctx-wiz-dir-warning' --style 'warning'
        return 0
        ;;
    esac
}
