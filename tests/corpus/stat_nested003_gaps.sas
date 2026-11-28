/* expect-rc: 2
 * STAT-NESTED-003: boundaries that stay loud. An unbalanced design whose
 * CLASS runs leave zero error degrees of freedom (SAS 15.4 prints missing
 * cells; owned by STAT-NESTED-004), also when the analysis of covariation is
 * requested, must fail visibly with no listing. Invented data (D-011).
 */
options nosyntaxcheck;
data s; input a b y z @@; datalines;
1 1 3 1 1 2 5 2 1 1 4 4 2 1 8 3 2 2 6 5
;
proc nested data=s; class a b; var y; run;
proc nested data=s; class a b; var y z; run;
