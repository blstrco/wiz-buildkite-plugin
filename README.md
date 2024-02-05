# Wiz Buildkite Plugin

Scans your infrastructure-as-code files or docker images for security vulnerabilities using wiz.io.

## Example

Add the following to your `pipeline.yml`, the build step must export artifacts to `cdk/*.template.json` that can either be CloudFormation files or be automatically generated via `cdk synth`:

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

If you are using the [AWS Assume Role Plugin](https://github.com/cultureamp/aws-assume-role-buildkite-plugin), you might have trouble getting your secret key from `aws secretsmanager` if the role you assumed doesn't have the right access rights. To restore your role, you can use the [AWS Restore Role Buildkite Plugin](https://github.com/franklin-ross/aws-restore-role-buildkite-plugin) before the wiz plugin.

## Configuration

### `image` (Optional, string)

The path to image file, if `scan-type` is `image`

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