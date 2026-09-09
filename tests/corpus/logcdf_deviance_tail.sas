/* BUG-logxdftail + BUG-devianceeps (tick244 F1/F2):
  LOGCDF/LOGSDF/LOGPDF deep tails are now computed in log-space (was: log of an
  underflowed CDF/PDF -> missing); DEVIANCE clamps its boundary args with the
  documented epsilon (SAS 9.4 functions ref pp.614-618: default 1e-12, floored
  to 1e-12, capped at 0.01; every distribution except NORMAL). */
data _null_;
  /* --- log-space tails (hand-verified vs mpmath 50-digit values) ---
     a1: log Phi(-10). Phi(-10)=7.619853024e-24, ln = ln(7.619853024)-24*ln(10)
       = 2.0307570 - 55.2620422 = -53.23128515051247 (mpmath logQ(10)).
     a2: log Q(10) — the symmetric right tail, identical value.
     a3: log Phi(-38) = -38^2/2 - ln(38*sqrt(2pi)) + ln(1 - 1/38^2 + ...)
       = -722 - 4.556307 - 0.000692 = -726.5572160188201 (mpmath).
     a4: logpdf = -39^2/2 - 0.5*ln(2pi) = -760.5 - 0.9189385332046727
       = -761.4189385332047.                                            */
  a1=logcdf('NORMAL',-10);
  a2=logsdf('NORMAL',10);
  a3=logcdf('NORMAL',-38);
  a4=logpdf('NORMAL',39);
  put a1= a2= a3= a4=;
  /* closed-form log tails: expo sdf=-x/lam=-800; weibull sdf=-(x/lam)^a=-1000;
     laplace cdf (z=-800) = z-ln(2) = -800-0.6931471805599453;
     pareto sdf = a*ln(k/x) = 2*ln(1e-200) = -400*ln(10).                 */
  b1=logsdf('EXPONENTIAL',800);
  b2=logsdf('WEIBULL',1000,1);
  b3=logcdf('LAPLACE',-800);
  b4=logsdf('PARETO',1e200,2,1);
  put b1= b2= b3= b4=;
  /* mid-range: byte-identical to log of the direct value */
  m1=logcdf('NORMAL',0);   /* ln(0.5)   */
  m2=logpdf('NORMAL',1);   /* -0.5 - 0.5*ln(2pi) */
  m3=deviance('POISSON',2,1); /* 2*(2*ln(2)-1), no clamp in range */
  put m1= m2= m3=;
  /* --- DEVIANCE epsilon clamps (doc pp.615-617) ---
     d1: BERN p=0 -> eps: -2*ln(1e-12) = 24*ln(10) = 55.262042231857096.
     d2: BERN p=1e-13 < eps -> eps: same value.
     d3: BINO mu=0 -> n*eps=1e-11: 2*(10*ln(10/1e-11)+0) = 20*ln(1e12)
       = 552.620422318571.
     d4: GAMMA y=0 -> eps: 2*((eps-5)/5 - ln(eps/5)) = 2*(ln(5e12)-1)
       = 2*(29.24045902836265-1) = 56.48091805672569.
     d5: POISSON mu=0 -> eps: 2*(3*ln(3/eps)-(3-eps)) = 166.37780042758195.  */
  d1=deviance('BERN',1,0);
  d2=deviance('BERN',1,1e-13);
  d3=deviance('BINO',10,0,10);
  d4=deviance('GAMMA',0,5);
  d5=deviance('POISSON',3,0);
  put d1= d2= d3= d4= d5=;
  /* epsilon itself is clamped to [1e-12, 0.01]; NORMAL has no epsilon.
     e1: eps=1e-9 honored: -2*ln(1e-9) = 18*ln(10) = 41.44653167389282.
     e2: eps=5 -> capped 0.01: -2*ln(0.01) = 4*ln(10) = 9.210340371976182.
     e3: POISSON with eps=1e-6: 2*(3*ln(3e6)-(3-1e-6)) = 83.48473907979431.
     e4: NORMAL ignores everything: (5-3)^2 = 4.                            */
  e1=deviance('BERN',1,0,1e-9);
  e2=deviance('BERN',1,0,5);
  e3=deviance('POISSON',3,0,1e-6);
  e4=deviance('NORMAL',5,3);
  put e1= e2= e3= e4=;
run;
