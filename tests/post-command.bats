#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

# Uncomment the following line to debug stub failures
# export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

@test "Container image scan sets up wiz and forwards --project" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export BUILDKITE_PLUGIN_WIZ_PROJECT="my-project-id"
  export WIZ_ANNOTATIONS="false"

  # setupWiz uses $HOME/.wiz and checks it is non-empty after authenticating.
  mkdir -p "$HOME/.wiz"
  touch "$HOME/.wiz/auth"

  stub aws 'echo "test-id:test-secret"'
  # auth, pull, then the docker scan (args captured to assert --project).
  stub docker \
    ":: echo authed" \
    ":: echo pulled" \
    ":: echo scan-args \"\$@\""

  run "$PWD/hooks/post-command"

  assert_output --partial "Setting up and authenticating wiz"
  assert_output --partial "--project my-project-id"
  assert_success

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
