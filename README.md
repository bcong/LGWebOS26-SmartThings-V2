# LG webOS TV V2 for SmartThings Edge

LG webOS 25/26에서 기존 LG TV V1.1 Edge Driver의 연결과 페어링을 보완한 커뮤니티 드라이버 패키지입니다.

## Maintainer

- Developer: **GyeongSeop Kim**
- Package name: `LG webOS TV V2 - webOS26`
- Package key: `seop.lgtv.webos26.v2`

## Distribution

이 저장소에는 SmartThings Edge에 업로드할 수 있는 완성된 드라이버 패키지가 들어 있습니다.

```text
work/LGWebOS26/hubpackage/
```

SmartThings CLI의 Edge Driver Channel은 드라이버를 다른 사용자와 공유하는 공식 커뮤니티 배포 방식입니다. CLI로 드라이버를 업로드한 뒤 채널에 배정하고, 생성된 초대 URL을 사용자에게 전달하면 사용자가 자신의 Hub에 드라이버를 설치할 수 있습니다.

CLI 채널은 초대받은 사용자에게만 공유됩니다. SmartThings 기본 드라이버 목록에 모든 사용자 대상으로 등록되는 공식 카탈로그 배포는 별도의 SmartThings 인증 및 게시 절차가 필요하며, 일반 CLI 업로드만으로 자동 공개되지 않습니다.

### 현재 공유 채널

