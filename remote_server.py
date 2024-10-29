import asyncio
import websockets
import json
import random
import string
import pyautogui
from aiohttp import web
import os
import qrcode
import socket
import psutil
import platform
import win32gui
import win32process
import time
import sys
import ctypes
import subprocess

def is_admin():
    """관리자 권한 확인"""
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

def run_as_admin():
    """관리자 권한으로 재실행"""
    if is_admin():
        return True
    else:
        try:
            script = os.path.abspath(sys.argv[0])
            params = ' '.join([script] + sys.argv[1:])
            
            if sys.executable.endswith('pythonw.exe'):
                # GUI 모드
                ctypes.windll.shell32.ShellExecuteW(
                    None, 
                    "runas", 
                    sys.executable, 
                    params, 
                    None, 
                    1
                )
            else:
                # 콘솔 모드
                ctypes.windll.shell32.ShellExecuteW(
                    None,
                    "runas",
                    sys.executable,
                    params,
                    None,
                    1
                )
            return True
        except Exception as e:
            print(f"관리자 권한 실행 실패: {e}")
            return False

def setup_firewall():
    """방화벽 규칙 설정"""
    if not is_admin():
        print("[!] 방화벽 설정을 위해 관리자 권한이 필요합니다.")
        return False

    try:
        # TCP 규칙 추가
        powershell_command = """
        $ports = @(8080, 8081)
        $ruleName = "Remote Control Server"

        foreach ($port in $ports) {
            # 기존 규칙 제거
            Remove-NetFirewallRule -DisplayName "$ruleName (TCP $port)" -ErrorAction SilentlyContinue
            
            # 새 규칙 추가
            New-NetFirewallRule -DisplayName "$ruleName (TCP $port)" `
                -Direction Inbound `
                -LocalPort $port `
                -Protocol TCP `
                -Action Allow
        }
        """
        
        subprocess.run(["powershell", "-Command", powershell_command], check=True)
        print("[+] 방화벽 규칙이 성공적으로 추가되었습니다.")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"[!] 방화벽 규칙 추가 중 오류 발생: {e}")
        return False
    except Exception as e:
        print(f"[!] 예상치 못한 오류 발생: {e}")
        return False

