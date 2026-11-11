/* expect-rc: 1; SAS rejects unknown agreement option. */
ods graphics off;
data t; r=1;c=2;run;
proc freq data=t;tables r*c / agree(forged_option);run;
