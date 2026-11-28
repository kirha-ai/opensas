/* STAT-NESTED-004: Error Terms in F Tests and the Computational Method in
 * degenerate balanced designs. Each factor is tested against the mean square
 * of the factor below it (the last against Error, p.6972), never skipping a
 * degenerate denominator: F and Pr > F print `.` when the factor or its
 * denominator has zero degrees of freedom or the denominator mean square is
 * 0; a zero-df factor (repeated CLASS variable, one level per parent level,
 * one level overall) or a zero-df error lists `.` sums of squares and mean
 * squares, component 0, an all-zero EMS row; the other components are solved
 * from the EMS equations (p.6973) with those components 0; a zero total
 * component prints 0 percent. Hand check (C4): MS_a = 4, MS_b = 5, no error
 * df, so s2_b = 5, s2_a = (4 - 5) / 2 = -0.5, F_a = 4 / 5 = 0.80 on (1, 2) df,
 * Pr = P(|t_2| > sqrt(0.8)) = 1 - sqrt(0.8 / 2.8) = 0.4655, SE of the mean
 * sqrt(4 / 4) = 1.
 * Invented data (D-011). The expected listing is a SAS 15.4 reference run of
 * this program; the blank line SAS writes before each new page title is
 * dropped (opensas starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data c1; input a y @@; datalines;
1 3 1 5 2 4 2 8
;
title 'C1 class a a';
proc nested data=c1; class a a; var y; run;
data c2; input a b y z @@; datalines;
1 1 3 1 1 1 5 2 2 1 4 4 2 1 8 3 3 1 6 5 3 1 7 7
;
title 'C2 zero-df second factor, covariation';
proc nested data=c2; class a b; var y z; run;
data c3; input a b y z @@; datalines;
1 1 3 2 1 1 5 1 1 2 4 4 1 2 8 3
;
title 'C3 zero-df first factor (one level), covariation';
proc nested data=c3; class a b; var y z; run;
data c4; input a b y z @@; datalines;
1 1 3 2 1 2 5 1 2 1 4 4 2 2 8 3
;
title 'C4 zero error df, covariation';
proc nested data=c4; class a b; var y z; run;
data c6; input a b y @@; datalines;
1 1 3 1 1 3 1 2 5 1 2 5 2 1 4 2 1 4 2 2 9 2 2 9
;
title 'C6 zero error mean square';
proc nested data=c6; class a b; var y; run;
data c7; input a b y @@; datalines;
1 1 3 1 1 5 1 2 3 1 2 5 2 1 6 2 1 8 2 2 6 2 2 8
;
title 'C7 zero mean square for b';
proc nested data=c7; class a b; var y; run;
data c8; input a b y z @@; datalines;
1 1 3 1 1 1 3 2 1 2 3 4 1 2 3 3 2 1 3 5 2 1 3 7 2 2 3 6 2 2 3 9
;
title 'C8 constant y, zero total';
proc nested data=c8; class a b; var y z; run;
data c13; input g a b c y @@; datalines;
1 1 1 1 3 1 1 1 1 5 1 1 2 1 4 1 1 2 1 8 1 2 1 1 6 1 2 1 1 7 1 2 2 1 2 1 2 2 1 4
;
title 'C13 three factors, middle zero-df';
proc nested data=c13; class a b c; var y; run;
title 'C14 BY variable in the AOV default list';
proc nested data=c13 aov; by g; class a b; var g y; run;
title 'C15 class a b a';
proc nested data=c13; class a b a; var y; run;
title 'C16 class a a b';
proc nested data=c13; class a a b; var y; run;
data c17; input a y @@; datalines;
1 3 1 5 1 4
;
title 'C17 one factor, one level';
proc nested data=c17; class a; var y; run;
data c18; input a y z; datalines;
1 3 7
;
title 'C18 single observation';
proc nested data=c18; class a; var y; run;
proc nested data=c18; class a; var y z; run;
