# TARS Remote

A tiny Android remote that lets your phone control media playback on your Linux laptop while the laptop is connected to the TV.

## What it does

From your phone you can:

- play / pause
- previous / next
- seek backward 15 seconds
- seek forward 15 seconds
- volume down / volume up
- drag a volume slider
- mute / unmute
- test whether the laptop is reachable

The phone app talks to a tiny HTTP receiver running on the laptop over your local Wi-Fi.

---

## Project layout

- `lib/main.dart` — Flutter phone app
- `receiver/media_remote_server.py` — lightweight Linux receiver

---

## Laptop setup

### 1. Find your laptop IP

On Ubuntu/Linux:

```bash
hostname -I
```

Use the Wi-Fi/LAN IP that looks like `192.168.x.x`.

### 2. Optional but recommended: install `playerctl`

`playerctl` gives the receiver the cleanest way to control active media players.

```bash
sudo apt install playerctl
```

Volume control uses `pactl` or `wpctl` if available.

### 3. Start the receiver

From this project directory:

```bash
python3 receiver/media_remote_server.py --token YOUR_SECRET_TOKEN
```

By default it listens on port `8765`.

If you want to change the port:

```bash
python3 receiver/media_remote_server.py --token YOUR_SECRET_TOKEN --port 9000
```

### 4. Keep the laptop and phone on the same Wi-Fi

The app assumes the phone can reach the laptop directly over the LAN.

---

## Phone app setup

### 1. Build / install the APK

Debug build:

```bash
flutter build apk --debug
```

Expected output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

### 2. Open the app

Enter:

- **Laptop IP or URL** — for example `192.168.1.25:8765`
- **Shared token** — the same token you passed to the Python server

Tap **Save & test connection**.

If the laptop is reachable, the status chip flips to **Online** and the controls become active.

---

## How the receiver works

Authentication is a simple Bearer token.

The receiver tries media backends in this order:

1. `playerctl`
2. MPRIS over `dbus-send`
3. `xdotool` media keys when available

Volume is handled with:

1. `pactl`
2. `wpctl`

---

## Caveats

- This is designed for **Linux laptops**.
- Phone and laptop must be on the **same network** unless you expose the port another way.
- Browsers and streaming sites behave best when they expose media controls to MPRIS / media keys.
- Plain HTTP is used for local-network simplicity, so Android cleartext traffic is enabled for this app.
- The token protects casual misuse on your LAN, but it is not a full zero-trust security system.

---

## Useful commands

Run Flutter app locally:

```bash
flutter run
```

Analyze project:

```bash
flutter analyze
```

Build debug APK:

```bash
flutter build apk --debug
```
