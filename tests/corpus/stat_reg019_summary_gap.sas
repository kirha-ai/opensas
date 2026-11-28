/* expect-rc: 2
 * STAT-REG-019: "Computer Resources in Regression Analysis" (S154 p. 8650)
 * points to TYPE=SSCP (and CORR/COV) summary input as the way to save CPU time.
 * That execution mode is not implemented: a typed input set must fail visibly
 * (D-009 gap), never be analysed as raw observations. A gap ends the run, so
 * TYPE=CORR/COV, DATA=x(TYPE=) and OUTSSCP= are asserted in
 * src/stat/reg_resources_tests.zig. Invented data; no listing may be produced.
 */
data s(type=sscp); input _TYPE_ $ _NAME_ $ Intercept x y; datalines;
SSCP Intercept 5 15 21
SSCP x 15 55 75
SSCP y 21 75 103
N . 5 5 5
;
proc reg data=s; model y=x; run; quit;
