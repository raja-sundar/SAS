options ls = 76 ps = 64 nodate nonumber macrogen symbolgen mlogic merror error=2;

** UPDATE HERE: MODIFY libname path to currnet month **;
libname perf  "\\vault\FINANCE\Analysis\TTM Loss\New_PERF";
libname perffull "\\vault\FINANCE\Analysis\PERF_Fulldata";

libname clid "\\vault\CREDIT\Reporting\Client Rating Files";
libname finsal "\\vault\CREDIT\Reporting\Final_Salary_Updating\final_salary_data";

/*
proc sql;
	connect to oracle (user='' password= path="@Hybrisrpt");
		create table credit_matrix as select * from connection to oracle 
		(
			select id,	name, CREDIT_RATING_CD,	PAYMENT_TY 
			from service_middle_tier.client
		);
		
		create table margin as select * from connection to oracle 
		(
			select order_id,  sum(DISPLAY_PRICE) as SDISPLAY_PRICE,   sum(case when PRODUCT_COST = 0 then VENDOR_ITEM_COST else product_cost end) as COGS
			from SERVICE_MIDDLE_TIER.ORDER_ITEM  
			left join xxapps.st_warranty@prodfin   on MANDITORY_ITEM_ID = SHIPPED_PRODUCT_ID
 			group by order_id
		);
	disconnect from oracle;

	connect to oracle (user='' password= path="@prodfin");
		create table contracts as select * from connection to oracle 
		(
			select orderid, duration, payfreq
	 		from xxcon_contract
		);

		create table oracle_fin as select * from connection to oracle
		(
			select 
				contracthostid,
				sum(original) as originationamt
			from XXCON_CONTRACT
			where 
				originationdate between '01-jan-16' and '31-Dec-17' 
			group by 
				contracthostid
		);

	disconnect from oracle;
quit;
** UPDATE ABOVE: MODIFY originationdate between CLAUSE TO UPPER RECENT MONTHEND DATE **;

proc sort data=oracle_fin; by  descending originationamt;run;

*proc print data=top50; run;

data top50;
  set oracle_fin;
  *by originationamt;
  retain rank;
  if first.originationamt then rank=0;
  rank+1;
  top50="Yes";
  sponsor_number = CONTRACTHOSTID +0;
  
  if rank le 50 then output;
run;


%macro monthly_perf(mnth, end_date);
 

data perf1;
set PERF.perf_&mnth.;
 
	
	vintage_year=trim(left(year(origination)));

	vintage_qtr = substr(strip(year(origination)),3,2)||"Q"||strip(qtr(origination));
	vintage = input((trim(left(year(origination)))||trim(left(put(month(origination),z2.)))),10.);
	if month(origination)<=6 then half="H1"; else half="H2";
	qtr = "Q"||strip(qtr(origination));
	month=month(origination);        

	* MOB calculation;
	MOB = intck('month', origination, &end_date.);

	as_of = &mnth.;

	if chargeoffamt = . then chargeoffamt = 0;
	if chargeoffrevamt = . then chargeoffrevamt = 0;
	if opb = . then opb = 0;
	if CMPrevPer=. then CMPrevPer=0;
	if CMCurrPer=. then CMCurrPer=0;
	if AdjPrevPer=. then AdjPrevPer=0;
	if AdjCurrPer=. then AdjCurrPer=0;

	adjustment = sum(AdjPrevPer, AdjCurrPer);
	credit_memo = sum(CMPrevPer, CMCurrPer);

	if apps_status='Chargeoff' and credit_memo >= chargeoffamt then new_credit = credit_memo - chargeoffamt; else new_credit = credit_memo;

	** GROSS Original;
	goriginal = original;

	** NET Original;
	noriginal = sum(original, -new_credit, -adjustment); 

	if max_days_pd < 1 then do; Bal_cur = opb; Num_cur = 1; end;
	else if max_days_pd < 31 then do; Bal01_30 = opb; Num01_30 = 1;	end;
	else if max_days_pd < 61 then do; Bal31_60 = opb; Num31_60 = 1;	end;
	else if max_days_pd < 91 then do; Bal61_90 = opb; Num61_90 = 1;	end;
	else if max_days_pd < 121 then do; Bal91_120 = opb; Num91_120 = 1; end;
	else if max_days_pd < 151 then do; Bal121_150 = opb; Num121_150 = 1; end;
	else if max_days_pd < 181 then do; Bal151_180 = opb; Num151_180 = 1; end;
	else do; Bal180p = opb; Num180p = 1; end;

	if chargeoffamt > 0 then do;
		CONum = 1;
		COAmt = chargeoffamt;
	end;

	Bankruptcy_flag = (Bankruptcy ne "");

	if curr_per > 0 and opb > 0 and opb/curr_per < 0.25 then payratio = 'LT25%';
	else if curr_per > 0 and opb > 0 and opb/curr_per < 0.50 then payratio = 'LT50%';
	else if curr_per > 0 and opb > 0 and opb/curr_per < 0.75 then payratio = 'LT75%';
	else if curr_per > 0 and opb > 0 then payratio = 'GE75%';
	
	year_vint_end = mdy("12","01",trim(left(year(origination))));
	format   year_vint_end mmddyy10.;

	mo_btwn = intck('month',  year_vint_end, mdy(month(intnx('month', date(),-1)),"01",year(date()) ) );
	
	if opb > 0 or new_credit apps_Status in ('Active','Chargeoff','PIF') and vintage_year in ('2016','2017') ; 
	if 0 < mob < 24;
run;

proc sql;
create table perf2 as
	select		
		as_of,
		vintage_year,
		year_vint_end,
		vintage,
		month as vintage_month,
		qtr,
		mob,
		PAYMENT_TY,
		CREDIT_RATING_CD,
		id,
		Top50,	 
		Sponsor_Name as Name,
		payfreq,
		duration as term,
		Bankruptcy_flag,
		mo_btwn,
		payratio,
 
		count(*) 			as orders,
		sum(a.noriginal*1) 	as noriginal,
		sum(a.goriginal*1) 	as goriginal,
		sum(opb) 			as balance,
		sum(Bal_cur) 		as Bal_cur,
		sum(Num_cur) 		as Num_cur,
		sum(Bal01_30)		as Bal01_30,
		sum(Num01_30)		as Num01_30,
		sum(Bal31_60)		as Bal31_60,
		sum(Num31_60)		as Num31_60,
		sum(Bal61_90)		as Bal61_90,
		sum(Num61_90)		as Num61_90,
		sum(Bal91_120)		as Bal91_120,
		sum(Num91_120)		as Num91_120,
		sum(Bal121_150)		as Bal121_150,
		sum(Num121_150)		as Num121_150,
		sum(Bal151_180)		as Bal151_180,
		sum(Num151_180)		as Num151_180,
		sum(Bal180p)		as Bal180p,
		sum(Num180p)		as Num180p,
		sum(ChargeOffAmt) 	as ChargeOffAmt,	
		sum(chargeoffrevamt) as CORevAmt,
		sum(new_credit)		as new_credit,
		sum(sdisplay_price) as display_price,
		sum(cogs)			as cogs
	from perf1 a 
		left join contracts c on a. order_id = c. orderid
		left join margin d on a. order_id = d. order_id
		left join credit_matrix e on a.sponsor_number = e.id
		left join top50 f on f.sponsor_number = a.sponsor_number 
	 

	group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17;
quit;




** 	SSA IS NOW PAYROLL ALLOTMENT **;
data perf2; set perf2;  if id = 1000 then PAYMENT_TY = "PA";  run;

%if &mnth. = 201601 %then %do;
	proc datasets library=work;   delete perfs; run;
	data perfs; set perf2; run;
%end;
%else %do;
	data perfs;   set perfs perf2; run;
%end;
run;

%mend;

%monthly_perf(201601, '31Jan2016'd);
%monthly_perf(201602, '29Feb2016'd);
%monthly_perf(201603, '31Mar2016'd);
%monthly_perf(201604, '30Apr2016'd);
%monthly_perf(201605, '31May2016'd);
%monthly_perf(201606, '30Jun2016'd);
%monthly_perf(201607, '31Jul2016'd);
%monthly_perf(201608, '31Aug2016'd);
%monthly_perf(201609, '30Sep2016'd);
%monthly_perf(201610, '31Oct2016'd);
%monthly_perf(201611, '30Nov2016'd);
%monthly_perf(201612, '31Dec2016'd);

%monthly_perf(201701, '31Jan2017'd);
%monthly_perf(201702, '28Feb2017'd);
%monthly_perf(201703, '31Mar2017'd);
%monthly_perf(201704, '30Apr2017'd);
%monthly_perf(201705, '31May2017'd);
%monthly_perf(201706, '30Jun2017'd);
%monthly_perf(201707, '31Jul2017'd);
%monthly_perf(201708, '31Aug2017'd);
%monthly_perf(201709, '30Sep2017'd);
%monthly_perf(201710, '31Oct2017'd);
%monthly_perf(201711, '30Nov2017'd);
%monthly_perf(201712, '31Dec2017'd);

%monthly_perf(201801, '31Jan2018'd);

** ADDING CLIENT RATING AND INDUSTRY **;
proc sql;
create table perfsc as 
 select a.*, b.rating, b.industry as industry072017
 from perfs a
 left join clid.client_rating_mapping_201707 b on a.ID = b.CLIENTID; quit;
 
data perfs3;
set perfsc;
if Top50 = "" then Top50 = "No";
if id  in(1000,1034,1037,1200,2039,2046,2047,2049,2051,2146,2147,2854,1301,1300,2399) then channel = 'FedGov       ';
		else channel = 'Affiliate';
format ChargeOffAmt 8.2;
run;

libname raja "X:\DOCUMENTS\Functional\Analysis\2018\Monthly performance";
data raja.perf_201712;
set perfs3;
run;

libname raja "X:\DOCUMENTS\Functional\Analysis\2018\Monthly performance";
data perfs3;
set raja.perf_201712;
run;


** UPDATE HERE: OUTPUTTED TO PUBLIC LOCATION FOR CONSUMPTION **;
proc export 
data=perfs3
dbms=csv
outfile="X:\DOCUMENTS\Functional\Analysis\2018\Monthly performance\portfolio_perf_201712.csv" 
replace;
run;

proc sql;
create table delq as
select
	as_of,
	sum(noriginal) as OrigAmt,
	sum(balance) as balance,
	sum(Bal_cur) / sum(Balance) format percent6.2 as cur,
	sum(Bal01_30) / sum(Balance) format percent6.2 as to30,
	sum(Bal31_60) / sum(Balance) format percent6.2 as to60,
	sum(Bal61_90) / sum(Balance) format percent6.2 as to90,
	sum(Bal91_120) / sum(Balance) format percent6.2 as to120,
	sum(Bal121_150) / sum(Balance) format percent6.2 as to150,
	sum(Bal151_180) / sum(Balance) format percent6.2 as to180,
	sum(Bal180p) / sum(Balance) format percent6.2 as p180,
	sum((ChargeOffAmt-CORevAmt)) / sum(noriginal) format percent6.2 as co
from
	perfs3
group by as_of
;
quit;

ods listing close; 
ods tagsets.ExcelXP path="C:\Users\rsundararajan\Documents\SAS\output\" file="monthly_report.xml" style= sasdocprinter ;

ods tagsets.ExcelXP options (sheet_name= 'Delq %' sheet_interval='none' frozen_headers = 'yes'); 
proc report data = delq
style(report)=[ cellspacing=0pt cellpadding=8pt borderwidth=50]
style(header)=[background=BWH FOREGROUND=Black font_weight=bold ] nowd split='*' spanrows missing ;

columns  as_of OrigAmt balance cur to30 to60 to90 to120 to150 to180 p180 co ;
define as_of / display;
define OrigAmt / display;
define balance / display;
define cur  / display;
define to30  / display;
define to60  / display;
define to90  / display;
define to120  / display;
define to150  / display;
define to180  / display;
define p180  / display;
define co  / display;
run;

ods tagsets.ExcelXP options (sheet_name= 'Delq1 %' sheet_interval='none' frozen_headers = 'yes'); 
proc report data = delq
style(report)=[ cellspacing=0pt cellpadding=8pt borderwidth=50]
style(header)=[background=BWH FOREGROUND=Black font_weight=bold ] nowd split='*' spanrows missing ;

columns  as_of OrigAmt balance cur to30 to60 to90 to120 to150 to180 p180 co ;
define as_of / display;
define OrigAmt / display;
define balance / display;
define cur  / display;
define to30  / display;
define to60  / display;
define to90  / display;
define to120  / display;
define to150  / display;
define to180  / display;
define p180  / display;
define co  / display;
run;

ods tagsets.excelxp close;
ods listing;

* email the reports;
%let todt = %sysfunc( putn( %sysfunc( date() ), MMDDYY10. ));
%put &todt;

options emailsys=smtp emailhost=Smtp.purchasingpwr.com emailport=25;

* IMPORTANT - use 8 characters for filename;
FILENAME moveacct EMAIL
	SUBJECT="List of past due accounts (no payments in 90 days) - &todt"
	FROM= 'SAS_no_reply@purchasingpower.com'
	TO= ("rsundararajan@purchasingpower.com")
	ATTACH= ("C:\Users\rsundararajan\Documents\SAS\output\monthly_report.xml");

DATA _NULL_;
FILE moveacct;
PUT "Attachment has a monthly report";
RUN;
*/


