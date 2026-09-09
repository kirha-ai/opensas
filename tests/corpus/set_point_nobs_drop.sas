/* BUG-setpointtemp: the SET point=/nobs= vars are TEMPORARY control vars — SAS
   drops them from the output schema (only <have>'s vars survive), while POINT=
   random access still reads obs p and nobs= still bounds the loop up front.
   want below must have columns k x ONLY (no p, no n). A control name that is
   ALSO a genuine input column is NOT dropped (want2 keeps p; n still goes).
   POINT= + BY is illegal SAS: the bad step ERRORs and prints nothing (it is
   last — an errored step poisons the rest of the run).
   expect-rc: 1 */
data have;
  input k x;
  datalines;
1 10
2 20
3 30
;
run;
data want;
  do p = 1 to n;
    set have point=p nobs=n;
    output;
  end;
  stop;
run;
proc print data=want; run;
data have2;
  input p x;
  datalines;
2 100
1 200
3 300
;
run;
data want2;
  p = 2;
  set have2 point=p nobs=n;
  output;
  stop;
run;
proc print data=want2; run;
data bad;
  set have point=p;
  by k;
run;
