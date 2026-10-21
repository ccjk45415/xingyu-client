"""Run isolated backend tests with project-local dependencies."""
import os, subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
env=os.environ.copy()
env['PYTHONPATH']=os.pathsep.join([str(root/'.toolchain/chatdeps'),str(root/'chat-server'),str(root/'tests')])
subprocess.run([sys.executable,'-m','unittest','test_chat_server','-v'],cwd=root,env=env,check=True)
