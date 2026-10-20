# macOS AI Solver Implementation Plan

> **대체된 초기안:** 사용자가 RAG와 Canvas/LearningX·Chromium 환경을 선택했다. 현재 설계는 [Canvas RAG Solver 계획](2026-10-15-canvas-rag-solver.md)을 참조한다. 아래는 수동 클립보드 입력을 전제로 한 초기 기록이다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 이 계획은 구현 요청을 받은 뒤 실행한다. 현재 산출물은 계획 문서뿐이다.

**Goal:** Mac에서 클립보드로 복사한 객관식 문제 이미지를 AI API로 풀고, 메뉴 막대에 답 번호를 표시한다. 키보드 LED 출력은 해당 기기에서 검증한 경우 추가한다.

**Architecture:** Swift와 AppKit으로 개인용 메뉴 막대 앱 하나를 만든다. 클립보드 변경을 감지하면 이미지 한 장을 비동기로 전송하고, 검증한 응답만 메뉴 막대에 반영한다. 별도 서버와 외부 패키지는 두지 않는다.

**Tech Stack:** Swift, AppKit, Foundation/URLSession, Security/Keychain. LED 단계에서만 IOKit을 추가한다. Command Line Tools의 Swift 컴파일러로 로컬 `.app` 번들을 빌드한다.

**Spec:** 이 문서의 `요구사항과 결정` 및 `데이터 계약`. 사용자 요청과 API 키 방식 선택을 반영한 계획 초안이다. API 제공자는 미지정이므로 첫 연결은 OpenAI Responses API로 가정한다.

## 확인한 현재 상태

- 2026-10-15 기준 저장소에는 `.git`만 있고 제품 코드·테스트·설정·기존 호출자는 없다. 코드 그래프에도 소스 노드가 없다.
- 현재 실행 환경은 macOS 27.2를 보고하며 Command Line Tools의 Swift 경로가 존재한다. 실제 앱 컴파일은 아직 실행하지 않았다.
- 일반 설치 경로 두 곳에서는 Hammerspoon 앱을 찾지 못했다. 추가 설치 없이 가능한 Swift 방식을 기본으로 한다.
- 키보드 모델과 LED 제어 가능 여부는 확인하지 못했다.

## 요구사항과 결정

1. 사용자가 `Control + Shift + Command + 4`로 문제와 보기 영역을 클립보드에 복사한다. 앱은 캡처 자체나 브라우저 조작을 수행하지 않는다.
2. 첫 버전은 한 이미지에 문제 하나, 정답 하나, 보기 2~10개를 처리한다. 모델이 여러 문제·복수 정답·잘린 보기로 판단한 경우 `?`로 표시한다. 누락 탐지가 항상 정확하다고 가정하지 않는다.
3. 답은 화면에서 보기가 나열된 순서의 1-based 번호다. A/B/C/D라면 1/2/3/4로 매핑한다. 메뉴의 최근 결과에 원래 보기 라벨과 짧은 근거도 표시한다.
4. 앱 시작 시 감시는 꺼져 있다. 사용자가 메뉴에서 감시를 시작한 뒤 새로 복사한 이미지부터 전송한다. 텍스트와 파일 경로는 전송하지 않는다.
5. 클립보드의 일반 이미지와 스크린샷을 확실히 구별할 수 있다고 가정하지 않는다. 감시 중에는 새 이미지가 전송된다는 점을 초기 설정에 명시한다.
6. 메뉴는 `감시 시작/중지`, `최근 결과`, `설정`, `종료`로 제한한다. 설정에는 API 키와 모델 ID를 둔다. API 키는 Keychain, 모델 ID는 UserDefaults에 저장한다.
7. 최초 연결 검증 모델은 이미지 입력과 Structured Outputs를 지원하는 `gpt-4.1-mini`로 한다. 이는 연결 검증용 출발점이며 문제 풀이 품질을 검증했다는 뜻이 아니다. 더 적합한 모델은 표본 평가 결과에 따라 바꾼다.
8. 앱은 `LSUIElement=true`로 메뉴 막대에서 실행한다. 결과 갱신으로 포커스를 바꾸거나 창을 열지 않는다.
9. 클립보드 접근이 거부되면 상태와 설정 방법을 표시한다. 접근 허용 여부는 사용자가 시스템 설정에서 결정한다. 클립보드만 읽는 첫 버전에는 자체 화면 캡처와 키 입력 감시를 넣지 않는다.
10. 첫 버전은 메뉴 막대 출력을 완성한다. LED는 별도 기기 검증 단계이며 메뉴 막대 구현의 선행 조건으로 삼지 않는다.

