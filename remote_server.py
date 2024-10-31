import asyncio
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
import time
import base64
import numpy as np
import cv2
from mss import mss
from PIL import Image
import io

class UDPServerProtocol:
    def __init__(self, server):
        self.server = server
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport
        print("UDP Server started")

    def datagram_received(self, data, addr):
        try:
            message = json.loads(data.decode())
            self.handle_message(message, addr)
        except json.JSONDecodeError:
            print(f"Invalid JSON from {addr}")
        except Exception as e:
            print(f"Error processing message: {e}")

    def handle_message(self, message, addr):
        msg_type = message.get('type', 'unknown')
        
        # 클라이언트 인증 검사
        if self.server.client_address is None:
            if msg_type != 'auth' and 'code' not in message:
                print(f"Unauthorized connection attempt from {addr}")
                self.transport.sendto(json.dumps({
                    'type': 'error',
                    'message': 'Unauthorized'
                }).encode(), addr)
                return
            
            if message.get('code') != self.server.connection_code:
                print(f"Invalid connection code from {addr}")
                self.transport.sendto(json.dumps({
                    'type': 'error',
                    'message': 'Invalid connection code'
                }).encode(), addr)
                return
            
            print(f"New client authenticated: {addr}")
            self.server.client_address = addr
        
        # 활동 시간 업데이트
        self.server.last_activity_time = time.time()
        
        print(f"\n[>] Received message from {addr}:")
        print(f"    Type: {msg_type}")
        
        try:
            if msg_type == 'mouse_move_relative':
                self.handle_mouse_move(message)
            elif msg_type == 'mouse_click':
                self.handle_mouse_click(message)
            elif msg_type == 'keyboard':
                self.handle_keyboard(message)
            elif msg_type == 'request_frame':
                asyncio.create_task(self.server.capture_and_send_frame())
            elif msg_type == 'keepalive':
                self.handle_keepalive(addr)
            elif msg_type == 'disconnect':
                self.handle_disconnect(addr)
            
            print(f"    Status: Success")
            
        except Exception as e:
            print(f"    Error: {e}")
            self.transport.sendto(json.dumps({
                'type': 'error',
                'message': str(e)
            }).encode(), addr)

    def handle_mouse_move(self, message):
        current_x, current_y = pyautogui.position()
        dx = float(message.get('dx', 0))
        dy = float(message.get('dy', 0))
        
        # 이동 거리에 속도 승수 적용
        dx *= self.server.mouse_speed_multiplier
        dy *= self.server.mouse_speed_multiplier
        
        # 새 위치 계산
        new_x = int(current_x + dx)
        new_y = int(current_y + dy)
        
        # 화면 경계 확인
        new_x = max(0, min(new_x, self.server.screen_width - 1))
        new_y = max(0, min(new_y, self.server.screen_height - 1))
        
        print(f"    Relative Move: dx={dx}, dy={dy}")
        print(f"    New Position: ({new_x}, {new_y})")
        
        pyautogui.moveTo(new_x, new_y, duration=0)

    def handle_mouse_click(self, message):
        click_type = message.get('click_type', 'left')
        print(f"    Click type: {click_type}")
        
        if click_type == 'double':
            pyautogui.doubleClick()
        elif click_type == 'right':
            pyautogui.rightClick()
        else:
            pyautogui.click()

    def handle_keyboard(self, message):
        key = message.get('key', '')
        print(f"    Key: {key}")
        
        try:
            if key in ['f5', 'esc']:
                asyncio.create_task(self.server.handle_presentation_toggle(message))
            else:
                pyautogui.press(key)
        except Exception as e:
            print(f"    Error pressing key: {e}")
            raise

    def handle_keepalive(self, addr):
        self.transport.sendto(json.dumps({
            'type': 'keepalive_response',
            'timestamp': time.time()
        }).encode(), addr)

    def handle_disconnect(self, addr):
        if addr == self.server.client_address:
            print(f"    Client disconnected: {addr}")
            self.server.client_address = None
            self.server.streaming_enabled = False

    def error_received(self, exc):
        print(f'Error received: {exc}')

    def connection_lost(self, exc):
        print(f'Connection lost: {exc}')
    
