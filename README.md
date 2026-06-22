# Lightspeed Configs

[![Apache2.0 License](https://img.shields.io/badge/License-Apache2.0-brightgreen.svg)](LICENSE)
[![Target LCORE Version](https://img.shields.io/badge/Target%20LCORE-0.7.0-blue)]()
[![RHDH Release](https://img.shields.io/badge/RHDH%20Release-2.1.0-blueviolet)]()

## Versions

See [images.yaml](./images.yaml) for current sprint images and versions.

`main` tracks one active release at a time. Historical releases are preserved in `rhdh-x.x` branches and Git tags.
`latest_release` field maps to the latest LCORE release tag for [lightspeed-core/lightspeed-stack-rhel9](https://catalog.redhat.com/en/software/containers/lightspeed-core/lightspeed-stack-rhel9/69149c6590bc83e678940a63).

## Architecture

The configuration in this repository is designed to run with [Lightspeed Core](https://github.com/lightspeed-core/lightspeed-stack) in **library mode**. In this mode, Lightspeed Core (LCORE) and Llama Stack run in the same container and process boundary, so these configs target a single combined runtime rather than separate services.

## Release Process

Release and hotfix workflow is documented in [docs/RELEASE_PROCESS.md](./docs/RELEASE_PROCESS.md).

## Provider Configuration

Provider-specific setup and environment variable details live in [docs/PROVIDERS.md](./docs/PROVIDERS.md).

## Contributing

See [docs/CONTRIBUTING.md](./docs/CONTRIBUTING.md) for local development setup, running services, syncing configs, and troubleshooting.
