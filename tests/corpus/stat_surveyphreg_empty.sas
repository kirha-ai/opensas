/* expect-rc: 1
 * STAT-SURVEYPHREG-001: an empty input data set (no BY) is a data error:
 * SAS 9.4 writes "ERROR: No valid observations present." and no listing.
 * Every WEIGHT missing: "ERROR: No nonmissing observations.". NAMELEN= out
 * of 20..200: "ERROR: The parameter value 10 is not within the required
 * range of 20 and 200." (SAS 9.4 runs.)
 * Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data e; stratum=1; cluster=1; weight=1; time=1; status=1; age=30; stop; run;
proc surveyphreg data=e; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
data s;
input stratum cluster weight time status age;
datalines;
1 1 2 5 1 30
1 2 2 3 0 41
2 1 3 4 1 25
2 2 3 6 1 52
;
data allx; set s; weight=.; run;
proc surveyphreg data=allx; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=s namelen=10; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=s namelen=201; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
