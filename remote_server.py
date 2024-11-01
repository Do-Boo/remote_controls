import asyncio
import json
import random
import string
import math
import pyautogui
from aiohttp import web
import os
import qrcode
import socket
import psutil
import platform
import time
import base64
from mss import mss
from PIL import Image
import io
import logging
from typing import Optional, Dict, Any
from dataclasses import dataclass
from enum import Enum

# 상수 정의
class Constants:
    INACTIVITY_TIMEOUT = 600  # 10분
    AUTH_TIMEOUT = 10  # 10초
    KEEPALIVE_INTERVAL = 5  # 5초
    QR_CODE_SIZE = 10
    QR_CODE_BORDER = 5
    SCREEN_COMPRESSION_QUALITY = 50
    SCREEN_SCALE_FACTOR = 0.5
    MOUSE_SPEED_MULTIPLIER = 2.0
    CONNECTION_CODE_LENGTH = 6

class MessageType(Enum):
    AUTH = 'auth'
    AUTH_RESPONSE = 'auth_response'
    ERROR = 'error'
    MOUSE_MOVE = 'mouse_move_relative'
    MOUSE_CLICK = 'mouse_click'
    KEYBOARD = 'keyboard'
    KEEPALIVE = 'keepalive'
    KEEPALIVE_RESPONSE = 'keepalive_response'
    DISCONNECT = 'disconnect'
    FRAME = 'frame'
    REQUEST_FRAME = 'request_frame'

@dataclass
class ClientInfo:
    address: tuple
    last_activity: float
    authenticated: bool = False
    streaming_enabled: bool = False

