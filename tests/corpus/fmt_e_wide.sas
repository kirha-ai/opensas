data _null_;
  x = 123.456;
  put x e12.;    /* narrow control: unchanged working width */
  put x e26.;    /* was rc=134 SIGABRT (BUG-efmtcrash) — now renders */
  put x e32.;    /* max numeric width — renders */
  y = 1;
  put y e26.;
run;
