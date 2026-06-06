# MCP Registry Static Content

This repository contains static JSON documents for an MCP registry layout, plus scripts to validate and publish the content.

## What this repo contains

- [docs/](docs/)
  - Static JSON files that make up the registry endpoints.
- [run.ps1](run.ps1)
  - HTTP-based validation and jq navigation demo for registry endpoints.
- [upload.ps1](upload.ps1)
  - Publishes the static content to Azure Storage static website hosting.

## Purpose of docs/404.json

The file [docs/404.json](docs/404.json) is the not-found payload for registry routes that do not exist.

Content:
- error: Not found
- message: The requested MCP registry resource could not be found.

## Is 404.json used when deployed to a Storage account?

Yes.

In [upload.ps1](upload.ps1), static website hosting is configured with:
- index document: v0.1/servers/index.json
- 404 document: 404.json

That happens via az storage blob service-properties update with the --404-document value set from ErrorDocument (default is 404.json).

When a request targets a missing path on the static website endpoint, Azure Storage serves this custom 404 file.

## Registry layout in this repo

Top-level index:
- [docs/v0.1/servers/index.json](docs/v0.1/servers/index.json)

Per-server indexes:
- [docs/v0.1/servers/github/versions/index.json](docs/v0.1/servers/github/versions/index.json)
- [docs/v0.1/servers/microsoft-learn/versions/index.json](docs/v0.1/servers/microsoft-learn/versions/index.json)
- [docs/v0.1/servers/playwright-mcp/versions/index.json](docs/v0.1/servers/playwright-mcp/versions/index.json)

Version or latest documents:
- [docs/v0.1/servers/github/versions/1.0.0/index.json](docs/v0.1/servers/github/versions/1.0.0/index.json)
- [docs/v0.1/servers/github/versions/latest/index.json](docs/v0.1/servers/github/versions/latest/index.json)
- [docs/v0.1/servers/microsoft-learn/versions/1.0.0/index.json](docs/v0.1/servers/microsoft-learn/versions/1.0.0/index.json)
- [docs/v0.1/servers/microsoft-learn/versions/latest/index.json](docs/v0.1/servers/microsoft-learn/versions/latest/index.json)
- [docs/v0.1/servers/playwright-mcp/versions/0.0.75/index.json](docs/v0.1/servers/playwright-mcp/versions/0.0.75/index.json)
- [docs/v0.1/servers/playwright-mcp/versions/latest/index.json](docs/v0.1/servers/playwright-mcp/versions/latest/index.json)

## Typical workflow

1. Edit JSON files under [docs/](docs/).
2. Validate and inspect over HTTP using [run.ps1](run.ps1).
3. Publish to Azure Storage static website using [upload.ps1](upload.ps1).
