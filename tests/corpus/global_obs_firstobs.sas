/* BUG-globalobs: global options obs=/firstobs= bound every later input read
   (Language Reference: Concepts p.247). A per-dataset option overrides; obs=max resets.
   BUG-globalobsproc: the bound re-applies on the PROC's own input read, so
   printing sub2 (obs 2-4 of base) under firstobs=2 obs=4 shows sub2 obs 2-4
   (values 3,4) — SAS bounds EVERY read, DATA-step SET and PROC alike. */
data base;
  do id = 1 to 10;
    output;
  end;
run;
options obs=3;
data sub; set base; run;
proc print data=sub noobs; run;
options firstobs=2 obs=4;
data sub2; set base; run;
proc print data=sub2 noobs; run;
/* per-dataset (obs=) overrides the global bound */
data sub3; set base(obs=6); run;
proc print data=sub3 noobs; run;
/* obs=max restores all-obs */
options obs=max firstobs=1;
data whole; set base; run;
proc print data=whole noobs; run;
