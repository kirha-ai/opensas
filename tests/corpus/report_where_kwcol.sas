data a; input by v; datalines;
1 10
2 20
3 30
;
run;
/* BUG-reportwherekw: the REPORT sub-statement scan used to reach into the
   WHERE predicate, so a column named `by` (ubiquitous clinically) tripped the
   BY-group guard → spurious "BY-group processing is not supported" (exit 2).
   SAS filters normally: rows with by>1 → 2,3. Same guard as BUG-printwherekw. */
proc report data=a nowd; column by v; define by/display; where by>1; run;
/* a keyword-named column works without the WHERE too (no regression of the
   reportby guard: a real BY statement still fails loud — see the by-group
   fixtures); here `break` is just a column. */
data b; input break v; datalines;
1 100
2 200
;
run;
proc report data=b nowd; column break v; define break/display; where break>1; run;
