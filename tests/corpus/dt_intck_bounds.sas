data _null_;
  m = intck('month', mdy(1,31,2020), mdy(2,1,2020));
  y = intck('year', mdy(12,31,2019), mdy(1,1,2020));
  d = intck('day', mdy(1,1,2020), mdy(2,1,2020));
  w = intck('week', mdy(1,1,2020), mdy(1,15,2020));
  q = intck('qtr', mdy(1,1,2020), mdy(12,31,2020));
  put "months=" m " years=" y " days=" d " weeks=" w " qtrs=" q;
run;
