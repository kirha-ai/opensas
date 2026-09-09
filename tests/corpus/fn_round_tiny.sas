/* GH#47: ROUND with a tiny unit must not inject FP noise (round(97,1e-10)=97),
   while normal ties still round away from zero (round(1.045,0.01)=1.05). */
data _null_;
  a = round(97, 0.0000000001);
  b = round(4.60733, 0.0000000001);
  c = round(1.045, 0.01);
  d = round(2.675, 0.01);
  e = round(1234.5678, 0.01);
  f = round(97, 0.001);
  g = round(123.456, 1);
  h = round(2.5);
  put a= b= c= d= e= f= g= h=;
run;
