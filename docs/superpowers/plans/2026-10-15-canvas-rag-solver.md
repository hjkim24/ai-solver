# Canvas RAG Solver Implementation Plan

> 실행 기록(2026-10-15): 로컬 앱·확장 구현 및 실제 Aside Native Messaging 연결까지 진행했다. 최신 검증 결과와 미검증 항목은 [README](../../../README.md)와 [구현 결정](../../implementation-notes.md)을 따른다. 아래 계획 체크 항목은 실제 API·다중 문항 캡처·품질 평가까지 포함하므로 로컬 테스트만으로 전체 완료 표시하지 않는다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 현재 작업은 계획 갱신이며 제품 코드를 구현하지 않는다.

**Goal:** Canvas/LearningX의 문제 번호에 커서를 올리고 단축키를 누르면 문제와 보기를 자동 캡처하고, 미리 등록한 자료를 검색해 풀이한 뒤 macOS 메뉴 막대에 답 번호를 표시한다.

**Architecture:** Chromium 확장이 문제 영역 탐지·단축키·탭 캡처를 담당한다. Swift 메뉴 앱은 Native Messaging으로 잘라낸 이미지와 문제 텍스트를 받아 자료 검색 및 AI 풀이를 수행한다. 자료는 OpenAI 관리형 Vector Store에 등록하고 별도 자체 서버는 두지 않는다.

**Tech Stack:** Chromium Manifest V3, JavaScript, Native Messaging, Swift/AppKit, URLSession, Keychain, OpenAI Vector Store Search 및 Responses API. 외부 제품 패키지는 추가하지 않는다.

**Spec:** [제품·기술 스펙 v1](../specs/2026-10-15-canvas-rag-solver-design.md). 구체적인 동작·프로토콜·검수 기준은 스펙을 따른다. 이 계획은 [수동 클립보드 입력 초기안](2026-10-15-macos-ai-solver.md)을 대체한다.

## 확정 사항과 제안

- 사용자 확정: API 키 사용, 등록 자료를 활용하는 RAG, Canvas/LearningX, Chromium 기반 브라우저.
- 사용자 추가 조건: 한 화면에 여러 문항이 보이는 경우도 정상 지원·검증 대상이다. 대상 문항의 본문과 보기는 대체로 화면 안에 들어오는 것을 전제로 한다.
- 이번 제안: 브라우저 확장 + macOS 메뉴 앱. 화면 픽셀에서 문제 경계를 추측하는 범용 탐지보다 해당 페이지의 HTML 문제 묶음을 활용한다.
- 실제 LearningX 도메인·브라우저 제품명·퀴즈 화면의 DOM은 아직 확인하지 않았다. 첫 구현 단계에서 실제 화면 한 종류를 확인하고 그 구조부터 지원한다. Canvas라는 이름만으로 특정 CSS selector나 iframe 구조를 확정하지 않는다.
- Canvas의 Classic Quizzes와 New Quizzes는 구별한다. New Quizzes에는 iframe 제거 통합이 도입되어 있으므로 실제 페이지가 iframe이라고 단정하지 않는다.
- 최초 범위는 지정 브라우저·프로필 하나, 지정 LearningX 사이트 하나, 한 번에 객관식 단일 문항·단일 정답이다. 보기는 2~10개를 지원한다.
- 메뉴 막대 숫자 표시를 우선 완성한다. Caps Lock LED는 초기안의 실기 검증 조건을 유지하는 후속 단계다.

## 동작 계약

