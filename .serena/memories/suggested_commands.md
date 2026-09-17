# Suggested Commands
- From the repository root in PowerShell, package/upload: `smartthings edge:drivers:package .\work\LGWebOS26\hubpackage --channel <channel-uuid>`.
- Install the new version on a hub when explicitly needed: `smartthings edge:drivers:package .\work\LGWebOS26\hubpackage --channel <channel-uuid> --install --hub <hub-uuid>`.
- Inspect deployed runtime logs: `smartthings edge:drivers:logcat <driver-id>`.
- No project-local automated test runner is documented.