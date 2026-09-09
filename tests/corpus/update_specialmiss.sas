/* BUG-updatespecialmiss (Language Reference: Concepts p.586): a PLAIN `.` in the transaction keeps the
   master value, but a SPECIAL missing (.A–.Z / ._) MUST overwrite it — the
   doc-sanctioned way to blank a master value. Old any-NaN test swallowed all
   three as no-change (kept 100/200/300). Shared applyTrans, so MODIFY-BY too. */
data master;
  input id v;
  datalines;
1 100
2 200
3 300
;
run;
data trans;
  input id v;
  datalines;
1 .
2 .A
3 .Z
;
run;
data out;
  update master trans;
  by id;
run;
proc print data=out noobs; run;
