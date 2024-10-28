import win32gui
import psutil

def get_active_program():
    """현재 선택된 프로그램 정보 반환"""
    try:
        # 현재 활성화된 윈도우의 핸들 가져오기
        hwnd = win32gui.GetForegroundWindow()
        # 윈도우 제목 가져오기
        window_title = win32gui.GetWindowText(hwnd).lower()
        
        # 프로세스 ID 가져오기
        _, pid = win32process.GetWindowThreadProcessId(hwnd)
        # 프로세스 이름 가져오기
        process_name = psutil.Process(pid).name().lower()
        
        print(f"Active Window: {window_title}")
        print(f"Process Name: {process_name}")
        
        return {
            'title': window_title,
            'process': process_name
        }
    except Exception as e:
        print(f"Error: {e}")
        return None

# 테스트
active = get_active_program()
if active:
    print(f"\n현재 선택된 프로그램:")
    print(f"- 프로세스: {active['process']}")
    print(f"- 창 제목: {active['title']}")