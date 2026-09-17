# Project Conventions
- Keep CLIENT-like device behavior, discovery, and transport concerns in their existing Lua modules; avoid introducing new dependencies or abstractions.
- `init.lua` stores per-device connection state in fields (`ws_client`, `ws_sock`, `WSSaddr`, timers) and routes failures through `clear_connection` plus `schedule_reconnect`.
- WebSocket messages are JSON request objects with generated IDs and are sent over a connection reused for the device lifetime.
- Preserve unsigned-pairing fallback and device-specific cloned auth payloads when changing connection code.