**** Past due buckets ******;

%macro buckets(mnth, end_date);

data perf1;
set perffull.perf&mnth.;

	as_of = &mnth.;

	if opb = . then opb = 0;

	if opb > 0;

	if max_days_pd < 1 then do; Bal_cur = opb; Num_cur = 1; end;
	else if max_days_pd < 31 then do; Bal01_30 = opb; Num01_30 = 1;	end;
	else if max_days_pd < 61 then do; Bal31_60 = opb; Num31_60 = 1;	end;
	else if max_days_pd < 91 then do; Bal61_90 = opb; Num61_90 = 1;	end;
	else if max_days_pd < 121 then do; Bal91_120 = opb; Num91_120 = 1; end;
	else if max_days_pd < 151 then do; Bal121_150 = opb; Num121_150 = 1; end;
	else if max_days_pd < 181 then do; Bal151_180 = opb; Num151_180 = 1; end;
	else do; Bal180p = opb; Num180p = 1; end;

	if curr_per <=0 and opb > 0 and max_days_pd > 150 then payratio = 'toCO%';
	else if curr_per <=0 and opb > 0 then payratio = 'Zero%';
	else if curr_per > 0 and opb > 0 and curr_per/invamount < 0.25 then payratio = 'LT25%';
	else if curr_per > 0 and opb > 0 and curr_per/invamount < 0.50 then payratio = 'LT50%';
	else if curr_per > 0 and opb > 0 and curr_per/invamount < 0.95 then payratio = 'LT95%';
	else if curr_per > 0 and opb > 0 then payratio = 'GE95%';
