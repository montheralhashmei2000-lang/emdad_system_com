import os, sys, subprocess
os.environ['QT_QPA_PLATFORM'] = 'offscreen'
result = subprocess.run([sys.executable, 'main.py'], cwd=r'd:\Emdad_Repository\Emdad_system')
sys.exit(result.returncode)