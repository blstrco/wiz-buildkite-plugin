#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

# Uncomment the following line to debug stub failures
export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

@test "Authenticates to wiz" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export WIZ_DIR="$HOME/.wiz"
  export WIZ_API_ID="test"

  stub aws 'echo test-key'
  stub docker 'echo TODO'
  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  run "$PWD/hooks/post-command"

  assert_output --partial "Authenticated successfully"
  #todo test docker scan
  assert_success
  #cleanup
  rm "$WIZ_DIR/key"
}

@test "Dir scan fails without path" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="dir"
  export WIZ_API_ID="test"
  export WIZ_DIR="$HOME/.wiz"

  stub aws 'echo test-key'
  stub docker 'echo OK'

  run "$PWD/hooks/post-command"

  assert_output --partial "Missing path"
  assert_failure
}

@test "Dir scan sets up wizcli and runs scan" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="dir"
  export BUILDKITE_PLUGIN_WIZ_PATH="my-app"
  export WIZ_DIR="$HOME/.wiz"
  export WIZ_API_ID="test"
  export WIZ_ANNOTATIONS="false"

  stub aws 'echo test-key'
  stub docker \
    "pull * : echo pulled" \
    "tag * * : echo tagged" \
    "run * version : echo wizcli v1.0.0" \
    "run * scan * : echo scanned"

  mkdir -p "$WIZ_DIR"

  run "$PWD/hooks/post-command"

  assert_output --partial "Setting up Wiz CLI"
  assert_success

  unstub docker
}

@test "Missing scan type fails" {
  unset BUILDKITE_PLUGIN_WIZ_SCAN_TYPE

  run "$PWD/hooks/post-command"

  assert_output --partial "Missing scan type"
  assert_output --partial "dir"
  assert_failure
}
