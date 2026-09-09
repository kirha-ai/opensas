/* CALL TANH / CALL LOGISTIC: element-wise in place. Phase-F-callbatch. */
data _null_;
  a=0; b=1; c=-1;
  call tanh(a,b,c);
  put "tanh=" a 8.5 " " b 8.5 " " c 8.5;
  x=0; y=1; z=-1;
  call logistic(x,y,z);
  put "logistic=" x 8.5 " " y 8.5 " " z 8.5;
run;
