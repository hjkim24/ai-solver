# Clipboard AI Solver

브라우저 확장 없이 직접 실행하는 기본 macOS 메뉴 앱입니다. 구 버전 Canvas RAG Solver는 보관용이며 더 이상 기본 빌드·실행 경로로 사용하지 않습니다.

## 실행과 사용

```bash
bash scripts/build.sh
open 'build/Clipboard AI Solver.app'
```

일반 설치·업데이트는 `bash scripts/install.sh`를 실행합니다. 앱을 정상 종료한 뒤 `/Applications/Clipboard AI Solver.app`에 설치하고 그 위치에서 실행합니다. 키·자료·설정은 유지됩니다. 앱 아이콘 원본과 제작 프롬프트는 `standalone/Resources/AppIcon.png`, `AppIcon.prompt.txt`에 보관합니다.

1. 메뉴 바 **— → 설정 → AI 연결**에서 OpenAI · GPT 또는 Anthropic · Claude를 선택하세요. 해당 공급자의 API 키를 입력하고 **모델 불러오기 → 모델 선택 → 저장**을 누르세요. 새 앱의 키·설정·자료 목록은 기존 앱과 별개입니다. 기본 모드는 자료 없이 쓰는 **일반 AI**입니다.
2. **사용 시작**을 누르세요. 실행할 때마다 중지 상태로 시작합니다.
3. 문제 하나와 모든 보기가 보이도록 화면을 준비한 뒤 **Control–Shift–Command–3**으로 전체 화면을 클립보드에 복사하세요. 영역만 복사하려면 **Control–Shift–Command–4**도 사용할 수 있습니다. 저장 파일만 만드는 Shift–Command–3은 감지하지 않습니다. [Apple 캡처 안내](https://support.apple.com/ko-kr/guide/mac-help/mh26782/mac)
4. 메뉴의 **숫자**가 위에서부터 1로 세는 보기 위치입니다. **최근 결과**에서 인식된 문제·해설·출처·토큰 사용량을 확인하세요. `…` 처리 중, `?` 보류, `!` 오류입니다.
5. **사용 중지**하면 감시·풀이·LED 점멸을 취소합니다. 텍스트/파일 경로 복사는 무시하고, 새 이미지는 이전 작업을 교체합니다. 사용 시작 전에 복사한 이미지는 처리하지 않습니다.

감시 중에는 새로 복사한 **모든 이미지**가 처리 대상입니다. 전체 화면의 문제 외 내용도 선택한 AI 공급자로 전달되므로 개인정보를 치우고 캡처하세요. 이미지 내용은 디스크·로그에 저장하지 않습니다. 결과는 앱 메모리에만 남고 새 요청/중지 시 사라집니다. 이 앱은 화면을 직접 녹화하거나 브라우저에 접근하지 않습니다. macOS가 클립보드 접근 허용을 요청하면 새 앱에 허용해야 합니다.

## 공급자와 모델 선택

설정의 **AI 연결** 탭에서 공급자를 고르고 키를 입력한 뒤 **모델 불러오기**를 누르세요. 모델 ID를 직접 입력하는 필드는 없습니다. 인식과 풀이에는 선택한 동일 공급자·모델을 사용합니다. 키·모델 선택과 자료 목록은 공급자별로 보존합니다. 키를 바꾸면 새 키로 목록을 조회한 후 저장하세요. 불러온 목록은 실행 중에 유지하며 재시작 후에도 저장된 모델로 사용할 수 있습니다.

OpenAI는 실제 계정의 [모델 목록 API](https://developers.openai.com/api/reference/resources/models/methods/list)와 [공식 모델 문서](https://developers.openai.com/api/docs/models/all)를 대조해 이미지 입력·구조화 출력·Responses를 지원하는 모델 ID와 명시된 기본 스냅샷만 표시합니다. 과거 스냅샷 전체에 최신 모델의 기능을 적용하지 않습니다. Anthropic은 [모델 목록 API](https://platform.claude.com/docs/en/api/models/list)의 `capabilities.image_input`과 `capabilities.structured_outputs`를 확인하고 모든 페이지를 조회합니다. 고정된 모델 ID 목록은 사용하지 않습니다.

지원 정보를 확인하지 못한 모델은 제외합니다. 일부 공식 문서 조회가 실패하면 확인된 모델만 표시하고 메시지를 남깁니다. 전체 조회가 실패하면 저장된 선택을 유지합니다. 목록 조회는 추론 요청을 하지 않지만 모델 사용 권한·잔액·자료 문맥 제한은 실제 호출에서 추가 확인될 수 있습니다. ChatGPT/Claude 구독과 API 과금은 별개입니다.

## 풀이 모드

| 모드 | 동작 |
|---|---|
| 일반 AI | 등록 자료를 보내지 않고 모델 지식과 이미지로 판단 |
| 첨부자료 우선 AI | 자료 관리에서 체크한 원본 파일을 첨부. 근거가 부족하면 모델 지식으로 보완 |
| RAG · 자료 근거만 | 준비된 자료를 검색하고 실제 검색 구절과 일치하는 인용이 있을 때만 답변 |

자료 관리에서 PDF/TXT/MD를 추가할 수 있으며 **공급자별 목록이 분리**됩니다. 기존 OpenAI 키·모델·자료는 유지합니다. 공급자 간 자료를 자동으로 이동하거나 전송하지 않습니다.

- OpenAI: 서버에 업로드하고 RAG는 Vector Store 검색을 사용합니다. 제거하면 원격 파일도 삭제됩니다. 원본 첨부는 파일당 50 MB 미만·합계 50 MB 이하입니다.
- Claude: `~/Library/Application Support/Clipboard AI Solver/ClaudeMaterials`에 별도 사본을 보관합니다. 제거하면 이 사본을 삭제하며 사용자가 선택했던 원본은 유지합니다. 원본 첨부는 선택 파일 합계 12 MB 이하로, PDF는 문서 블록, UTF-8 TXT/MD는 텍스트 문서 블록으로 전송합니다. PDF 페이지·문맥 제한은 선택 모델에 따릅니다.
- Claude RAG: PDFKit으로 추출한 텍스트 또는 TXT/MD를 로컬 구절로 나누어 어휘 겹침으로 검색하고 상위 5개 구절을 보냅니다. 임베딩 의미 검색과 OCR은 수행하지 않아 동의어·스캔·그림 검색에 한계가 있습니다. 텍스트가 없거나 2 MB를 넘으면 **원본 첨부 전용**으로 표시합니다.

첨부자료 모드의 인용은 파일 ID만 검증하므로 원문 확인이 필요합니다. RAG 인용은 실제 검색 구절과 대조합니다.

## Caps Lock LED

설정에서 **정답 번호만큼 Caps Lock LED 깜빡이기**를 켜거나 **LED 3회 테스트**를 누르세요. MacBook 내장 키보드용이며 Caps Lock 입력 상태는 바꾸지 않습니다. 입력 모니터링 권한을 요청하면 **Clipboard AI Solver**에 허용한 다음 새 앱을 종료·재실행하세요. 권한 오류는 풀이 번호와 별도로 표시됩니다. 원복 실패 후에는 LED 알림을 중단하므로 표시등 상태를 확인하고 앱을 재실행하세요.

0.2.1부터 빌드용 고정 로컬 인증서로 서명해 업데이트 간 코드 식별 조건을 유지합니다. 기존 임시 서명에서 전환하는 최초 한 번은 입력 모니터링 항목을 제거하고 다시 추가해야 할 수 있습니다. 이후 빌드에서는 같은 서명 폴더·bundle ID·설치 위치를 유지하세요. 실제 권한 유지 여부는 OS에서도 확인해야 합니다. [서명·백업 안내](../docs/SIGNING.ko.md). 구 버전의 키·자료는 삭제하거나 자동 이전하지 않습니다.

## 비용과 한계

- 이미지 정규화 → **문항 인식 API 1회 → 풀이 API 1회**. OpenAI RAG는 중간 검색 요청이 추가되고, Claude RAG는 Mac에서 검색합니다. 이미지/첨부 입력은 호출별 과금이며 실패 시 자동 재시도하지 않습니다. OpenAI Responses 요청은 `store: false`이며 Claude는 Messages의 `output_config.format`을 사용합니다. [OpenAI 이미지 입력 문서](https://developers.openai.com/api/docs/guides/images-vision)
- 전체 처리 제한 45초. RAG에 준비된 자료가 없으면 AI 호출 전에 보류합니다.
- 입력은 이미지 한 개, 64 MiB 이하, 최대 40 MP/한 변 20,000 px. 메타데이터를 제거한 PNG가 10 MiB를 넘으면 작게 다시 캡처하세요. Claude는 추가로 한 변 8,000 px·PNG 7.5 MB 이하, 전체 JSON 요청 32 MB 이하로 검사합니다.
- 보기 2~10개의 단일 정답 객관식만 지원합니다. 여러 문제·잘림·판독 불가·복수 정답을 AI가 감지하면 보류합니다. **AI가 잘못 읽거나 잘못 답할 수 있으므로 최근 결과의 인식 내용을 대조하세요.** 여러 디스플레이의 전체 화면 복사는 여러 이미지가 될 수 있으므로 영역 캡처를 사용하세요.
- 실행은 로컬 앱에서 하지만 AI 추론은 선택한 공급자 서버에서 이루어집니다. 자료 저장 위치는 위의 공급자별 설명을 따릅니다. 자동 답안 입력/제출은 없습니다.

## 확인 상태

이전 OpenAI 버전의 일반 AI·첨부자료 우선 AI는 사용자가 실제 동작을 확인했습니다. 이번 공급자 선택·Claude 연결은 모의 HTTP/합성 이미지/임시 자료와 격리 UI로 검증하며 실제 계정·유료 추론은 별도 확인이 필요합니다. 2026-10-20에는 고정 서명 0.2.1 → 0.2.2 실제 업데이트 후, 사용자가 입력 모니터링 재등록 없이 내장 LED 3회 점멸을 확인했습니다.

## 개발 검증

```bash
bash scripts/check.sh
python3 standalone/smoke.py
```

검사는 별도 이름의 pasteboard와 합성 이미지, 모의 HTTP 응답을 사용합니다. 실제 클립보드·Keychain·유료 API는 사용하지 않습니다. macOS pasteboard/GUI 서버에 접근 가능한 로컬 터미널에서 실행하세요. smoke 검사는 임시 bundle ID로 앱을 복사하고 실행·종료한 후 임시 설정과 앱을 지웁니다.

공유 소스: `Models.swift`, `OpenAIClient.swift`, `JobController.swift`, `CapsLockLED.swift`. 기본 scripts/build.sh와 scripts/install.sh는 현재 앱을 빌드·실행합니다. 구 타깃 관련 스크립트는 scripts/legacy-*.sh에 보관합니다. 구 문서는 docs/legacy-extension.md를 참고하세요. 키는 새 서비스 `com.hjkim24.clipboard-ai-solver`의 Keychain 항목에, 설정은 같은 bundle ID의 UserDefaults에 저장됩니다.
