# 구조와 제약

`TeleportCore.DisplayLayout`은 현재 포인터와 디스플레이 사각형에서 다음 화면을 선택하는 순수 함수입니다. 화면 좌표는 `CGEvent.location`, `CGDisplayBounds`, `CGWarpMouseCursorPosition`의 Quartz 전역 좌표로 통일합니다. Retina 물리 픽셀을 별도로 곱하지 않습니다.

`GlobalHotKey`는 Carbon `RegisterEventHotKey`로 Option + Tab을 독점 등록합니다. 일반 키 입력을 가로채거나 기록하지 않으며, press/release 상태로 길게 누른 키의 반복을 억제합니다. 등록 실패는 오류로 종료하여 작동하지 않는 앱이 조용히 남지 않게 합니다.

`TeleportService`는 호출할 때마다 활성 화면을 새로 읽고 미러링 대상을 제거합니다. 연결 변경 이벤트를 위한 상시 폴링은 없습니다. 마우스 버튼이 눌린 상태에서는 이동하지 않습니다.

`NativeCursor`는 SkyLight의 `SLSMainConnectionID`, `SLSGetCursorScale`, `SLSSetCursorScale`을 런타임에 조회합니다. **실제 WindowServer 커서의 크기를 변경하지만 macOS 흔들기 제스처의 내부 애니메이션을 호출하는 것은 아닙니다.** 공개 API에 제스처를 시작하는 진입점이 없어 앱에서 약 0.8초의 확대·복원을 제어합니다. 설정 파일의 시스템 포인터 크기는 수정하지 않습니다. 확대 도중 사용자가 크기를 바꾸면 그 값을 존중합니다.

확대는 `--cursor-pulse` 보조 프로세스에서 수행합니다. 본체가 비정상 종료되어도 보조 프로세스는 짧은 애니메이션을 마치고 복원합니다. 정상 종료·SIGTERM·SIGINT에도 복원합니다. 보조 프로세스 자체가 SIGKILL로 종료되면 정리 코드를 실행할 수 없으므로 크기가 남을 수 있습니다. 이 경우 시스템 설정 → 손쉬운 사용 → 디스플레이에서 포인터 크기를 조절하면 됩니다.

`ScreenEdgeFlash`는 도착 디스플레이 ID와 일치하는 `NSScreen.frame` 전체에 비활성 패널을 표시합니다. 네 가장자리에서 안쪽 약 64pt까지 퍼지는 푸른색 그라데이션만 Core Animation으로 0.24초 동안 밝아졌다 사라지며 중앙은 투명합니다. 패널은 키·메인 창이 될 수 없고 마우스 입력을 통과시킵니다. 전체 화면 앱 위에서도 표시할 수 있도록 구성했으며, 반복 호출·효과 종료·잠자기·세션 비활성화 때 패널을 정리합니다. 동작 줄이기 설정에서는 애니메이션 없이 약한 효과만 0.12초 표시합니다.

`LSUIElement`와 `.accessory` 활성화 정책으로 Dock·Command + Tab·메뉴바·일반 창을 만들지 않으면서 비활성 효과 패널만 잠깐 표시합니다. 진단과 커서 helper는 `.prohibited`로 실행합니다. 최초 실행에만 `SMAppService.mainApp`을 등록하며 사용자 해제 상태를 존중합니다. 보안 정책이 로그인 항목 승인을 요구하면 시스템 설정에서 허용해야 합니다.

네트워크 코드, 자동 업데이트 확인, 텔레메트리, 외부 Swift 패키지는 없습니다. 앱은 Apple Silicon/macOS 14 이상으로 빌드합니다. 실제 실행 검증 환경은 [검증 기록](verification.md)에 따릅니다.
