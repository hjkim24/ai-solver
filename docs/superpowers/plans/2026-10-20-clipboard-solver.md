# Clipboard AI Solver implementation plan

Goal: 기존 앱을 보존하며 클립보드 이미지 기반 독립 앱을 실행 가능한 상태로 제공한다.

Architecture: 기존 Models/OpenAIClient/JobController/CapsLockLED를 새 타깃에서 재사용. 새 입력 모니터와 이미지 문항 인식 파이프라인, 별도 AppDelegate/Main/Keychain/Menu/Info.plist를 standalone에 둔다.

Tech Stack: Swift 5, macOS 13+, AppKit, ImageIO, Security, IOKit, URLSession. 추가 의존성 없음.

Spec: ../specs/2026-10-20-clipboard-solver-design.md

Global constraints: 기존 소스·빌드·서명·설정·host 등록을 수정하지 않는다. 실제 키·클립보드·유료 API에 접근하지 않는다. .git 쓰기 제한과 기존 untracked 작업 때문에 브랜치/커밋 변경 없이 전용 checkout에서 작업한다.

Review focus: 활성화 이전 이미지/텍스트 노출 방지, 새 요청의 이전 결과 차단, 문항 구조/응답 경계 검증, 비용·시간 제한, 키/설정 분리, 기존 앱 보존, 종료 시 LED 원복.

- [x] 1. 별도 입력·이미지·모의 API 테스트를 먼저 작성하고 실패 확인.
- [x] 2. 클립보드 입력과 이미지 인식→기존 풀이 연결을 구현하고 테스트 통과.
- [x] 3. 새 앱 UI·키·설정·빌드·사용 문서를 구현.
- [x] 4. 자체 검사, 기존 회귀 검사, 임시 앱 실행/종료, 원본 해시 비교.
- [x] 5. 한 번의 독립 코드 리뷰와 필요한 수정, 최종 빌드 후 새 앱 실행.