class RemoteControlServer:
    def __init__(self, udp_port=8080, http_port=8081):
        self.udp_port = udp_port
        self.http_port = http_port
        self.connection_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
        self.client_address = None
    
        # 마우스/키보드 설정
        pyautogui.FAILSAFE = False
        self.screen_width, self.screen_height = pyautogui.size()
        
        # 마우스 이동 관련 설정
        self.mouse_speed_multiplier = 2.0
        
        # 스트리밍 관련 설정
        self.screen_capture = mss()
        self.streaming_enabled = False
        self.compression_quality = 50  # JPEG 압축 품질 (1-100)
        self.scale_factor = 0.5       # 스트리밍 해상도 스케일
        
        # 시스템 설정
        self.os_type = platform.system()
        self.presentation_mode = False
        
        # UDP 소켓
        self.transport = None
        self.protocol = None
        
        # 활동 관리
        self.last_activity_time = None
        self.inactivity_timeout = 600  # 10분
        
        # QR 코드 생성
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
            'port': self.udp_port,
            'ip': local_ip
        }
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(json.dumps(qr_data))
        qr.make(fit=True)
        qr_image = qr.make_image(fill_color="black", back_color="white")
        qr_image.save('connection_qr.png')
        
        print(f"[*] Server IP: {local_ip}")

    async def capture_and_send_frame(self):
        """화면 캡처 및 전송"""
        try:
            # 전체 화면 캡처
            screen = self.screen_capture.grab(self.screen_capture.monitors[0])
            
            # PIL Image로 변환
            img = Image.frombytes('RGB', screen.size, screen.rgb)
            
            # 리사이즈
            new_size = (int(screen.width * self.scale_factor), 
                       int(screen.height * self.scale_factor))
            img = img.resize(new_size, Image.LANCZOS)
            
            # JPEG으로 압축
            buffer = io.BytesIO()
            img.save(buffer, format='JPEG', quality=self.compression_quality)
            compressed_image = buffer.getvalue()
            
            # Base64 인코딩
            base64_frame = base64.b64encode(compressed_image).decode('utf-8')
            
            # 프레임 전송
            if self.client_address and self.transport:
                self.transport.sendto(json.dumps({
                    'type': 'frame',
                    'data': base64_frame
                }).encode(), self.client_address)
            
        except Exception as e:
            print(f"Frame capture error: {e}")

