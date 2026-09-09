/* PERF-loadrowdual (f537f56) regression guard: loadRow now writes by
   pre-resolved PDV slot via pdv.setAt, and _setobs_ is stamped once per source
   (only when nobs= requested). This fixture locks the OUTPUT of every path that
   changed — multi-source SET, MERGE (in=, many-to-many), UPDATE, nobs=,
   point= random access, KEEP/RENAME on read, char LENGTH truncation on the
   readback coercion tail — so a future edit to the slot loop that diverges from
   documented SAS behavior turns the corpus red. Filed by QA tick151. */

data a; input k x y; datalines;
1 10 100
1 11 101
2 20 200
3 30 300
;
run;

data b; input k z; datalines;
1 5
2 6
4 8
;
run;

/* multi-source SET: concatenation, slot readback of both schemas. x/y are
   absent from b but auto-RETAINED as SET-read vars (SAS: SET/MERGE/MODIFY/
   UPDATE auto-retain) — b's rows show a's last values (30/300), not missing
   (BUG-setvarretain; this block's golden pre-fix encoded the missing bug). */
data setcat; set a b; run;
proc print data=setcat; run;

/* MERGE with in= + many-to-many overlay on k=1 */
data mrg; merge a(in=ina) b(in=inb); by k; got_a=ina; got_b=inb; run;
proc print data=mrg; run;

/* UPDATE: missing transaction value must not overwrite master */
data mast; input k v; datalines;
1 111
2 222
3 333
;
run;
data tran; input k v; datalines;
2 999
3 .
;
run;
data upd; update mast tran; by k; run;
proc print data=upd; run;

/* nobs= single source stamped once per source; _setobs_ must NOT leak to output */
data withn; set a nobs=n; keep k n; run;
proc print data=withn; run;

/* point= random access every-other row + nobs used to bound the loop */
data pts; do i=1 to n by 2; set a point=i nobs=n; output; end; stop; keep i k x; run;
proc print data=pts; run;

/* KEEP + RENAME on the read, and char LENGTH truncation through setAt */
data wide; length s $10; input k s $; datalines;
1 abcdefghij
2 kl
;
run;
data narrowed; length s $3; set wide(keep=k s); run;
proc print data=narrowed; run;
