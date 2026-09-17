# Project Core
- SmartThings Edge Lua driver package: `work/LGWebOS26/hubpackage/`.
- Main runtime/control flow is `src/init.lua`; SSDP discovery is in `src/discovery.lua`; vendored WebSocket implementation is under `src/websocket/`.
- TV control uses persistent WSS connections to port 3001; registration/auth payloads live in `src/authreq.lua` and `src/authreq_unsigned.lua`.
- Read `mem:tech_stack` for runtime/dependency assumptions, `mem:conventions` for Lua/driver patterns, and `mem:task_completion` for validation/deployment commands.