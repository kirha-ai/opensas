/* SUBSTR-posclamp: SUBSTR (read direction) with a NONPOSITIVE start position is
   invalid in SAS 9.4 — it logs a NOTE (2nd arg invalid) and returns the WHOLE
   remainder from the clamped start to the end, IGNORING the length argument.
   This is deliberately UNLIKE SUBSTRN (begins at char 1 with length reduced).
   Ref: SAS 9.4 Functions Reference, SUBSTRN comparison table (p.1535). */
data _null_;
  a = substr('hello', 0, 2);    /* start<1: whole remainder, length ignored -> hello */
  b = substr('hello', -1, 3);   /* start<1: whole remainder            -> hello */
  c = substr('hello', 0);       /* start<1, no length: whole remainder -> hello */
  d = substr('hello', 3, 2);    /* valid position unchanged            -> ll    */
  put "a=[" a "]";
  put "b=[" b "]";
  put "c=[" c "]";
  put "d=[" d "]";
run;
