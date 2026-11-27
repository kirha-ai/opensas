/* S154 physical p.7745: PLOTONLY suppresses analysis listings. POWER uses
   scenario values, not an implicit DATA= input. The visible exact-power
   quantity is the independent SAS 15.4 COMMON018 reference value. */
proc power plotonly;
 twosamplemeans meandiff=2 stddev=3 alpha=0.05 ntotal=100 power=.;
run;
proc power;
 twosamplemeans meandiff=2 stddev=3 ntotal=100 power=.;
run;
