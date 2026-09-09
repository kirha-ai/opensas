/* ISS-sqlremerge #37: `select * … group by … having col=min(col)` must remerge
   the group aggregate onto each detail row and keep only matching rows, not
   return every row via the plain select* fast-path. */
data t;
  length recid 8 epoch $12;
  input recid epoch $;
  datalines;
1 SCREENING
1 TREATMENT
2 TREATMENT
3 SCREENING
3 TREATMENT
;
run;
proc sql;
  create table res as select * from t group by recid having epoch=min(epoch);
quit;
proc print data=res noobs; run;
proc sql; select count(*) as nrows from res; quit;
