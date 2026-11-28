/* expect-rc: 2
 * STAT-CANCORR-001: a valid PROC CANCORR request owned by a later ticket
 * stays a loud D-009 gap and prints nothing: here the PARTIAL statement
 * (STAT-CANCORR-003). The other gaps (OUT=, OUTSTAT=, NCAN=, REDUNDANCY,
 * VDEP, EDF=, MSTAT=, repeated statements, ...) are pinned in
 * src/stat/cancorr_tests.zig through the captured reporter. Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data T;
input a b c d;
datalines;
1 2 5 3
2 1 3 4
3 4 4 1
4 3 1 5
5 5 2 2
6 2 6 6
;
proc cancorr data=T; var a; with b; partial c; run;
