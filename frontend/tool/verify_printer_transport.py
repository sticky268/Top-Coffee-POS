"""Compile and run the production printer writer without Android or hardware."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pos-printer-") as build:
    subprocess.run([
        "java", "-m", "jdk.compiler/com.sun.tools.javac.Main", "-d", build,
        str(root / "android/app/src/main/java/com/example/top_coffee_pos/CheckedPrinterWriter.java"),
        str(root / "tool/printer_tests/CheckedPrinterWriterTest.java"),
    ], check=True)
    subprocess.run(["java", "-cp", build,
                    "com.example.top_coffee_pos.CheckedPrinterWriterTest"], check=True)
