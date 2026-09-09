data _null_;
  /* BUG-noncentralinverse: nc must shift the quantile right of central
     (scipy: nct.ppf(0.95,10,2)=4.3574751787, ncf.ppf(0.95,3,10,2)=5.9527056417,
      ncx2.ppf(0.95,10,2)=21.8055148281, nct.ppf(0.05,10,-2)=-4.3574751787) */
  tn=tinv(0.95,10,2);  tc=tinv(0.95,10);
  fn=finv(0.95,3,10,2); fc=finv(0.95,3,10);
  cn=cinv(0.95,10,2);  cc=cinv(0.95,10);
  tneg=tinv(0.05,10,-2);
  put "tinv_nc=" tn tc;
  put "finv_nc=" fn fc;
  put "cinv_nc=" cn cc;
  put "tinv_neg=" tneg;
  /* round-trip: forward noncentral CDF recovers p */
  rt1=probt(tn,10,2); rt2=probf(fn,3,10,2); rt3=probchi(cn,10,2);
  put "rt=" rt1 rt2 rt3;
  /* nc=0 explicit equals omitted (central path) */
  z1=(tinv(0.975,10,0)=tinv(0.975,10)); z2=(cinv(0.95,10,0)=cinv(0.95,10));
  put "zero=" z1 z2;
run;
