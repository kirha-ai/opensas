/* BUG-substrneglen: SUBSTR (read direction) with a NONPOSITIVE length (zero or
   negative) is invalid in SAS 9.4 — it logs a NOTE (3rd arg invalid) and returns
   the REMAINDER from the position to the end (NOT ""). Ref: SAS 9.4 Functions
   Reference, SUBSTRN comparison table (p.1535, "length nonpositive" row).
   Also covers the pos<1 + neg-length combo: the invalid position wins and the
   whole remainder is returned consistently. */
data _null_;
  a = substr('hello', 2, -1);   /* neg length: remainder from pos 2 -> ello  */
  b = substr('hello', 2, 0);    /* zero length: remainder from pos 2 -> ello  */
  c = substr('hello', 3, -5);   /* neg length: remainder from pos 3 -> llo    */
  d = substr('hello', 0, -1);   /* pos<1 AND neg length: whole remainder -> hello */
  e = substr('hello', 2, 3);    /* positive length unchanged            -> ell  */
  put "a=[" a "]";
  put "b=[" b "]";
  put "c=[" c "]";
  put "d=[" d "]";
  put "e=[" e "]";
run;
