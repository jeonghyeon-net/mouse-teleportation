# 개발과 기여

macOS 14 이상의 Apple Silicon Mac, Swift 6.0 이상 Command Line Tools 또는 Xcode, Python 3.11 이상이 필요합니다. Python은 개발·배포에만 사용합니다. 앱에는 포함하지 않습니다.

```sh
make check       # Swift 테스트, 배포 도구 테스트, Release 앱 빌드, 자체 진단
make install     # /Applications에 설치하고 로그인 자동 시작 등록, 실행
make status      # 화면, 커서, 로그인 항목 상태 출력
make package     # ZIP, DMG, 체크섬 생성 및 실제 패키지 검사
```

`mise`를 사용한다면 같은 이름의 태스크를 실행할 수 있습니다. 일부 Command Line Tools의 Swift Testing 매크로 검색 문제를 피하도록 설치된 매크로 라이브러리가 있으면 테스트 명령에 경로를 명시합니다.

## 원칙

- 화면 선택 규칙은 `TeleportCore`, 시스템 연동은 `MouseTeleportation`에 둡니다.
- Quartz 전역 좌표를 사용합니다. AppKit 좌표와 혼합하지 않습니다.
- 일반 실행에 창·메뉴바·Dock 항목을 추가하지 않습니다.
- 전역 키는 Carbon Hot Key API로 등록합니다. 모든 키 입력을 수집하지 않습니다.
- README와 주석은 한국어, 식별자는 영어로 작성합니다.
- 필요한 범위의 로컬 검증을 실행하고 결과와 한계를 남깁니다.
- GitHub Actions 워크플로를 추가하거나 활성화하지 않습니다.

모니터 배치 규칙은 `make test`로 검사합니다. 실제 단축키·커서 확대 검사는 로그인된 GUI 세션과 두 개 이상의 확장 디스플레이가 필요합니다. 단축키의 충돌 여부와 macOS 버전에 따른 비공개 API 동작도 확인하세요.

`make install` 후 `make live-check`를 실행하면 실제 전역 키를 보내 이동·확대·복원·키 반복·포커스 유지를 검사하고 포인터를 기존 위치로 돌려놓습니다. 검사 중 약 4초 동안 마우스와 키보드를 사용하지 마세요. 이 개발용 입력 검사에만 실행 주체의 이벤트 전송 권한이 필요하며, 일반 앱은 해당 권한을 요청하지 않습니다.

## 제안과 변경

버그에는 macOS 버전, 화면 배치·배율, 기대 동작과 실제 동작을 적어 주세요. 개인정보가 들어 있는 화면 캡처나 로그는 지워 주세요. 커밋 전에 `make check`를 실행합니다. 릴리스 방법은 [배포 문서](docs/releasing.md)에 있습니다.
