/* CALL RANNOR/RANEXP/RANCAU/RANTRI/RANPOI/RANBIN/RANGAM/RANTBL: draw one variate
   into the last arg, seed updated in place. Deterministic under SAS's Lehmer
   stream (16807). Phase-F-callbatch. */
data _null_;
  seed=123; call rannor(seed, xn); put "rannor=" xn 10.6;
  seed=123; call ranexp(seed, xe); put "ranexp=" xe 10.6;
  seed=123; call rancau(seed, xc); put "rancau=" xc 10.4;
  seed=123; call rantri(seed, 0.5, xt); put "rantri=" xt 10.6;
  seed=123; call ranpoi(seed, 5, xp); put "ranpoi=" xp;
  seed=123; call ranbin(seed, 100, 0.3, xb); put "ranbin=" xb;
  seed=123; call rangam(seed, 2, xg); put "rangam=" xg 10.6;
  seed=123; call rantbl(seed, 0.2, 0.3, 0.5, xtb); put "rantbl=" xtb;
run;
