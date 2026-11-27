/* Complete non-graph numerical analysis from S154 physical p.7738.
   Its PLOT request remains in the unchanged temporary composite reference;
   this permanent case owns the full four-scenario listing contract. */
proc power;
 onesamplemeans mean=5 10 ntotal=150 stddev=30 50 power=.;
run;