run;

proc sql;
create table perf2 as
	select		
		as_of,
		payratio,
		Apps_Status,
 
		count(*) 			as orders,
		sum(opb) 			as balance,
		sum(Bal_cur) 		as Bal_cur,
		sum(Num_cur) 		as Num_cur,
		sum(Bal01_30)		as Bal01_30,
		sum(Num01_30)		as Num01_30,
		sum(Bal31_60)		as Bal31_60,
		sum(Num31_60)		as Num31_60,
		sum(Bal61_90)		as Bal61_90,
		sum(Num61_90)		as Num61_90,
		sum(Bal91_120)		as Bal91_120,
		sum(Num91_120)		as Num91_120,
		sum(Bal121_150)		as Bal121_150,
		sum(Num121_150)		as Num121_150,
		sum(Bal151_180)		as Bal151_180,
		sum(Num151_180)		as Num151_180,
		sum(Bal180p)		as Bal180p,
		sum(Num180p)		as Num180p
	from perf1 a 
	group by 1,2,3;
quit;

%if &mnth. = 201601 %then %do;
	proc datasets library=work;   delete perfs; run;
	data perfs; set perf2; run;
%end;
%else %do;
	data perfs;   set perfs perf2; run;
%end;
run;

%mend;

%buckets(201601, '31Jan2016'd);
%buckets(201602, '29Feb2016'd);
%buckets(201603, '31Mar2016'd);
%buckets(201604, '30Apr2016'd);
%buckets(201605, '31May2016'd);
%buckets(201606, '30Jun2016'd);
%buckets(201607, '31Jul2016'd);
%buckets(201608, '31Aug2016'd);
%buckets(201609, '30Sep2016'd);
%buckets(201610, '31Oct2016'd);
%buckets(201611, '30Nov2016'd);
%buckets(201612, '31Dec2016'd);