async def handle_presentation_toggle(self, data):
    """프레젠테이션 모드 전환 처리"""
    try:
        if self.os_type == 'Windows':
            import win32gui
            import win32process
            
            hwnd = win32gui.GetForegroundWindow()
            window_title = win32gui.GetWindowText(hwnd).lower()
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
            process_name = psutil.Process(pid).name().lower()
            
        elif self.os_type == 'Darwin':  # macOS
            # AppleScript를 사용하여 현재 활성 창 정보 가져오기
            import subprocess
            
            # 활성 앱 이름 가져오기
            script = 'tell application "System Events" to get name of first application process whose frontmost is true'
            process_name = subprocess.check_output(['osascript', '-e', script]).decode().strip().lower()
            
            # 창 제목 가져오기
            script = '''
            tell application "System Events"
                get title of first window of first application process whose frontmost is true
            end tell
            '''
            try:
                window_title = subprocess.check_output(['osascript', '-e', script]).decode().strip().lower()
            except:
                window_title = ""
            
        else:  # Linux
            try:
                import subprocess
                # xdotool을 사용하여 현재 창 정보 가져오기
                window_id = subprocess.check_output(['xdotool', 'getactivewindow']).decode().strip()
                window_title = subprocess.check_output(['xdotool', 'getwindowname', window_id]).decode().strip().lower()
                process_name = subprocess.check_output(['xdotool', 'getwindowpid', window_id]).decode().strip()
                process_name = psutil.Process(int(process_name)).name().lower()
            except:
                window_title = ""
                process_name = ""

        print(f"Active Window: {window_title}")
        print(f"Process: {process_name}")

        # PowerPoint 처리
        if any(name in process_name for name in ['powerpnt', 'keynote', 'libreoffice']):
            if any(term in window_title for term in ['slide show', '슬라이드 쇼', 'presentation']):
                pyautogui.press('esc')
            else:
                if 'keynote' in process_name:
                    if self.os_type == 'Darwin':
                        # Keynote용 프레젠테이션 시작 명령
                        script = '''
                        tell application "Keynote"
                            tell the front document
                                start from first slide
                            end tell
                        end tell
                        '''
                        subprocess.run(['osascript', '-e', script])
                else:
                    pyautogui.press('f5')
        
        # PDF 뷰어 처리
        elif any(name in process_name for name in ['acrord32', 'preview', 'msedge', 'chrome', 'safari']):
            if any(term in window_title for term in ['full screen', '전체 화면']):
                pyautogui.press('esc')
            else:
                if self.os_type == 'Darwin':
                    pyautogui.hotkey('command', 'shift', 'f')
                else:
                    pyautogui.hotkey('ctrl', 'l')
        
        # 기타 프로그램
        else:
            print(f"Unknown program: {process_name}")
            pyautogui.press(data.get('key', 'f5'))

    except Exception as e:
        print(f"Error in handle_presentation_toggle: {e}")
        pyautogui.press(data.get('key', 'f5'))

    async def check_inactivity(self):
        """비활성 타이머 체크"""
        while True:
            await asyncio.sleep(60)  # 1분마다 체크
            if (self.client_address and self.last_activity_time and 
                time.time() - self.last_activity_time > self.inactivity_timeout):
                print("Inactive timeout reached, disconnecting client")
                self.client_address = None
                self.streaming_enabled = False

    def create_html(self):
        """HTML 페이지 생성"""
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Remote Control Server</title>
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
                <p>UDP Port: {self.udp_port}</p>
                <h3>QR 코드로 연결하기</h3>
                <img src="connection_qr.png" alt="Connection QR Code">
            </div>
        </body>
        </html>
        """
        with open('connection.html', 'w', encoding='utf-8') as f:
            f.write(html_content)

    async def start(self):
        """서버 시작"""
        self.create_html()
        
        # HTTP 서버 설정
        app = web.Application()
        app.router.add_get('/', lambda r: web.FileResponse('connection.html'))
        app.router.add_get('/connection_qr.png', lambda r: web.FileResponse('connection_qr.png'))

        # 브라우저 자동 실행
        import webbrowser
        webbrowser.open(f'http://localhost:{self.http_port}')
        
        print("\n" + "="*50)
        print("=== Remote Control Server ===")
        print(f"[*] Starting server...")
        
        # UDP 서버 시작
        loop = asyncio.get_event_loop()
        self.transport, self.protocol = await loop.create_datagram_endpoint(
            lambda: UDPServerProtocol(self),
            local_addr=('0.0.0.0', self.udp_port)
        )
        
        # HTTP 서버 시작
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', self.http_port)
        await site.start()
        
        print(f"[+] Server is running")
        print(f"[*] Connection Code: {self.connection_code}")
        print(f"[*] UDP Port: {self.udp_port}")
        print(f"[*] HTTP Port: {self.http_port}")
        print(f"[*] QR Code generated: connection_qr.png")
        print(f"[*] Web interface: http://localhost:{self.http_port}")
        print("\n[*] Waiting for connections...")
        print("="*50)
        
        # 비활성 타이머 시작
        asyncio.create_task(self.check_inactivity())
        
        # 서버 실행 유지
        try:
            await asyncio.Future()  # 영원히 실행
        except asyncio.CancelledError:
            pass
        finally:
            # 정리
            self.transport.close()
            await runner.cleanup()

    async def stop(self):
        """서버 중지"""
        if self.transport:
            self.transport.close()
        
        # 연결된 클라이언트에게 종료 알림
        if self.client_address:
            try:
                self.transport.sendto(json.dumps({
                    'type': 'server_shutdown',
                    'message': 'Server is shutting down'
                }).encode(), self.client_address)
            except:
                pass
        
        # 임시 파일 정리
        try:
            os.remove('connection_qr.png')
            os.remove('connection.html')
        except:
            pass

def setup_logging():
    """로깅 설정"""
    import logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler('remote_control_server.log')
        ]
    )
    return logging.getLogger('RemoteControlServer')

async def main_async():
    """비동기 메인 함수"""
    server = None
    try:
        server = RemoteControlServer()
        await server.start()
    except KeyboardInterrupt:
        print("\n키보드 인터럽트 감지: 서버를 종료합니다...")
    except Exception as e:
        print(f"\n서버 실행 중 오류 발생: {e}")
    finally:
        if server:
            await server.stop()

def main():
    """메인 실행 함수"""
    logger = setup_logging()
    try:
        # Windows에서 이벤트 루프 정책 설정
        if platform.system() == 'Windows':
            asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
        
        # 메인 실행
        asyncio.run(main_async())
    except Exception as e:
        logger.error(f"프로그램 실행 중 치명적 오류 발생: {e}", exc_info=True)
    finally:
        logger.info("프로그램이 종료되었습니다.")

if __name__ == '__main__':
    main()