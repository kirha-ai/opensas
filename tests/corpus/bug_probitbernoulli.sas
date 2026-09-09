/* BUG-probitbernoulli (tick218): Halley-refined PROBIT to full double
   precision + BERNOULLI wired into CDF/PDF/QUANTILE. */
data _null_;
  p1=probit(0.975);           /* SAS: 1.959963984540054          */
  p2=probit(0.025);
  qn=quantile('NORMAL',0.975);
  ql=quantile('LOGNORMAL',0.975);
  cb0=cdf('bernoulli',0,0.3);   /* 1-p = 0.7 */
  cb1=cdf('bernoulli',1,0.3);   /* 1         */
  cbm=cdf('bernoulli',-1,0.3);  /* 0         */
  pb0=pdf('bernoulli',0,0.3);   /* 0.7 */
  pb1=pdf('bernoulli',1,0.3);   /* 0.3 */
  pb2=pdf('bernoulli',2,0.3);   /* 0   */
  qb0=quantile('bernoulli',0.5,0.3);  /* <= 1-p -> 0 */
  qb1=quantile('bernoulli',0.8,0.3);  /* >  1-p -> 1 */
  bad=cdf('bernoulli',0,1.5);         /* p out of [0,1] -> missing */
  put "probit=" p1 p2;
  put "quant_norm=" qn ql;
  put "bern_cdf=" cb0 cb1 cbm;
  put "bern_pdf=" pb0 pb1 pb2;
  put "bern_quant=" qb0 qb1;
  put "bern_bad=" bad;
run;
