# iOS PhotoKit Backup

> [!WARNING]
> This project is 100% AI coded and should not be trusted for full backups, even though the goal is to be able to.

An iOS app and a small server that back up original photos and videos with PhotoKit’s background upload extension. It was largely inspired by [YAIIU](https://github.com/FawenYo/YAIIU). The original goal was to work with Synology Photos, and it is made to work with anything that can use the same folders. The phone queues the original files, and the server writes them under each API key’s folder as `YYYY/MM/{filename}`.

A Live Photo is two files with the same name, for example `IMG_2456.HEIC` and `IMG_2456.MOV`. If that filename is already anywhere in the folder, it is left alone.

## Quick start

You need a machine that can run the proxy (a Synology is the example below) and a physical iPhone on iOS 27. The upload extension does not run in the Simulator.

1. Create the folder that should receive the photos. On a Synology that is often a personal Photos folder, for example `/volume1/photo/tinus`. Any existing files there are kept. A filename that is already in the folder is not uploaded again.

2. On that machine, save [`photokit-backup-proxy/docker-compose.yml`](photokit-backup-proxy/docker-compose.yml) and a `config.json` next to it:

```json
{
  "port": 8080,
  "keys": [
    { "name": "tinus", "apiKey": "change-me", "directory": "/data/tinus" }
  ]
}
```

Change `apiKey`. In the Compose file, the left side of the volume must be your folder and the right side must match `directory`:

```yaml
- /volume1/photo/tinus:/data/tinus
```

3. Start it and check that it answers:

```sh
docker compose up -d
curl http://127.0.0.1:8080/health
```

4. Open [`photokit-backup`](photokit-backup) in Xcode and run **PhotoKit Backup** on the iPhone. Enter the server as `192.168.1.20:8080` (or `https://…` if you have a certificate the phone trusts) and the same API key. Allow access to the whole photo library.

5. Leave the phone on Wi-Fi. Apple starts background uploads when `https://github.com` is reachable, then sends the files to the address you entered. For a faster first run, turn on Settings → Developer → Resource Upload Test Mode.

New files show up as `YYYY/MM/{filename}`. The app lists what is still waiting and what is already in the folder. Settings has **Upload Live Photo movies**, which is on by default. Standalone videos are always included.

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
