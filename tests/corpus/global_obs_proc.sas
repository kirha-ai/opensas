/* BUG-globalobsproc: the global `options obs=/firstobs=` default range bounds
   PROC input reads too, not just DATA-step SET (opensas read PROC inputs with
   input=false → N=10/Sum=55 where SAS gives N=3/Sum=9). A per-dataset
   (obs=)/(firstobs=) still overrides; obs=max restores all-obs. */
data base;
  do id = 1 to 10;
    output;
  end;
run;
options obs=3;
proc means data=base;
  var id;
run;
proc print data=base noobs; run;
options firstobs=2 obs=4;
proc means data=base;
  var id;
run;
proc print data=base noobs; run;
/* per-dataset (obs=) overrides the global bound on the PROC read */
proc print data=base(obs=6) noobs; run;
/* obs=max restores all-obs for later PROCs */
options obs=max firstobs=1;
proc print data=base noobs; run;
