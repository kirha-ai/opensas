/* PERF-arraydeclquad + PERF-setinflagquad: drops/keeps/retained membership is
   hash-backed (was a linear scan per PDV var per row — O(N²) decl for a
   _temporary_ array of N) and setInFlags early-outs with no in= var. Pure
   optimization — behavior must be byte-identical: exact case-insensitive
   match, pfx: wildcard fallback, in=/end= flags, temporary elems dropped. */
data d1; do i = 1 to 2; x = i; output; end; run;
data d2; do i = 3 to 4; x = i; output; end; run;

data w;
  set d1(in=from1) d2 end=last;
  array t[3] _temporary_ (7 8 9);
  s = t[1] + t[2] + t[3] + x;
  put x= from1= last= s=;
run;

/* wildcard drop keeps the linear prefix path; case-insensitive exact drop */
data p;
  array q[3] q1-q3 (1 2 3);
  KEEPME = q1 + q2 + q3;
  Gone = 99;
  drop q: gone;
  put keepme=;
run;

/* keep= of a retained set: only the named vars survive, mixed case */
data r;
  retain Alpha 5 beta 10 gamma 15;
  keep ALPHA GAMMA;
  put alpha= gamma=;
  output;
run;
