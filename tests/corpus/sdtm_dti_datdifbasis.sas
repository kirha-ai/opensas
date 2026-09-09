/* DATDIF day counts under ACT/ACT and 30/360 */
data d;
  a1 = datdif("01JAN2020"d, "01FEB2020"d, "ACT/ACT");
  a2 = datdif("31JAN2020"d, "31MAR2020"d, "30/360");
  a3 = datdif("01JAN2024"d, "31DEC2024"d, "ACT/ACT");
run;
proc print data=d; var a1 a2 a3; run;
