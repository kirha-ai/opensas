/* BUG-proctypoexits2 — the rc-2 twin of rc_sort_unknownopt_typo.sas: FORCE
   is a documented SAS 9.4 PROC SORT option (Procedures Guide, 7th ed.,
   printed pp. 2406-2408) that opensas does not implement — an opensas gap,
   exit 2 ("file an opensas issue"), byte-identical UNSUPPORTED message.
   If someone flips the catch-all wholesale to rc 1, this fixture reds.
   expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc sort data=h force;
  by x;
run;