- Channel: `LG webOS 26 Compatibility`
- Driver ID: `63c66b59-1c9a-4d63-9b4b-766c9406385c`
- Package key: `seop.lgtv.webos26.v2`
- Latest deployed version: `2026-11-10T02:38:45.260550112`
- 초대 URL: [SmartThings 채널 초대 링크](https://bestow-regional.api.smartthings.com/invite/3X21QoBZ8O2R)

위 초대 URL을 열고 채널 초대를 수락한 다음 SmartThings 앱에서 공유 채널의 드라이버를 Hub에 설치합니다.

### Edge Driver 설치 위치

이 프로젝트는 VS Code 확장이 아니라 SmartThings Hub용 Edge Driver입니다. 다음 순서로 설치합니다.

1. [SmartThings 채널 초대 링크](https://bestow-regional.api.smartthings.com/invite/3X21QoBZ8O2R)를 엽니다.
2. 사용하는 Samsung 계정으로 로그인하고 사용할 Hub에서 `Enroll`을 선택합니다.
3. `Available Drivers`를 열고 `LG webOS TV V2 - webOS26`을 선택합니다.
4. `Install`을 누릅니다.
5. SmartThings 앱에서 기기 추가 → 주변 기기 검색을 실행합니다.

공식 안내: [Enroll in a Shared Channel and Install Drivers](https://developer.smartthings.com/docs/devices/hub-connected/enroll-in-a-shared-channel)

## SmartThings CLI 사용법

### 1. CLI 로그인과 계정 확인

Windows용 공식 SmartThings CLI를 설치합니다.

- [SmartThings CLI releases](https://github.com/SmartThingsCommunity/smartthings-cli/releases)
- [SmartThings CLI documentation](https://developer.smartthings.com/docs/sdks/cli)

Windows에서는 Releases 페이지의 `smartthings.msi`를 내려받아 설치합니다. 설치 후 PowerShell에서 다음으로 확인합니다.

```powershell
smartthings --version
```

CLI 사용자 설정 파일은 다음 위치에 있습니다.

```text
%LOCALAPPDATA%\@smartthings\cli\config.yaml
```

PAT는 저장소에 넣지 말고 이 설정 파일의 `default.token`으로 관리합니다.

PowerShell에서 로그인과 계정을 확인합니다.

```powershell
smartthings --version
smartthings locations
```

브라우저 로그인이 표시되면 드라이버 채널을 소유할 SmartThings 계정으로 로그인합니다.

### 2. Driver Channel 생성

처음 한 번만 실행합니다.

```powershell
smartthings edge:channels:create
```

대화형 질문에서 채널 이름과 설명을 입력합니다. 약관 URL을 요구하는 경우 공개 저장소의 약관 또는 프로젝트 안내 URL을 입력할 수 있습니다.

### 3. 드라이버 업로드

리모컨 capability와 capability presentation은 기존 SmartThings 계정에 한 번 등록해야 합니다. 새 계정에서 처음 등록할 때는 다음을 실행합니다.

```powershell
smartthings capabilities:create -n mirrordouble43237 -i .\work\LGWebOS26\capabilities\lgremotecontrol.json
smartthings capabilities:presentation:create mirrordouble43237.lgTvRemote --capability-version 1 -i .\work\LGWebOS26\capabilities\lgremotecontrol-presentation.json
```

이미 `mirrordouble43237.lgTvRemote` capability가 등록되어 있다면 기존 버전에 고유 입력 전환 명령을 추가합니다. `selectRemoteInputSource`는 기기의 다른 capability에도 있는 `setInputSource`와 명령 이름이 겹치지 않도록 추가한 alias입니다.

```powershell
smartthings capabilities:update mirrordouble43237.lgTvRemote --capability-version 1 -i .\work\LGWebOS26\capabilities\lgremotecontrol.json --profile oauth
smartthings capabilities:presentation:update mirrordouble43237.lgTvRemote --capability-version 1 -i .\work\LGWebOS26\capabilities\lgremotecontrol-presentation.json --profile oauth
```

capability 생성 결과의 ID를 프로필과 capability presentation에 동일하게 지정합니다. 수정한 리모컨 항목 구성을 SmartThings에 반영하고 새 `vid`를 발급받습니다.

```powershell
smartthings presentation:device-config:create -i .\work\LGWebOS26\capabilities\lgtv-v2d-device-config.json
```

명령 결과의 `vid`를 `hubpackage\profiles\lgtv_v2d.yaml`의 `metadata.vid`에 반영한 뒤 아래 명령으로 드라이버를 업로드합니다.

저장소 루트에서 실행합니다.

```powershell
smartthings edge:drivers:package .\work\LGWebOS26\hubpackage --channel 0b04b476-b7c8-48be-92a5-97922a0441e1
```

이 명령은 Edge Driver 패키지를 빌드하고 계정에 새 드라이버 버전을 업로드합니다. 기존 LG TV V1.1을 덮어쓰지 않도록 별도의 `packageKey`를 사용합니다.

업로드와 동시에 Hub의 설치 버전까지 교체하려면 PAT에 `w:devices:*` 권한을 포함하고 다음을 실행합니다.

```powershell
$env:SMARTTHINGS_PROFILE = "oauth"
smartthings edge:drivers:package .\work\LGWebOS26\hubpackage --channel 0b04b476-b7c8-48be-92a5-97922a0441e1 --hub 00f21b64-3565-453d-bb39-23d4decbd678
Remove-Item Env:SMARTTHINGS_PROFILE
```

이 `oauth` 프로필은 SmartThings CLI 로그인으로 저장된 인증을 사용합니다. PAT를 사용할 경우에는 `w:devices:*` 권한이 필요합니다.

### 4. 채널에 드라이버 배정

CLI 질문에 따라 드라이버와 버전을 선택할 수 있습니다.

```powershell
smartthings edge:channels:assign
```

특정 값을 알고 있다면 다음처럼 지정할 수 있습니다.

```powershell
smartthings edge:channels:assign <driver-id> <driver-version> --channel <channel-uuid>
```

### 5. 외부 사용자 초대

채널 소유자가 초대 URL을 생성합니다.

```powershell
smartthings edge:channels:invites:create
```

생성된 URL을 사용자에게 전달합니다. 사용자는 URL을 열어 채널 초대를 수락한 뒤 SmartThings 앱에서 공유 채널의 드라이버를 자신의 Hub에 설치합니다.

관련 공식 문서: [Driver Channels](https://developer.smartthings.com/docs/devices/hub-connected/driver-channels)

### 6. 채널 소유자의 Hub에 설치

채널 소유자가 자신의 Hub를 사용할 때는 먼저 채널에 등록합니다.

```powershell
smartthings edge:channels:enroll
smartthings edge:drivers:install
```

CLI가 채널과 Hub를 묻지 않게 하려면 각 명령의 `--channel`과 `--hub` 옵션을 사용합니다.

## 기능 및 호환성 변경

- 기존 LG TV V1.1을 덮어쓰지 않는 별도 `packageKey` 사용
- webOS 26에서 legacy `com.lge.test` 인증서가 거절되는 경우 unsigned pairing manifest로 1회 재시도
- unsigned fallback에 `CONTROL_INPUT_TEXT`, `CONTROL_MOUSE_AND_KEYBOARD`, `READ_INSTALLED_APPS` 권한 포함
- 여러 TV를 동시에 사용하는 경우 registration handshake 데이터를 TV별로 복제
- SSDP 검색을 기존 단일 MediaRenderer 검색에서 `ssdp:all` 검색으로 확장
- SmartThings 기기 화면에서 리모컨 항목 하나에 방향키, 숫자키, 음량/채널, 재생, 색상, 바로가기와 입력 선택 기능을 모아 제공
- TV가 보고한 외부 입력 목록을 리모컨의 입력 선택 목록에 반영
- 리모컨 키는 TV 모델/펌웨어에 따라 지원 여부가 다를 수 있으며, 음성 입력·휠/포인터 움직임·통합 리모컨 기기 제어는 webOS 네트워크 버튼 입력으로 동일하게 재현되지 않을 수 있음
- 예전 `DLNADEVICENAME` 형식뿐 아니라 LG/webOS service, server, name marker 인식
- 10초 간격 WebSocket heartbeat와 30초 PONG timeout으로 유휴 연결 감시
- WebSocket CLOSE/error/timeout을 동일한 재연결 경로로 처리하고 중복 재연결 타이머 방지; 연결 실패 시 5초 간격 재시도
- 화면만 끄고 WebSocket을 유지하는 모드 지원; TV 전원은 실제 standby가 아니라 켜진 상태로 남음
- 전원 켜기 시 WOL 패킷 3회 전송, 최대 2분간 15초마다 재전송하고 WebSocket은 5초 간격으로 재접속
- 명령 전송 실패 시 즉시 재연결하고, DHCP/IP 변경을 주기적으로 감지해 주소 갱신

## TV 연결

1. TV를 켜고 Hub와 같은 네트워크에 연결합니다.
2. SmartThings 앱에서 기기 추가 후 주변 기기 검색을 실행합니다.
3. TV에 표시되는 연결 승인 요청을 허용합니다.
4. 전원 켜기 기능을 사용하려면 `WOL MAC Address`에 TV의 MAC 주소를, `WOL Broadcast Address`에 네트워크 브로드캐스트 주소와 포트를 입력합니다.
5. TV 설정에서 `TV On With Mobile` 또는 Wi-Fi를 통한 전원 켜기를 활성화합니다.

TV가 대기 중 네트워크를 끄면 WebSocket heartbeat만으로 연결을 유지할 수 없습니다. 이때 드라이버는 WOL 패킷을 보내고 WebSocket 재접속을 시도하므로, TV의 네트워크 대기/원격 전원 켜기가 활성화되어 있어야 합니다.

기기 설정의 `Keep WebSocket Active Screen Off`는 기본 활성화되어 있습니다. 켜져 있으면 SmartThings 전원 끄기는 화면만 끄고 TV와 WebSocket은 계속 실행합니다. 실제 전원 standby를 원하면 이 옵션을 끄세요.

설치된 드라이버의 로그는 다음 명령으로 확인할 수 있습니다.

```powershell
smartthings edge:drivers:logcat <driver-id>
```

## SmartThings에서 LG TV 선택 및 페어링

드라이버를 설치한 뒤 SmartThings 앱에서 **기기 추가 → 주변 기기 검색**을 실행하면 `LG TV 선택기` 기기 하나가 추가됩니다. 선택기의 상세 화면에서 주변 LG TV 목록을 확인하고 원하는 TV를 선택하면 해당 TV만 SmartThings에 추가되고 연결/페어링이 시작됩니다. 선택 전까지는 주변 TV를 계속 재검색하며, TV를 선택하면 검색을 멈춥니다. LG TV 화면에 페어링 허용 팝업이 뜨면 허용하세요. 다시 검색하려면 선택기 화면을 새로고침합니다.

새 드라이버는 주변 TV를 자동으로 추가하지 않습니다. 선택기 목록에는 주변 LG TV가 표시되고, 기존에 SmartThings에 추가된 TV는 `이미 추가됨`으로 구분됩니다. 새 TV를 선택하면 그 TV만 추가되며, 이미 추가된 TV를 선택하면 연결을 다시 시도합니다. 기존 기기는 자동 삭제되지 않습니다.

## SharpTools 리모컨 타일

실제 리모컨 형태의 UI는 SharpTools 대시보드용 Custom Tile로 제공합니다. [lg-tv-remote.html](work/LGWebOS26/sharptools/lg-tv-remote.html)은 SharpTools HTML 타일 편집기에 붙여 넣는 body 내용입니다. 파일을 전체 복사해 HTML 타일에 넣고 다음 Thing 설정을 추가합니다.

- 설정 ID: `tv`
- 유형: Thing
- capability 필터: `mirrordouble43237.lgTvRemote`

타일을 대시보드에 추가한 뒤 설정에서 SmartThings LG TV 기기를 선택합니다. 타일은 드라이버의 `pressButton`으로 전원, 방향, 홈/뒤로, Amazon·Disney+·Coupang Play·TVING·Laftel 앱 바로가기, 음량/채널, 숫자, 재생, 색상 및 기타 키를 보내고, TV가 보고한 입력 목록은 `selectRemoteInputSource`로 전환합니다. 앱 바로가기는 TV의 설치 앱 목록에서 앱 ID를 찾아 실행합니다. 입력 목록이 비어 있으면 직접 선택은 비활성화되며, `입력 목록` 버튼으로 TV 자체 입력 메뉴를 열 수 있습니다. 이전 드라이버는 `selectRemoteInputSource` 명령을 처리하지 않으므로 입력 직접 전환을 사용하려면 capability/presentation 업데이트 후 드라이버도 다시 패키징해 Hub에 설치해야 합니다.

SmartThings 기본 capability 화면은 드래그 제스처를 지원하지 않아 원격 버튼을 표시하지 않습니다. SharpTools HTML Custom Tile의 중앙 패드에서 드래그하면 방향키가 전송되고, 짧게 누르면 확인이 전송됩니다. 별도 앱 설치 없이 휴대폰 브라우저에서 SharpTools 대시보드를 열어 사용할 수 있습니다. SharpTools 편집기 사용법은 [HTML Custom Tiles](https://docs.sharptools.io/developer-tools/custom-tiles/html) 및 [stio 라이브러리](https://docs.sharptools.io/developer-tools/custom-tiles/stio-lib)를 참고하세요.

드라이버의 원격 버튼 명령과 포인터 입력 WebSocket은 기본적으로 꺼져 있습니다. 다시 사용할 경우 TV 기기 설정에서 **Enable Remote Control**을 켜세요. 꺼져 있는 동안 기존 원격 코드와 capability 파일은 보존되지만 원격 명령은 무시되고 포인터 WebSocket은 연결되지 않습니다.

## SharpTools 없이 브라우저 리모컨 사용

같은 네트워크에 있는 Windows PC에서 저장소 루트 기준으로 실행합니다. 추가 npm 패키지는 필요하지 않습니다.
브라우저 리모컨을 사용하려면 먼저 해당 TV의 **Enable Remote Control** 설정을 켜야 합니다. 서버는 자동 실행되지 않으므로 사용하지 않을 때는 실행하지 마세요.

```powershell
node .\work\LGWebOS26\browser-remote\server.mjs
```

터미널에 표시되는 로컬 URL을 같은 Wi-Fi의 PC 또는 휴대폰 브라우저에서 엽니다. 페이지는 이 PC의 기존 SmartThings CLI `oauth` 프로필을 사용해 등록된 TV를 찾고 명령을 전달하므로 브라우저에서 SharpTools 계정에 로그인하지 않아도 됩니다. PC와 서버는 사용하는 동안 켜 둬야 하며, 출력된 접근 URL은 TV 제어 권한이 있으므로 공유하지 마세요. 종료하려면 터미널에서 `Ctrl+C`를 누릅니다.

## 출처 및 Fork 정보

이 프로젝트는 다음 원본 드라이버를 기반으로 한 호환 패치입니다.

- **LG TV V1.1 원본 / upstream `hubpackage` 경로**: [toddaustin07/LGTV/tree/main/hubpackage](https://github.com/toddaustin07/LGTV/tree/main/hubpackage)
- **webOS 26 pairing 호환성 참고**: [hobbyquaker/lgtv2](https://github.com/hobbyquaker/lgtv2)
- **SmartThings CLI**: [SmartThingsCommunity/smartthings-cli](https://github.com/SmartThingsCommunity/smartthings-cli)

원본 Todd Austin 드라이버의 Apache-2.0 라이선스 전문은 다음 파일에 보존되어 있습니다.

```text
work/LGWebOS26/LICENSE-TODD-AUSTIN.txt
```

이 프로젝트는 LG Electronics 또는 Samsung SmartThings의 공식 제품이나 공식 인증 드라이버가 아닙니다. LG의 비공개 webOS SSAP 인터페이스와 SmartThings Edge API 동작 변경에 따라 호환성이 달라질 수 있습니다.

## License

원본 드라이버에 적용되는 라이선스는 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)입니다. 원본 저작권 고지와 라이선스 전문을 배포물에서 제거하지 마십시오.
