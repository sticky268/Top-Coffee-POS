"""Validate report fixtures with independent Excel and PDF readers."""
from pathlib import Path
import re
from openpyxl import load_workbook
from pypdf import PdfReader

root = Path("build/report-exports")
book = load_workbook(root / "sales.xlsx", data_only=False)
sheet = book["Sales report"]
assert sheet["A1"].value == "Top Coffee POS sales report"
assert sheet["B2"].value == "Cafe & Coffee"
assert any(c.value == 12.5 and c.data_type == "n" for row in sheet for c in row)
formula_name = next(c for row in sheet for c in row if c.value == '=1+1, "Latte"')
assert formula_name.data_type == "s", "Product names must remain literal text"
reader = PdfReader(root / "sales.pdf")
assert reader.pages
text = "\n".join(page.extract_text() for page in reader.pages)
compact = re.sub(r"\s+", "", text)
assert "TopCoffee" in compact and "12.5" in compact, repr(text)
print("Excel opens correctly, amounts are numeric, formula names are text, and PDF contains report data.")
