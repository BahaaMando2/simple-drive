# Simple Drive

A Ruby on Rails API that stores and retrieves blobs of data behind one interface, with four
interchangeable storage backends:

- **Amazon S3-compatible storage.** Spoken to with a plain HTTP client and a hand-written
  AWS Signature V4 implementation, with no S3 library.
- **Database table**
- **Local filesystem**
- **FTP** (the bonus backend)

All requests are authenticated with a Bearer token. Every backend is tested against the real
thing (a filesystem, Postgres, MinIO, vsftpd), locally and in CI.

## Run it

Requires Docker. This starts the app, Postgres, MinIO (S3) and an FTP server:

```sh
docker compose up --build

curl -X POST http://localhost:3000/v1/blobs \
  -H "Authorization: Bearer dev-token-change-me" -H "Content-Type: application/json" \
  -d '{"id": "hello", "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh"}'

curl http://localhost:3000/v1/blobs/hello -H "Authorization: Bearer dev-token-change-me"
```

To pick a storage backend, set `STORAGE_BACKEND` to `local` (the default), `database`, `s3` or `ftp`:

```sh
STORAGE_BACKEND=s3 docker compose up
```

On Windows PowerShell: `$env:STORAGE_BACKEND="s3"; docker compose up`.

## Test

```sh
docker compose run --rm app bin/rails test
```

That's 73 tests: unit tests for every backend and the signer, plus integration tests for
the API. On GitHub, CI also runs RuboCop, Brakeman and bundler-audit.

## API

| Method | Path             | Request body                        | Response |
|--------|------------------|-------------------------------------|----------|
| POST   | `/v1/blobs`      | `{"id": "...", "data": "<base64>"}` | `201` with `id`, `size`, `created_at` and a `Location` header |
| GET    | `/v1/blobs/<id>` | none                                | `200` with `id`, `data`, `size`, `created_at` |

```json
{
  "id": "any_valid_string_or_identifier",
  "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh",
  "size": "27",
  "created_at": "2023-01-22T21:37:55Z"
}
```

Every request needs `Authorization: Bearer <token>`. `/up` is an unauthenticated health check
for load balancers.

| Status | When |
|--------|------|
| 400 | The body isn't valid JSON |
| 401 | The token is missing or wrong |
| 404 | No blob with that id |
| 409 | A blob with that id already exists (blobs are never overwritten) |
| 422 | `id` isn't a non-blank string of at most 1024 bytes without NUL characters, or `data` isn't valid Base64 |
| 502 | The storage backend failed, or the backend holding that blob is no longer configured |

Errors are always `{"error": "<message>"}`.

## Configuration

All settings are environment variables, read in `config/storage.yml` and `config/application.rb`.
Compose sets working values for every backend.

| Variable | Purpose |
|----------|---------|
| `API_TOKEN` | The Bearer token, e.g. `openssl rand -hex 32`. If unset, every request is rejected |
| `STORAGE_BACKEND` | Where new blobs go: `local`, `database`, `s3` or `ftp` |
| `LOCAL_STORAGE_PATH` | The local backend's directory. This is its only setting |
| `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | Any S3-compatible service (path-style URLs; the bucket must exist) |
| `FTP_HOST`, `FTP_PORT`, `FTP_USER`, `FTP_PASSWORD` | FTP server (passive mode) |
| `DB_HOST`, `DB_USER`, `DB_PASSWORD` | Postgres connection |

A backend with missing settings refuses to start, and so does an unknown `STORAGE_BACKEND`.
Both fail at boot rather than on the first request.

## How it's built

```
POST /v1/blobs ─► BlobsController ─► blobs table (metadata: id, size, backend, created_at)
                                 └─► Storage.backend.put(id, bytes) ─► local | database | s3 | ftp
