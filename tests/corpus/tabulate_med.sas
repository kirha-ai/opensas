/* BUG-tabulatemed (doc-finder tick242 #4/#5/#6):
   #4 1-way `all` COLUMN = the ROW-RESTRICTED subtotal (each row's own All),
      never the grand total on every row — mirrors the cross path.
   #5 each TABLE statement renders its OWN table (they used to merge silently
      when a later table added no new row var).
   #6 CLASS `/` options honored: /missing keeps the missing class level (N/SUM
      include it), /order= overrides the level order; unknown options fail loud.
   expect-rc: 2 */
data d;
  input a $ v;
  datalines;
x 10
x 20
y 30
;
run;

/* #4: cell(x,All)=30, cell(y,All)=30 — with no column class the All column
   duplicates the row's own stat (it used to show the grand 60 on both rows);
   the All Pctsum is the row share 50/50 (used to be 100/100). The v block
   renders ONLY its own Sum: per-element stat lists (GAP-tabulateforms #7,
   Procedures Guide p.2548 concatenation) — the old union gave v the All
   block's Pctsum too, an unrequested column. */
proc tabulate data=d; class a; var v; table a, v*sum all*v*(sum pctsum); run;

/* #5: two TABLE statements → two separate tables. */
proc tabulate data=d; class a; var v;
  table a, v*sum;
  table a, v*mean;
run;

/* #6: `/ missing` keeps the missing-class obs as a "." level (N includes it);
   without it the obs is excluded (BUG-tabulatemissclass fixture pins that). */
data m;
  input g v;
  datalines;
1 10
. 20
2 30
;
run;
proc tabulate data=m; class g / missing; var v; table g, v*(n sum); run;

/* #6: `/ order=freq` on the CLASS statement orders the levels by descending
   count — b(3), c(2), a(1) — overriding the internal default. */
data o;
  input g $ v;
  datalines;
a 1
b 2
b 3
c 4
b 5
c 6
;
run;
proc tabulate data=o; class g / order=freq; var v; table g, v*sum; run;

/* #6: an unknown CLASS `/` option fails loud (stderr UNSUPPORTED, exit 2) and
   prints nothing more — `/mlf` (multilabel) fails loud the same way. If the
   silent swallow regresses, a bogus table would append below and mismatch. */
proc tabulate data=d; class a / zonk; var v; table a, v*sum; run;