class UDPServerProtocol:
    def __init__(self, server):
        self.server = server
        self.transport = None
        self.logger = logging.getLogger('UDPServerProtocol')
        self._message_handlers = {
            MessageType.AUTH: self._handle_auth,
            MessageType.MOUSE_MOVE: self._handle_mouse_move,
            MessageType.MOUSE_CLICK: self._handle_mouse_click,
            MessageType.KEYBOARD: self._handle_keyboard,
            MessageType.KEEPALIVE: self._handle_keepalive,
            MessageType.DISCONNECT: self._handle_disconnect,
            MessageType.REQUEST_FRAME: self._handle_frame_request,
        }

    def connection_made(self, transport):
        self.transport = transport
        self.logger.info("UDP Server started")

    def datagram_received(self, data: bytes, addr: tuple):
        try:
            message = json.loads(data.decode())
            self.logger.debug(f"Received from {addr}: {message}")
            self._process_message(message, addr)
        except json.JSONDecodeError:
            self.logger.error(f"Invalid JSON from {addr}")
            self._send_error(addr, "Invalid message format")
        except Exception as e:
            self.logger.error(f"Error processing message: {e}", exc_info=True)
            self._send_error(addr, str(e))

    def _process_message(self, message: Dict[str, Any], addr: tuple):
        msg_type = MessageType(message.get('type', 'unknown'))
        
        # 인증 상태 확인
        if not self.server.is_client_authenticated(addr):
            if msg_type != MessageType.AUTH:
                self._send_error(addr, "Unauthorized")
                return
            
            handler = self._message_handlers.get(MessageType.AUTH)
            if handler:
                handler(message, addr)
            return

        # 인증된 클라이언트의 메시지 처리
        self.server.update_client_activity(addr)
        
        handler = self._message_handlers.get(msg_type)
        if handler:
            try:
                handler(message, addr)
            except Exception as e:
                self.logger.error(f"Error handling {msg_type}: {e}", exc_info=True)
                self._send_error(addr, f"Command execution failed: {str(e)}")
        else:
            self._send_error(addr, f"Unknown message type: {msg_type}")

    def _handle_auth(self, message: Dict[str, Any], addr: tuple):
        code = message.get('code')
        if code != self.server.connection_code:
            self.logger.warning(f"Invalid auth code from {addr}")
            self._send_error(addr, "Invalid connection code")
            return

        self.server.authenticate_client(addr)
        self.logger.info(f"Client authenticated: {addr}")
        
        self._send_message(addr, {
            'type': MessageType.AUTH_RESPONSE.value,
            'status': 'success',
            'timestamp': int(time.time() * 1000)
        })

    def _handle_mouse_move(self, message: Dict[str, Any], addr: tuple):
        try:
            # 현재 마우스 위치
            current_x, current_y = pyautogui.position()
            
            # 가속도계 데이터
            dx = float(message.get('dx', 0))
            dy = float(message.get('dy', 0))
            
            # 데드존 적용
            if abs(dx) < self.server.mouse_deadzone and abs(dy) < self.server.mouse_deadzone:
                return
                
            # 가속도 기반 감도 조정
            acceleration = self._calculate_acceleration(dx, dy)
            dx *= acceleration * self.server.mouse_speed_multiplier
            dy *= acceleration * self.server.mouse_speed_multiplier
            
            # 이동 거리 누적 (부드러운 이동을 위해)
            self._accumulated_dx = getattr(self, '_accumulated_dx', 0) + dx
            self._accumulated_dy = getattr(self, '_accumulated_dy', 0) + dy
            
            # 실제 이동할 거리 계산
            move_x = int(self._accumulated_dx)
            move_y = int(self._accumulated_dy)
            
            # 남은 소수점 저장
            self._accumulated_dx -= move_x
            self._accumulated_dy -= move_y
            
            # 최종 위치 계산
            new_x = max(0, min(current_x + move_x, self.server.screen_width - 1))
            new_y = max(0, min(current_y + move_y, self.server.screen_height - 1))
            
            if abs(move_x) > 0 or abs(move_y) > 0:
                pyautogui.moveTo(new_x, new_y, duration=0)
                self.logger.debug(f"Mouse moved: ({move_x}, {move_y}) to ({new_x}, {new_y})")
                
        except Exception as e:
            self.logger.error(f"Mouse move error: {e}")

    def _calculate_acceleration(self, dx: float, dy: float) -> float:
        """가속도 기반 감도 계산"""
        # 움직임의 크기 계산
        movement = math.sqrt(dx * dx + dy * dy)
        
        # 기본 감도
        base_sensitivity = 0.8  # 기본 감도를 낮춤
        
        # 미세 움직임
        if movement < 0.1:  # 더 작은 임계값
            return base_sensitivity * 0.3
        # 일반 움직임
        elif movement < 0.5:  # 임계값 조정
            return base_sensitivity
        # 빠른 움직임
        else:
            # 최대 1.5배로 제한
            acceleration = min(1.5, 1.0 + (movement - 0.5) * 0.3)
            return base_sensitivity * acceleration

    def _handle_mouse_click(self, message: Dict[str, Any], addr: tuple):
        click_type = message.get('click_type', 'left')
        self.logger.debug(f"Mouse click: {click_type}")
        
        if click_type == 'double':
            pyautogui.doubleClick()
        elif click_type == 'right':
            pyautogui.rightClick()
        else:
            pyautogui.click()

    def _handle_keyboard(self, message: Dict[str, Any], addr: tuple):
        key = message.get('key', '')
        self.logger.debug(f"Keyboard input: {key}")
        
        if key in ['f5', 'esc']:
            asyncio.create_task(self.server.handle_presentation_toggle(message))
        else:
            pyautogui.press(key)

    def _handle_keepalive(self, message: Dict[str, Any], addr: tuple):
        self._send_message(addr, {
            'type': MessageType.KEEPALIVE_RESPONSE.value,
            'timestamp': int(time.time() * 1000)
        })

    def _handle_disconnect(self, message: Dict[str, Any], addr: tuple):
        self.server.remove_client(addr)
        self.logger.info(f"Client disconnected: {addr}")

    def _handle_frame_request(self, message: Dict[str, Any], addr: tuple):
        asyncio.create_task(self.server.send_frame(addr))

    def _send_message(self, addr: tuple, message: Dict[str, Any]):
        try:
            data = json.dumps(message).encode()
            self.transport.sendto(data, addr)
        except Exception as e:
            self.logger.error(f"Error sending message to {addr}: {e}")

    def _send_error(self, addr: tuple, message: str):
        self._send_message(addr, {
            'type': MessageType.ERROR.value,
            'message': message,
            'timestamp': int(time.time() * 1000)
        })

    def error_received(self, exc):
        self.logger.error(f'Transport error: {exc}')

    def connection_lost(self, exc):
        self.logger.warning(f'Connection lost: {exc}')
    
