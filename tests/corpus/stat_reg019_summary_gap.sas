/* STAT-REG-019 / STAT-REG-001: "Computer Resources in Regression Analysis"
 * (S154 p. 8650) points to TYPE=SSCP (and CORR/COV) summary input as the way
 * to save CPU time. STAT-REG-001 implemented that mode; this hand-written
 * TYPE=SSCP set (its $8 _NAME_ truncates Intercept to Intercep) now fits from
 * the crossproducts, and the listing equals a SAS 9.4 run of this program
 * token for token. Invented data.
 */
data s(type=sscp); input _TYPE_ $ _NAME_ $ Intercept x y; datalines;
SSCP Intercept 5 15 21
SSCP x 15 55 75
SSCP y 21 75 103
N . 5 5 5
;
proc reg data=s; model y=x; run; quit;
