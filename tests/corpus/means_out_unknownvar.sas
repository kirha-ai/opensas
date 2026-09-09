/* BUG-meansoutevarunknown: an unknown var inside an OUTPUT stat's (varlist)
   must FAIL LOUD (SAS 9.4: "Variable X not found") — it used to silently REMAP
   to the FIRST analysis variable, writing plausible stats of the WRONG column
   into a correctly-named output var at exit 0 (worst failure class).
   The legal forms must stay legal (all verified before the failing step):
   (a) stat=newname over the VAR list — newname is a NEW output var, not an
       input var reference;
   (b) a (varlist) var that exists in the dataset but is NOT in the VAR
       statement (LEGAL SAS: mb = mean(b));
   (c) stat(realvar)=name over an existing var, no VAR statement.
   Then (d) mean(nosuchvar)=m → ERROR: PROC MEANS: OUTPUT variable nosuchvar
   not in d (stderr; the step stops, od is never created, run aborts — the
   corpus diff is over stdout, which carries only (a)-(c)).
   expect-rc: 1 */
data d; input a b @@; datalines;
1 100 2 200 3 300
;
run;
/* (a) positional stat=name over the VAR list */
proc means data=d noprint; var a; output out=oa mean=m sum=s; run;
proc print data=oa noobs; run;
/* (b) b not in VAR but present in d — legal, mb = mean(b) = 200 */
proc means data=d noprint; var a; output out=ob mean(b)=mb; run;
proc print data=ob noobs; run;
/* (c) explicit existing var, default analysis set */
proc means data=d noprint; output out=oc mean(a)=ma; run;
proc print data=oc noobs; run;
/* (d) unknown var in the (varlist) → loud ERROR, nothing further runs */
proc means data=d noprint; var a; output out=od mean(nosuchvar)=m; run;
proc print data=od noobs; run;
