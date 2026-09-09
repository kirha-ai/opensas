data _null_;
   s1 = savings("01jan2005"d, "01jan2000"d, 300, 24, "MONTH", "QUARTER", "01jan2000"d, 4.00);
   s3 = savings("01jan2001"d, "01jan2000"d, 300, 24, "MONTH", "QUARTER", "01jan2000"d, 4.00);
   put s1=;
   put s3=;
run;
