# Caps Lock LED Implementation Plan

> Native execution: same session implementation, one fresh final reviewer.

**Goal:** MacBook 내장 Caps Lock LED를 검증된 정답 번호만큼 점멸한다.
**Architecture:** 기존 JobController 상태 알림을 CapsLockNotifier에 연결한다. CapsLockLED 파일이 IOKit 출력, 취소/원복 순서, 중복 방지를 담당한다.
**Tech Stack:** Swift5/macOS13, AppKit, IOKit, CoreGraphics; 추가 의존성 없음.
**Spec:** ../specs/2026-10-20-caps-lock-led-design.md

## Global Constraints
- 기존 checkout·키·자료·설정을 보존한다. .git 변경 없이 구현한다.
- 키 이벤트 생성, 잠금 상태 변경, 입력 소스 변경, 키 입력 수집을 하지 않는다.
- 권한 요청은 사용자 설정/테스트 동작에서만 한다. 실제 LED 검증은 모의 검사와 구분한다.

## Review Focus
- 취소/이전 작업 원복이 새 점멸을 덮어쓰는 경합.
- 종료 전에 복원이 완료되는지.
- 권한·장치·복원 오류를 숨기거나 풀이 답을 지우는지.
- 이미 켜진 LED와 사용자가 바꾼 잠금 상태의 복원.
- 장치 동기 I/O가 UI나 native 입력을 막는지.

## Task 1: LED 드라이버와 알림
- [x] LED 설정 저장 검사 실패를 확인하고 Configuration을 확장한다.
- [x] Tests/LEDCheck.swift를 먼저 작성하고 실패를 확인한다.
- [x] Sources/AISolver/CapsLockLED.swift 구현: CapsLockLight, blinkCapsLockLED, InternalCapsLockLight, CapsLockNotifier.
- [x] 정확한 횟수·원복·취소·오류·중복 방지·교체 순서를 가짜 출력 장치로 검사한다.

## Task 2: 앱 연결과 검증
- [x] App.swift의 상태 알림·설정·테스트 버튼·정상 종료에 연결한다. JobController 자체는 변경하지 않는다.
- [x] scripts/check.sh/build.sh에 IOKit와 LED 검사를 연결한다.
- [x] 전체 self-check, 앱 빌드, native 프로세스 smoke 검사. 새 리뷰어가 한 번 검토한다.
- [x] README와 구현 기록에 권한 경로·미검증 하드웨어 범위를 명시한다.
