/* BUG-contentsfmtcol regression lock (tick156 QA): OUT= FORMAT holds the
   uppercase NAME only ($ kept for char formats, blank for a nameless w.d
   format), with width/decimals split into FORMATL/FORMATD (0 when absent).
   Covers char $CHAR, nameless 5., named-no-width BEST., decimals COMMA. */
data d;
  format nm $char10. raw 5. plain best. amt comma12.2;
  nm='hi'; raw=1; plain=2; amt=3;
run;
proc contents data=d out=meta noprint; run;
proc sort data=meta; by name; run;
proc print data=meta noobs; var name type format formatl formatd; run;
