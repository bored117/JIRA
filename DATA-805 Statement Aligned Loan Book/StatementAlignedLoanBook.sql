declare @asofdate date
set @asofdate = getdate()
DECLARE @PostedDate datetime = OdsLapro.dbo.udfGetNthPreviousLAProBusinessDay(@AsOfDate, 5);

IF OBJECT_ID(N'tempdb..#LoanStatusAligning') IS NOT NULL
	DROP TABLE #LoanStatusAligning

IF OBJECT_ID(N'tempdb..#loanbook') IS NOT NULL
	DROP TABLE #loanbook

create table #LoanStatusAligning
(
	LoanId varchar(15)
	,MonthNumber int
	,PaymentNumber int
	,PaymentDate date
)

insert into #LoanStatusAligning
select LoanID, null as MonthNumber, PaymentNumber, PaymentDate from
	(SELECT ZA.LoanID
			,PaymentDate
			,PaymentNumber
        FROM dbo.AmortizationScheduleWithBillHistory ZA) A
		where paymentdate <= @AsOfDate
			and loanid=  '00BCD103E4C3'


update LSA set
	MonthNumber = B.MonthNumber
	from #LoanStatusAligning LSA, 
		(select LoanID, MonthNumber, PaymentDate
			from (select ZA.LoanID
					,PaymentDate
					,MonthNumber
					--,PrincipalPayment
					--,InterestPayment
					from AmortizationScheduleWithPaymentHistory ZA
				) ZZA
				where paymentdate <= getdate()
		) B
	where LSA.loanid = B.LoanID

select * from #LoanStatusAligning order by loanid, monthnumber

select LSA.LoanID
	,l.LoanOfficer as PayoffUID
	,LSA.PaymentNumber as StatementNumber
	,LSA.PaymentDate as StatementDueDate
	,ASWP.PrincipalDue
	,ASWP.InteresteDue
	,ASWP2.PrincipalReceivedToDate
	,ASWP2.InterestReceivedToDate
	,ASWB.ScheduledPrincipalReceivedToDate
	,ASWB.ScheduledInterestReceivedToDate
	,PASTDUE.NumberOfStatementsPastDue
	,case when CAST(IIF(@PostedDate >= L.PaidOffDate, 1, 0) AS BIT) = 1 then 'Paid In Full'
        --per Kenny and Al we don't want to report this
        --when CB.AccountStatus = '93' THEN 'Assigned To Collections'
        when CB.AccountStatus = '97' THEN 'Charge off'
	    --when isNULL(U_LoanModRateLength,0)=999  THEN 'Debt Settlement'
		when ISNULL(l2.U_PortMoveCode,'x')='DS' then 'Debt Settlement'
        when @AsOfDate BETWEEN L2.ETL_LoanModForbearEffDt AND L2.ETL_LoanModForbearEndDt  then 'Current'
        when isnull(datediff(dd,PDL.EarliestUnpaidBill, @AsOfDate),0) < 30 then 'Current'
        when isnull(datediff(dd,PDL.EarliestUnpaidBill, @AsOfDate),0) between 30 and 59 then 'Delinquent 1 Payment'
        when isnull(datediff(dd,PDL.EarliestUnpaidBill, @AsOfDate),0) between 60 and 89 then 'Seriously Delinquent 2 Payments'
        when isnull(datediff(dd,PDL.EarliestUnpaidBill, @AsOfDate),0) > 89 then 'Seriously Delinquent 3+ Payments'
--		else 'Delinquent'
     end as [Status]
	,RIGHT(L.Classification,1) AS Tier
	,CB.TermsDuration AS Term
	,L.OriginalAmount AS LoanAmount
	,CONVERT(decimal(9,4), CONVERT(decimal(9,4), CASE WHEN CB.AccountStatus= '97' THEN L.PAInterestRate 
	                                                  WHEN @AsOfDate BETWEEN L2.U_LoanModRateEffDt AND L2.ETL_LoanModRateEndDt THEN L.PAInterestRate 
	                                                  ELSE L.Rate 
	                                             END)
							  / 100.0) AS InterestRate
into #loanbook
from
	lapro.Loan L inner join #LoanStatusAligning LSA on L.loanid = LSA.loanid
	left outer join 
		(select A.LoanId, sum(AmountPrincipal) as PrincipalDue, sum(AmountInterest) as InteresteDue 
			from AmortizationScheduleWithPaymentHistory A, #LoanStatusAligning B
			where status <> 'posted' and A.MonthNumber <= B.MonthNumber and A.loanid = B.loanid group by A.LoanID) ASWP
		on L.Loanid = ASWP.LoanID
	left outer join
		 (select A.LoanId, sum(AmountPrincipal) as PrincipalReceivedToDate, sum(AmountInterest) as InterestReceivedToDate
			from AmortizationScheduleWithPaymentHistory A, #LoanStatusAligning B
			where status = 'posted' and A.PaymentDate <= B.PaymentDate and A.loanid = B.loanid group by A.LoanID) ASWP2
		on L.Loanid = ASWP2.LoanID
	left outer join
		(select A.LoanID, sum(PrincipalPayment) as ScheduledPrincipalReceivedToDate, sum(InterestPayment) as ScheduledInterestReceivedToDate
			from AmortizationScheduleWithBillHistory A, #LoanStatusAligning B
			where A.PaymentNumber < B.PaymentNumber and A.loanid = B.loanid group by A.LoanID) ASWB
		on L.LoanId = ASWB.LoanID
	left outer join
		(select A.LoanID, count(1) as NumberOfStatementsPastDue
			from AmortizationScheduleWithPaymentHistory A, #LoanStatusAligning not reaB
			where A.MonthNumber <= B.MonthNumber and A.LoanID = B.LoanId and A.status = 'past_due' group by A.LoanID) PASTDUE
		on L.LoanID = PASTDUE.LoanID
	LEFT outer JOIN LAPro.CREDITBUREAU CB ON CB.LoanID = L.LoanID
	LEFT outer JOIN LAPro.Loan2 L2 ON L2.LoanID = L.LoanID
	left outer join 
		(select A.loanID, MIN(PastDueDate) as EarliestUnpaidBill from LAPro.ViewPastDueLoan A where A.PastDueDate < @AsOfDate group by A.loanid) PDL 
		on PDL.LoanID = L.LoanID 
select * from #loanbook
--select * from #loanbook where loanid = '003B5F453022'
--select * from AmortizationScheduleWithPaymentHistory where status = 'past_due'