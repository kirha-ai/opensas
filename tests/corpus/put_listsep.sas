data _null_;
  length k $20;
  k='Joyce'; n=42;
  put k 'removed from hash object';  /* Language Reference: Concepts p.621: Joyce removed from hash object */
  put n 'lit';                       /* a list value owes the literal one blank */
  put 'lit' n;                       /* a literal owes nothing AFTER itself */
  put '[' n 5. ']';                  /* a formatted item fills its own field (putfmtblank) */
  put n 5. 'lit';                    /* a formatted predecessor owes no blank */
  put k= 'lit';                      /* named output is list-style: blank owed */
  put k n;
  put n k;
run;
