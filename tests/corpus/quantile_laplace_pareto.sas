/* GAP-quantiledists (doc-finder tick140): LAPLACE and PARETO for the
   CDF/PDF/QUANTILE family, closed forms per the SAS 9.4 reference.
   LAPLACE(0,1): cdf(-1)=e^-1/2, quantile(0.9)=-ln(0.2); PARETO(a,k):
   cdf=1-(k/x)^a, quantile=k*(1-p)^(-1/a). Roundtrips included. */
data _null_;
  l1=cdf('LAPLACE',-1);            /* 0.5*exp(-1)   */
  l2=cdf('LAPLACE',1);             /* 1-0.5*exp(-1) */
  lp=pdf('LAPLACE',0);             /* 1/2           */
  lq=quantile('LAPLACE',0.9);      /* -ln(0.2)      */
  lrt=quantile('LAPLACE',cdf('LAPLACE',-1)); /* roundtrip = -1 */
  put l1= l2= lp= lq= lrt=;
  ls=cdf('LAPLACE',8,2,3);         /* 1-0.5*exp(-2) */
  lsq=quantile('LAPLACE',0.9323323583816937,2,3); /* = 8 */
  put ls= lsq=;
  p1=cdf('PARETO',2,2);            /* 1-(1/2)^2 = 0.75 */
  pp=pdf('PARETO',2,2);            /* (2/2)*(1/2)^2 = 0.25 */
  pq=quantile('PARETO',0.75,2);    /* = 2 */
  prt=quantile('PARETO',cdf('PARETO',4,3,2),3,2); /* roundtrip = 4 */
  put p1= pp= pq= prt=;
  pz=cdf('PARETO',0.5,2);          /* x < k → 0 */
  put pz=;
run;
