* pin: keyword stats print in the REQUESTED order with exact values; *
* hand-verified for x=1..10: Q1=3 Median=5.5 Q3=8 P90=9.5 P95=P99=10  *
* QRange=5 Mode=. Range=9 Sum=55 CSS=82.5 USS=385 CV=55.048 StdErr=.96 *
* (doc-finder tick156);
data d;
  input x;
  datalines;
1
2
3
4
5
6
7
8
9
10
;
run;

proc means data=d max min n;
run;

proc means data=d p25 p50 p75 p90 p95 p99 qrange mode range sum css uss cv stderr;
run;
