/* STAT-SURVEYREG-001: CLUSTER with RATE= (one stratum, three PSUs of two
 * observations) and an unweighted simple regression. Invented data.
 * Expected numbers checked by independent hand computation: OLS
 * b = (0.73333333, 1.17142857); Taylor variance
 * V = (n-1)/(n-p) (X'X)^-1 G (X'X)^-1 with G = (1-f) m/(m-1) sum_c e_c e_c',
 * e_c = sum over PSU c of r x, f = 0.25, m = 3, df = m - 1 = 2. The listing
 * layout (Design Summary "Number of Clusters", 8-decimal estimates) was
 * confirmed against a SAS 9.4 run of this program.
 */
options nodate nonumber nocenter linesize=160;
data psu;
input c x y;
datalines;
1 1 2
1 2 3
2 3 5
2 4 4
3 5 7
3 6 8
;
proc surveyreg data=psu rate=0.25;
cluster c;
model y = x;
run;
