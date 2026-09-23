/* BUG-date-literal-2digityear: 'ddMMMyy'd / 'ddMMMyy:hh:mm:ss'dt literals honor
   YEARCUTOFF (lrcon printed pp.141-142; default 1926, span 1926-2025) through
   the SAME format.expandYear the informats use — before the fix, a literal
   year read verbatim ('26oct50'd was year 50 AD) at rc 0. A 4-digit year is
   verbatim. Invented data. */
data _null_;
  a='26oct02'd;   /* 1902 < 1926 -> 2002: the doc's example value 15639 */
  put a=;
  b='26oct50'd;   /* 1950 */
  put b=;
  c='26oct99'd;   /* 1999 */
  put c=;
  d='26oct25'd;   /* 1925 < 1926 -> 2025 */
  put d=;
  e='26oct26'd;   /* span start: 1926 */
  put e=;
  f='26oct02:00:00:00'dt;  /* datetime literal inherits: 26OCT2002 midnight */
  put f=;
  g='26oct2002'd; /* 4-digit year: verbatim */
  put g=;
run;
/* lrcon p.142's own example program. NOTE on literal timing
   (BUG-yearcutoffflushorder): the OPTIONS statement flushes together with the
   step it precedes (one run; blob), and its value is wired BEFORE that step's
   tokens exist — so the step's '…'d literal AND its exec-time informat read
   share the new [1950,2049] window. ('02' maps to 2002 under both spans, so
   the doc's value holds regardless.) c pins the flip: 49 reads 2049, where
   the old tokenize-first order lexed it under the PRIOR 1926 window as 1949
   while the same step's informat read 2049 — one step, two windows. */
options yearcutoff=1950;
data _null_;
  a='26oct02'd;
  put a=;
  b=input('01jan49', date9.);
  put b year4.;
  c='26oct49'd;   /* same flush: lexed under THIS statement's 1950 → 2049 */
  put c year4.;
run;
