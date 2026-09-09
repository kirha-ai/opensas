/* GAP-sqlsortseqlinguistic — PROC SQL's ORDER BY honours SORTSEQ=LINGUISTIC,
   from the system option AND from PROC SQL's own statement option, with the
   statement option winning. Before this, both were ignored: the system option
   was never read by sql.zig (io.global_sortseq_linguistic had exactly ONE
   consumer, proc.zig's runSort) and `proc sql sortseq=` sat in
   isNoopSqlOption, accepted and silently dropped — silent wrong ROW ORDER,
   the D-002 class.

   Doc, all four citations verified against the page markers:
     * Base SAS 9.4 Procedures Guide printed p.2403 (`=== pdf 2452 ===`), Note:
       "Only PROC SORT and PROC SQL are affected when the SORTSEQ=LINGUISTIC
       system option is specified."  Same page: "Starting in the third
       maintenance release of SAS 9.4, you can specify linguistic collation
       using the SORTSEQ= option in the SQL procedure and by specifying the
       SORTSEQ=LINGUISTIC system option."
     * SQL Procedure User's Guide printed p.45 (`=== pdf 60 ===`): "Beginning
       with SAS 9.4M3, linguistic collation is supported with the SORTSEQ
       statement option." — the SQL half is dated with the SAME M3 vintage, so
       both halves of the feature arrived together.
     * SQL Procedure User's Guide printed p.261 (`=== pdf 276 ===`),
       SORTSEQ=sort-table | LINGUISTIC: "specifies the collating sequence to use
       when a query contains an ORDER BY clause … If LINGUISTIC is specified for
       the SORTSEQ system option, then PROC SQL honors the setting. The setting
       of the PROC SQL SORTSEQ option overrides the setting of the SORTSEQ
       system option."  PRECEDENCE IS DOC-STATED, not inferred.

   WHAT IS PINNED IS THE ORDER, not the absence of an error. ASCII puts every
   uppercase letter before every lowercase one (Banana, Zebra, apple);
   case-folded dictionary order interleaves them (apple, Banana, Zebra). Each
   block below would gain the WRONG ROW ORDER if its half of the fix were
   reverted, so a regression shows up as a golden diff and not as a silent pass.
   expect-rc: 0 */
data names;
  input name $ @@;
datalines;
Zebra apple Banana
;
run;

/* 1. SYSTEM option only — p.2403's Note and p.261's "PROC SQL honors the
      setting". This is the half the ticket named. */
options sortseq=linguistic;
title "1 system option: apple Banana Zebra";
proc sql;
  select name from names order by name;
quit;

/* 2. STATEMENT option only, with the system option explicitly ASCII — p.45's
      "Beginning with SAS 9.4M3 … with the SORTSEQ statement option". This half
      was a silent no-op in isNoopSqlOption. */
options sortseq=ascii;
title "2 statement option: apple Banana Zebra";
proc sql sortseq=linguistic;
  select name from names order by name;
quit;

/* 3. PRECEDENCE, the direction that proves the rule rather than agreeing with
      it by accident: system says LINGUISTIC, the statement says ASCII, and
      p.261 says the statement wins — so this must come out in ASCII order. */
options sortseq=linguistic;
title "3 statement ASCII overrides system LINGUISTIC: Banana Zebra apple";
proc sql sortseq=ascii;
  select name from names order by name;
quit;

/* 4. RESET carries the option mid-step (it mutates the same g_opts). */
options sortseq=ascii;
title "4 reset sortseq=linguistic: apple Banana Zebra";
proc sql;
  reset sortseq=linguistic;
  select name from names order by name;
quit;

/* 5. DEFAULT is untouched: no system option, no statement option → ASCII. */
title "5 default ascii: Banana Zebra apple";
proc sql;
  select name from names order by name;
quit;

/* 6. ORDER BY DESC still reverses the COLLATED order, not the byte order. */
options sortseq=linguistic;
title "6 desc under linguistic: Zebra Banana apple";
proc sql;
  select name from names order by name desc;
quit;
