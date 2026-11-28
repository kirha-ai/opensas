/* STAT-ORTHOREG-001: BY groups (BY Statement, PDF pp.7289-7290). Two BY
 * groups hold identical copies of the Longley data, so each group must
 * reproduce the single-group listing (see stat_orthoreg_longley.sas for the
 * provenance of the expected cells, including the four exact-solution
 * estimate cells that differ from SAS's last digit).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'PROC ORTHOREG used with Longley data';
data Longley;
input Employment Prices GNP Jobless Military PopSize Year;
datalines;
60323 83.0 234289 2356 1590 107608 1947
61122 88.5 259426 2325 1456 108632 1948
60171 88.2 258054 3682 1616 109773 1949
61187 89.5 284599 3351 1650 110929 1950
63221 96.2 328975 2099 3099 112075 1951
63639 98.1 346999 1932 3594 113270 1952
64989 99.0 365385 1870 3547 115094 1953
63761 100.0 363112 3578 3350 116219 1954
66019 101.2 397469 2904 3048 117388 1955
67857 104.6 419180 2822 2857 118734 1956
68169 108.4 442769 2936 2798 120445 1957
66513 110.8 444546 4681 2637 121950 1958
68655 112.6 482704 3813 2552 123366 1959
69564 114.2 502601 3931 2514 125368 1960
69331 115.7 518173 4806 2572 127852 1961
70551 116.9 554894 4007 2827 130081 1962
;
data twice; set Longley; do g=1 to 2; output; end; run;
proc sort data=twice; by g; run;
proc orthoreg data=twice;
by g;
model Employment = Prices Prices *Prices
GNP GNP *GNP
Jobless Jobless *Jobless
Military Military*Military
PopSize PopSize *PopSize
Year Year *Year;
run;
