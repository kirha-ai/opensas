/* STAT-CANCORR-001: input edge cases, invented data. An empty input data
 * set prints nothing (SAS 9.4: NOTE "No observations in the input data
 * set."); repeated VAR and repeated WITH statements accumulate their
 * variables; three observations for one VAR and one WITH variable (df - p -
 * q = 0, N=-0.5) still analyse, with S=1 exact F statistics and the "F
 * statistic is exact" note. Expected output is the SAS 9.4 (SAS/STAT 15.4)
 * listing of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data t; input a b c d; datalines;
1 2 5 3
2 1 3 4
3 4 4 1
4 3 1 5
5 5 2 2
6 2 6 6
;
data e; set t; stop; run;
proc cancorr data=e short; var a; with b; run;
proc cancorr data=t short; var a; var c; with b; run;
proc cancorr data=t short; var a; with b; with c; run;
proc cancorr data=t(obs=3) short; var a; with b; run;
