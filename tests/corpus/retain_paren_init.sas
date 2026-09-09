/* GAP-retainpareninit: parenthesised RETAIN initial values distribute
   POSITIONALLY over the preceding element list — `retain a b c (0)` inits
   only a=0 (b,c stay missing), `retain v1-v3 (1 2 3)` binds 1→v1, 2→v2,
   3→v3, `retain m ('JAN')` char-inits m. The BARE form is unchanged: a
   single trailing value still seeds ALL vars (GH#51 control: x=y=5). */
data t;
  retain a b c (0);
  retain v1-v3 (1 2 3);
  retain m ('JAN');
  retain x y 5;
  output;
run;

proc print data=t; run;