## Global Constraints

- macOS 개인용 로컬 앱. 별도 백엔드·계정 시스템·DB·외부 패키지 없음.
- 이미지 한 장당 API 요청 한 번. 자동 재시도와 다중 모델 투표 없음.
- 전송 직전의 PNG는 10 MiB 이하로 제한한다. 디코딩 실패·초과 이미지는 `!`와 재캡처 안내로 처리한다.
- API 요청 타임아웃은 45초. 실패·취소·거절·불완전 응답을 숫자 답으로 처리하지 않는다.
- API 키·이미지·전체 응답을 파일이나 로그에 남기지 않는다. 최근 결과는 메모리에 하나만 보관한다.
- OpenAI 요청에는 `store:false`를 지정한다. 이것이 제공자 측 모든 보관을 없애거나 완전 로컬 처리를 의미하지는 않는다.
- 새 클립보드 변경·감시 중지 시 이전 답을 지우고 진행 중 요청을 취소한다. 취소 후 도착하는 응답도 표시하지 않는다.

## 데이터 계약

`SolveResult`는 다음 필드를 가진다.

| 필드 | 타입 / 의미 |
| --- | --- |
| `status` | `answered`, `uncertain`, `unreadable`, `unsupported` 중 하나 |
| `answer_index` | `Int?`, 보기가 나열된 순서의 1-based 번호 |
| `option_count` | `Int?`, 보기가 확인되면 2~10 |
| `answer_label` | `String?`, 화면에서 읽은 원래 보기 라벨 |
| `explanation` | `String`, 짧은 한국어 근거 또는 실패 이유 |

- `answered`일 때만 `option_count`와 `answer_index`가 필수이며 `1 <= answer_index <= option_count`를 검증한다.
- 다른 상태의 `answer_index`와 `answer_label`은 `null`이어야 한다. 모순된 결과는 잘못된 응답으로 처리한다.
- 모든 필드를 JSON Schema의 required에 포함하되 nullable 필드에는 null을 허용한다. `additionalProperties:false`, `strict:true`를 사용한다.
- 프롬프트에는 문제·보기·부정 표현·단위를 확인하고, 읽을 수 없거나 단일 정답을 정할 수 없으면 해당 상태를 반환하도록 지시한다. 신뢰도 숫자를 정답 확률로 표시하지 않는다.
- 구조화 출력은 형식 검증에 사용한다. 정답의 사실성이나 누락 탐지를 보장하는 것으로 취급하지 않는다.

| 앱 상태 | 메뉴 막대 |
| --- | --- |
| 감시 중지 | `—` |
| 감시 중, 새 이미지 대기 | `·` |
| 풀이 요청 중 | `…` |
| 유효한 답 | `3` 등의 숫자 |
| 불명확·읽기 실패·지원하지 않는 문제 | `?` |
| 권한·인증·네트워크·형식 오류 | `!` |

## 파일 구성과 영향 범위

모두 새 파일이다. 기존 호출자·설정·테스트·exports의 변경은 없다.

| 경로 | 책임 |
| --- | --- |
| `Sources/AISolver/AppMain.swift` | NSApplication 시작 및 AppDelegate 유지 |
| `Sources/AISolver/App.swift` | AppDelegate, 메뉴·설정 창, AppController의 요청 취소와 최신 결과 관리 |
| `Sources/AISolver/ClipboardMonitor.swift` | 변경 감지, 안정된 이미지 읽기와 PNG 변환 |
| `Sources/AISolver/SolverClient.swift` | 고정된 HTTPS API 호출, 응답 envelope 처리 |
| `Sources/AISolver/SolveResult.swift` | 응답 모델과 의미 검증 |
| `Sources/AISolver/KeychainStore.swift` | 키 저장·읽기·삭제 및 오류 전달 |
| `Resources/Info.plist` | 고정 bundle ID와 `LSUIElement` |
| `scripts/build.sh` | 로컬 아키텍처용 `.app` 빌드와 서명 절차 |
| `scripts/check.sh`, `Tests/SelfCheck.swift` | 별도 패키지 없는 assert 기반 동작 검증 |
| `Tests/Fixtures/*.json` | 성공·거절·불완전·잘못된 응답의 합성 표본 |
| `README.md`, `.gitignore` | 실행·권한·검증 절차, 빌드 산출물 제외 |
| `Sources/AISolver/LEDNotifier.swift` | LED 검증에 성공한 경우에만 추가 |

