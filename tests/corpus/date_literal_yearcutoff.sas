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
/* lrcon p.142's own example program. NOTE on literal timing: a global
   statement flushes with the FOLLOWING step at its run; boundary, so this
   step's literals were lexed under the prior window; '02' maps to 2002 under
   BOTH spans [1926,2025] and [1950,2049], so the doc's value holds regardless.
   The informat read (exec time) proves cutoff=1950 is in effect: 49 -> 2049. */
options yearcutoff=1950;
data _null_;
  a='26oct02'd;
  put a=;
  b=input('01jan49', date9.);
  put b year4.;
run;
