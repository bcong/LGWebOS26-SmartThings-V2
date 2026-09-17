# Technology Stack
- SmartThings Edge driver runtime with Lua source; package permissions are LAN and discovery.
- Uses SmartThings `st.*` APIs, `cosock` sockets, `dkjson`, and the vendored `websocket`/`sha1` modules.
- Transport is WebSocket Secure (`wss://<TV-IP>:3001`) with SSL verification disabled for TV pairing compatibility.