%buckets(201701, '31Jan2017'd);
%buckets(201702, '28Feb2017'd);
%buckets(201703, '31Mar2017'd);
%buckets(201704, '30Apr2017'd);
%buckets(201705, '31May2017'd);
%buckets(201706, '30Jun2017'd);
%buckets(201707, '31Jul2017'd);
%buckets(201708, '31Aug2017'd);
%buckets(201709, '30Sep2017'd);
%buckets(201710, '31Oct2017'd);
%buckets(201711, '30Nov2017'd);
%buckets(201712, '31Dec2017'd);

%buckets(201801, '31Jan2018'd);


proc sql;
create table delq as
select
	as_of,
	sum(balance) as balance,
	sum(Bal_cur) / sum(Balance) format percent6.2 as cur,
	sum(Bal01_30) / sum(Balance) format percent6.2 as to30,
	sum(Bal31_60) / sum(Balance) format percent6.2 as to60,
	sum(Bal61_90) / sum(Balance) format percent6.2 as to90,
	sum(Bal91_120) / sum(Balance) format percent6.2 as to120,
	sum(Bal121_150) / sum(Balance) format percent6.2 as to150,
	sum(Bal151_180) / sum(Balance) format percent6.2 as to180,
	sum(Bal180p) / sum(Balance) format percent6.2 as p180
