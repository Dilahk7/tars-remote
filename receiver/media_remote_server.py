#!/usr/bin/env python3
"""Tiny LAN media remote receiver for Linux.

Runs a small authenticated HTTP server that accepts playback and volume commands
from the Flutter phone app.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

DEFAULT_PORT = 8765


class MediaController:
    def __init__(self) -> None:
        self.has_playerctl = shutil.which("playerctl") is not None
        self.has_pactl = shutil.which("pactl") is not None
        self.has_wpctl = shutil.which("wpctl") is not None
        self.has_dbus_send = shutil.which("dbus-send") is not None
        self.has_xdotool = shutil.which("xdotool") is not None

    def run(self, command: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def _mpris_names(self) -> list[str]:
        if not self.has_dbus_send:
            return []
        result = self.run(
            [
                "dbus-send",
                "--session",
                "--dest=org.freedesktop.DBus",
                "--type=method_call",
                "--print-reply",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus.ListNames",
            ]
        )
        if result.returncode != 0:
            return []
        return sorted(set(re.findall(r'org\.mpris\.MediaPlayer2\.[^\"]+', result.stdout)))

    def _run_mpris_method(self, method: str, extra: list[str] | None = None) -> bool:
        names = self._mpris_names()
        if not names:
            return False
        args = [
            "dbus-send",
            "--session",
            f"--dest={names[0]}",
            "--type=method_call",
            "/org/mpris/MediaPlayer2",
            f"org.mpris.MediaPlayer2.Player.{method}",
        ]
        if extra:
            args.extend(extra)
        result = self.run(args)
        return result.returncode == 0

    def _run_media_key(self, key: str) -> bool:
        if not self.has_xdotool:
            return False
        result = self.run(["xdotool", "key", key])
        return result.returncode == 0

    def _playerctl(self, *args: str) -> bool:
        if not self.has_playerctl:
            return False
        result = self.run(["playerctl", *args])
        return result.returncode == 0

    def _playerctl_output(self, *args: str) -> str | None:
        if not self.has_playerctl:
            return None
        result = self.run(["playerctl", *args])
        if result.returncode != 0:
            return None
        return result.stdout.strip() or None

    def play_pause(self) -> None:
        if self._playerctl("play-pause"):
            return
        if self._run_mpris_method("PlayPause"):
            return
        if self._run_media_key("XF86AudioPlay"):
            return
        raise RuntimeError("No working playback backend found. Install playerctl if needed.")

    def next_track(self) -> None:
        if self._playerctl("next"):
            return
        if self._run_mpris_method("Next"):
            return
        if self._run_media_key("XF86AudioNext"):
            return
        raise RuntimeError("Next track command is unavailable.")

    def previous_track(self) -> None:
        if self._playerctl("previous"):
            return
        if self._run_mpris_method("Previous"):
            return
        if self._run_media_key("XF86AudioPrev"):
            return
        raise RuntimeError("Previous track command is unavailable.")

    def seek(self, seconds: int) -> None:
        signed = f"{abs(seconds)}{'+' if seconds >= 0 else '-'}"
        if self._playerctl("position", signed):
            return
        offset = str(seconds * 1_000_000)
        if self._run_mpris_method("Seek", [f"int64:{offset}"]):
            return
        raise RuntimeError("Seek is unavailable for the current player.")

    def toggle_mute(self) -> None:
        if self.has_pactl:
            result = self.run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"])
            if result.returncode == 0:
                return
        if self.has_wpctl:
            result = self.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
            if result.returncode == 0:
                return
        raise RuntimeError("Mute control is unavailable.")

    def get_volume(self) -> float | None:
        if self.has_pactl:
            result = self.run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"]) 
            if result.returncode == 0:
                match = re.search(r"/(?:\s*)(\d+)%", result.stdout)
                if match:
                    return float(match.group(1))
        if self.has_wpctl:
            result = self.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]) 
            if result.returncode == 0:
                match = re.search(r"Volume:\s*([0-9.]+)", result.stdout)
                if match:
                    return max(0.0, min(100.0, float(match.group(1)) * 100.0))
        return None

    def set_volume(self, level: float) -> None:
        level = max(0.0, min(100.0, level))
        if self.has_pactl:
            result = self.run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{round(level)}%"])
            if result.returncode == 0:
                return
        if self.has_wpctl:
            result = self.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{level / 100:.2f}"])
            if result.returncode == 0:
                return
        raise RuntimeError("Volume control is unavailable.")

    def adjust_volume(self, delta: float) -> None:
        current = self.get_volume()
        if current is None:
            raise RuntimeError("Could not read current volume.")
        self.set_volume(current + delta)

    def is_muted(self) -> bool:
        if self.has_pactl:
            result = self.run(["pactl", "get-sink-mute", "@DEFAULT_SINK@"]) 
            if result.returncode == 0:
                return "yes" in result.stdout.lower()
        if self.has_wpctl:
            result = self.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]) 
            if result.returncode == 0:
                return "MUTED" in result.stdout
        return False

    def media_backend(self) -> str | None:
        player_name = self._playerctl_output("metadata", "--format", "{{playerName}}")
        if player_name:
            return f"playerctl:{player_name}"
        names = self._mpris_names()
        if names:
            return f"mpris:{names[0].split('.')[-1]}"
        return None

    def status_payload(self, message: str = "Ready") -> dict[str, Any]:
        return {
            "ok": True,
            "message": message,
            "volume": self.get_volume(),
            "muted": self.is_muted(),
            "media_backend": self.media_backend(),
        }


class RemoteHandler(BaseHTTPRequestHandler):
    controller = MediaController()
    token = ""

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        return

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _require_auth(self) -> bool:
        header = self.headers.get("Authorization", "")
        if header == f"Bearer {self.token}":
            return True
        self._send_json({"error": "Unauthorized"}, HTTPStatus.UNAUTHORIZED)
        return False

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        return json.loads(raw) if raw else {}

    def do_GET(self) -> None:  # noqa: N802
        if not self._require_auth():
            return
        if self.path == "/status":
            self._send_json(self.controller.status_payload())
            return
        self._send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        if not self._require_auth():
            return

        try:
            data = self._read_json()
            if self.path == "/command":
                self._handle_command(data)
                return
            if self.path == "/volume":
                level = float(data.get("level"))
                self.controller.set_volume(level)
                self._send_json(self.controller.status_payload("Volume updated"))
                return
            self._send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
        except ValueError:
            self._send_json({"error": "Invalid number supplied."}, HTTPStatus.BAD_REQUEST)
        except RuntimeError as error:
            self._send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
        except Exception as error:  # noqa: BLE001
            self._send_json({"error": str(error)}, HTTPStatus.INTERNAL_SERVER_ERROR)

    def _handle_command(self, data: dict[str, Any]) -> None:
        command = data.get("command")
        if command == "play_pause":
            self.controller.play_pause()
        elif command == "next":
            self.controller.next_track()
        elif command == "previous":
            self.controller.previous_track()
        elif command == "seek_forward":
            self.controller.seek(int(data.get("seconds", 15)))
        elif command == "seek_backward":
            self.controller.seek(-int(data.get("seconds", 15)))
        elif command == "volume_up":
            self.controller.adjust_volume(5)
        elif command == "volume_down":
            self.controller.adjust_volume(-5)
        elif command == "mute_toggle":
            self.controller.toggle_mute()
        elif command == "ping":
            pass
        else:
            self._send_json({"error": f"Unknown command: {command}"}, HTTPStatus.BAD_REQUEST)
            return

        self._send_json(self.controller.status_payload(f"Command '{command}' sent"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="LAN media remote receiver")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to (default: 0.0.0.0)")
    parser.add_argument("--port", default=DEFAULT_PORT, type=int, help=f"Port to bind to (default: {DEFAULT_PORT})")
    parser.add_argument("--token", required=True, help="Bearer token required by the phone app")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    RemoteHandler.token = args.token
    server = ThreadingHTTPServer((args.host, args.port), RemoteHandler)
    print(f"TARS Remote receiver listening on http://{args.host}:{args.port}")
    print("Press Ctrl+C to stop.")
    server.serve_forever()


if __name__ == "__main__":
    main()