## Review Focus

- A 이미지 요청보다 B 요청이 먼저 완료되어도 A의 답이 B를 덮어쓰지 않아야 한다. Task 3에서 응답 순서를 뒤집어 검사한다.
- 클립보드 접근 거부·비이미지·감시 중지에는 이전 답이 남거나 이미지가 전송되면 안 된다. Task 1 및 Task 3에서 검사한다.
- 401/429/5xx·타임아웃·거절·잘린 JSON·범위 밖 번호는 숫자로 표시되면 안 된다. Task 2에서 검사한다.
- 한글·작은 글씨·수식·그림·잘린 보기의 정답률과 실패 양상은 형식 테스트만으로 입증되지 않는다. Task 4에서 정답이 알려진 이미지로 별도 평가한다.
- 전체화면·메뉴 막대 자동 숨김·재실행·강제종료는 표시와 권한·LED 원복에 영향을 줄 수 있다. Task 4 및 Task 5에서 실제 기기로 확인한다.

## Task 1: 클립보드 감지와 메뉴 막대 골격

**Files:** `AppMain.swift`, `App.swift`, `ClipboardMonitor.swift`, `Info.plist`, `build.sh`, `check.sh`, `SelfCheck.swift`, `.gitignore`.

**Interfaces:** `ClipboardMonitor(onChange: (Int, Data?) -> Void)`의 `start()`/`stop()`. 콜백은 MainActor에서 동작한다. 변경 감지 시 `(changeCount, nil)`로 이전 결과를 먼저 무효화하고, 같은 count가 안정되고 이미지가 있으면 `(changeCount, png)`를 한 번 더 전달한다. 비이미지에는 두 번째 콜백이 없다. `MenuState`는 위 상태 표를 따른다.

- [ ] 합성 pasteboard 입력으로 감시 시작 전 기존 이미지 무시, 변경당 무효화 콜백 1회와 이미지 콜백 최대 1회, PNG/TIFF/HEIF 이미지의 PNG 변환, 비이미지에는 이미지 콜백 없음, 읽는 동안 count가 바뀐 항목 폐기를 self-check에 추가한다.
- [ ] `scripts/check.sh`에서 새 계약의 미구현으로 실패함을 확인한다. 실제 시스템 클립보드를 바꾸지 않고 별도 named pasteboard로 검사한다.
- [ ] `build.sh`는 `swiftc -parse-as-library`로 앱 소스를 컴파일하고 Info.plist를 복사해 `build/AISolver.app`을 만든다. `check.sh`는 AppMain.swift를 제외한 소스와 자체 `@main`을 가진 SelfCheck.swift를 임시 디렉터리에 컴파일해 실행한다. 테스트 fixture 경로는 저장소 루트를 기준으로 명시적으로 전달한다.
- [ ] 0.5초 간격으로 `NSPasteboard.changeCount`를 확인한다. 변경 감지 즉시 이전 표시를 무효화하고, 다음 tick에 count가 안정됐을 때 이미지를 읽는다. 읽기 전후 count가 다르면 다음 tick에 최신 내용을 다시 읽는다.
- [ ] 메뉴 막대·감시 토글·종료 동작을 구현한다. 이미지 감지까지는 API 호출 없이 `…` 상태로 확인한다. 첫 접근 거부 시 반복 알림을 만들지 않고 감시를 중지한다.
- [ ] `scripts/check.sh`, `scripts/build.sh` 성공 후 `.app`을 열어 직접 복사한 이미지 감지와 감시 중지를 확인한다.

## Task 2: API 풀이와 응답 검증

**Files:** `SolverClient.swift`, `SolveResult.swift`, `Tests/SelfCheck.swift`, `Tests/Fixtures/*.json`.

**Interfaces:** `SolverClient(apiKey: String, model: String, session: URLSession)`의 `solve(png: Data) async throws -> SolveResult`. `SolveResult.validate() throws`는 데이터 계약을 검사한다. 테스트에는 URLProtocol을 사용하는 URLSession을 주입한다.

