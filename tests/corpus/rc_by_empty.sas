/* BUG-bystmtempty — `by;` with no variables used to be SILENTLY ACCEPTED,
   no-opping the entire BY mechanism (silent wrong output, the worst class).
   sas9.4.ebnf by_stmt requires >= 1 var, so this is a USER error (rc 1,
   D-009b) — the parser's shared scanByList now rejects it. The PROC PRINT
   first makes the golden non-empty, so this fixture fails on both surfaces
   (stdout AND rc) rather than passing vacuously.
   expect-rc: 1 */
data have;
  input grp v;
  datalines;
1 10
2 30
;
run;
proc print data=have;
run;
data out;
  set have;
  by;
run;
