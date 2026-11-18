#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

# Uncomment the following line to debug stub failures
# export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

@test "Container image scan uses Wiz CLI v1 with the extract driver and forwards --project" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export BUILDKITE_PLUGIN_WIZ_PROJECT="my-project-id"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"
  export WIZ_ANNOTATIONS="false"
  local hook="$PWD/hooks/post-command"
  cd "$BATS_TEST_TMPDIR"

  stub aws 'echo "{\"client_id\":\"test-client\",\"client_secret\":\"test-secret\"}"'
  # wizcli pull, tag, version, image pull, then the scan (args captured).
  stub docker \
    ":: echo pulled" \
    ":: echo tagged" \
    ":: echo wizcli version" \
    "pull ubuntu:22.04 : echo pulled image" \
    ":: echo scan-args \"\$@\"; echo findings > docker-scan-result"

  run "$hook"

  assert_output --partial "Setting up Wiz CLI"
  assert_output --partial "wizcli:latest scan container-image ubuntu:22.04 --driver extract"
  assert_output --partial "--project my-project-id"
  refute_output --partial "/var/lib/docker"
  assert_success

  unstub docker
}

@test "Container image scan annotates an error when the scan itself fails, even with annotations disabled" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="registry.example.com/my-app:latest"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"
  export WIZ_ANNOTATIONS="false"
  local hook="$PWD/hooks/post-command"
  cd "$BATS_TEST_TMPDIR"

  stub aws 'echo "{\"client_id\":\"test-client\",\"client_secret\":\"test-secret\"}"'
  stub docker \
    ":: echo pulled" \
    ":: echo tagged" \
    ":: echo wizcli version" \
    "pull registry.example.com/my-app:latest : echo pulled image" \
    ":: echo 'ERROR: failed creating image driver'; exit 1"
  stub buildkite-agent \
    "annotate --append --style error --context ctx-wiz-docker-error : cat"

  run "$hook"

  assert_output --partial "Wiz docker image scan failed to run (exit code 1)"
  assert_output --partial "Wiz Docker Image Scan for my-app:latest failed to run"
  assert_output --partial "ERROR: failed creating image driver"
  assert_success

  unstub docker
  unstub buildkite-agent
}

@test "Container image scan policy failure annotates a warning, not a scan error" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="registry.example.com/my-app:latest"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"
  export WIZ_ANNOTATIONS="true"
  local hook="$PWD/hooks/post-command"
  cd "$BATS_TEST_TMPDIR"

  stub aws 'echo "{\"client_id\":\"test-client\",\"client_secret\":\"test-secret\"}"'
  stub docker \
    ":: echo pulled" \
    ":: echo tagged" \
    ":: echo wizcli version" \
    "pull registry.example.com/my-app:latest : echo pulled image" \
    ":: echo 'CVE-0000-0001' > docker-scan-result; exit 4"
  stub buildkite-agent \
    "annotate --append --context ctx-wiz-docker-warning --style warning : cat"

  run "$hook"

  assert_output --partial "my-app:latest does not meet policy requirements"
  assert_output --partial "CVE-0000-0001"
  refute_output --partial "failed to run"
  assert_success

  unstub docker
  unstub buildkite-agent
}

@test "Container image scan annotates an error and passes when Wiz CLI setup fails" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="registry.example.com/my-app:latest"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"
  export WIZ_ANNOTATIONS="false"
  local hook="$PWD/hooks/post-command"
  cd "$BATS_TEST_TMPDIR"

  stub aws 'echo ""'
  stub docker \
    ":: echo pulled" \
    ":: echo tagged" \
    ":: echo wizcli version"
  stub buildkite-agent \
    "annotate --append --style error --context ctx-wiz-docker-error : cat"

  run "$hook"

  assert_output --partial "Failed to retrieve Wiz API credentials"
  assert_output --partial "Wiz Docker Image Scan for my-app:latest failed to run (Wiz CLI setup failed)"
  assert_success

  unstub docker
  unstub buildkite-agent
}

@test "Dir scan fails when Wiz CLI setup fails" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="iac"
  export BUILDKITE_PLUGIN_WIZ_PATH="my-app"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"

  stub aws 'echo ""'
  stub docker \
    ":: echo pulled" \
    ":: echo tagged" \
    ":: echo wizcli version"

  run "$PWD/hooks/post-command"

  assert_output --partial "Failed to retrieve Wiz API credentials"
  refute_output --partial "Running Wiz CLI directory scan"
  assert_failure

  unstub docker
}

@test "Dir scan fails without path" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="iac"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"

  run "$PWD/hooks/post-command"

  assert_output --partial "Missing cdk.out path"
  assert_failure
}

@test "Dir scan sets up wizcli and forwards --project" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="iac"
  export BUILDKITE_PLUGIN_WIZ_PATH="my-app"
  export BUILDKITE_PLUGIN_WIZ_PROJECT="my-project-id"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"
  export WIZ_ANNOTATIONS="false"

  stub aws 'echo "{\"client_id\":\"test-client\",\"client_secret\":\"test-secret\"}"'
  # pull, tag, version, then the directory scan (args captured to assert --project).
  stub docker \
    ":: echo pulled" \
    ":: echo tagged" \
    ":: echo wizcli version" \
    ":: echo scan-args \"\$@\""

  run "$PWD/hooks/post-command"

  assert_output --partial "Setting up Wiz CLI"
  assert_output --partial "--project my-project-id"
  assert_success

  unstub docker
}

@test "Dir scan omits --project when project is not set" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="iac"
  export BUILDKITE_PLUGIN_WIZ_PATH="my-app"
  export WIZ_DIR="$BATS_TEST_TMPDIR/.wiz"
  export WIZ_ANNOTATIONS="false"

  stub aws 'echo "{\"client_id\":\"test-client\",\"client_secret\":\"test-secret\"}"'
  stub docker \
    ":: echo pulled" \
    ":: echo tagged" \
    ":: echo wizcli version" \
    ":: echo scan-args \"\$@\""

  run "$PWD/hooks/post-command"

  refute_output --partial "--project"
  assert_success

  unstub docker
}

@test "Missing scan type fails" {
  unset BUILDKITE_PLUGIN_WIZ_SCAN_TYPE

  run "$PWD/hooks/post-command"

  assert_output --partial "Missing scan type"
  assert_output --partial "iac"
  assert_failure
}
