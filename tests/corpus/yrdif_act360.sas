data _null_;
  q = yrdif(mdy(1,1,2021), mdy(4,1,2021), 'ACT/360');
  h = yrdif(mdy(1,1,2021), mdy(6,30,2021), 'ACT/360');
  put "q=" q;
  put "h=" h;
run;
