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

class RemoteControlServer:
    def __init__(self, websocket_port=8080, http_port=8081):
        self.websocket_port = websocket_port
        self.http_port = http_port
        self.connection_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
        self.connected_clients = set()
        
        # 마우스/키보드 설정
        pyautogui.FAILSAFE = False
        self.screen_width, self.screen_height = pyautogui.size()
        
        # 마우스 이동 관련 설정
        self.mouse_speed_multiplier = 2.0  # 기본 속도
        
        self.os_type = platform.system()  # 'Windows', 'Darwin' (macOS), 'Linux'
        self.presentation_mode = False
        
        self._generate_qr_code()

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
            </style>
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
        </body>
        </html>
        """
        with open('connection.html', 'w', encoding='utf-8') as f:
            f.write(html_content)

    def get_active_window_process(self):
        """현재 실행 중인 프로세스 확인"""
        try:
            presentation_processes = {
                'Windows': ['powerpnt.exe', 'acrord32.exe', 'msedge.exe', 'chrome.exe'],
                'Darwin': ['keynote', 'preview', 'chrome', 'safari'],  # macOS
                'Linux': ['libreoffice', 'evince', 'chrome', 'firefox']
            }
            
            target_processes = presentation_processes.get(self.os_type, [])
            
            for proc in psutil.process_iter(['name']):
                if any(p in proc.info['name'].lower() for p in target_processes):
                    return {'name': proc.info['name'].lower()}
            return None
        except Exception as e:
            print(f"Error getting processes: {e}")
            return None

    async def handle_presentation_toggle(self, data):
        """프레젠테이션 모드 전환 처리"""
        proc_info = self.get_active_window_process()
        print(f"Current process: {proc_info}")  # 디버깅용 로그 추가
        
        key = data.get('key')
        print(f"Received key: {key}")  # 디버깅용 로그 추가

        if not proc_info:
            # 프레젠테이션 프로그램이 실행중이지 않을 때는 기본 키 전송
            pyautogui.press(key)
            return

        if self.os_type == 'Windows':
            if 'powerpnt' in proc_info['name']:
                print("PowerPoint detected, sending F5/ESC")
                pyautogui.press(key)
            elif any(viewer in proc_info['name'] for viewer in ['acrord32', 'msedge', 'chrome']):
                print("PDF viewer detected, sending Ctrl+L/ESC")
                if key == 'f5':
                    pyautogui.hotkey('ctrl', 'l')
                else:
                    pyautogui.press('esc')
        
        elif self.os_type == 'Darwin':  # macOS
            if 'keynote' in proc_info['name']:
                pyautogui.hotkey('command', 'shift', 'p' if data.get('key') == 'f5' else 'esc')
            else:
                pyautogui.hotkey('command', 'shift', 'f' if data.get('key') == 'f5' else 'esc')
        
        else:  # Linux
            if 'libreoffice' in proc_info['name']:
                pyautogui.press('f5' if data.get('key') == 'f5' else 'esc')
            else:
                pyautogui.hotkey('ctrl', 'l' if data.get('key') == 'f5' else 'esc')

    async def handle_websocket(self, websocket):
        """WebSocket 연결 처리"""
        client_id = ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))
        
        print("\n" + "="*50)
        print(f"[+] New client connected! (ID: {client_id})")
        print(f"[*] Client IP: {websocket.remote_address[0]}")
        print(f"[*] Connection Code: {self.connection_code}")
        
        self.connected_clients.add(websocket)
        print(f"[*] Total connected clients: {len(self.connected_clients)}")
        print("="*50 + "\n")
        
        try:
            await websocket.send(json.dumps({
                'type': 'connection_status',
                'status': 'connected',
                'message': f'Connected successfully with ID: {client_id}'
            }))
            
            async for message in websocket:
                try:
                    data = json.loads(message)
                    msg_type = data.get('type', 'unknown')
                    
                    print(f"\n[>] Received message from client {client_id}:")
                    print(f"    Type: {msg_type}")
                    
                    if msg_type == 'mouse_move_relative':
                        # 상대적 마우스 이동 처리
                        current_x, current_y = pyautogui.position()
                        dx = float(data.get('dx', 0))
                        dy = float(data.get('dy', 0))
                        
                        # 이동 거리에 속도 승수 적용
                        dx *= self.mouse_speed_multiplier
                        dy *= self.mouse_speed_multiplier
                        
                        # 새 위치 계산
                        new_x = int(current_x + dx)
                        new_y = int(current_y + dy)
                        
                        # 화면 경계 확인
                        new_x = max(0, min(new_x, self.screen_width - 1))
                        new_y = max(0, min(new_y, self.screen_height - 1))
                        
                        print(f"    Relative Move: dx={dx}, dy={dy}")
                        print(f"    New Position: ({new_x}, {new_y})")
                        
                        pyautogui.moveTo(new_x, new_y, duration=0)
                        
                    elif msg_type == 'mouse_move':
                        # 절대 좌표 이동
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
                    
                    # 메시지 처리 성공 로그
                    print(f"    Status: Success")
                    
                except json.JSONDecodeError:
                    print(f"[!] Invalid JSON message from client {client_id}")
                except Exception as e:
                    print(f"[!] Error processing message from client {client_id}: {e}")

        except Exception as e:
            print(f"\n[!] Error in websocket handler for client {client_id}: {e}")
        finally:
            self.connected_clients.remove(websocket)
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

def main():
    server = RemoteControlServer()
    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        print("\n서버를 종료합니다...")
    except Exception as e:
        print(f"서버 실행 중 오류 발생: {e}")

if __name__ == '__main__':
    main()
