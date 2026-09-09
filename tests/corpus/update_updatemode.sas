/* GAP-updatemode (split of GAP-mergeby-batch, doc-finder tick128):
   UPDATEMODE= on the UPDATE statement. Default MISSINGCHECK keeps the master
   when the transaction value is a plain missing; NOMISSINGCHECK applies the
   missing (overwrites). Special missings (.A) overwrite in BOTH modes. */
data master;
  input id x y;
  datalines;
1 10 100
2 20 200
3 30 300
;
run;
data trans;
  input id x y;
  datalines;
2 . 250
3 35 .a
;
run;
data d_default;
  update master trans;
  by id;
run;
proc print data=d_default noobs; run;
data d_nomiss;
  update master trans updatemode=nomissingcheck;
  by id;
run;
proc print data=d_nomiss noobs; run;
