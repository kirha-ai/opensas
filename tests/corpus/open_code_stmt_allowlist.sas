/* BUG-opencodestmtswallow (doc-finder tick305 F4 — the open-code sibling of
   BUG-optionsstmtswallow): the top-level statement splitter recognized only
   DATA/PROC and the global keywords and silently DISCARDED every other
   open-code statement — a typo'd `titl 'x';` / `libnam raw 'p';` vanished at
   exit 0 with the program built on the setting that never took effect, and
   `endsas;` (Language Reference: Concepts p.487 step boundary) was a silent no-op, so a program
   gated off by ENDSAS ran to completion. Now the chain has a real final else:
   an explicit inert allowlist is skipped to its `;`, and anything else errors
   LOUD naming it (the loud paths are pinned by in-file tests in main.zig).
   This green fixture is the POSITIVE CONTROL (the D-014 anti-regression
   half): every top-level statement class in real use must keep parsing. */

/* inert open-code statements — real SAS with no observable effect in a batch
   interpreter: the windowing environment (DM), graphics devices (GOPTIONS),
   dataset caching (SASFILE), windowing catalogs (CATNAME). The `;` INSIDE the
   DM string must not end the skip early (the skip is token-level). */
dm 'log;clear;output;clear';
goptions reset=all hsize=6in vsize=4in;
sasfile work.d load;
catname pcats (work work.cat1);

/* the global-statement classes (see also global_accept.sas) */
filename myref "/tmp/open_code_allowlist_out.txt";
options nodate nonumber;
ods listing;
x "echo hello";
title 'open-code positive control';
footnote 'allowlist fixture';

data d;
  input name $ v;
  datalines;
a 1
b 2
;
run;

/* a bare run; / quit; in open code is harmless */
run;
quit;

proc print data=d noobs; run;

proc sort data=d; by descending v; run;
proc print data=d noobs; run;

title;
footnote;
