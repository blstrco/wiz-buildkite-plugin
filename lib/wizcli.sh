#!/bin/bash

WIZCLI_IMAGE="public-registry.wiz.io/wiz-app/wizcli:1"
WIZCLI_LOCAL_TAG="wizcli:latest"

setupWizCli() {
    echo "--- :wiz: Setting up Wiz CLI"

    if [[ -z "${WIZ_DIR:-}" ]]; then
        echo "WIZ_DIR is not set"
        exit 1
    fi

    mkdir -p "$WIZ_DIR"

    if ! docker pull "$WIZCLI_IMAGE"; then
        echo "Failed to pull Wiz CLI image"
        exit 1
    fi

    docker tag "$WIZCLI_IMAGE" "$WIZCLI_LOCAL_TAG"

    echo "Verifying Wiz CLI version:"
    docker run --rm "$WIZCLI_LOCAL_TAG" version

    WIZ_API_DETAILS="$(aws secretsmanager get-secret-value --secret-id global/buildkite/wiz-cli-credentials --query "SecretString" --output text)"
    if [[ -z "$WIZ_API_DETAILS" ]]; then
        echo "Failed to retrieve Wiz API credentials from Secrets Manager"
        exit 1
    fi

    WIZ_CLIENT_ID="$(jq -r '.client_id' <<<"$WIZ_API_DETAILS")"
    WIZ_CLIENT_SECRET="$(jq -r '.client_secret' <<<"$WIZ_API_DETAILS")"

    if [[ -z "$WIZ_CLIENT_ID" || "$WIZ_CLIENT_ID" == "null" || -z "$WIZ_CLIENT_SECRET" || "$WIZ_CLIENT_SECRET" == "null" ]]; then
        echo "Failed to parse client_id or client_secret from Wiz API credentials"
        exit 1
    fi
}

buildScanName() {
    local repo_name="${BUILDKITE_PIPELINE_SLUG:-repo}"
    local branch_name="${BUILDKITE_BRANCH:-branch}"
    local build_number="${BUILDKITE_BUILD_NUMBER:-0}"

    branch_name="${branch_name//\//-}"

    echo "${repo_name}:${branch_name}:${build_number}"
}

buildGithubPrUrl() {
    if [[ "${BUILDKITE_PULL_REQUEST:-false}" == "false" || -z "${BUILDKITE_PULL_REQUEST_REPO:-}" ]]; then
        return 0
    fi

    local pr_repo="${BUILDKITE_PULL_REQUEST_REPO%/}"
    pr_repo="${pr_repo%.git}"

    echo "${pr_repo}/pull/${BUILDKITE_PULL_REQUEST}"
}

buildScanTags() {
    local tags=("buildkite_url=${BUILDKITE_BUILD_URL}")
    local github_pr_url
    github_pr_url="$(buildGithubPrUrl)"

    if [[ -n "${github_pr_url}" ]]; then
        tags+=("github_pr_url=${github_pr_url}")
    fi

    printf '%s\n' "${tags[@]}"
}

dockerScan() {
    IMAGE="${BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS:-}"
    SCAN_NAME="$(buildScanName)"
    TAG_ARGS=()

    if [[ -z "${IMAGE}" ]]; then
        echo "Missing image address, docker scans require an address to pull the image"
        return 1
    fi

    while IFS= read -r tag; do
        TAG_ARGS+=(--tags "${tag}")
    done < <(buildScanTags)

    # Make sure local docker has the image
    echo "--- :wiz: Pulling image ${IMAGE}"
    docker pull "$IMAGE"

    echo "--- :wiz: Running Wiz CLI docker scan on ${IMAGE}"
    docker run \
        --rm \
        --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
        --mount type=bind,src="$PWD",dst=/scan \
        "$WIZCLI_LOCAL_TAG" \
        scan docker "$IMAGE" \
        --name "$SCAN_NAME" \
        --client-id "$WIZ_CLIENT_ID" \
        --client-secret "$WIZ_CLIENT_SECRET" \
        --by-policy-hits=BLOCK \
        --stdout=human \
        --human-output-file=/scan/docker-scan-result \
        "${TAG_ARGS[@]}"
    exit_code="$?"
    image_name=$(echo "$IMAGE" | cut -d "/" -f 2)

    if [[ "${WIZ_ANNOTATIONS:-false}" == "false" ]]; then
        return 0
    fi

    case $exit_code in
    0)
        if [[ -n "${BUILDKITE_PLUGIN_WIZ_ANNOTATE_SUCCESS:-}" ]]; then
            buildAnnotation "docker" "$image_name" true "$PWD/docker-scan-result" | buildkite-agent annotate --append --style 'success' --context 'ctx-wiz-docker-success'
        fi
        return 0
        ;;
    *)
        buildAnnotation "docker" "$image_name" false "$PWD/docker-scan-result" | buildkite-agent annotate --append --context 'ctx-wiz-docker-warning' --style 'warning'
        return 0
        ;;
    esac
}

dirScan() {
    SCAN_PATH="${BUILDKITE_PLUGIN_WIZ_PATH:-}"
    SCAN_NAME="$(buildScanName)"
    TAG_ARGS=()
    if [[ -z "${SCAN_PATH}" ]]; then
        echo "Missing path. Directory scans require a path to the directory to scan."
        return 1
    fi

    while IFS= read -r tag; do
        TAG_ARGS+=(--tags "${tag}")
    done < <(buildScanTags)

    echo "--- :wiz: Running Wiz CLI directory scan on ${SCAN_PATH}"
    docker run \
        --rm \
        --mount type=bind,src="$PWD",dst=/scan \
        "$WIZCLI_LOCAL_TAG" \
        scan dir "/scan/${SCAN_PATH}" \
        --name "$SCAN_NAME" \
        --client-id "$WIZ_CLIENT_ID" \
        --client-secret "$WIZ_CLIENT_SECRET" \
        --by-policy-hits=BLOCK \
        --stdout=human \
        --human-output-file=/scan/dir-scan-result \
        "${TAG_ARGS[@]}"
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
