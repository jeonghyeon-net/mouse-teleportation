# 개발 규칙

- 일반 작업은 현재 `main`에서 진행한다. 사용자 요청 없이 PR이나 GitHub Actions를 만들지 않는다.
- 빌드·검증·릴리스는 로컬 Mac에서 수행한다. `make check`, `make package`, `make release`가 진입점이다.
- 앱은 창·메뉴바·Dock 항목 없이 동작한다. `LSBackgroundOnly`와 비활성화 정책을 유지한다.
- 디스플레이 선택은 `TeleportCore`에 두고 Quartz 좌표를 사용한다.
- 커서 확대가 macOS의 내장 흔들기 제스처를 직접 실행한다고 표현하지 않는다. 실제 시스템 커서를 비공개 API로 조절한다는 제약을 명시한다.
- 한국어 문서·주석, 영어 식별자를 사용한다.
- 검사 결과와 실제로 확인하지 않은 항목을 구분한다. 공개된 태그·릴리스 첨부 파일을 덮어쓰지 않는다.
- security-audit 또는 open-code-review-delegate 사용 시 소스와 도구는 로컬에 유지한다. Codex 모델 호출 외 네트워크, 텔레메트리, 외부 API·라이브 엔드포인트·패키지 업데이트 확인을 금지한다. 명시적으로 요청한 설치·업데이트 다운로드만 허용한다.
- Open Code Review는 `/Users/pi/.local/bin/ocr`의 `ocr delegate` 명령만 사용한다. OCR 관리 LLM 리뷰 명령은 금지한다.
- 보안 감사 대상 코드는 OS 강제 격리에서만 실행한다. 승인된 경로는 `/Users/pi/.local/bin/security-audit-run`이며 관련 소스·더미 fixture만 `/Users/pi/.local/share/security-audit-volume/fixtures/<fixture-id>`에 준비한다. `--fixture <fixture-id> --image python|node --agent-id <id> --promote <scratch-relative-file> -- <command>` 형식을 사용한다. 자격 증명을 복사하거나 호스트에서 대상 코드를 직접 실행하지 않는다. 지원 도구 체인이 없으면 needs_validation을 유지한다.