```

- `app/controllers/v1/blobs_controller.rb`: validates the input, decodes Base64, saves the
  metadata row, and writes the bytes.
- `lib/storage.rb`: the storage interface. Every backend implements `put(id, bytes)` and
  `get(id)`, and the controller only talks to that interface.
- `lib/storage/*_backend.rb`: one class per backend.
- `lib/storage/sig_v4_signer.rb`: AWS Signature Version 4.
- `test/support/storage_backend_contract.rb`: one shared test suite that every backend must pass.

## Design decisions

**API**
- **Base64 is decoded strictly (RFC 4648).** Ruby's `Base64.decode64` silently skips invalid
  characters, so garbage would be stored instead of rejected. Line breaks, missing padding and
  the URL-safe alphabet are rejected too. Base64 is only the transport format: inside the
  system, and in every backend, data is raw bytes.
- **`size` is the decoded byte count, returned as a string**, as in the brief's example
  (`"27"` for its 36-character Base64 string). `created_at` is in UTC, to the second.
- **Ids can be any string, including paths** like `docs/report.pdf`. The GET route is a glob
  (`*id`) with `format: false`. A plain `:id` route would reject the `/` and treat `.pdf` as a
  response format. Ids are capped at 1024 bytes, which keeps the primary-key index bounded, and
  can't contain NUL characters, which Postgres can't store.
- **Percent-encode the id in the URL.** Rails merges `//` and drops a trailing `/` before
  routing, so ids like `a/b/` or `/leading` are only reachable with `/` encoded as `%2F`
  (`/v1/blobs/a%2Fb%2F`). The `Location` header from POST always encodes the id fully, so it
  works for every id.
- **Single shared Bearer token.** The brief asks to keep auth simple. The token is compared in
  constant time to prevent timing attacks, and blob contents are filtered out of the logs.

**Storage and consistency**
- **The tracking table holds only metadata**: id (the primary key), size, backend and
  created_at. The bytes live in the backend. Because the primary key is the client's id, the
  database itself rejects duplicates, even when two POSTs arrive at the same time.
- **Write order: metadata row first, then bytes, in one transaction.** A duplicate id fails on
  the primary key before any bytes are written, so existing data is never overwritten. A failed
  backend write rolls the row back, so metadata never points at missing data. The one remaining
  gap: if the commit fails after the write, unreachable bytes are left behind. They're harmless,
  and a later POST with the same id overwrites them. The trade-off is that a DB connection is
  held open during the backend write.
- **Each blob records the backend it was written to.** Changing `STORAGE_BACKEND` affects only
  new blobs, and old ones are still read from where they live.
- **Backends name things by the SHA-256 of the id, never by the id itself.** For local and FTP,
  that means `../../etc/passwd` can't escape the storage directory. For S3, I started with raw
  ids as object keys. Testing against MinIO showed `..`, `./a` and `a//b` were rejected, and
  `/leading` silently overwrote `leading`. Key rules differ between S3-compatible servers, and
  hex keys never trip them. These ids are now part of the shared contract, so every backend is
  tested against them.

## Storage backends

- **Local filesystem.** One file per blob in `LOCAL_STORAGE_PATH`.
- **Database.** Bytes in their own `blob_contents` table, as `bytea` (raw bytes, not Base64).
  It's separate from the `blobs` metadata table, as the brief requires, and has no foreign key
  to it, because a backend only knows ids and bytes. It shares the app's database, so the bytes
  and the metadata row commit or roll back together.
- **S3-compatible.** Ruby's built-in `Net::HTTP` plus a hand-written Signature V4 implementation.
  - Signing never sends the secret key. The request (method, path, headers, a SHA-256 of the
    body, the time) is signed with a key derived from the secret, which proves who sent it and
    that nothing changed on the way.
  - The signer is tested step by step (canonical request, string to sign, signature) against
    AWS's official SigV4 test suite.
  - The backend passes the contract against a real MinIO server, which rejects a wrong secret
    key with `SignatureDoesNotMatch`.
  - A 404 with `NoSuchBucket` is reported as a misconfiguration (502). Only `NoSuchKey` means
    the blob isn't there.
  - Official MinIO images left Docker Hub in 2025, so compose and CI use `bitnamilegacy/minio`,
    the last Bitnami build of the real server.
- **FTP.** Uses the `net-ftp` gem (the brief allows any FTP library), in passive mode, with one
  short connection per operation. FTP reply `550` (file unavailable) means "not found"; any
  other failure, such as a wrong password, is a backend error.
