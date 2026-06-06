# MCP Registry setup

This folder contains a Docker Compose setup for running the official MCP Registry locally.

## Start the stack

From this folder:

```bash
docker compose up -d
```

## Check status

```bash
docker compose ps
```

## View logs

```bash
docker compose logs -f registry
```

## Stop the stack

```bash
docker compose down
```

## Useful links

- Official MCP Registry repository: https://github.com/modelcontextprotocol/registry
- Official README: https://github.com/modelcontextprotocol/registry/blob/main/README.md
- Docker Compose example: https://github.com/modelcontextprotocol/registry/blob/main/docker-compose.yml
- Example environment variables: https://github.com/modelcontextprotocol/registry/blob/main/.env.example
- Live registry API docs: https://registry.modelcontextprotocol.io/docs
