/* PERF-inlist: eval-time membership-set for all-literal IN / NOT-IN chains.
   Proves CORRECTNESS (not speed): each chain is desugared to an OR/AND chain,
   recognized once at eval time, then probed per row. Covers an optimized IN
   (>=8 numeric literals, hits + misses), an optimized NOT IN, and bail cases
   (a short <8 list and a char-var IN) that must still return the right answer
   via the unchanged OR-chain. */
data _null_;
  do x = 1 to 12;
    /* 8 numeric literals -> optimized IN membership set */
    hit = x in (2, 3, 5, 7, 11, 13, 17, 19);
    /* 8 numeric literals -> optimized NOT IN (and-of-ne, negated set) */
    big = x not in (1, 2, 3, 4, 5, 6, 7, 8);
    put "x=" x "hit=" hit "big=" big;
  end;
  /* bail: only 3 literals (< IN_SET_MIN) -> OR-chain, still correct */
  y = 5;
  short = y in (4, 5, 6);
  put "short=" short;
  /* bail: char-var IN (string literals, not .num) -> OR-chain, still correct */
  c = "B";
  cin = c in ("A", "B", "C");
  put "cin=" cin;
run;
