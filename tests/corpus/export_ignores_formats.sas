/* NOTE-exportformatraw, adjudicated CONFORMANT — this fixture PINS the verdict
   so a future "fix" cannot quietly make PROC EXPORT format-aware.

   The board suspected we were wrong: "EXPORT emits `put var;` which honors
   formats -> DATE9 should export a DDMONYYYY string, not a day count". The Base
   SAS 9.4 Procedures Guide disproves it with EXPORT's OWN generated code, which
   both worked examples print in their log (p.860 Ex.1 DBMS=DLM, p.863 Ex.2
   DBMS=CSV): the generated DATA step first re-declares every character
   variable as `format <var> $w.;` and every numeric one as
   `format <var> best12.;`, and only then emits the `put <var> @;` lines.

   So it does emit `put var` — but only AFTER re-assigning the variable's format
   to $w. / BEST12. for the duration of the generated step, which by ordinary
   DATA-step semantics overrides whatever format the variable carries. The only
   format-related statement in the whole EXPORT chapter is FMTLIB, and that one
   is "valid only when DBMS=JMP" and writes value labels — there is no way to
   make a delimited export honour attached formats.

   So: attached formats are IGNORED, and numerics are written as BEST12. would
   write them, which is what the rows below pin. `wide` is the discriminating
   case — 16 digits do not fit BEST12., so it must come out in E-notation
   rather than as all its digits. */
data fmtd;
  length who $8;
  who   = 'Ondrej';
  day   = '15mar2021'd;
  stamp = '15mar2021:14:45:00'dt;
  clock = '14:45:00't;
  cost  = 8765.4;
  wide  = 9876543210987654;
  ratio = 2/3;
  format day date9. stamp datetime. clock time. cost dollar10.2;
  output;
run;

/* the formats ARE attached — PROC PRINT honours them, EXPORT must not */
proc print data=fmtd noobs; var day stamp clock cost; run;

proc export data=fmtd outfile="tests/corpus/includes/eif_formats.csv" dbms=csv replace; run;

data _null_;
  infile "tests/corpus/includes/eif_formats.csv" truncover;
  input line $200.;
  put 'CSV: ' line;
run;

/* every exported numeric equals what BEST12. writes (blanks trimmed) */
data _null_;
  set fmtd;
  put 'best12 day   = ' day   best12.;
  put 'best12 cost  = ' cost  best12.;
  put 'best12 wide  = ' wide  best12.;
  put 'best12 ratio = ' ratio best12.;
run;
