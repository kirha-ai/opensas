* GAP-distsilentmiss: WEIBULL/GEOMETRIC/NEGBINOMIAL/HYPERGEOMETRIC for the
  CDF/PDF/QUANTILE family + noncentrality wired through. Three anchor calls
  keep the arguments printed in Functions and CALL Routines: Reference (CDF
  entry) because the manual's printed result is the oracle - the rest are
  closed-form checks. ;
data _null_;
  w1=cdf('WEIBULL',1,2);          /* manual anchor: 0.63212 (lambda defaults 1) */
  w2=cdf('WEIBULL',1.5,2,3);      /* 1-exp(-(1.5/3)^2)                        */
  wp=pdf('WEIBULL',1.5,2,3);
  wq=quantile('WEIBULL',0.5,2,3); /* 3*sqrt(ln2)                            */
  put w1= w2= wp= wq=;
  g1=cdf('GEOMETRIC',3,0.25);     /* 1-0.75^4   */
  gp=pdf('GEOMETRIC',3,0.25);     /* 0.25*0.75^3 */
  gq=quantile('GEOMETRIC',0.9,0.25);
  put g1= gp= gq=;
  n1=cdf('NEGB',1,0.5,2);         /* manual anchor: 0.5 */
  np=pdf('NEGBINOMIAL',2,0.5,3);
  nq=quantile('NEGBINOMIAL',0.5,0.5,3);
  put n1= np= nq=;
  h1=cdf('HYPER',2,200,50,10);    /* manual anchor: 0.52367 */
  hp=pdf('HYPERGEOMETRIC',1,10,4,3);
  hq=quantile('HYPERGEOMETRIC',0.5,10,4,3);
  put h1= hp= hq=;
  /* noncentrality parm: CDF family now matches the PROB* noncentral paths */
  cc=(cdf('CHISQUARE',7,3,2)=probchi(7,3,2));
  cf=(cdf('F',2.5,3,20,4)=probf(2.5,3,20,4));
  ct=(cdf('T',1.5,10,1)=probt(1.5,10,1));
  put cc= cf= ct=;
  /* right-tail/log siblings ride the same extended code path */
  sw=sdf('WEIBULL',1.5,2,3);
  lg=logcdf('GEOMETRIC',3,0.25);
  put sw= lg=;
run;
data _null_;
  call streaminit(42);
  rw=rand('WEIBULL',2,3);
  rg=rand('GEOMETRIC',0.25);
  rn=rand('NEGBINOMIAL',0.5,3);
  rh=rand('HYPERGEOMETRIC',10,4,3);
  put rw= rg= rn= rh=;
run;
