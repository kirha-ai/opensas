/* Under H0 the exact continuous test rejects with alpha, even at N=2.
   S154 physical p.7887 requires N>=2 for ONESAMPLEMEANS TEST=T. */
proc power;
 onesamplemeans mean=0 stddev=3 ntotal=2 power=.;
run;
proc power;
 onesamplemeans mean=0 stddev=3 ntotal=3 power=.;
run;
