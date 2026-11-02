# Simple Drive

A Rails API that stores and retrieves blobs behind one interface, with pluggable
storage backends (S3-compatible, database, local filesystem, FTP).

> Work in progress: the API skeleton, authentication and metadata table are in
> place; storage backends are being added one at a time.

## Run it

Requires Docker.

```sh
docker compose up --build
curl -H "Authorization: Bearer dev-token-change-me" http://localhost:3000/v1/blobs/some-id
```

Set `API_TOKEN` to choose the token (e.g. `API_TOKEN=$(openssl rand -hex 32) docker compose up`).

## Test

```sh
docker compose run --rm app bin/rails test
```

## API

| Method | Path             | Body                                   |
|--------|------------------|----------------------------------------|
| POST   | `/v1/blobs`      | `{"id": "...", "data": "<base64>"}`    |
| GET    | `/v1/blobs/<id>` | returns `id`, `data`, `size`, `created_at` |

Every request needs `Authorization: Bearer <token>`. `/up` is an unauthenticated health check.

## Design decisions

- **Single shared Bearer token from `API_TOKEN`.** The brief asks to keep auth simple.
  It's compared in constant time, and if no token is configured, every request is rejected.
- **The client's id is the primary key of `blobs`.** Uniqueness is enforced by the
  database, so two concurrent POSTs with the same id can't both succeed.
- **Ids are capped at 1024 bytes.** That's the S3 object-key limit, so any accepted id fits every backend.
- **`GET /v1/blobs/*id` is a glob route with `format: false`.** Ids may be paths such as
  `docs/report.pdf`. A plain `:id` route would reject the `/` and treat `.pdf` as a response format.
- **Blobs are immutable.** The metadata table has `created_at` but no `updated_at`.