class RemoteControlServer:
    def __init__(self, udp_port=8080, http_port=8081):

        # 로거 설정
        self.logger = logging.getLogger('RemoteControlServer')
        
        # 네트워크 설정
        self.udp_port = udp_port
        self.http_port = http_port
        self.connection_code = ''.join(random.choices(
            string.ascii_uppercase + string.digits, 
            k=Constants.CONNECTION_CODE_LENGTH
        ))

        # 클라이언트 관리
        self._clients: Dict[tuple, ClientInfo] = {}
        
        # 시스템 설정
        self.os_type = platform.system()
        pyautogui.FAILSAFE = False
        self.screen_width, self.screen_height = pyautogui.size()
        self.mouse_speed_multiplier = Constants.MOUSE_SPEED_MULTIPLIER

        # 화면 캡처 설정
        self.screen_capture = mss()
        self.compression_quality = Constants.SCREEN_COMPRESSION_QUALITY
        self.scale_factor = Constants.SCREEN_SCALE_FACTOR

        # 서버 상태
        self.transport = None
        self.protocol = None
        
        # QR 코드 생성
        self._generate_qr_code()
        
        # 비활성 체크 태스크
        self._inactivity_check_task = None

        # 마우스 제어 설정
        self.mouse_speed_multiplier = 0.5  # 기본값을 더 낮게 조정
        self.mouse_acceleration = 1.1   # 가속 계수를 약간 낮춤
        self.mouse_smoothing = 0.4     # 부드러움을 약간 높임
        self.mouse_deadzone = 0.02     # 데드존을 더 작게 설정
        
        # 마우스 보정 설정
        self.calibration = {
            'x_scale': 1.0,
            'y_scale': 1.0,
            'x_offset': 0.0,
            'y_offset': 0.0
        }

    def _generate_qr_code(self):
        """QR 코드 생성"""
        try:
            local_ip = self._get_local_ip()
            
            qr_data = {
                'code': self.connection_code,
                'port': self.udp_port,
                'ip': local_ip
            }
            
            qr = qrcode.QRCode(
                version=1,
                box_size=Constants.QR_CODE_SIZE,
                border=Constants.QR_CODE_BORDER
            )
            qr.add_data(json.dumps(qr_data))
            qr.make(fit=True)
            
            qr_image = qr.make_image(fill_color="black", back_color="white")
            qr_image.save('connection_qr.png')
            
            self.logger.info(f"QR code generated with IP: {local_ip}")
            
        except Exception as e:
            self.logger.error(f"Failed to generate QR code: {e}")
            raise

    def _get_local_ip(self) -> str:
        """로컬 IP 주소 얻기"""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            local_ip = s.getsockname()[0]
            s.close()
            return local_ip
        except Exception:
            self.logger.warning("Could not determine local IP, using localhost")
            return '127.0.0.1'

    def create_html(self):
        """연결 페이지 HTML 생성"""
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
                    box-shadow: 0 2px 5px rgba(0,0,0,0.1);
                }}
                .code {{
                    font-size: 24px;
                    font-weight: bold;
                    color: #333;
                    margin: 20px 0;
                    padding: 10px;
                    background: #fff;
                    border-radius: 5px;
                    border: 2px solid #ddd;
                }}
                img {{
                    max-width: 300px;
                    margin: 20px 0;
                    border: 1px solid #ddd;
                    border-radius: 5px;
                    box-shadow: 0 2px 5px rgba(0,0,0,0.1);
                }}
                .info {{
                    color: #666;
                    font-size: 14px;
                    margin: 10px 0;
                }}
            </style>
        </head>
        <body>
            <h1>Remote Control Server</h1>
            <div class="container">
                <h2>연결 정보</h2>
                <p class="code">Connection Code: {self.connection_code}</p>
                <p class="info">UDP Port: {self.udp_port}</p>
                <h3>QR 코드로 연결하기</h3>
                <img src="connection_qr.png" alt="Connection QR Code">
                <p class="info">모바일 앱에서 QR 코드를 스캔하여 연결하세요.</p>
            </div>
        </body>
        </html>
        """
        with open('connection.html', 'w', encoding='utf-8') as f:
            f.write(html_content)

    async def start(self):
        """서버 시작"""
        try:
            self.create_html()
            
            # HTTP 서버 설정
            app = web.Application()
            app.router.add_get('/', lambda r: web.FileResponse('connection.html'))
            app.router.add_get('/connection_qr.png', lambda r: web.FileResponse('connection_qr.png'))

            # 브라우저 자동 실행
            import webbrowser
            webbrowser.open(f'http://localhost:{self.http_port}')
            
            self.logger.info("="*50)
            self.logger.info("=== Remote Control Server ===")
            
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
            
            # 서버 정보 출력
            self.logger.info(f"Server is running")
            self.logger.info(f"Connection Code: {self.connection_code}")
            self.logger.info(f"UDP Port: {self.udp_port}")
            self.logger.info(f"HTTP Port: {self.http_port}")
            self.logger.info(f"QR Code: connection_qr.png")
            self.logger.info(f"Web interface: http://localhost:{self.http_port}")
            self.logger.info("Waiting for connections...")
            self.logger.info("="*50)
            
            # 비활성 체크 시작
            self._inactivity_check_task = asyncio.create_task(self._check_inactivity())
            
            # 서버 실행 유지
            await asyncio.Future()  # 영원히 실행
            
        except Exception as e:
            self.logger.error(f"Server startup failed: {e}", exc_info=True)
            raise
        finally:
            await self.stop()

    async def stop(self):
        """서버 중지"""
        self.logger.info("Shutting down server...")
        
        if self._inactivity_check_task:
            self._inactivity_check_task.cancel()
        
        if self.transport:
            self.transport.close()
        
        # 연결된 클라이언트들에게 종료 알림
        for addr in list(self._clients.keys()):
            try:
                self.protocol._send_message(addr, {
                    'type': MessageType.ERROR.value,
                    'message': 'Server is shutting down'
                })
            except:
                pass
        
        # 임시 파일 정리
        try:
            os.remove('connection_qr.png')
            os.remove('connection.html')
        except:
            pass

    async def _check_inactivity(self):
        """비활성 클라이언트 체크"""
        while True:
            try:
                await asyncio.sleep(60)  # 1분마다 체크
                current_time = time.time()
                
                for addr, client in list(self._clients.items()):
                    if current_time - client.last_activity > Constants.INACTIVITY_TIMEOUT:
                        self.logger.info(f"Client {addr} timed out due to inactivity")
                        self.remove_client(addr)
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in inactivity check: {e}")

    # 클라이언트 관리 메서드들
    def authenticate_client(self, addr: tuple):
        self._clients[addr] = ClientInfo(
            address=addr,
            last_activity=time.time(),
            authenticated=True
        )

    def remove_client(self, addr: tuple):
        self._clients.pop(addr, None)

    def update_client_activity(self, addr: tuple):
        if client := self._clients.get(addr):
            client.last_activity = time.time()

    def is_client_authenticated(self, addr: tuple) -> bool:
        if client := self._clients.get(addr):
            return client.authenticated
        return False

    async def send_frame(self, addr: tuple):
        """화면 캡처 및 전송"""
        try:
            screen = self.screen_capture.grab(self.screen_capture.monitors[0])
            img = Image.frombytes('RGB', screen.size, screen.rgb)
            
            # 리사이즈
            new_size = (
                int(screen.width * self.scale_factor),
                int(screen.height * self.scale_factor)
            )
            img = img.resize(new_size, Image.LANCZOS)
            
            # 압축
            buffer = io.BytesIO()
            img.save(buffer, format='JPEG', quality=self.compression_quality)
            compressed_image = buffer.getvalue()
            
            # 전송
            base64_frame = base64.b64encode(compressed_image).decode('utf-8')
            self.protocol._send_message(addr, {
                'type': MessageType.FRAME.value,
                'data': base64_frame
            })
            
        except Exception as e:
            self.logger.error(f"Frame capture error: {e}")

async def main():
    """메인 함수"""
    # 로깅 설정
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler('remote_control_server.log')
        ]
    )

    server = None
    try:
        # Windows에서 이벤트 루프 정책 설정
        if platform.system() == 'Windows':
            asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
        
        server = RemoteControlServer()
        await server.start()
        
    except KeyboardInterrupt:
        logging.info("Keyboard interrupt received, shutting down...")
    except Exception as e:
        logging.error(f"Fatal error: {e}", exc_info=True)
    finally:
        if server:
            await server.stop()

if __name__ == '__main__':
    asyncio.run(main())