from
	perfs
group by as_of
;
quit;


proc sql;
create table payratio as
select
	as_of,

	sum(case when payratio = 'LT25%' then balance else 0 end) format comma16.2 as lt25,
	sum(case when payratio = 'LT50%' then balance else 0 end) format comma16.2 as lt50,
	sum(case when payratio = 'LT95%' then balance else 0 end) format comma16.2 as lt95,
	sum(case when payratio = 'GE95%' then balance else 0 end) format comma16.2 as gt95,
	sum(case when payratio = 'CO??%' then balance else 0 end) format comma16.2 as toCO,
	sum(case when payratio = 'Zero%' then balance else 0 end) format comma16.2 as zero,

	sum(case when payratio = 'LT25%' then balance else 0 end)/sum(balance) format percent6.2 as lt25pct,
	sum(case when payratio = 'LT50%' then balance else 0 end)/sum(balance) format percent6.2 as lt50pct,
	sum(case when payratio = 'LT95%' then balance else 0 end)/sum(balance) format percent6.2 as lt95pct,
	sum(case when payratio = 'GE95%' then balance else 0 end)/sum(balance) format percent6.2 as gt95pct,
	sum(case when payratio = 'CO??%' then balance else 0 end)/sum(balance) format percent6.2 as toCOpct,
	sum(case when payratio = 'Zero%' then balance else 0 end)/sum(balance) format percent6.2 as zeropct
from
	perfs
group by as_of
;
quit;


proc sql;
create table termstat as
select
	as_of,

	sum(case when termstatus = 'Active' then balance else 0 end) format comma16.2 as Active_OPB,
	sum(case when termstatus = 'Chargeoff' then balance else 0 end) format comma16.2 as CO_OPB,
	sum(case when termstatus = 'PIF' then balance else 0 end) format comma16.2 as PIF_OPB,
	sum(case when termstatus in ('Cancel','Return','Returned') then balance else 0 end) format comma16.2 as Return_OPB,
	sum(case when termstatus in ('Repo','SIP','SIF') then balance else 0 end) format comma16.2 as SIP_OPB,
from
	perfs
group by as_of
;
quit;


ods listing close; 
ods tagsets.ExcelXP file="C:\Users\rsundararajan\Documents\SAS\output\monthly_report.xml" style= sasdocprinter ;

ods tagsets.ExcelXP options (sheet_name= 'Delq %' sheet_interval='none' frozen_headers = 'yes' embedded_titles= 'yes'); 
proc print data = delq noobs;
title "overall";
run;
title;
proc print data = delq noobs;
title "overall";
run;

ods tagsets.ExcelXP options (sheet_name= 'pay ratio' sheet_interval='none' frozen_headers = 'yes' embedded_titles= 'yes'); 
proc print data = payratio noobs;
title "overall";
run;
title;

ods tagsets.excelxp close;
ods listing;

* email the reports;
%let todt = %sysfunc( putn( %sysfunc( date() ), MMDDYY10. ));
%put &todt;

options emailsys=smtp emailhost=Smtp.purchasingpwr.com emailport=25;

* IMPORTANT - use 8 characters for filename;
FILENAME moveacct EMAIL
	SUBJECT="List of past due accounts (no payments in 90 days) - &todt"
	FROM= 'SAS_no_reply@purchasingpower.com'
	TO= ("rsundararajan@purchasingpower.com")
/*	CC= ("rsundararajan@purchasingpower.com")*/
	ATTACH= ("C:\Users\rsundararajan\Documents\SAS\output\monthly_report.xml");

DATA _NULL_;
FILE moveacct;
PUT "Attachment has a monthly report";
RUN;
