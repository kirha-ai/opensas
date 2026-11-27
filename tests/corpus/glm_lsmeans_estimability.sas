/* COMMON009: standard equal-margin means with a missing B1 cell.
 * S154 physical pp.278-284,4072-4076,4081,4144-4147. Full original
 * default-Type-III oracle is separately replayed without source edits.
 */
ods graphics off;
data cells;
 input group $ h y;
 datalines;
A 0 6
A 0 9
A 0 12
A 1 4
A 1 7
A 1 13
B 0 19
B 0 23
B 0 24
;
run;
proc glm data=cells;
 class group h;
 model y=group h group*h / ss1;
 lsmeans group*h / e;
 lsmeans group h / e stderr;
run;
quit;
