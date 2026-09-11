LG webOS TV V2 - SmartThings Edge 자동 설치 패키지
====================================================

목적
- 기존 toddaustin07/LGTV의 LG TV V1.1이 최신 webOS 25/26에서 연결/페어링되지 않는 경우를 보완합니다.
- SmartThings Hub + LG TV만으로 운영합니다.
- PC는 최초 Edge Driver 빌드/업로드 때만 사용하며, 설치 이후 PC는 꺼도 됩니다.

주요 변경
1. 기존 LG TV V1.1을 덮어쓰지 않는 별도 packageKey 사용
2. webOS 26의 legacy com.lge.test signed manifest 거절 대응
   - 기존 signed pairing을 먼저 시도
   - "blacklisted certificate" 오류가 발생하면 unsigned manifest로 1회 자동 재시도
3. unsigned fallback에 CONTROL_INPUT_TEXT / CONTROL_MOUSE_AND_KEYBOARD 권한 추가
4. 멀티 TV 환경에서 registration handshake table을 TV별 복제
5. SSDP 검색을 기존 MediaRenderer 하나에서 ssdp:all로 확장
6. 예전 DLNADEVICENAME 문자열 형식만 요구하지 않고 LG/webOS service/server marker도 인식

사용법
1. 압축을 풉니다.
2. RUN_INSTALL.cmd를 더블 클릭합니다.
3. SmartThings CLI가 없으면 공식 최신 Windows x64 standalone 버전을 .tools 폴더에 자동으로 받습니다.
4. 브라우저 로그인이 요구되면 사용하는 삼성/SmartThings 계정으로 로그인합니다.
5. 개인 Edge 채널이 없다면 Y를 선택하여 채널 생성 및 Hub enroll을 진행합니다.
6. package --install 단계에서 사용할 채널과 Hub를 선택합니다.
7. 완료 후 TV를 켠 상태에서 SmartThings 앱 -> 기기 추가 -> 주변 검색을 실행합니다.
8. TV에 연결 승인 팝업이 나오면 허용합니다.

전원 켜기(WOL)
- SmartThings에 추가된 LG TV 기기 설정에서 TV MAC 주소를 WOL MAC Address에 입력해야 합니다.
- TV 설정에서 네트워크를 통한 전원 켜기 / Wake on LAN 관련 옵션도 활성화되어 있어야 합니다.

문제 발생 시
- RUN_LOGCAT.cmd 실행
- LG TV를 켠 상태에서 SmartThings 주변 검색 또는 기기 조작
- 표시되는 로그를 복사해서 전달

주의
- 이 패키지는 LG의 비공개 webOS SSAP 인터페이스를 사용하는 커뮤니티 Edge Driver의 호환 패치입니다.
- 모든 LG TV 모델/펌웨어에서 동작을 보장할 수 없습니다.
- Todd Austin 원본 소스는 Apache-2.0 라이선스입니다. 설치 과정에서 원본 LICENSE도 작업 폴더에 보존됩니다.
