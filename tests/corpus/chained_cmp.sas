/* SAS chained comparisons: `a op b op c` means (a op b) AND (b op c) — not the
   C-style ((a op b)) op c, whose 0/1 result made every low<=x<=high window
   check near-always-true (QA-chaincmp; inflated AE via an EPOCH macro's
   SESTDTM<=dtm<=SEENDTM). */
data d;
  a = (5 <= 3 <= 10);      /* (5<=3) and (3<=10) = 0 */
  b = (1 <= 2 <= 3);       /* 1 */
  c = (10 < 20 < 15);      /* 0 */
  e = (3 = 3 = 3);         /* 1 */
  f = (0 lt 5 le 4);       /* 0 */
  g = (1 <= 2 <= 3 <= 4);  /* longer chain: 1 */
  h = (1 <= 5 <= 3 <= 9);  /* middle link fails: 0 */
  i = ("a" <= "b" <= "c"); /* char chain: 1 */
  j = (2 < 3) + 1;         /* plain comparison in arithmetic unaffected: 2 */
  k = (1 < 2 and 5 < 4);   /* explicit AND unaffected: 0 */
  put a= b= c= e= f= g= h= i= j= k=;
run;
