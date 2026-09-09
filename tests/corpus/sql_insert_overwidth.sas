/* BUG-sqlinsertoverwidth — INSERT ... SELECT must not store a value wider than
   the target column's declared char(n) width. The VALUES form already clipped
   via coerceToColumn (GAP-sqldatatypewidth); the SELECT form appended raw
   cells, so the descriptor said Char 3 while the cell held 8 bytes — PROC
   PRINT and EXPORT render the raw cell, the DATA-step read clips to the
   descriptor (1dcc5b51), and one stored table disagreed with itself by reader.
   The SQL volume's INSERT section (pp.290-292) is silent on truncation, but a
   cell disagreeing with its own descriptor is not a doc question (2a4a2b6a:
   "a descriptor must not disagree with the cell it describes"). Fixed AT THE
   STORE: both SELECT forms route through the same coerceToColumn as VALUES/
   UPDATE, so every surface is right by construction. Pinned through FOUR
   surfaces (PRINT cell, CONTENTS descriptor, DATA-step read-back, raw EXPORT
   bytes) plus within-width controls that must stay untouched. (no PHI) */
data a; length s $3; s='abc'; output; run;

proc sql;
  create table t (k char(3), n num);
  insert into t select 'abcdefgh' as k, 1 as n from a; /* over-width -> abc    */
  insert into t (k) select 'ijklmn' as k from a;       /* over-width, col list */
  insert into t select 'pq' as k, 3 as n from a;       /* within: control      */
  insert into t values ('wxyz', 4);                    /* VALUES control: wxy  */
  insert into t values ('st', 5);                      /* VALUES within: st    */
quit;

proc print data=t; run;      /* cell surface: abc ijk pq wxy st, never 8-wide */
proc contents data=t; run;   /* descriptor: k Char 3                          */

data chk; set t;             /* read-back surface: agrees with PRINT          */
  l = lengthn(k);
  put 'READBACK=[' k +0 '] len=' l;
run;

/* EXPORT reads the raw cells (io.writeCsvExport) — read the file back RAW so
   the stored bytes are pinned, not a round-trip that could re-clip on import */
proc export data=t outfile="tests/corpus/includes/siov_rt.csv" dbms=csv replace; run;
data raw;
  infile "tests/corpus/includes/siov_rt.csv" truncover;
  length line $32;
  input line $;
run;
proc print data=raw noobs; run;