1. **자료 준비:** 메뉴의 자료 관리에서 PDF/TXT/MD를 여러 개 등록한다. 업로드와 인덱싱이 끝난 문서만 검색 대상으로 사용하며 파일별 준비·실패 상태를 보여 준다.
2. **문제 지정:** 사용자가 문제 번호 또는 해당 문제 내부에 마우스를 올린다. 클릭·드래그·클립보드 복사는 필요하지 않다.
3. **단축키:** 브라우저가 활성화된 상태에서 `Command + Shift + Y`를 누른다. 등록 충돌을 검사하고 사용자가 브라우저 단축키 설정에서 바꿀 수 있게 안내한다. 첫 버전은 브라우저 밖의 전역 단축키를 등록하지 않는다.
4. **범위 탐지:** 단축키로 실행된 첫 DOM 스냅샷의 `:hover` 요소 체인에서 가장 안쪽 요소를 찾고, 실제 화면에서 검증한 문제 컨테이너까지 올라간다. 스냅샷은 native 준비 응답 전에 얻고 이후 커서 이동으로 대상을 바꾸지 않는다. 사이드바의 문제 이동 번호와 본문 문제 번호를 구별한다. 본문 문제와 보기 전체를 포함하는 컨테이너만 인정한다.
5. **범위 검증:** 선택한 컨테이너의 문항 하나, 문제 본문, 보기 2~10개를 확인한다. 화면 전체에 보이는 문항 수는 제한하지 않는다. 대상 문항이 화면 안에 완전히 들어오면 해당 영역만 캡처하며, 이웃 문항의 내용은 포함하지 않는다. 외부 공통 지문·그림이 컨테이너 밖에 있어 누락될 수 있는 화면은 지원 확인 전 전송하지 않는다.
6. **캡처:** `tabs.captureVisibleTab()`으로 현재 탭의 보이는 화면을 얻고, 문제 사각형만 확장 내부에서 잘라 PNG로 만든다. 전체 탭 이미지는 외부 API로 보내지 않는다. CSS 좌표와 실제 이미지 크기의 비율로 자르며 DPR만으로 크기를 단정하지 않는다.
7. **일관성:** 범위 측정 전후의 탭·문서·스크롤·viewport·문제 사각형을 비교한다. 캡처 중 바뀌면 폐기한다. 잘린 문제는 자동 스크롤·분할 합성하지 않고 화면에 전체가 보이도록 조정하라는 상태를 표시한다.
8. **RAG 검색:** 확장이 현재 화면에서 읽은 문제 본문과 보기 텍스트를 검색 질의로 전달한다. 메뉴 앱이 선택된 Vector Store에서 관련 구절 최대 5개를 검색한다. 숨겨진 정답 데이터나 Canvas 내부 API를 읽지 않는다.
9. **풀이:** 잘라낸 문제 이미지·표시된 문제 텍스트·검색된 구절을 Responses API에 함께 보낸다. 최종 번호와 짧은 근거, 참조한 자료 ID 및 근거 문구를 구조화 출력으로 받는다.
10. **표시:** 번호는 보기 순서의 1-based 값이다. 메뉴 막대에는 숫자를, 최근 결과에는 문제 번호·원래 보기 라벨·근거와 파일명을 표시한다. 페이지 번호는 실제 추출 메타데이터가 있을 때만 표시한다.
11. **실패:** 범위 미확인·자료 근거 부족은 `?`, 권한·연결·인증·형식 오류는 `!`, 진행 중은 `…`, 사용 중지는 `—`로 표시한다. 번호 범위·참고자료 ID·인용 구절 검증에 실패하면 숫자로 표시하지 않는다.

## Global Constraints

- 클립보드 상시 감시를 제거한다. 사용자의 단축키 동작에만 캡처·풀이를 수행한다.
- 확장 기본 권한은 `activeTab`, `scripting`, `storage`, `nativeMessaging`으로 제한한다. 학습 사이트 origin을 로컬 설정에 등록하고 다른 사이트에서는 처리하지 않는다. 광범위한 상시 사이트 접근을 기본으로 요청하지 않는다.
- cross-origin iframe은 activeTab만으로 접근할 수 있다고 가정하지 않는다. 해당 구조를 확인한 뒤 필요한 origin에 대한 권한과 프레임 어댑터를 추가하거나 첫 버전에서 미지원으로 표시한다.
- 확장과 앱 사이에는 Native Messaging을 사용한다. localhost HTTP 서버는 추가하지 않는다.
- 브라우저 확장의 `connectNative()`가 메뉴 앱 실행 파일을 시작하고 포트를 유지한다. 첫 버전은 확장을 통해 앱을 시작하며 포트 종료 시 작업을 취소하고 종료한다. 별도 상시 앱과 별도 중계 서버를 동시에 실행하지 않는다.
- native host manifest의 allowed_origins는 설치된 확장 ID 하나로 한정한다. 브라우저 제품별 사용자 manifest 경로는 실제 설치 환경에 맞춰 정한다.
- native 메시지는 길이 prefix가 있는 UTF-8 JSON이다. 수신 길이는 16 MiB 이하, PNG 디코딩 후 크기는 10 MiB 이하, 출력 메시지는 1 MB보다 작게 제한한다. 부분 read/write·EOF·잘못된 JSON을 처리한다. stdout은 프로토콜 메시지에만 사용한다.
- API 키는 Keychain에만 저장한다. 이미지·전체 응답·키를 로그와 파일에 남기지 않는다. 모델 ID와 Vector Store ID는 UserDefaults에 저장한다.
- 등록 자료는 외부 서비스에 저장된다. 자료 관리에서 제거할 때 앱이 생성한 Vector Store 연결과 Files 객체를 모두 정리하고 실패를 표시한다. 응답의 `store:false`는 등록 자료를 삭제하는 옵션이 아니다.
- 문제당 검색 요청 1회와 최종 모델 풀이 요청 1회를 기본으로 한다. 자동 재시도·다중 모델 투표는 추가하지 않는다. 전체 요청 제한 시간은 45초로 시작하고 실제 지연 측정 뒤 조정한다.
- 새 단축키 입력·탭/문서 변경·사용 중지 시 이전 결과와 요청을 무효화한다. 늦게 도착한 검색·풀이 결과는 표시하지 않는다.
- 첫 검증 모델은 초기안의 `gpt-4.1-mini`다. 도메인별 정답률은 미검증이며 최종 모델 선택은 표본 평가로 결정한다.

