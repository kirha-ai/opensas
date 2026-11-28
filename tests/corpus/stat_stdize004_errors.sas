/* expect-rc: 1
 * STAT-STDIZE-004: PCTLDEF= outside 1..5 is a user error in SAS 9.4
 * (verified, invented data): "ERROR: The parameter value 6 is not within the
 * required range of 1 and 5." (also for 0); the step stops and nothing is
 * printed. The final step: PCTLDEF=2 median of 1..5, np = 2.5, g = 1/2,
 * j = 2 even, so x_2 = 2 (hand), values x - 2.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=120;
data a;
input x @@;
datalines;
1 2 3 4 5
;
proc stdize data=a method=std pctldef=6 pstat; var x; run;
proc stdize data=a method=median pctldef=0 pstat; var x; run;
proc stdize data=a method=median pctldef=2 out=o; var x; run;
data _null_; set o; file print; put 'ok ' x 14.9; run;