- [ ] 합성 응답으로 정상 번호 3, 범위 밖 번호 6/보기 5, null 답, 모순된 상태, refusal, incomplete 응답, 잘못된 JSON, 401/429/5xx 및 타임아웃 테스트를 추가하고 실패를 확인한다.
- [ ] `POST https://api.openai.com/v1/responses`에 data URL 방식의 `input_image`와 문제 풀이 지시를 보낸다. `URLSession` 비동기 호출, 45초 타임아웃, `store:false`, `text.format`의 strict JSON Schema를 사용한다. 이미지 입력 detail은 `high`로 한다.
- [ ] HTTP 상태와 response status를 먼저 확인하고, `output`에서 `output_text`를 찾아 디코딩한다. refusal과 incomplete는 별도 실패로 처리하며 SDK 전용 편의 필드가 HTTP JSON에 있다고 가정하지 않는다.
- [ ] 결과를 의미 검증한 뒤 반환한다. 이미지 안의 지시문은 문제 자료로 다루며 시스템 설정 변경 지시로 취급하지 않는다. 도구 호출 기능은 부여하지 않는다.
- [ ] `scripts/check.sh`를 실행하여 모든 합성 응답이 기대 상태로 분류되고 실제 API 연결이 발생하지 않음을 확인한다.

## Task 3: 연결·최신 요청 관리·API 키 설정

**Files:** `App.swift`, `KeychainStore.swift`, `Tests/SelfCheck.swift`.

**Interfaces:** `@MainActor AppController`의 `setEnabled(_ enabled: Bool)`, `clipboardChanged(changeCount: Int, png: Data?)`. 초기화 시 `solve: (Data) async throws -> SolveResult`와 `onStateChange: (MenuState) -> Void`를 받아 실제 API와 지연 응답 테스트를 연결한다.

- [ ] A/B 요청의 완료 순서를 뒤집은 경우 B만 표시, 감시 중지 후 완료 무시, 이미지 뒤 텍스트 복사 시 이전 결과 무효화, 실패 후 이전 번호 미표시 테스트를 추가하고 실패를 확인한다.
- [ ] 클립보드 변경과 감시 상태 전환마다 요청 식별자를 갱신한다. 기존 Task를 취소하고, 성공·실패 콜백 모두 현재 식별자 및 감시 상태가 일치할 때만 반영한다.
- [ ] API 키 설정 창과 Keychain 저장·읽기·삭제를 구현한다. 저장 실패를 성공처럼 표시하지 않는다. 키가 없으면 감시를 시작하지 않고 설정 안내를 표시한다.
- [ ] 최근 결과에는 원래 보기 라벨·짧은 근거와 요청 시각을 표시한다. 새 클립보드 변경 시 최근 결과도 지운다.
- [ ] `scripts/check.sh`, `scripts/build.sh` 후 실제 키로 샘플 이미지 한 장을 사용해 연결을 검증한다. 키 자체를 명령행 인수·문서·로그에 남기지 않는다. 요청 취소가 이미 처리된 API 비용을 되돌리지 않는 점을 설정 안내에 포함한다.

## Task 4: 실제 사용 검증과 로컬 실행 정리

**Files:** `scripts/build.sh`, `README.md`, 필요 시 앞 단계의 결함 수정.

- [ ] 고정 bundle ID와 설치 경로에서 재실행해 클립보드·Keychain 권한 유지 여부를 확인한다. 개발 중 서명 변경 때문에 재허용이 필요하면 실제 재현 조건과 로컬 코드 서명 절차를 README에 기록한다.
- [ ] 한글 일반 문제, 부정형 질문, 계산·수식, 그림 포함, 흐린 이미지, 잘린 보기, 여러 문제 등 정답이 알려진 표본 20개를 사용해 번호 일치·판독 실패·오답을 구분한다. 모델이 자신 있게 틀린 경우도 별도 집계한다.
- [ ] 전체화면, 메뉴 막대 자동 숨김, 연속 캡처, 네트워크 단절, 감시 중지, 종료·재실행을 직접 검사한다. 메뉴 막대가 항상 보인다고 보장하지 않는다.
- [ ] 캡처부터 결과 표시까지 지연의 중앙값·최댓값과 응답의 사용 토큰을 측정한다. 비용은 선택한 모델의 당시 단가로 계산한다. 측정 전 정답률·초당 처리량·건당 비용을 확정값으로 제시하지 않는다.
- [ ] `scripts/check.sh`, `scripts/build.sh`를 최종 실행하고 `build/AISolver.app` 실행 절차와 검증 결과를 README에 기록한다. 자체 화면 캡처를 추가하지 않았으므로 앱에 Screen Recording 권한을 요구하는지 실제 동작으로 확인한다.

