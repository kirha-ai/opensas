/* BUG-quantilediscrete (doc-finder tick140): QUANTILE/SQUANTILE for POISSON
   and BINOMIAL must return the documented integer quantile, not missing.
   SAS 9.4 reference: QPOIS=3 QBIN=5 SQPOIS=3 SQBIN=5 QTIE=0 QRT=2 */
data _null_;
  qpois=quantile('POISSON',0.857,2);
  qbin=quantile('BINOMIAL',0.5,0.5,10);
  sqpois=squantile('POISSON',0.143,2);
  sqbin=squantile('BINOMIAL',0.5,0.5,10);
  qtie=quantile('BINOMIAL',0.25,0.5,2);   /* exact CDF tie at 0 */
  qrt=quantile('POISSON',cdf('POISSON',2,2),2); /* roundtrip */
  put "QPOIS=" qpois " QBIN=" qbin " SQPOIS=" sqpois " SQBIN=" sqbin;
  put "QTIE=" qtie " QRT=" qrt;
run;
