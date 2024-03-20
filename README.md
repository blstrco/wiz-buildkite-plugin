# Wiz Buildkite Plugin

Scans your infrastructure-as-code Cloudformation stacks or docker images for security vulnerabilities using [wiz](https://www.wiz.io/)

This plugin is forked from [blstrco/wiz-buildkite-plugin](https://github.com/blstrco/wiz-buildkite-plugin).

## Examples

### Docker Scanning

Add the following to your `pipeline.yml`, the plugin will pull the image, scan it using wiz and create a buildkite annotation with the results.

```yml
steps:
  - command: ls
    env:
    - WIZ_API_ID: "<your-id-goes-here>"
    plugins:
      - blstrco/wiz#v1.0.0:
          scan-type: 'docker'
          image-address: "<image-address-to-pull-and-scan>"
```

If you are using the [AWS Assume Role Plugin](https://github.com/cultureamp/aws-assume-role-buildkite-plugin), you might have trouble getting your secret key from `aws secretsmanager` if the role you assumed doesn't have the necessary access rights. To restore your role, you can use the [AWS Restore Role Buildkite Plugin](https://github.com/franklin-ross/aws-restore-role-buildkite-plugin) before the wiz plugin.

```yml
...
  plugins:
      - franklin-ross/aws-restore-role#HEAD
      - blstrco/wiz#v1.0.1:
...
```

### IaC (Infrastructure-as-Code) Cloudformation Scanning

To avoid adding build time overhead, you can add IaC scanning to your `cdk diff` step. You will need to mount/export the `cdk.out` folder and pass its path to the plugin. The plugin will then scan each Cloudformation stack in the folder and create a buildkite annotation with the results.

```yml
steps:
  - command: ls
    env:
    - WIZ_API_ID: "<your-id-goes-here>"
    plugins:
      - docker-compose#v4.16.0:
        ...
        # to get the output of CDK diff, mount the volume in cdk diff stage
        - volumes:
          - './infrastructure/cdk.out:/app/infrastructure/cdk.out'
        ...
      - blstrco/wiz#v1.0.1:
          scan-type: 'iac'
          path: "infrastructure/cdk.out"
```

## Configuration

### `scan-type` (Required, string) : 'docker | iac'
The scan type can be either docker or iac

### `image-address` (Optional, string)

The path to image file, if the `scan-type` is `docker`

### `path` (Optional, string)

The path to `cdk.out` folder containing CloudFormation stack(s), if the `scan-type` is `iac`

## Developing

To run the tests:

```shell
docker-compose run --rm tests
```

## Contributing

1. Fork the repo
2. Make the changes
3. Run the tests
4. Commit and push your changes
5. Send a pull request