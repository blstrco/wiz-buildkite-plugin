#!/usr/bin/env bash

set -euo pipefail

# Used to generate the Wiz CLI arguments, including using the scan type for specific arguments
# $1 - Scan Type
function build_wiz_cli_args() {
    local scan_type="${1}"

    PARAMETER_FILES="${BUILDKITE_PLUGIN_WIZ_PARAMETER_FILES:-}"
    IAC_TYPE="${BUILDKITE_PLUGIN_WIZ_IAC_TYPE:-}"
    SCAN_FORMAT="${BUILDKITE_PLUGIN_WIZ_SCAN_FORMAT:=human}"
    SHOW_SECRET_SNIPPETS="${BUILDKITE_PLUGIN_WIZ_SHOW_SECRET_SNIPPETS:=false}"
    local -a args=()

    # Global Parameters
    if [[ "${SHOW_SECRET_SNIPPETS}" == "true" ]]; then
        args+=("--show-secret-snippets")
    fi

    local scan_formats=("human" "json" "sarif")
    if [[ ${scan_formats[*]} =~ ${SCAN_FORMAT} ]]; then
        args+=("--format=${SCAN_FORMAT}")
    else
        echo "+++ 🚨 Invalid Scan Format: ${SCAN_FORMAT}" >&2
        echo "Valid Formats: ${scan_formats[*]}" >&2
        exit 1
    fi

    # Define valid formats
    local valid_file_formats=("human" "json" "sarif" "csv-zip")

    # Default file output which is used for build annotation
    args+=("--output=/scan/result/output,human")

    # Declare result array
    declare -a result

    # Read file output formats into result array
    if plugin_read_list_into_result "BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT"; then
        declare -A seen_formats
        for format in "${result[@]}"; do
            # Multiple output files with the same format are supported
            # but would need to rework this loop to handle and validate i.e., specifying file names, etc.,
            #  -o, --output file-outputs             Output to file, can be passed multiple times to output to multiple files with possibly different formats.
            #                                        Must be specified in the following format: file-path[,file-format[,policy-hits-only[,group-by[,include-audit-policy-hits]]]]
            #                                        Options for file-format: [csv-zip, human, json, sarif], policy-hits-only: [true, false], group-by: [default, layer, resource], include-audit-policy-hits: [true, false]
            # Check for duplicates
            if [[ -n "${seen_formats[$format]:-}" ]]; then
                echo "+++ ⚠️  Duplicate file output format ignored: ${format}"
                continue
            fi
            seen_formats["$format"]=1

            # Check for invalid formats
            if in_array "$format" "${valid_file_formats[@]}"; then
                args+=("--output=/scan/result/output-${format},${format}")
            else
                echo "+++ 🚨 Invalid File Output Format: ${format}" >&2
                echo "Valid Formats: ${valid_file_formats[*]}" >&2
                exit 1
            fi
        done
    fi

    # IAC Scanning Parameters
    if [[ "${scan_type}" == "iac" ]]; then

        if [[ -n "${IAC_TYPE}" ]]; then
            args+=("--types=${IAC_TYPE}")
        fi

        if [[ -n "${PARAMETER_FILES}" ]]; then
            args+=("--parameter-files=${PARAMETER_FILES}")
        fi
    fi

    echo "${args[*]}"
}

# Determine the machine architecture to select the appropriate container image tag.
# Available images: `latest`, `latest-amd64`, and `latest-arm64`.
# For x86_64 and arm64/aarch64, use the corresponding tag; for unknown architectures, fallback to the default `latest` tag.
function detect_wiz_cli_container() {
    local architecture
    architecture=$(uname -m)
    local container_image_tag="latest"

    case $architecture in
    x86_64)
        container_image_tag+="-amd64"
        ;;
    arm64 | aarch64)
        container_image_tag+="-arm64"
        ;;
    *) ;;
    esac

    local wiz_cli_container_repository="wiziocli.azurecr.io/wizcli"
    echo "${wiz_cli_container_repository}:${container_image_tag}"
}

function validate_wiz_client_credentials() {
    local missing_vars=()

    [ -z "${WIZ_CLIENT_ID:-}" ] && missing_vars+=("WIZ_CLIENT_ID")
    [ -z "${WIZ_CLIENT_SECRET:-}" ] && missing_vars+=("WIZ_CLIENT_SECRET")

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "+++ 🚨 The following required environment variables are not set: ${missing_vars[*]}" >&2
        exit 1
    fi
}

# Use WIZ_CLIENT_ID and WIZ_CLIENT_SECRET environment variables to authenticate to Wiz and get auth file
# $1 - Wiz CLI Container Image 
# $2 - Directory to store auth file
function get_wiz_auth_file() {
    local wiz_container_image="${1:-}"
    local wiz_dir="${2:-}"

    if [ -z "${wiz_container_image}" ]; then
        echo "+++ 🚨 Wiz CLI container image not specified" >&2
        exit 1
    fi
        
    if [ -z "${wiz_dir}" ]; then
        echo "+++ 🚨 Wiz directory not specified" >&2
        exit 1
    fi

    echo "Setting up and authenticating wiz"
    validate_wiz_client_credentials
    mkdir -p "$wiz_dir"

    docker run \
        --rm \
        --mount type=bind,src="${wiz_dir}",dst=/cli \
        -e WIZ_CLIENT_ID \
        -e WIZ_CLIENT_SECRET \
        "${wiz_container_image}" \
        auth

    # check that wiz-auth work expected, and a file in WIZ_DIR is created
    if [ -z "$(ls -A "${wiz_dir}")" ]; then
        echo "+++ 🚨 Wiz authentication failed, please confirm the credentials are set for WIZ_CLIENT_ID and WIZ_CLIENT_SECRET" >&2
        exit 1
    else
        echo "Authenticated successfully"
    fi
}

