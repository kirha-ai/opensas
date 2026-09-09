/* Phase-F correctness audit: known-answer regression guard for verified [x] funcs
   (stat inverses, bitwise, date alignment, descriptive stats). All values checked
   against the SAS Functions Dictionary. */
data _null_;
  a=probnorm(1.96); b=probit(0.975); c=tinv(0.975,10); d=finv(0.95,3,10); e=cinv(0.95,5);
  f=band(12,10); g=bxor(12,10); h=blshift(1,4);
  i=intnx("month","15jan2020"d,1,"e"); j=intck("month","15jan2020"d,"20mar2020"d);
  k=geomean(1,2,4); l=harmean(1,2,4); m=skewness(1,2,3,4,10); n=kurtosis(1,2,3,4,10);
  o=mad(1,2,3,4,100); p=mod(-7,3);
  put "probnorm=" a 10.7;
  put "probit=" b 10.6;
  put "tinv=" c 10.6;
  put "finv=" d 10.6;
  put "cinv=" e 10.5;
  put "band=" f;
  put "bxor=" g;
  put "blshift=" h;
  put "intnx_e=" i;
  put "intck=" j;
  put "geomean=" k 8.5;
  put "harmean=" l 8.5;
  put "skewness=" m 8.5;
  put "kurtosis=" n 8.5;
  put "mad=" o;
  put "mod_neg=" p;
run;
