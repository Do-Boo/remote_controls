import os

def create_flutter_project_structure():
    # 기본 디렉토리 구조
    directories = [
        'lib',
        'lib/bindings',
        'lib/controllers',
        'lib/models',
        'lib/services',
        'lib/views'
    ]
    
    # 파일 목록
    files = [
        'lib/main.dart',
        'lib/bindings/remote_control_binding.dart',
        'lib/controllers/remote_control_controller.dart',
        'lib/models/connection_info.dart',
        'lib/services/udp_service.dart',
        'lib/views/remote_control_view.dart',
        'lib/views/qr_scan_view.dart'
    ]
    
    # 디렉토리 생성
    for directory in directories:
        os.makedirs(directory, exist_ok=True)
        print(f'디렉토리 생성됨: {directory}')
    
    # 파일 생성
    for file in files:
        with open(file, 'w') as f:
            f.write('')  # 빈 파일 생성
        print(f'파일 생성됨: {file}')

if __name__ == '__main__':
    create_flutter_project_structure()