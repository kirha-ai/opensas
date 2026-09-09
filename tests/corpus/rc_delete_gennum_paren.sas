/* BUG-deletegennumsilent — GENNUM=ALL in parens after the file name is the
   doc's OWN spelling for deleting all generations (Procedures Guide, 7th ed.,
   PROC DELETE Statement, printed pp. 786-787). opensas has no generation
   model, so this is a recognized gap, exit 2 — and it must fail LOUD: the
   old paren-skip deleted h and said nothing (rc 0, no diagnostic), a silent
   drop on a destructive request. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc delete data=h(gennum=all);
run;
