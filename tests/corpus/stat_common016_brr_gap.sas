/* expect-rc: 2
 * STAT-COMMON-016: VARMETHOD=BRR needs exactly two PSUs per stratum; three
 * PSUs in a stratum is not implemented and must fail visibly (D-009 gap)
 * without printing a listing. Invented data.
 */
data survey;
input stratum psu w y;
datalines;
1 1 1 4
1 2 2 6
1 3 1 5
2 4 1 7
2 5 2 9
;
proc surveymeans data=survey varmethod=brr;
strata stratum; cluster psu; weight w; var y;
run;
