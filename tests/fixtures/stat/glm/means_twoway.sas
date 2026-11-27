/* Public S154 physical pp.4129–4130, all33 observations of the Means versus LS-Means example. */
data twoway;
input Treatment Block y;
datalines;
1 1 17
1 1 28
1 1 19
1 1 21
1 1 19
1 2 43
1 2 30
1 2 39
1 2 44
1 2 44
1 3 16
2 1 21
2 1 21
2 1 24
2 1 25
2 2 39
2 2 45
2 2 42
2 2 47
2 3 19
2 3 22
2 3 16
3 1 22
3 1 30
3 1 33
3 1 31
3 2 46
3 3 26
3 3 31
3 3 26
3 3 33
3 3 29
3 3 25
;
run;
