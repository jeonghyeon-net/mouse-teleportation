# 로컬 빌드와 릴리스

GitHub Actions를 사용하지 않습니다. 로그인된 Apple Silicon Mac에서 Swift 6.0 이상, Python 3.11 이상, Git, 인증된 GitHub CLI로 실행합니다.

```sh
make check
make package
```

`build/Mouse Teleportation.app`과 `dist/packages/<버전>/`의 ZIP, DMG, `SHA256SUMS`, `release-manifest.json`을 생성합니다. 앱 아이콘은 `Assets/AppIcon.png`에서 macOS `.icns`로 변환됩니다.

패키지 검사는 ZIP을 실제로 풀고 DMG를 읽기 전용으로 마운트해 두 앱의 모든 파일, 서명, 버전, 소스 커밋, arm64 아키텍처를 대조합니다. ZIP에 포함된 앱의 자체 진단도 실행합니다. 로그인 항목 등록이나 커서 이동은 자체 진단에서 수행하지 않습니다.

## 게시

1. `VERSION`과 `CHANGELOG.md`를 갱신합니다.
2. 로컬 검증 후 `main`을 커밋·푸시합니다.
3. 준비 명령으로 검증·패키지·릴리스 노트를 생성합니다.
4. 게시 명령으로 태그와 GitHub Release를 만듭니다.

```sh
make release-prepare
make release
```

`mise run release-prepare`, `mise run release`도 같은 스크립트를 호출합니다. 일반 커밋·푸시에서는 릴리스가 실행되지 않습니다.

릴리스 산출물은 `dist/releases/<버전>/`에 별도로 저장합니다. 깨끗한 `main`, 허용한 origin 주소, 원격 main과 현재 HEAD 일치를 확인한 뒤 로컬 검증을 실행합니다. 같은 버전의 검증된 산출물이 있으면 재사용합니다. 태그를 푸시하고 GitHub 초안 릴리스를 생성한 다음 첨부 파일을 다시 내려받아 SHA-256을 대조한 후 공개합니다.

이미 존재하는 태그·릴리스를 덮어쓰지 않습니다. 게시가 중간에 실패하면 생성된 태그와 초안을 보존하고 중단합니다. 초안을 확인하여 누락된 업로드를 복구하고 첨부 파일을 대조한 뒤 수동 공개하거나 새 버전으로 다시 릴리스하세요. 공개된 파일을 교체하거나 태그를 이동하지 마세요.

## 서명과 공증

기본값은 ad-hoc 서명입니다. 이 빌드는 Apple 공증을 받지 않았으며, 다른 Mac에서 다운로드하면 Gatekeeper가 실행을 차단할 수 있습니다. 이 사실을 릴리스 본문에 표시합니다.

Developer ID 인증서와 키체인 공증 프로필이 준비되어 있으면 다음처럼 실행합니다.

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='mouse-teleportation' make release
```

앱을 공증하고 티켓을 붙인 뒤 ZIP·DMG를 생성합니다. DMG도 공증한 최종 파일로 체크섬을 기록합니다. 자격 증명은 저장소에 넣지 마세요. `SIGNING_IDENTITY`는 반드시 Developer ID Application 인증서를 지정합니다.

## 무결성 확인

사용자는 선택적으로 배포 파일과 함께 받은 `SHA256SUMS`를 확인할 수 있습니다.

```sh
shasum -a 256 -c SHA256SUMS
```

이 명령은 ZIP과 DMG를 모두 내려받은 폴더에서 실행합니다. `release-manifest.json`에는 소스 커밋, 최소 macOS, 아키텍처, 서명·공증 상태, 파일 크기·체크섬을 기록합니다.