## 파일과 인터페이스

기존 제품 코드는 없다. 아래는 모두 신규 파일이며 현재 변경은 계획 문서만이다.

| 파일 | 책임 |
| --- | --- |
| `extension/manifest.json` | MV3, 단축키, 권한 |
| `extension/background.js` | 단축키 처리, 탭 검증, 캡처, native port 관리 |
| `extension/question-locator.js` | 해당 Canvas 화면의 문제 컨테이너·텍스트·좌표 추출 |
| `extension/crop.js` | 실제 캡처 이미지 기준 좌표 변환과 PNG 자르기 |
| `extension/tests/selfcheck.html`, `extension/tests/fixtures/*.html` | 합성 문제 화면과 브라우저 내 self-check |
| `Sources/AISolver/AppMain.swift`, `App.swift` | 메뉴 앱 수명, 메뉴·설정·자료 관리, 최신 요청 관리 |
| `Sources/AISolver/NativeMessaging.swift` | stdio 프레이밍 및 메시지 검증 |
| `Sources/AISolver/KnowledgeBaseClient.swift` | 파일 등록·인덱싱 상태·검색·삭제 |
| `Sources/AISolver/SolverClient.swift`, `SolveResult.swift` | 이미지와 근거를 통한 최종 풀이 및 결과 검증 |
| `Sources/AISolver/KeychainStore.swift` | API 키 보관 |
| `Resources/Info.plist`, `Resources/native-host.json` | LSUIElement 및 native host 설정 |
| `scripts/build.sh`, `scripts/install.sh`, `scripts/check.sh` | 빌드·브라우저별 등록·assert 기반 검사 |
| `Tests/SelfCheck.swift`, `Tests/Fixtures/*.json` | native·검색·응답·요청 경쟁 테스트 |
| `README.md`, `.gitignore` | 설치·권한·제약·검증 기록과 산출물 제외 |

- 확장 → 앱 `begin`: 새 request_id로 기존 작업·결과를 무효화한다. 탐지 실패 시에도 기존 답부터 지운다.
- 확장 → 앱 `solve`: `{version, request_id, remaining_ms, question, png_base64}`. question은 문서 세션·문항 키·표시 번호·본문·보기 배열이다. 상세 필드는 스펙 IPC-02를 따른다.
- 확장 → 앱 `cancel`: request_id가 일치하는 작업만 취소한다. 오래된 취소 메시지가 새 작업에 영향을 주면 안 된다.
- 앱 → 확장 `state`: `{version, request_id, state, message}`. 확장은 현재 request_id와 다른 작업 결과를 반영하지 않는다.
- `KnowledgeBaseClient.search(query: String) async throws -> [Evidence]`: Evidence는 검색 응답의 file_id, filename, text, score를 보존한다.
- `SolverClient.solve(png: Data, questionText: String, optionLabels: [String], evidence: [Evidence]) async throws -> SolveResult`. 호출 전 question의 보기 배열에서 화면 순서와 원래 라벨을 보존한다.
- `SolveResult`: status, nullable answer_index/answer_label, explanation, sources(file_id, quote). answered에는 유효한 번호와 sources가 필요하다. sources는 실제 검색 결과의 파일 ID와 해당 파일 결과에 포함된 인용 문구로 검증한다. 이 검증은 정답 자체의 정확성을 보장하지 않는다.

