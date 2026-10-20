# Solver modes implementation

Goal: 자료 없는 일반 AI와 원본 첨부 우선 + 모델 지식 판단을 지원한다.
Architecture: 기존 Configuration / OpenAIClient / AppKit 창을 확장한다. 의존성을 추가하지 않는다.
Tech Stack: Swift, AppKit, Responses / Files API, URLProtocol self-check.
Spec: ../specs/2026-10-20-solver-modes-design.md

Global Constraints: 기존 키·자료 보존. 유료 호출 없이 모의 HTTP 검사. 현재 체크아웃의 미추적 파일을 보존하며 .git 변경 없이 작업한다.
Review Focus: 모드 간 자료 유출, 실패 시 무근거 답으로 전환, 이전 파일 설정 마이그레이션, 직접 첨부 용량·인용 신뢰도, 취소된 답 노출.

## Task 1: 모델과 API
- Tests/ModeCheck.swift 추가, scripts/check.sh 연결. 기존 코드에서 실패를 확인한다.
- Configuration의 모드와 파일 선택/크기, 결과 basis 검증, 모드별 API 흐름을 구현한다.
- 일반 AI 무자료 호출, 원본 첨부, 지식 fallback, 기존 RAG 보류, 용량 초과·API 오류·잘못된 출처를 검사한다.

## Task 2: 앱과 사용 문서
- 설정 모드 선택, 자료 체크박스, mode/basis 결과 표시를 연결한다.
- 작업 중 모드/첨부 변경 시 기존 JobController.invalidate를 재사용한다.
- README에 선택 경로·재연결·첨부 비용·미검증 항목을 기록한다.
- check.sh / build.sh / native-smoke.py로 검증한다. 전체 변경을 새 리뷰어가 한 번 검토한다.
