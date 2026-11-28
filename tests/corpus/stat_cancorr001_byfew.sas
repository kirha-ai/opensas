/* expect-rc: 1
 * STAT-CANCORR-001: a BY group with fewer than two observations is an ERROR
 * ("There must be at least 2 observations in data set WORK.B1." for the
 * group g=2) and the other BY groups are still analysed. Invented data.
 * Expected output is the SAS 9.4 (SAS/STAT 15.4) listing of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data B1; input g a c; datalines;
1 1 2
1 2 1
1 3 5
2 4 4
3 5 1
3 6 3
3 7 2
;
proc cancorr data=B1 short; by g; var a; with c; run;
