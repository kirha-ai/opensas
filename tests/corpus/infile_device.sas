/* ISS-infiledevice: INFILE naming the inline-data device (DATALINES/DATALINES4/
   CARDS/CARDS4) reads the embedded block with options (DLM=/DSD) applied, rather
   than reading an external file. All four device keywords must work. */
data t1;
  infile datalines dlm='#' dsd;
  input a $ b $;
datalines;
foo#bar
;
run;
data _null_; set t1; put "T1 a=[" a "] b=[" b "]"; run;

data t2;
  infile datalines4 dlm='#' dsd missover;
  input a $ b $;
datalines4;
foo#bar
;;;;
run;
data _null_; set t2; put "T2 a=[" a "] b=[" b "]"; run;

data t3;
  infile cards dlm='#' dsd;
  input a $ b $;
cards;
foo#bar
;
run;
data _null_; set t3; put "T3 a=[" a "] b=[" b "]"; run;

data t4;
  infile cards4 dlm='#' dsd;
  input a $ b $;
cards4;
foo#bar
;;;;
run;
data _null_; set t4; put "T4 a=[" a "] b=[" b "]"; run;
