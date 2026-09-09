/* BUG-substrlvalue-declared: an omitted-length SUBSTR lvalue spans to the
   target's DECLARED width (SAS 9.4), replacing chars to the declared end. */
data _null_;
  length t s $5;
  t='ab';    substr(t,2)='XXXX'; put "omitted=[" t "]";    /* [aXXXX] — 4 chars replaced, not 1 */
  s='ab';    substr(s,2)='Z';    put "shortrepl=[" s "]";  /* [aZ   ] — window spans declared, tail blank */
  u='ab';    substr(u,2,1)='X';  put "explicit=" u;        /* aX — EXPLICIT length 1, unchanged */
  w='abcde'; substr(w,2)='ZZ';   put "full=" w;            /* aZZde — short repl leaves the tail */
run;
