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
- 초대 URL: [SmartThings 채널 초대 링크](https://bestow-regional.api.smartthings.com/invite/3X21QoBZ8O2R)

위 초대 URL을 열고 채널 초대를 수락한 다음 SmartThings 앱에서 공유 채널의 드라이버를 Hub에 설치합니다.

## SmartThings CLI 사용법

### 1. CLI 로그인과 계정 확인

Windows용 공식 SmartThings CLI를 설치합니다.

- [SmartThings CLI releases](https://github.com/SmartThingsCommunity/smartthings-cli/releases)
- [SmartThings CLI documentation](https://developer.smartthings.com/docs/sdks/cli)

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

저장소 루트에서 실행합니다.

```powershell
smartthings edge:drivers:package .\work\LGWebOS26\hubpackage
```

이 명령은 Edge Driver 패키지를 빌드하고 계정에 새 드라이버 버전을 업로드합니다. 기존 LG TV V1.1을 덮어쓰지 않도록 별도의 `packageKey`를 사용합니다.

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
- 예전 `DLNADEVICENAME` 형식뿐 아니라 LG/webOS service, server, name marker 인식

## TV 연결

1. TV를 켜고 Hub와 같은 네트워크에 연결합니다.
2. SmartThings 앱에서 기기 추가 후 주변 기기 검색을 실행합니다.
3. TV에 표시되는 연결 승인 요청을 허용합니다.
4. 전원 켜기 기능을 사용하려면 기기 설정의 `WOL MAC Address`에 TV의 MAC 주소를 입력합니다.
5. TV에서 네트워크를 통한 전원 켜기 또는 Wake on LAN 관련 설정을 활성화합니다.

설치된 드라이버의 로그는 다음 명령으로 확인할 수 있습니다.

```powershell
smartthings edge:drivers:logcat <driver-id>
```

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
