/* BUG-updateinnestedopts: Statements Reference pp.315,351,355-356.
   Nested rename mappings and WHERE comparisons are not IN= options.
   Genuine IN= flags remain temporary, before or after nested options. */
data m; k=1; in=7; run;
data w; k=1; in=7; flag=7; run;
data t; k=1; x=20; run;

data renamed_master;
  update m(rename=(in=flag)) t; by k;
run;
proc print data=renamed_master noobs; run;
data filtered_master;
  update w(where=(in=flag)) t; by k;
run;
proc print data=filtered_master noobs; run;
data renamed_transaction;
  update t m(rename=(in=flag)); by k;
run;
proc print data=renamed_transaction noobs; run;
data filtered_transaction;
  update t w(where=(in=flag)); by k;
run;
proc print data=filtered_transaction noobs; run;

data flags_after;
  update m(rename=(in=flag) in=im) t(in=it); by k;
  fm=im; ft=it;
run;
proc print data=flags_after noobs; run;
data flags_before;
  update t(in=im) m(in=it rename=(in=flag)); by k;
  fm=im; ft=it;
run;
proc print data=flags_before noobs; run;
data where_after;
  update w(where=((in=flag)) in=im) t(in=it); by k;
  fm=im; ft=it;
run;
proc print data=where_after noobs; run;
data where_before;
  update t(in=im) w(in=it where=((in=flag))); by k;
  fm=im; ft=it;
run;
proc print data=where_before noobs; run;
