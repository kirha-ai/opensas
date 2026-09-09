/* BUG-mathoverflowinf: float overflow must yield a genuine SAS missing
   (MISSING()=1, x=. true), not a live ±inf. SAS has no infinity. */
data _null_;
  x = exp(710);
  xeq = (x = .); xm = missing(x);
  put x= xeq= xm=;
  d = divide(1, 0);
  deq = (d = .); dm = missing(d);
  put d= deq= dm=;
  g = gamma(200);
  geq = (g = .); gm = missing(g);
  put g= geq= gm=;
  /* non-overflow control: unchanged */
  c = exp(2);
  ceq = (c = .); cm = missing(c);
  put c= ceq= cm=;
run;