## Task 5: 키보드 LED 기기 검증과 조건부 추가

**Files:** 검증 성공 시 `LEDNotifier.swift`, `App.swift`, `Tests/SelfCheck.swift`, `README.md`. 이 단계까지 전에는 LED 제어 기능을 제품에 넣지 않는다.

- [ ] 실제 내장/외장 키보드와 연결 방식을 확인한다. Hammerspoon의 `hs.hid.led.set("caps", state)`는 LED 전용 제어가 존재한다는 참고 근거이며, 현재 기기 호환성의 증거는 아니다.
- [ ] IOKit에서 해당 키보드의 Caps Lock LED output element를 찾고 원래 값을 읽을 수 있는지 확인한다. 단일 on/off를 시도해 반환 코드와 실제 점등을 함께 확인하고, 입력 소스·Caps Lock 상태가 변하지 않는지 검사한다.
- [ ] 읽기·쓰기·원복 중 하나라도 검증되지 않으면 이 단계 결과를 미지원으로 기록하고 메뉴 막대 버전을 유지한다. 권한 요구도 실제 결과로 기록한다.
- [ ] 검증 성공 시 `LEDNotifier.blink(count: Int) async throws`를 구현한다. 답 번호만큼 0.2초 켜짐/0.3초 꺼짐을 반복하고 원래 LED 값을 복구한다. 동기 HID 쓰기는 메인 스레드 밖에서 실행한다.
- [ ] 새 요청·감시 중지·종료에는 깜빡임을 취소하고 원복한다. 키보드가 제거되면 중단한다. 강제종료 시 원복 보장이 어려운 한계를 README에 기록한다.
- [ ] 합성 LED 쓰기 콜백과 대기 함수를 사용해 N회 점등·취소·실패 시 복구 시도를 self-check로 확인한다. 실제 키보드에서 1~5회 패턴과 원복을 검사한 뒤에만 설정에 LED 토글을 추가한다.

## 대안과 이번 범위에서 제외한 것

- Hammerspoon + Lua로 클립보드·메뉴·HTTP·LED를 묶을 수도 있다. 이미 Hammerspoon을 쓰는 환경이면 좋은 대안이지만 현재 확인한 설치 경로에는 없어 기본안으로 선택하지 않았다.
- OCR 별도 파이프라인, 웹앱, 브라우저 자동화, 자동 정답 클릭, 다중 AI, 자체 서버, 기록 DB, App Store 배포, 로그인 시 자동 실행은 첫 버전에 넣지 않는다.
- 앱을 Mac에서 실행하는 것과 풀이까지 Mac 안에서 끝내는 것은 별개다. 이번에 선택한 API 방식은 인터넷 연결·외부 이미지 전송·호출 비용이 필요하다.

## 근거 자료

- [Apple: 스크린샷과 Control 키를 사용한 클립보드 복사](https://support.apple.com/en-us/102646)
- [Apple: NSPasteboard.changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)
- [Apple: NSPasteboard.AccessBehavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum)
- [Apple: NSStatusBar와 텍스트 표시](https://developer.apple.com/documentation/appkit/nsstatusbar)
- [Apple: LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [Apple: Keychain services](https://developer.apple.com/documentation/security/keychain-services)
- [OpenAI Docs: 이미지 입력](https://developers.openai.com/api/docs/guides/images-vision)
- [OpenAI Docs: 구조화 출력](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)
- [OpenAI Docs: GPT-4.1 mini의 입력·출력 기능](https://developers.openai.com/api/docs/models/gpt-4.1-mini)
- [OpenAI Docs: 데이터 처리와 보관 설정](https://developers.openai.com/api/docs/guides/your-data)
- [Hammerspoon: hs.hid.led](https://www.hammerspoon.org/docs/hs.hid.led.html)
- [Apple: IOHIDDeviceSetValue](https://developer.apple.com/documentation/iokit/1588651-iohiddevicesetvalue)

**미확인:** 실제 컴파일·실행, API 호출 결과, 문제별 정답률·지연·비용, 현재 키보드 LED 호환성. 계획 작성 중에는 제품 코드 작성과 API 호출을 하지 않았다.
