/* BUG-scanmmod: SCAN's 'm' modifier (4th arg) was ignored — the function always
   merged runs of delimiters (tokenizeAny) and never read the modifier arg. With
   'm', consecutive and edge delimiters each yield a NULL token, so token indexing
   shifts. Guard: default (no 'm') still merges delimiter runs. */
data _null_;
  d  = scan('a..b..c', 2, '.');        /* b (merge) */
  m2 = scan('a..b..c', 2, '.', 'm');   /* '' (empty token) */
  m3 = scan('a..b..c', 3, '.', 'm');   /* b */
  ml = scan('.x.y', 1, '.', 'm');      /* '' (leading delim) */
  mn = scan('a..b', -1, '.', 'm');     /* b (last token) */
  put 'default=[' d ']';
  put 'm2=[' m2 ']';
  put 'm3=[' m3 ']';
  put 'mlead=[' ml ']';
  put 'mneg=[' mn ']';
run;