## Review Focus

- 번호에 올린 커서가 사이드바·다른 문제를 가리키거나 문제 밖 공통 지문을 놓치는 경우: Task 1에서 실제 화면과 합성 fixture로 확인한다.
- 한 화면에 2·3·5개 문항이 있을 때 첫째·가운데·마지막 중 커서가 가리킨 문항만 선택하고 이웃 문항을 제외하는지 Task 1 및 Task 2에서 확인한다.
- 브라우저 확대·Retina·스크롤·탭 전환으로 잘못된 영역을 자르는 경우: Task 2에서 이미지와 좌표를 검증한다.
- 키·이미지·프로토콜 신뢰 경계 및 프로세스 중복·종료 처리: Task 3에서 합성 메시지와 실제 브라우저 연결을 검사한다.
- 인덱싱 실패·근거 누락·잘못된 인용·자료 삭제 실패: Task 4 및 Task 5에서 검사한다.
- 새 문제보다 이전 응답이 늦게 도착하거나 검색과 풀이 사이에 문서가 바뀌는 경우: Task 5에서 완료 순서를 뒤집어 검사한다.

## Task 1: 대상 화면의 문제 범위 판별

- [ ] 실제 사용하는 LearningX 화면에서 퀴즈 엔진, 프레임, 문제 번호·본문·보기·공통 지문 구조를 읽기 전용으로 확인한다. 정확한 도메인·브라우저 제품명·검증한 문제 컨테이너 selector를 README에 기록한다.
- [ ] 해당 구조를 반영한 합성 HTML fixture를 만든다. 한 화면의 1·2·3·5개 문항, 첫째·가운데·마지막 선택, 사이드바 번호, 문항 간 여백, 그림, 긴 보기, 공통 지문, hover 없음, 다른 사이트, iframe을 포함한다. 스펙 AC-01~AC-14의 성공·전송 중단 조건을 검사한다.
- [ ] `locateQuestion(hoveredElement, viewport)` self-check가 올바른 문항 rect·본문·보기 라벨을 반환하고, 모호한 경우 실패하는지 먼저 검사한다. 사이트 어댑터를 구현해 통과시킨다.
- [ ] 실제 화면에서 API 전송 없이 탐지 영역을 일시적으로 표시해 문제·보기·그림 포함 여부를 확인한다. 검증한 레이아웃만 지원 목록에 넣는다. 확장이 DOM을 읽을 수 없는 구조라면 이 단계 결과를 보고하고 캡처 접근을 재설계한다.

## Task 2: 단축키와 자동 캡처

- [ ] 단축키 등록·충돌 안내, activeTab 기반 스크립트 실행, 지정 origin 확인을 구현한다. 입력창 편집과 충돌하는 조합은 변경할 수 있게 안내한다.
- [ ] `cropRect(rect, viewportSize, imageSize)`의 80/100/125/150% 확대·Retina·경계 밖 입력을 assert로 검사하고 구현한다.
- [ ] 현재 탭 캡처 → 로컬 crop → PNG 제한 검사까지 연결한다. 탭/문서/스크롤/크기 변경과 화면 밖 문제에는 전송 이미지가 생성되지 않는지 확인한다.
- [ ] 처음에는 확장의 개발용 미리보기에서 잘라낸 이미지가 맞는지만 검증한다. 일상 사용 시 매번 미리보기 확인을 요구하지 않는다.

## Task 3: Mac 메뉴 앱과 native 연결

- [ ] 부분 메시지·연속 메시지·EOF·과대 길이·잘못된 origin·잘못된 base64·PNG 손상 테스트를 먼저 만들고 NativeMessaging을 구현한다.
- [ ] 확장의 port 하나가 메뉴 앱 프로세스 하나를 유지하도록 연결한다. 연결 종료·브라우저 종료·앱 종료·service worker 재시작에 중복 메뉴 앱과 응답 재전송이 없는지 검사한다.
- [ ] 메뉴의 사용 시작/중지·설정·자료 관리·최근 결과·종료와 Keychain 저장을 구현한다. 결과 갱신 시 포커스는 이동하지 않는다.
- [ ] `scripts/check.sh`와 `scripts/build.sh`를 통과시키고, 실제 브라우저 제품과 확장 ID가 확정된 뒤에만 사용자용 native host 등록 파일을 설치한다. 현재 계획 단계에서는 설치 위치를 변경하지 않는다.

