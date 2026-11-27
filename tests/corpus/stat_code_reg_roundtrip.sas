/* COMMON020: independent DATA-step scoring from an actual REG fit.
   Full-rank design has exact y=1+2*x+3*z and mean4.5. */
ods graphics off;
filename scorecd temp;
data training;
input x z y;
datalines;
0 0 1
1 0 3
2 0 5
0 1 4
1 1 6
2 1 8
;
run;
proc reg data=training noprint;
model y=x z;
code file=scorecd residual impute;
run;
quit;
data incoming;
input x z y;
datalines;
1 0 10
2 1 8
. 0 0
1 .A 0
;
run;
data scored;
set incoming;
%include scorecd;
put 'p=' P_y 8.3 ' r=' R_y 8.3 ' warn=[' _WARN_ $char2. ']';
run;
