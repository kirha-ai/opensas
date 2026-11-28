/* STAT-KDE-001: PROC KDE UNIVAR / BIVAR / BY / FREQ / WEIGHT roles, missing
 * values, closed-form bandwidths (bivariate default, METHOD=SNR, METHOD=OS,
 * BW=, BWM=), NGRID=, GRIDL=/GRIDU=, TRUNCATE, v-options, explicit pairs and
 * NOPRINT: the default Inputs and Controls tables. Invented data; the
 * expected listing is the SAS 9.4 listing of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data s;
input x y f w;
datalines;
1 2 1 1
2 3 2 0.5
4 1 1 2
7 5 3 1
3 . 1 1
. 4 1 1
5 6 0 1
6 2 1 -1
;
data t;
input x y g @@;
datalines;
0 0 1 1 1 1 2 3 1 3 2 1 4 4 1 5 5 1 6 7 1 7 6 1 8 8 1 9 9 1
10 10 2 11 12 2 12 11 2 13 13 2 14 14 2 15 15 2 16 17 2 17 16 2 18 18 2 19 19 2 100 100 2
;
proc kde data=s;
bivar x y;
run;
proc kde data=s;
freq f;
bivar x y;
run;
proc kde data=s;
weight w;
bivar x y / bwm=2 ngrid=10;
run;
proc kde data=s;
bivar x (ngrid=5 gridl=0) y / truncate;
run;
proc kde data=s;
weight w;
freq f;
univar x y / method=snr;
run;
proc kde data=t;
univar x / method=os;
univar x (bw=2) y / bw=1 bwm=1.5 ngrid=11;
run;
proc kde data=t;
univar x / bw=1 gridl=-5;
univar y / method=snr gridu=50;
run;
proc kde data=t;
by g;
bivar x y;
univar x / bw=1;
run;
proc kde data=work.t;
where g = 2;
bivar (x y) (y x) / bw=1 plots=(contour surface);
run;
proc kde data=t;
bivar x y / bw=1 noprint;
run;
proc kde data=t;
freq y;
freq x;
univar x / bw=1;
run;
