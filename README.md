# Simple Drive

A Rails API that stores and retrieves blobs behind one interface, with pluggable
storage backends (S3-compatible, database, local filesystem, FTP).

> Work in progress: the API, authentication and local filesystem backend are done;
> the S3, database and FTP backends are being added one at a time.

## Run it

Requires Docker.

```sh
docker compose up --build

curl -X POST http://localhost:3000/v1/blobs \
  -H "Authorization: Bearer dev-token-change-me" -H "Content-Type: application/json" \
  -d '{"id": "hello", "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh"}'

curl http://localhost:3000/v1/blobs/hello -H "Authorization: Bearer dev-token-change-me"
```

## Configuration

| Variable             | Default                | Meaning                                  |
|----------------------|------------------------|------------------------------------------|
| `API_TOKEN`          | `dev-token-change-me` in compose; unset elsewhere means every request is rejected | Bearer token, e.g. `openssl rand -hex 32` |
| `STORAGE_BACKEND`    | `local`                | Backend for new blobs: `local`           |
| `LOCAL_STORAGE_PATH` | `storage/blobs` (`/data/blobs` in compose) | Directory for the local backend |

Settings live in `config/storage.yml`.

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

| Status | When |
|--------|------|
| 201 | Stored. Body has `id`, `size`, `created_at`; `Location` points at the blob |
| 200 | Retrieved |
| 400 | Body isn't valid JSON |
| 401 | Missing or wrong token |
| 404 | No blob with that id |
| 409 | A blob with that id already exists (blobs are never overwritten) |
| 422 | `id` isn't a non-blank string of ≤ 1024 bytes, or `data` isn't valid Base64 |
| 502 | The storage backend failed |

Errors are always `{"error": "<message>"}`.

## Design decisions

- **Single shared Bearer token from `API_TOKEN`.** The brief asks to keep auth simple.
  It's compared in constant time, and if no token is configured, every request is rejected.
- **The client's id is the primary key of `blobs`.** Uniqueness is enforced by the
  database, so two concurrent POSTs with the same id can't both succeed.
- **Ids are capped at 1024 bytes.** That's the S3 object-key limit, so any accepted id fits every backend.
- **`GET /v1/blobs/*id` is a glob route with `format: false`.** Ids may be paths such as
  `docs/report.pdf`. A plain `:id` route would reject the `/` and treat `.pdf` as a response format.
- **Blobs are immutable.** The metadata table has `created_at` but no `updated_at`.
- **Base64 is decoded strictly (RFC 4648).** Ruby's `Base64.decode64` silently skips invalid
  characters, so garbage would be stored instead of rejected. Line breaks, missing padding and
  the URL-safe alphabet are rejected too.
- **`size` is the decoded byte count, returned as a string.** That matches the brief's example:
  `"27"` for its 36-character Base64 string.
- **Write order: metadata row first, then bytes, in one transaction.** A duplicate id fails on
  the primary key before any bytes are written, so existing data is never clobbered. A failed
  backend write rolls the row back, so metadata never points at missing data. The remaining
  gap: if the commit itself fails after the write, unreachable bytes are left behind. They're
  harmless, and a later POST with the same id overwrites them. The trade-off is that a DB
  connection is held during the backend write.
- **Each blob records the backend it was written to.** Changing `STORAGE_BACKEND` affects only
  new blobs, and old ones are still read from where they live.

## Storage backends

All backends implement `put(id, bytes)` and `get(id)` (see `lib/storage.rb`). One shared test
suite, `test/support/storage_backend_contract.rb`, runs against every backend: binary bytes,
empty blobs, path-like and unicode ids, overwrite, not-found.

- **Local filesystem.** One file per blob, named by the SHA-256 of the id. The id is never used
  as a path, so `../../etc/passwd` can't escape the directory, and distinct ids can't collide.
