# Native macOS interface and primary app

Goal: 사용자 검증이 끝난 Clipboard AI Solver를 기본 앱으로 승격하고 UI만 정리한다.

Design: Apple HIG의 macOS Settings/Menus 관례. AppKit 기본 시스템 글꼴, semantic colors, native tabs/group boxes/buttons, 고정 하단 작업 버튼과 스크롤 가능한 본문. 설정은 일반/알림 탭, 자료는 정렬된 파일 행과 빈 상태, 최근 결과는 요약/본문/LED 안내로 구분한다. 메뉴 바는 숫자와 기존 상태 문자만 표시한다.

Constraints: bundle ID, Keychain service, UserDefaults 키와 기존 설정을 그대로 유지한다. AI·RAG·이미지·클립보드·LED·자료 처리 로직을 바꾸지 않는다. 기존 extension 타깃 코드는 복구용으로 보존하되 기본 build/install/check/README는 새 앱을 가리킨다. .git 메타데이터는 기존 제한에 따라 수정하지 않는다.

Scope: standalone App/Menu + native view helpers + synthetic UI checks; main scripts and documentation. 구 앱을 정상 종료하고 새 앱을 재시작한다. 구 앱 자료/키·브라우저 확장은 삭제하지 않는다.

Verification: 기존 기능 검사, 실제 AppKit 화면을 fake Keychain/fixture 설정으로 열어 layout/action/data retention 검증 및 light/dark 이미지 확인, 임시 번들 smoke. 엔진/식별자/비 UI 메서드 원본 해시 대조. 실제 키·일반 클립보드·유료 API는 테스트에서 사용하지 않는다.

- [x] UI 구성과 메뉴 정리
- [x] 기본 실행/빌드 경로 승격 및 문서 갱신
- [x] 기능 회귀/화면 렌더링/앱 실행·종료/원본 대조
- [x] 독립 리뷰 후 최종 앱 적용
