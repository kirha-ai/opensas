data s; input reg $ prod $ amt; datalines;
E A 10
E B 20
W A 30
W B 40
;
run;
/* GAP-tabdenom: PCTSUM<prod> = cell share of the prod COLUMN subtotal (the
   <dim> clause holds prod fixed: E×A 10/40=25, W×B 40/60≈66.67); PCTSUM<reg> =
   share of the reg ROW subtotal (W×A 30/70≈42.86). Used to die with the bogus
   "unknown statistic 'prod'". A later block in this fixture reaches a
   documented PROC TABULATE feature opensas does not implement, which is a GAP
   and exits 2 under D-009 — not a user error.
   expect-rc: 2 */
proc tabulate data=s; class reg prod; var amt;
  table reg, prod*amt*(sum pctsum<prod> pctsum<reg>); run;
/* PCTN<reg> on the no-analysis-var count path: each cell 1 of 2 in its row → 50
   (grand-total pctn would be 25). */
proc tabulate data=s; class reg prod;
  table reg, prod*(n pctn<reg>); run;
/* 1-way degenerate: <reg> holds the only crossing dimension fixed → 100. */
proc tabulate data=s; class reg prod; var amt;
  table reg, amt*(sum pctsum<reg>); run;
/* A denominator outside the TABLE crossing fails loud naming the PCTN/PCTSUM
   denominator — stderr, exit 2, no table below. */
proc tabulate data=s; class reg prod; var amt;
  table reg, prod*amt*pctsum<amt>; run;
