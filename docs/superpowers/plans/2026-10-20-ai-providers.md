# OpenAI / Anthropic selection

Goal: 공급자와 이미지·구조화 출력 지원 모델을 설정의 목록에서 선택한다. 기존 OpenAI 키·모델·자료와 LED/클립보드 동작을 유지한다.

Design: OpenAI GET /v1/models와 공식 모델 Markdown의 image_input, structured_outputs, Responses 지원을 교차 확인한다. Anthropic GET /v1/models는 image_input/structured_outputs capability를 필터링하고 모든 페이지를 읽는다. 키는 공급자별 Keychain 항목에 저장한다. 모델 목록은 설정에서 조회하며 실패 시 저장된 선택은 유지한다. 공급자 전환 시 초안·응답이 다른 공급자에 섞이지 않도록 취소/식별한다. 이미지 인식·풀이의 스키마와 결과 검증은 공유하고 API 요청만 각 규격에 맞춘다.

Materials: 기존 OpenAI 원격 자료는 그대로 보존한다. Claude 자료는 별도 로컬 사본으로 저장하고 첨부 시 PDF/텍스트를 Claude로 보낸다. Claude RAG는 로컬 PDF/TXT/MD의 텍스트 구절을 검색한다. 텍스트 없는 스캔 PDF는 원본 첨부로 사용할 수 있지만 로컬 RAG 인덱스에서는 제외한다. 자동 공급자 간 파일 이동은 하지 않는다.

Scope: shared Models/OpenAIClient, standalone Claude client/materials/model catalog/Keychain/settings, compile scripts/tests/docs, 버전 0.2.0 및 설치·DMG. 기존 extension/Canvas 전용 UI와 설치된 구 앱 번들은 보존한다. 공유 소스 변경은 기본 OpenAI 경로와 기존 검사로 호환성을 확인한다. 현재 .git은 읽기 전용이고 기존 작업물이 미커밋 상태이므로 브랜치 전환·정리는 하지 않는다.

- [x] Configuration migration/provider isolation 및 실패하는 테스트
- [x] 공통 구조화 요청 + Claude 이미지·일반·첨부·RAG 구현, API/로컬 자료 검사
- [x] 실제 모델 조회·기능 필터·페이지 처리·오류 검사
- [x] 설정의 공급자/모델 목록·키 저장·초안/비동기 취소 검사
- [x] 전체 검사와 UI 실행/렌더링, 독립 리뷰
- [x] 현재 Mac 설치·실행 및 새 DMG 검증

Review focus: 공급자 변경 중 늦게 도착한 모델 목록, 잘못된 키/빈 목록/부분 문서 실패, 이전 OpenAI 설정 보존, Claude 이미지 거절·잘린 JSON/출처 검증·제한 크기, 로컬 파일 삭제/경로 검증과 스캔 PDF의 빈 텍스트. 실제 개인 키·클립보드·유료 추론은 검증에 사용하지 않는다.

Official references checked 2026-10-20: OpenAI Models API / model Markdown / Structured Outputs; Anthropic Models API / Messages / Vision / Structured Outputs. OpenAI 모델 문서는 인증 헤더 없이 조회한다. 문서 형식이 바뀌면 확인할 수 없는 모델은 제외하며 오류를 표시한다.

Review resolution: 과거 스냅샷에 최신 기능을 일괄 적용하는 문제를 혼합 스냅샷 회귀 검사로 재현 후 수정했다. 공식 페이지의 Model ID와 명시된 Default snapshot에만 해당 페이지의 기능을 적용하며 나머지 과거 스냅샷은 제외한다. 독립 리뷰에서 해당 수정 확인 및 승인.


Final verification (2026-10-20): scripts/check.sh 통과 — clipboard 55, editing 2, catalog 7, Claude 27, native UI 21, shared 63 및 configuration migration/isolation 검사. 설치 교체·복원 검사 4개 통과. 공개 OpenAI Markdown을 실제 네트워크로 불러와 production parser로 판별(계정 목록은 fixture, 실제 키 없음). 라이트/다크 UI 렌더링과 임시 앱 직접 실행·정상 종료 통과. 독립 리뷰의 Important 지적 수정 후 해당 수정 승인.

Installed /Applications/Clipboard AI Solver.app 0.2.0 (3), 단일 실행 프로세스 확인. 새 dist/Clipboard-AI-Solver-0.2.0-arm64.dmg 및 SHA-256 검증. 읽기 전용 DMG와 설치 앱이 빌드의 네 파일과 동일하고 서명·아이콘 일치, 개인 파일 없음. 기존 DMG 보존. ClipboardInput/LED/JobController/메뉴·네이티브 UI helper와 구 앱 전용 소스의 원본 일치 확인. 실제 계정 모델 조회·유료 추론·실물 LED는 별도 검증 필요.
