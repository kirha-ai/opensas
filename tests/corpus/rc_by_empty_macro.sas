/* BUG-bystmtempty — `by &bv;` with an EMPTY macro variable used to no-op the
   BY mechanism silently. Macro expansion is textual before lex/parse (D-004),
   so the parser sees `by ;` and the SAME scanByList guard rejects it — this
   fixture pins that the macro spelling really reaches the parser check.
   User error, rc 1 (D-009b). The PROC PRINT first keeps the golden
   non-empty so the fixture fails on both surfaces.
   expect-rc: 1 */
%let bv=;
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
  by &bv;
run;
