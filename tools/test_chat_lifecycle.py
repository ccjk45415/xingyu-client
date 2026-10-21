"""Local JVM regression test for chat navigation cleanup; no public service access."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JDK = Path(os.environ.get("JAVA_HOME", "C:/Program Files/Java/jdk-17"))
OUT = ROOT / "app/build/chat-lifecycle-tests"
OUT.mkdir(parents=True, exist_ok=True)
SRC = ROOT / "app/src/main/java/moe/cangku/reader"
subprocess.run([
    str(JDK / "bin/javac.exe"), "-encoding", "UTF-8", "--release", "17", "-d", str(OUT),
    str(SRC / "ChatRules.java"), str(SRC / "ChatSocket.java"), str(ROOT / "tests/ChatLifecycleTest.java"),
], check=True)
subprocess.run([
    str(JDK / "bin/java.exe"), "-ea", "-cp", str(OUT), "moe.cangku.reader.ChatLifecycleTest",
], check=True)
