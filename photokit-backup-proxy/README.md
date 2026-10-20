# PhotoKit backup proxy

Receives original photos and videos from the iOS background upload extension and stores them under each API key’s directory.

A file is already backed up when that filename exists anywhere in the directory. The proxy does not keep a separate database of uploads, so files you already copied into the folder are left as they are. New files are written to `YYYY/MM/{filename}` using the capture time sent by the app. A Live Photo is two files with the same name, for example `IMG_2456.HEIC` and `IMG_2456.MOV`.

## Configure

Copy `config.example.json` to `config.json`. Each key has a display name, an API key, and an absolute directory inside the container.

```json
{
  "port": 8080,
  "keys": [
    { "name": "tinus", "apiKey": "change-me", "directory": "/data/tinus" }
  ]
}
```

The file is read once at startup. Edit it, then restart the container.

## Synology

Pushes to `main` publish `ghcr.io/tinusnl/ios-photokit-backup:latest` for both Intel and ARM NASs. Public images on GitHub Container Registry are free. The first publish may stay private until the package visibility is set to Public, which lets the NAS pull it without a login.

In Container Manager, create a project from `docker-compose.yml`. Point each volume at that person’s Photos folder:

```yaml
services:
  proxy:
    image: ghcr.io/tinusnl/ios-photokit-backup:latest
    ports:
      - "8080:8080"
    volumes:
      - ./config.json:/config/config.json:ro
      - /volume1/homes/tinus/Photos/test:/data/tinus
    restart: unless-stopped
```

The path on the right (`/data/tinus`) must match `directory` in the config. The container runs as root so it can write to those shared folders.

## Run locally

```sh
npm install
cp config.example.json config.json
# Edit directory to an absolute folder that already exists.
npm test
npm run build
CONFIG_PATH=./config.json node dist/index.js
```

## API

`GET /health` needs no key. Everything else uses `Authorization: Bearer <apiKey>`.

- `GET /api/session` returns the key’s name.
- `GET /api/uploads?limit=40&offset=0` lists files in `YYYY/MM` folders, newest first. Other folders are ignored. `total` is the number of those files.
- `POST /api/uploads/lookup` with `{ "files": [{ "assetId", "resourceType", "filename", "relativePath" }] }` returns the ones whose filename is already on disk.
- `OPTIONS /api/upload` returns `501` so PhotoKit sends the file in one request.
- `POST /api/upload` reads the raw file. Headers: `X-Asset-Id`, `X-Resource-Type` (`photo`, `pairedVideo`, or `video`), `X-Filename` (percent-encoded), `X-Created-At`, and `Content-Type`. An existing filename returns `200` and is not replaced. A new file returns `201`.
