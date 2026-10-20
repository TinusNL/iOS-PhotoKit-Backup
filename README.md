# iOS PhotoKit Backup

> [!WARNING]
> This project is 100% AI coded and should not be trusted for full backups, even though the goal is to be able to.

An iOS app and a small server that back up original photos and videos with PhotoKit’s background upload extension. The phone queues the original files. The server writes them under each API key’s folder as `YYYY/MM/{filename}`.

A Live Photo is two files with the same name, for example `IMG_2456.HEIC` and `IMG_2456.MOV`. If that filename is already anywhere in the folder, it is left alone.

## App

The Xcode project is in [`photokit-backup`](photokit-backup). It needs iOS 27 and a physical iPhone. The upload extension does not run in the Simulator.

Enter the server address and API key. After that, the app lists files still waiting and files already in the folder. Settings has **Upload Live Photo movies** (on by default). Standalone videos are always included.

`BackgroundUploadURLBase` in the extension is `https://github.com`. Apple uses that only to decide whether the network is up. Uploads go to the address you type in the app. HTTP to a LAN address is allowed. A self-signed certificate works only if the phone trusts it.

While debugging, turn on Settings → Developer → Resource Upload Test Mode.

## Proxy

The server is in [`photokit-backup-proxy`](photokit-backup-proxy). Pushes to `main` publish a free public image, `ghcr.io/tinusnl/ios-photokit-backup:latest`. [`docker-compose.yml`](photokit-backup-proxy/docker-compose.yml) pulls that image and mounts each person’s Photos folder.

Copy `config.example.json` to `config.json`. Each API key points at one directory inside the container. The file is read at startup, so a restart picks up edits.

```json
{
  "port": 8080,
  "keys": [
    { "name": "tinus", "apiKey": "change-me", "directory": "/data/tinus" }
  ]
}
```

See [photokit-backup-proxy/README.md](photokit-backup-proxy/README.md) for the endpoints and the Compose volume mounts.
