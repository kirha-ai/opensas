/* GH#20 BUG-exportimportdsopts: PROC EXPORT's `data=NAME(...)` and PROC IMPORT's
   `out=NAME(...)` dataset options were PARSED PAST and dropped on the floor, so
   the exported file / imported table landed with the wrong columns, the wrong
   rows and the wrong names at rc 0 and no warning — the worst failure class for
   clinical use (D-002, CLAUDE.md fail-loud). Both positions are documented: Base
   SAS 9.4 Procedures Guide, 7th ed., printed pp. 851-852
   `PROC EXPORT DATA=<libref.>SAS data set <(SAS data set options)>` +
   "(SAS data set options) specifies SAS data set options", with the chapter's own
   worked example `data=sashelp.class (where=(sex='F'))` (printed p. 862); and
   printed p. 1328 `OUT=<libref.>SAS data set <(SAS data set options)>` for IMPORT.

   Every option is pinned INDEPENDENTLY and then in combination, and the file
   CONTENT is compared by reading the raw CSV back line by line — a PROC IMPORT
   round-trip would hide a wrong header row, which is exactly the symptom.
   Invented data only (no PHI, D-011). */
data eido;
  do id = 1 to 5;
    x = id * 10;
    y = id * 100;
    output;
  end;
run;

/* control: no dataset options — the whole table, id,x,y + 5 rows. Doubles as the
   DATAFILE= source for the IMPORT direction at the bottom. */
proc export data=eido outfile="tests/corpus/includes/eido_full.csv" dbms=csv replace; run;
data r_full;
  infile "tests/corpus/includes/eido_full.csv" truncover;
  length line $40;
  input line $;
run;
proc print data=r_full noobs; run;

/* keep= : only the named columns reach the file */
proc export data=eido(keep=id x) outfile="tests/corpus/includes/eido_keep.csv" dbms=csv replace; run;
data r_keep;
  infile "tests/corpus/includes/eido_keep.csv" truncover;
  length line $40;
  input line $;
run;
proc print data=r_keep noobs; run;

/* drop= : the complement of the keep= case above — same file */
proc export data=eido(drop=y) outfile="tests/corpus/includes/eido_drop.csv" dbms=csv replace; run;
data r_drop;
  infile "tests/corpus/includes/eido_drop.csv" truncover;
  length line $40;
  input line $;
run;
proc print data=r_drop noobs; run;

/* where= : the doc example's own option — a row subset, all columns */
proc export data=eido(where=(id<3)) outfile="tests/corpus/includes/eido_where.csv" dbms=csv replace; run;
data r_where;
  infile "tests/corpus/includes/eido_where.csv" truncover;
  length line $40;
  input line $;
run;
proc print data=r_where noobs; run;

/* rename= : the HEADER row must carry the new name (x -> xx) */
proc export data=eido(rename=(x=xx)) outfile="tests/corpus/includes/eido_rename.csv" dbms=csv replace; run;
data r_rename;
  infile "tests/corpus/includes/eido_rename.csv" truncover;
  length line $40;
  input line $;
run;
proc print data=r_rename noobs; run;

/* firstobs=/obs= : honoured on EXPORT because data= is an INPUT read (obs= is the
   LAST position, not a count) — observations 2, 3, 4 only */
proc export data=eido(firstobs=2 obs=4) outfile="tests/corpus/includes/eido_obs.csv" dbms=csv replace; run;
data r_obs;
  infile "tests/corpus/includes/eido_obs.csv" truncover;
  length line $40;
  input line $;
run;
proc print data=r_obs noobs; run;

/* all combined: keep= names the OLD name, rename= applies after keep=/drop=, and
   where= subsets the rows — id,xx + 2 rows (the issue's repro) */
proc export data=eido(keep=id x where=(id<3) rename=(x=xx))
  outfile="tests/corpus/includes/eido_all.csv" dbms=csv replace;
run;
data r_all;
  infile "tests/corpus/includes/eido_all.csv" truncover;
  length line $40;
  input line $;
run;
proc print data=r_all noobs; run;

/* the OTHER direction: IMPORT's options sit on the dataset being CREATED, so they
   filter the imported table (not the input file) — keep/drop/where/rename all
   apply to the OUT= member. */
proc import datafile="tests/corpus/includes/eido_full.csv"
  out=eido_in(keep=id x where=(id<3) rename=(x=xx)) dbms=csv replace;
run;
proc print data=eido_in noobs; run;

/* firstobs=/obs= are INPUT-ONLY dataset options: SAS ignores them on an OUTPUT
   data set and writes every row, so OUT=(firstobs=/obs=) must NOT slice the
   imported table (settled, BUG-outdsobsslice) — all 5 observations. */
proc import datafile="tests/corpus/includes/eido_full.csv"
  out=eido_in2(firstobs=2 obs=3) dbms=csv replace;
run;
proc print data=eido_in2 noobs; run;