# Create a Buildkite Annotation from a scan results
# $1 - scan type
# $2 - scan name
# $3 - scan pass/fail
# $4 - scan result file
function build_annotation() {
    annotation_file=${RANDOM:0:2}-annotation.md
    docker_or_iac=$(if [ "$1" = "docker" ]; then echo "Wiz Docker Image Scan"; else echo "Wiz IaC Scan"; fi)
    pass_or_fail=$(if [ "$3" = "true" ]; then echo 'meets'; else echo 'does not meet'; fi)
    summary="${docker_or_iac} for ${2} ${pass_or_fail} policy requirements"
    # we need to create a new file to avoid conflicts, we need scan type, name, pass/fail
    cat <<EOF >>./"${annotation_file}"
<details>
<summary>$summary.</summary>

\`\`\`term
$(cat "$4")
\`\`\`

</details>
EOF
    printf "%b\n" "$(cat ./"${annotation_file}")"
}

# Execute annotation command (custom or default buildkite-agent annotate)
# $1 - context
# $2 - style
# stdin - annotation content
function execute_annotation() {
    local context="${1:-}"
    local style="${2:-}"
    
    CUSTOM_ANNOTATION_COMMAND="${BUILDKITE_PLUGIN_WIZ_ANNOTATION_COMMAND:-}"
    
    if [[ -n "${CUSTOM_ANNOTATION_COMMAND}" ]]; then
        eval "${CUSTOM_ANNOTATION_COMMAND}"
    else
        # Use default buildkite-agent annotate
        buildkite-agent annotate --append --context "$context" --style "$style"
    fi
}

# Docker Image Scan
# $1 - Wiz CLI Container Image
# $2 - Directory with auth file
# $3 - Image Address
# $4 - CLI Arguments
function docker_image_scan() {
    local wiz_cli_container_image="${1:-}"
    local wiz_dir="${2:-}"
    local image="${3:-}"
    shift 3
    local -a cli_args=("${@}")

    mkdir -p result

    # make sure local docker has the image
    docker pull "$image"

    local -i exit_code=0
    docker run \
        --rm \
        --mount type=bind,src="$wiz_dir",dst=/cli,readonly \
        --mount type=bind,src="$PWD",dst=/scan \
        --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock,readonly \
        "${wiz_cli_container_image}" \
        docker scan --image "$image" \
        --policy-hits-only \
        "${cli_args[@]}" || exit_code=$?

    local image_name
    image_name="$(echo "$image" | cut -d "/" -f 2)"
    
    if [[ $exit_code -eq 0 ]]; then
        build_annotation "docker" "$image_name" true "result/output" | execute_annotation 'ctx-wiz-docker-success' 'success'
    else
        build_annotation "docker" "$image_name" false "result/output" | execute_annotation 'ctx-wiz-docker-warning' 'warning'
    fi

    exit $exit_code
}

# IaC Scan
# $1 - Wiz CLI Container Image
# $2 - Directory with auth file
# $3 - File Path
# $4 - CLI Arguments
function iac_scan() {
    local wiz_cli_container_image="${1:-}"
    local wiz_dir="${2:-}"
    local file_path="${3:-}"
    shift 3
    local -a cli_args=("${@}")

    mkdir -p result

    local -i exit_code=0
    docker run \
        --rm \
        --mount type=bind,src="$wiz_dir",dst=/cli,readonly \
        --mount type=bind,src="$PWD",dst=/scan \
        "${wiz_cli_container_image}" \
        iac scan \
        --name "$BUILDKITE_JOB_ID" \
        --path "/scan/$file_path" \
        "${cli_args[@]}" || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        build_annotation "iac" "$BUILDKITE_LABEL" true "result/output" | execute_annotation 'ctx-wiz-iac-success' 'success'
    else
        build_annotation "iac" "$BUILDKITE_LABEL" false "result/output" | execute_annotation 'ctx-wiz-iac-warning' 'warning'
    fi

    # buildkite-agent artifact upload "result/**/*" --log-level info
    # this post step will be used in template to check the step was run
    echo "${BUILDKITE_BUILD_ID}" >check-file && buildkite-agent artifact upload check-file

    exit $exit_code
}

# Directory Scan
# $1 - Wiz CLI Container Image
# $2 - Directory with auth file
# $3 - File Path
# $4 - CLI Arguments
function dir_scan() {
    local wiz_cli_container_image="${1:-}"
    local wiz_dir="${2:-}"
    local file_path="${3:-}"
    shift 3
    local -a cli_args=("${@}")

    mkdir -p result

    local -i exit_code=0
    docker run \
        --rm \
        --mount type=bind,src="$wiz_dir",dst=/cli,readonly \
        --mount type=bind,src="$PWD",dst=/scan \
        "${wiz_cli_container_image}" \
        dir scan \
        --name "$BUILDKITE_JOB_ID" \
        --path "/scan/$file_path" \
        "${cli_args[@]}" || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        build_annotation "dir" "$BUILDKITE_LABEL" true "result/output" | execute_annotation 'ctx-wiz-dir-success' 'success'
    else
        build_annotation "dir" "$BUILDKITE_LABEL" false "result/output" | execute_annotation 'ctx-wiz-dir-warning' 'warning'
    fi
    
    # buildkite-agent artifact upload "result/**/*" --log-level info
    # this post step will be used in template to check the step was run
    echo "${BUILDKITE_BUILD_ID}" >check-file && buildkite-agent artifact upload check-file

    exit $exit_code
}

