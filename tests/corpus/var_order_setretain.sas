/* BUG-varorder-setretain: a RETAIN (or sum statement `v + expr;`) that textually
   PRECEDES the SET establishes its vars in the PDV BEFORE the input dataset's
   columns — SAS orders columns by first mention, and RETAIN-before-SET is the
   canonical column-reorder idiom. Values were already correct; only the ORDER was
   wrong (opensas put SET vars first). SET-first (retain/sum AFTER set) is unchanged.
   corpus-varorder. */
data src; input x y; datalines;
1 2
3 4
;
run;

/* RETAIN before SET → b a x y (b,a own the first slots, filled by assignment). */
data o1; retain b a; set src; a = x + 1; b = y + 1; run;
proc print data=o1 noobs; run;

/* sum statement before SET → s x y. */
data o2; s + 1; set src; run;
proc print data=o2 noobs; run;

/* sum statement AFTER SET → x y c (regression guard: stays last, as SAS orders it). */
data o3; set src; c + 1; run;
proc print data=o3 noobs; run;

/* RETAIN reordering EXISTING source columns → y x (retain names them first). */
data o4; retain y x; set src; run;
proc print data=o4 noobs; run;
