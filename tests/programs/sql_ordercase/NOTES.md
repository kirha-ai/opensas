# sql_ordercase

Synthetic data. Regression guard for BUG-ordercase:
PROC SQL ORDER BY a CASE expression sorts by the CASE key. **Passes** (feature was
already fixed under SQLORDER; this pins it).
