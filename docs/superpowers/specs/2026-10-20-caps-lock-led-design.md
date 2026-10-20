# MacBook 내장 Caps Lock LED 알림

- 검증된 answered 결과의 보기 순서(1~10)만큼 LED를 한 번 점멸한다. 모든 풀이 모드에 적용하며 메뉴 숫자를 유지한다.
- 설정의 ‘정답 번호만큼 Caps Lock LED 깜빡이기’는 기본 꺼짐이며 이전 설정을 보존한다. ‘LED 3회 테스트’는 AI/API 없이 실행한다.
- 내장 키보드의 HID LED Caps Lock 출력만 변경한다. 키 이벤트, 대문자 잠금 상태, 한영 입력 소스는 변경하지 않는다. 외장·가상 키보드는 대상으로 하지 않는다.
- 원래 LED가 꺼져 있으면 켜졌다 꺼지는 것을, 켜져 있으면 꺼졌다 켜지는 것을 한 번으로 센다. 반전 250ms, 원래 상태 350ms를 사용한다.
- 새 문항·취소·중지·설정/사용 자료 변경은 점멸을 취소한다. 중복 상태 알림은 재점멸하지 않는다. 새 점멸은 이전 점멸의 원복을 기다린다.
- 완료·오류·취소·정상 종료 시 원래 LED 상태를 복원한다. 사용자가 그 사이 Caps Lock 상태를 바꿨다면 현재 잠금 상태를 따른다. 강제 종료·전원 차단의 복원은 보장할 수 없다.
- 권한과 장치 오류는 LED 상태 안내에 표시하며 풀이 성공을 오류로 바꾸지 않는다. macOS 권한 요청은 사용자가 설정에서 LED를 켜거나 테스트할 때만 한다.
- IOHIDDeviceSetValue는 동기 API이므로 장치 I/O는 메인 UI 실행 경로에서 분리한다.

2026-10-20 장치 사전 확인: Apple Internal Keyboard / Trackpad, Built-In=true, GenericDesktop/Keyboard. IOHIDCheckAccess ListenEvent=unknown(2), 비독점 IOHIDDeviceOpen=NotPermitted(-536870174). 읽기 확인만 했으며 실제 점멸 미검증.

근거: [Apple IOHIDDeviceSetValue](https://developer.apple.com/documentation/iokit/1588651-iohiddevicesetvalue), 로컬 SDK IOHIDDevice.h의 Open/Close/SetValue 계약. 권한을 우회하지 않는다.
