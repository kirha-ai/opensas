/* GAP-vtabledisk fallout: WHERE is an ENGINE-level (pre-read) filter, so
   end=/first./last. reflect the FILTERED stream. As a subsetting-if desugar,
   the physically-last row (k=5, g=0) was discarded and `if last` never ran —
   exactly how a real XPT-export macro's CALL SYMPUT('nb') silently missed. */
data src;
  do k = 1 to 5;
    g = (k <= 3);
    output;
  end;
run;
data _null_;
  set src end=last;
  where g = 1;
  n + 1;
  put k= _n_=;
  if last then put 'lastk=' k 'n=' n;
run;
