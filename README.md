# MCP Registry Static Content

This repository contains static JSON documents for an MCP registry layout, plus scripts to validate and publish the content.

## Live registry endpoint

The `docs/` folder is published with GitHub Pages and is available here:

- https://jannemattila.github.io/my-mcp-registry

Example endpoints:

- Servers index: https://jannemattila.github.io/my-mcp-registry/v0.1/servers/index.json
- Not-found payload: https://jannemattila.github.io/my-mcp-registry/404.json

## What this repo contains

- [docs/](docs/)
  - Static JSON files that make up the registry endpoints.
- [extract.ps1](extract.ps1)
  - Extracts a live MCP registry into the static `docs/` layout by crawling its endpoints.
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
- index document: index.json
- 404 document: 404.json

That happens via az storage blob service-properties update with the --404-document value set from ErrorDocument (default is 404.json).

When a request targets a missing path on the static website endpoint, Azure Storage serves this custom 404 file.

## Extracting a registry with extract.ps1

[extract.ps1](extract.ps1) crawls a running MCP registry and mirrors it into the static `docs/` layout used by this repo, producing a self-contained static site you can publish.

### Parameters

- `RegistryRoot` (default `http://localhost:8080`)
  - Absolute http/https URL of the source registry to extract.
- `OutputFolder` (default `docs/` next to the script)
  - Destination folder for the generated static files.
- `PageLimit` (default `100`)
  - Page size used when paging through API results.

### Layout detection

The script auto-detects the source registry layout:

- API layout: probes `/v0/servers` and pages through results using cursors (`nextCursor`).
- Static layout: falls back to `/v0.1/servers/index.json` if the API layout is not found.

If neither layout is discovered, the script throws an error.

### What it writes

For each server it discovers, the script writes:

- The top-level servers index: `v0.1/servers/index.json`
- A per-server versions index: `v0.1/servers/<id>/versions/index.json`
- A document per version: `v0.1/servers/<id>/versions/<version>/index.json`
- A `latest` document: `v0.1/servers/<id>/versions/latest/index.json`

For the API layout, the `latest` document is written from the version flagged with `isLatest`. All JSON is written as UTF-8 without a BOM to match the original bytes.

It also mirrors `404.json` from the source registry (falling back to a default not-found body if the source does not expose one), so the extracted folder is a complete static site.

### Example

```powershell
# Extract a remote registry into the local docs/ folder
.\extract.ps1 -RegistryRoot https://registry.modelcontextprotocol.io
```

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

## Using this registry with GitHub Enterprise AI controls

GitHub Enterprise administrators govern how Copilot uses Model Context Protocol
(MCP) servers through the **AI controls** in Copilot policies (the "MCP servers
in Copilot" policy and the associated allowed/curated server configuration). A
self-hosted registry like the one published here lets you present a *curated,
organization-approved* catalog of MCP servers to your developers instead of
relying solely on the public [GitHub MCP Registry](https://github.com/mcp).

The live URL is a complete, standards-shaped registry surface:

```
https://jannemattila.github.io/my-mcp-registry
```

How it fits into enterprise AI controls:

1. **Curate the catalog.** Keep only the MCP servers your organization has
   reviewed and approved as JSON documents under [docs/](docs/) (each server,
   its versions, and a `latest` document). The static layout mirrors the MCP
   registry API shape, so it can be consumed the same way as a hosted registry.
2. **Host it on a trusted, stable URL.** GitHub Pages (this repo) or Azure
   Storage static website hosting (via [upload.ps1](upload.ps1)) both serve the
   exact same JSON, over HTTPS, with permissive CORS — suitable for tools and
   clients that fetch the registry directly.
3. **Point your enterprise/organization at it.** In the GitHub Enterprise
   Copilot policy settings (AI controls), enable the "MCP servers in Copilot"
   policy and configure the approved registry/servers your members are allowed
   to use. Developers then discover and install only the servers in your
   curated registry, giving you a governed, auditable allowlist.
4. **Update centrally.** Adding, removing, or version-bumping a server is just a
   JSON edit plus a publish. Every Copilot client that reads the registry picks
   up the change without per-developer configuration.

> Note: The GitHub MCP Registry and the related Copilot MCP policies are evolving
> (parts are in public preview), so confirm the exact policy UI and registry
> configuration fields in your enterprise against the current
> [GitHub Copilot enterprise policy documentation](https://docs.github.com/en/copilot/how-tos/administer/enterprises/managing-policies-and-features-for-copilot-in-your-enterprise).
