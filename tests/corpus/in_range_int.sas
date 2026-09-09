/* BUG-inrangecontinuous: an IN range M:N enumerates the INTEGERS M..N
   (Language Reference: Concepts p.128) — it is NOT a continuous interval, so 2.5 in (1:3) is 0.
   Integer-valued membership, boundaries, negative bounds, and mixed
   range+singleton lists are unchanged. */
data _null_;
  a1 = (2.5 in (1:3));    /* 0 — 2.5 is not one of 1,2,3 */
  a2 = (3 in (1:3));      /* 1 */
  a3 = (1 in (1:5));      /* 1 (boundary) */
  a4 = (5 in (1:5));      /* 1 (boundary) */
  a5 = (6 in (1:5));      /* 0 */
  a6 = (-2 in (-3:0));    /* 1 (negative-integer range) */
  a7 = (-2.5 in (-3:0));  /* 0 — in the interval but not an integer */
  a8 = (2 in (1:3, 7, 9:10));  /* 1 (mixed list, first range) */
  a9 = (7 in (1:3, 7, 9:10));  /* 1 (mixed list, singleton) */
  a10 = (10 in (1:3, 7, 9:10));/* 1 (mixed list, second range) */
  a11 = (8 in (1:3, 7, 9:10)); /* 0 (mixed list, gap) */
  a12 = (4 not in (1:3)); /* 1 */
  a13 = (2.5 not in (1:3));/* 1 */
  put a1= a2= a3= a4= a5= a6= a7=;
  put a8= a9= a10= a11= a12= a13=;
run;
