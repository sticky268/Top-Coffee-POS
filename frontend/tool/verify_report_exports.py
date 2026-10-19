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

# New report money stays numeric and the fourth (net) PDF column is retained.
exact = load_workbook(root / "sales-exact.xlsx", data_only=False)["Sales report"]
assert exact["D4"].value == 8.01 and exact["D4"].data_type == "n"
assert exact["B5"].value == -0.1 and exact["B5"].data_type == "n"
exact_text = "".join(page.extract_text() for page in PdfReader(root / "sales-exact.pdf").pages)
assert "8.01" in exact_text and "-0.10" in exact_text, repr(exact_text)
print("Exact-money workbook and four-column PDF preserve net and negative amounts.")

profit = load_workbook(root / "profit-exact.xlsx", data_only=False)["Sales report"]
for value in [1.123457, 4.876543]:
    assert any(c.value == value and c.data_type == "n" for row in profit for c in row)
profit_text = "".join(page.extract_text() for page in PdfReader(root / "profit-exact.pdf").pages)
assert "Profitability" in profit_text and "1.123457" in profit_text and "4.876543" in profit_text
assert "Riverside" in profit_text and "2026-10-19" in profit_text
print("Profit exports preserve six-decimal COGS, profit, branch and dates.")