## Task 4: 자료 등록과 검색

- [ ] 파일 업로드·Vector Store 연결·인덱싱 완료/실패·검색 결과·삭제 실패를 합성 HTTP 응답으로 검사한다.
- [ ] 자료 여러 개의 등록/상태/삭제 UI와 KnowledgeBaseClient를 구현한다. 준비된 자료가 없으면 풀이를 시작하지 않는다.
- [ ] 질문 텍스트로 Vector Store Search를 호출해 상위 구절 최대 5개를 얻는다. 실제 검색 결과의 ID·파일명·문구를 그대로 다음 단계에 전달한다.
- [ ] 사용자가 제공할 실제 자료에서 인덱싱 텍스트와 그림·수식의 보존 수준을 확인한다. 텍스트 검색만으로 정보가 누락되는 자료는 페이지 이미지 보완이 필요한 대상으로 기록하며 첫 버전에서 해결됐다고 표시하지 않는다.

## Task 5: RAG 풀이·최신 결과·품질 평가

- [ ] 정답·범위 밖 번호·근거 없음·알 수 없는 출처 ID·검색에 없는 인용·refusal·incomplete·401/429/5xx·timeout을 self-check에 추가하고 실패를 확인한다.
- [ ] 문제 이미지와 검색 구절로 최종 풀이를 요청하고 strict JSON Schema 및 의미 검증을 적용한다. 검색 근거가 부족하면 no_evidence 상태로 `?`를 반환하도록 지시한다. 출처 불일치 결과는 표시하지 않는다.
- [ ] 새 요청 ID·사용 중지·탭 변경·문서 이동이 검색/풀이 단계 모두를 무효화하도록 구현한다. A/B 응답 순서를 뒤집어 B만 표시됨을 확인한다.
- [ ] 정답이 알려진 문제 20개로 캡처 정확성, 검색 근거 적합성, 답 정확성, 답을 보류한 경우를 나눠 평가한다. 전체 지연과 검색/모델별 사용량을 기록한다.
- [ ] 최종 `scripts/check.sh`, `scripts/build.sh`, 확장 브라우저 self-check 및 실제 연결 검사를 수행한다. 수치와 지원 레이아웃은 이 결과만 근거로 기록한다.

## 후속 단계와 제외 범위

- Caps Lock LED 출력은 초기안 Task 5의 기기별 점등·입력 상태 불변·원복 검증 후 추가한다.
- 클립보드 상시 감시, 범용 화면 OCR 탐지, 자동 스크롤·긴 문제 합성, 숨겨진 문제/정답 조회, 답 자동 클릭, 다중 사이트·브라우저/프로필 동시 지원, 별도 서버는 첫 버전에 넣지 않는다.
- 실제 화면 DOM, 브라우저별 설치, RAG 정확도·지연·비용, 키보드 LED는 미검증이다. API 방식에서는 등록 자료와 잘라낸 문제 이미지가 외부 서비스로 전송된다.

## 근거 자료

- [Chrome: Commands와 단축키](https://developer.chrome.com/docs/extensions/reference/api/commands)
- [Chrome: activeTab과 단축키에 의한 접근](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab)
- [Chrome: tabs.captureVisibleTab](https://developer.chrome.com/docs/extensions/reference/api/tabs#method-captureVisibleTab)
- [Chrome: Native Messaging과 macOS 등록](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
- [OpenAI Docs: Vector Store Search](https://developers.openai.com/api/reference/resources/vector_stores/methods/search)
- [OpenAI Docs: 등록 문서를 활용하는 검색](https://developers.openai.com/api/docs/guides/tools-file-search)
- [Instructure: Classic/New Quizzes 구분](https://community.instructure.com/en/kb/articles/660992-how-do-i-use-the-quizzes-index-page)
- [Instructure: New Quizzes의 iframe 제거 통합](https://community.instructure.com/en/discussion/comment/1255351)
