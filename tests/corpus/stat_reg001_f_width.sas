/* STAT-REG-001: the ANOVA "F Value" column of PROC REG is 7 characters wide
 * in SAS 9.4; an F whose two-decimal form is wider is printed in BEST7.
 * (1.215E7, 13381.5, 1349087 from a SAS 9.4 run of these steps.)
 * Invented data.
 */
data r; do i=1 to 20; x=i; y=2*i+mod(i*7,5)*0.01; z=2*i+mod(i*7,5)*0.3; w=2*i+mod(i*7,5)*0.03; output; end; run;
proc reg data=r; model y=x; run; quit;
proc reg data=r; model z=x; run; quit;
proc reg data=r; model w=x; run; quit;
