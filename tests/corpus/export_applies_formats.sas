/* GH#25 — NOTE-exportformatraw OVERTURNED: EXPORT (EFI) PRESERVES attached
   formats. This fixture PINS the reversal so a future "fix" cannot quietly
   make PROC EXPORT format-blind again (the predecessor fixture
   export_ignores_formats.sas pinned the opposite verdict under this evidence).

   Why the old ruling was wrong: it generalized from the two worked examples in
   the Base SAS 9.4 Procedures Guide EXPORT chapter, which print their generated
   EFI code for SASHELP.CLASS-style input whose numerics carry NO formats — so
   the generated `format <var> best12.;` lines there RE-STATE the source
   variables' (absent) formats; they strip nothing and discriminate nothing.
   Live-SAS 9.4 evidence, all pointing the other way:
     - a real EFI (EXPORT) log for SASHELP.CARS preserves `format MSRP dollar8.;`
       and `format Invoice dollar8.;` — best12. appears only beside the columns
       that had no format to preserve;
     - runtime corroboration: comma separators show up in exported CSVs exactly
       for COMMA/DOLLAR-formatted columns (BEST12. never emits one);
     - the standard answer to "how do I keep my date format when exporting" is
       "attach the format to the variable" — and it works.
   Deciding repro: `format d yymmdd10.;` + EXPORT writes 2024-02-15, not the
   day count 23421 (docs/decisions.md D-027).

   So the EXPORT path renders every formatted numeric exactly as `put var fmt.`
   would (leading width padding trimmed — EFI writes the value, not the field),
   and BEST12. is only the DEFAULT for numerics with NO format:
     - `wide` is the BEST12. control: 16 digits do not fit, so it must come out
       in E-notation rather than as all its digits;
     - `who` is the char control: written verbatim, formats don't touch it;
     - `cost` (dollar10.2) renders `$8,765.40`, which contains the delimiter
       and must be DSD-QUOTED exactly like a char field with a comma;
     - `hole` is a FORMATTED missing: still an EMPTY field — EFI's missing
       handling wins over the format (BUG-exportmissing keeps its verdict);
     - the same cells through the internal libname CSV writer stay raw
       (D-001: that engine is not format-aware; not re-pinned here). */
data fmtd;
  length who $8;
  who   = 'Ondrej';
  day   = '15mar2021'd;
  iso   = '15mar2021'd;
  stamp = '15mar2021:14:45:00'dt;
  clock = '14:45:00't;
  cost  = 8765.4;
  wide  = 9876543210987654;
  ratio = 2/3;
  hole  = .;
  format day date9. iso yymmdd10. stamp datetime. clock time. cost dollar10.2 hole yymmdd10.;
  output;
run;

/* the formats ARE attached — PROC PRINT honours them, and EXPORT must too */
proc print data=fmtd noobs; var day iso stamp clock cost; run;

proc export data=fmtd outfile="tests/corpus/includes/eif_formats.csv" dbms=csv replace; run;

data _null_;
  infile "tests/corpus/includes/eif_formats.csv" truncover;
  input line $200.;
  put 'CSV: ' line;
run;