class RemoteControlServer:
    def __init__(self, websocket_port=8080, http_port=8081):
        self.websocket_port = websocket_port
        self.http_port = http_port
        self.connection_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
        self.connected_clients = set()
        self.web_clients = set()
        
        # 마우스/키보드 설정
        pyautogui.FAILSAFE = False
        self.screen_width, self.screen_height = pyautogui.size()
        
        # 마우스 이동 관련 설정
        self.mouse_speed_multiplier = 2.0
        
        self.os_type = platform.system()
        self.presentation_mode = False
        
        self._generate_qr_code()
        self.is_client_connected = False
        self.last_activity_time = None
        self.inactivity_timeout = 600

    def _generate_qr_code(self):
        """QR 코드 생성"""
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(('8.8.8.8', 80))
            local_ip = s.getsockname()[0]
        except Exception:
            local_ip = '127.0.0.1'
        finally:
            s.close()

        qr_data = {
            'code': self.connection_code,
            'port': self.websocket_port,
            'ip': local_ip
        }
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(json.dumps(qr_data))
        qr.make(fit=True)
        qr_image = qr.make_image(fill_color="black", back_color="white")
        qr_image.save('connection_qr.png')
        
        print(f"[*] Server IP: {local_ip}")

    def create_html(self):
        """HTML 페이지 생성"""
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Remote Control Connection</title>
            <meta charset="UTF-8">
            <style>
                body {{
                    font-family: Arial, sans-serif;
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 20px;
                    text-align: center;
                }}
                .container {{
                    background-color: #f5f5f5;
                    border-radius: 10px;
                    padding: 20px;
                    margin-top: 20px;
                }}
                .code {{
                    font-size: 24px;
                    font-weight: bold;
                    color: #333;
                    margin: 20px 0;
                }}
                img {{
                    max-width: 300px;
                    margin: 20px 0;
                    border: 1px solid #ddd;
                    border-radius: 5px;
                }}
                .connected-message {{
                    display: none;
                    color: green;
                    font-size: 18px;
                    margin: 20px 0;
                }}
            </style>
            <script>
                let ws = null;
                let isConnected = false;
                
                function connectWebSocket() {{
                    ws = new WebSocket('ws://' + window.location.hostname + ':{self.websocket_port}');
                    
                    ws.onopen = function() {{
                        console.log('WebSocket 연결됨');
                        ws.send(JSON.stringify({{
                            'client_type': 'web'
                        }}));
                    }};
                    
                    ws.onclose = function() {{
                        console.log('WebSocket 연결 끊김');
                        if (isConnected) {{
                            document.querySelector('.container').style.display = 'block';
                            document.querySelector('.connected-message').style.display = 'none';
                            isConnected = false;
                        }}
                        setTimeout(connectWebSocket, 3000);
                    }};
                    
                    ws.onmessage = function(event) {{
                        const data = JSON.parse(event.data);
                        if (data.type === 'client_connected' && !isConnected) {{
                            document.querySelector('.container').style.display = 'none';
                            document.querySelector('.connected-message').style.display = 'block';
                            isConnected = true;
                        }}
                        if (data.type === 'client_disconnected') {{
                            document.querySelector('.container').style.display = 'block';
                            document.querySelector('.connected-message').style.display = 'none';
                            isConnected = false;
                        }}
                    }};
                    
                    ws.onerror = function(error) {{
                        console.error('WebSocket 에러:', error);
                    }};
                }}
                
                window.onload = connectWebSocket;
            </script>
        </head>
        <body>
            <h1>Remote Control Server</h1>
            <div class="container">
                <h2>연결 정보</h2>
                <p class="code">Connection Code: {self.connection_code}</p>
                <p>WebSocket Port: {self.websocket_port}</p>
                <h3>QR 코드로 연결하기</h3>
                <img src="connection_qr.png" alt="Connection QR Code">
            </div>
            <div class="connected-message">
                <h2>✅ 기기가 연결되었습니다</h2>
                <p>리모컨 앱에서 제어가 가능합니다.</p>
            </div>
        </body>
        </html>
        """
        with open('connection.html', 'w', encoding='utf-8') as f:
            f.write(html_content)

    def get_active_window_process(self):
        """현재 실행 중인 프로세스와 윈도우 상태 확인"""
        try:
            presentation_processes = {
                'Windows': ['powerpnt.exe', 'acrord32.exe', 'msedge.exe', 'chrome.exe'],
                'Darwin': ['keynote', 'preview', 'chrome', 'safari'],
                'Linux': ['libreoffice', 'evince', 'chrome', 'firefox']
            }
            
            target_processes = presentation_processes.get(self.os_type, [])
            
            for proc in psutil.process_iter(['name', 'pid']):
                proc_name = proc.info['name'].lower()
                if any(p in proc_name for p in target_processes):
                    if 'powerpnt' in proc_name:
                        try:
                            window_title = win32gui.GetWindowText(win32gui.GetForegroundWindow()).lower()
                            is_slideshow = 'slide show' in window_title or '슬라이드 쇼' in window_title
                            return {
                                'name': proc_name,
                                'is_slideshow': is_slideshow
                            }
                        except:
                            return {'name': proc_name, 'is_slideshow': False}
                    return {'name': proc_name}
            return None
        except Exception as e:
            print(f"Error getting processes: {e}")
            return None

    async def handle_presentation_toggle(self, data):
        """프레젠테이션 모드 전환 처리"""
        try:
            hwnd = win32gui.GetForegroundWindow()
            window_title = win32gui.GetWindowText(hwnd).lower()
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
            process_name = psutil.Process(pid).name().lower()
            
            print(f"Active Window: {window_title}")
            print(f"Process: {process_name}")

            if 'powerpnt' in process_name:
                if 'slide show' in window_title or '슬라이드 쇼' in window_title:
                    print("PowerPoint: Slideshow mode -> ESC")
                    pyautogui.press('esc')
                else:
                    print("PowerPoint: Normal mode -> F5")
                    pyautogui.press('f5')
            
            elif any(name in process_name for name in ['acrord32', 'msedge', 'chrome']):
                if 'full screen' in window_title or '전체 화면' in window_title:
                    print("PDF: Fullscreen mode -> ESC")
                    pyautogui.press('esc')
                else:
                    print("PDF: Normal mode -> Ctrl+L")
                    pyautogui.hotkey('ctrl', 'l')
            
            else:
                print(f"Unknown program: {process_name}")
                pyautogui.press(data.get('key', 'f5'))

        except Exception as e:
            print(f"Error in handle_presentation_toggle: {e}")
            pyautogui.press(data.get('key', 'f5'))

    async def handle_websocket(self, websocket):
        """WebSocket 연결 처리"""
        try:
            initial_message = await websocket.recv()
            print(f"Initial message received: {initial_message}")
            data = json.loads(initial_message)
            
            client_type = data.get('client_type', 'unknown')
            auth_code = data.get('code', '')

            if auth_code != self.connection_code:
                await websocket.send(json.dumps({
                    'type': 'auth_response',
                    'status': 'failed',
                    'message': 'Invalid connection code'
                }))
                return

            if client_type == 'web':
                self.web_clients.add(websocket)
                await websocket.send(json.dumps({
                    'type': 'auth_response',
                    'status': 'success'
                }))
                try:
                    while True:
                        await websocket.recv()
                except:
                    self.web_clients.remove(websocket)
                return

            if self.is_client_connected:
                await websocket.send(json.dumps({
                    'type': 'auth_response',
                    'status': 'failed',
                    'message': 'Another client is already connected'
                }))
                return

            await websocket.send(json.dumps({
                'type': 'auth_response',
                'status': 'success'
            }))
            
            self.is_client_connected = True
            self.last_activity_time = time.time()
            client_id = ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))
            
            print("\n" + "="*50)
            print(f"[+] New control client connected! (ID: {client_id})")
            print(f"[*] Client IP: {websocket.remote_address[0]}")
            print(f"[*] Connection Code: {self.connection_code}")
            
            self.connected_clients.add(websocket)
            
            for web_client in self.web_clients:
                try:
                    await web_client.send(json.dumps({
                        'type': 'client_connected'
                    }))
                except:
                    pass

            while True:
                if time.time() - self.last_activity_time > self.inactivity_timeout:
                    print("Inactive timeout reached, disconnecting client")
                    break

                message = await websocket.recv()
                self.last_activity_time = time.time()
                try:
                    data = json.loads(message)
                    msg_type = data.get('type', 'unknown')
                    
                    print(f"\n[>] Received message from client {client_id}:")
                    print(f"    Type: {msg_type}")
                    
                    if msg_type == 'mouse_move_relative':
                        current_x, current_y = pyautogui.position()
                        dx = float(data.get('dx', 0))
                        dy = float(data.get('dy', 0))
                        
                        dx *= self.mouse_speed_multiplier
                        dy *= self.mouse_speed_multiplier
                        
                        new_x = int(current_x + dx)
                        new_y = int(current_y + dy)
                        
                        new_x = max(0, min(new_x, self.screen_width - 1))
                        new_y = max(0, min(new_y, self.screen_height - 1))
                        
                        print(f"    Relative Move: dx={dx}, dy={dy}")
                        print(f"    New Position: ({new_x}, {new_y})")
                        
                        pyautogui.moveTo(new_x, new_y, duration=0)
                        
                    elif msg_type == 'mouse_move':
                        x = int(float(data['x']) * self.screen_width)
                        y = int(float(data['y']) * self.screen_height)
                        print(f"    Position: ({x}, {y})")
                        
                        pyautogui.moveTo(x, y, duration=0)
                        
                        if data.get('is_laser'):
                            print("    Laser mode: On")
                        if data.get('is_gyro'):
                            print("    Mode: Gyroscope")
                    
                    elif msg_type == 'mouse_click':
                        click_type = data.get('click_type', 'left')
                        print(f"    Click type: {click_type}")
                        if click_type == 'double':
                            pyautogui.doubleClick()
                        elif click_type == 'right':
                            pyautogui.rightClick()
                        else:
                            pyautogui.click()
                    
                    elif msg_type == 'mouse_drag':
                        action = data.get('action', '')
                        print(f"    Drag action: {action}")
                        if action == 'start':
                            pyautogui.mouseDown()
                        elif action == 'end':
                            pyautogui.mouseUp()
                    
                    elif msg_type == 'keyboard':
                        key = data.get('key', '')
                        print(f"    Key: {key}")
                        try:
                            await asyncio.sleep(0.1)
                            if key in ['f5', 'esc']:
                                await self.handle_presentation_toggle(data)
                            else:
                                pyautogui.press(key)
                            print(f"    Pressed key: {key}")
                        except Exception as e:
                            print(f"    Error pressing key: {e}")
                    
                    elif msg_type == 'disconnect':
                        print(f"    Client requested disconnect")
                        break
                    
                    print(f"    Status: Success")
                    
                except json.JSONDecodeError:
                    print(f"[!] Invalid JSON message from client {client_id}")
                except Exception as e:
                    print(f"[!] Error processing message from client {client_id}: {e}")

        finally:
            if websocket in self.connected_clients:
                self.is_client_connected = False
                self.connected_clients.remove(websocket)
                for web_client in self.web_clients:
                    try:
                        await web_client.send(json.dumps({
                            'type': 'client_disconnected'
                        }))
                    except:
                        pass
            print("\n" + "="*50)
            print(f"[-] Client {client_id} disconnected")
            print(f"[*] Remaining connected clients: {len(self.connected_clients)}")
            print("="*50)

    async def start(self):
        """서버 시작"""
        self.create_html()
        
        app = web.Application()
        app.router.add_get('/', lambda r: web.FileResponse('connection.html'))
        app.router.add_get('/connection_qr.png', lambda r: web.FileResponse('connection_qr.png'))

        # 브라우저 자동 실행
        import webbrowser
        webbrowser.open(f'http://localhost:{self.http_port}')
        
        print("\n" + "="*50)
        print("=== Remote Control Server ===")
        print(f"[*] Starting server...")
        
        async with websockets.serve(self.handle_websocket, '0.0.0.0', self.websocket_port):
            runner = web.AppRunner(app)
            await runner.setup()
            site = web.TCPSite(runner, '0.0.0.0', self.http_port)
            await site.start()
            
            print(f"[+] Server is running")
            print(f"[*] Connection Code: {self.connection_code}")
            print(f"[*] WebSocket Port: {self.websocket_port}")
            print(f"[*] HTTP Port: {self.http_port}")
            print(f"[*] QR Code generated: connection_qr.png")
            print(f"[*] Web interface: http://localhost:{self.http_port}")
            print("\n[*] Waiting for connections...")
            print("="*50)
            
            await asyncio.Future()

def cleanup_firewall():
    """방화벽 규칙 제거"""
    if is_admin():
        try:
            powershell_command = """
            $ruleName = "Remote Control Server"
            Remove-NetFirewallRule -DisplayName "$ruleName (TCP 8080)" -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "$ruleName (TCP 8081)" -ErrorAction SilentlyContinue
            """
            subprocess.run(["powershell", "-Command", powershell_command], check=True)
            print("[+] 방화벽 규칙이 제거되었습니다.")
        except Exception as e:
            print(f"[!] 방화벽 규칙 제거 중 오류 발생: {e}")

def main():
    if not is_admin():
        print("[!] 관리자 권한이 필요합니다. 관리자 권한으로 재시작합니다...")
        run_as_admin()
        sys.exit()

    if not setup_firewall():
        print("[!] 방화벽 설정에 실패했습니다.")
        input("계속하려면 아무 키나 누르세요...")
        sys.exit(1)

    server = RemoteControlServer()
    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        print("\n서버를 종료합니다...")
    except Exception as e:
        print(f"서버 실행 중 오류 발생: {e}")
        input("계속하려면 아무 키나 누르세요...")
    finally:
        cleanup_firewall()

if __name__ == '__main__':
    main()
