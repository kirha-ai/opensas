%let mainvar = frommain;
data _null_; put "start"; run;
%include "tests/corpus/includes/inc_body.sas" /nosource;
data _null_; put "main sees &bodyvar"; run;
