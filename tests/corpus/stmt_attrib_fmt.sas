data _null_;
  attrib d length=8 format=date9. label="Visit Date";
  attrib s length=$3 informat=$char3. label="Code";
  d = '15MAR2024'd;
  s = "hello";
  put "d=" d;
  put "s=" s;
run;
