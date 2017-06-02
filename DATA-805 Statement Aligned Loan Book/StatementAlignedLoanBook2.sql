/*
;with x as
(
	select LoanID, PaymentNumber, PaymentDate, PrincipalPayment, SumPrincipal = PrincipalPayment, InterestPayment, SumInterest = InterestPayment
		from AmortizationScheduleWithBillHistory
		where PaymentNumber = 1
	union all
	select y.LoanID, y.PaymentNumber, y.PaymentDate, y.PrincipalPayment, cast(x.SumPrincipal + y.PrincipalPayment as DECIMAL(10,2)),
			y.InterestPayment, CAST(X.SumInterest + y.InterestPayment as decimal(10,2))
		from x inner join AmortizationScheduleWithBillHistory y
		on y.PaymentNumber = x.PaymentNumber + 1
			and x.loanid = y.loanid
)
	select LoanID, PaymentNumber, PaymentDate, PrincipalPayment, SumPrincipal, InterestPayment, SumInterest
	from x
	order by LoanId, PaymentNumber
	option (maxrecursion 100);

;with x as
(
	select LoanID, MonthNumber, PaymentDate, EffectiveDate, AmountPrincipal = cast(AmountPrincipal as decimal(10,2))
		, SumPrincipal = cast(AmountPrincipal as decimal(10,2)), AmountInterest = cast(AmountInterest as decimal(10,2)), SumInterest = cast(AmountInterest as decimal(10,2))
		from AmortizationScheduleWithPaymentHistory_jin
		where MonthNumber = 1
	union all
	select y.LoanID, y.MonthNumber, y.PaymentDate, y.EffectiveDate, cast(y.AmountPrincipal as decimal(10,2)), cast(x.SumPrincipal + cast(y.AmountPrincipal as decimal(10,2)) as decimal(10,2)),
			cast(y.AmountInterest as decimal(10,2)), cast(X.SumInterest + cast(y.AmountInterest as decimal(10,2)) as decimal(10,2))
		from x inner join AmortizationScheduleWithPaymentHistory_jin y
		on y.MonthNumber = x.MonthNumber + 1
			and x.loanid = y.loanid
)
	select LoanID, MonthNumber, PaymentDate, EffectiveDate, AmountPrincipal, SumPrincipal, AmountInterest, SumInterest
	from x
	--where loanid = '0008B6840D8C'
	order by LoanId, MonthNumber
	option (maxrecursion 100);
*/
--select * into AmortizationScheduleWithPaymentHistory_Jin from AmortizationScheduleWithPaymentHistory
declare @loanid varchar(max) = '3FC5207643A2'
select LoanID, PaymentNumber, PaymentDate
		, PrincipalPayment, SumPrincipal = sum(PrincipalPayment) OVER (PARTITION BY LoanID ORDER BY LoanID ROWS UNBOUNDED PRECEDING) 
		, InterestPayment, SumInterest = sum(InterestPayment) OVER (PARTITION BY LoanID ORDER BY LoanID ROWS UNBOUNDED PRECEDING) 
	from AmortizationScheduleWithBillHistory
	where loanid = @loanid
	order by LoanId, PaymentNumber, PaymentDate

select ASWP.LoanID, MonthNUmber -- StatementNumber using paymentnumber?
	, PaymentDate as StatementDueDate, EffectiveDate
	, AmountPrincipal
	, AmountInterest
	, PrincipalDue = sum(iif(status <> 'posted', AmountPrincipal,0)) OVER (PARTITION BY ASWP.LoanID ORDER BY ASWP.LoanID,  MonthNumber ROWS UNBOUNDED PRECEDING) 
	, InterestDue= sum(iif(status <> 'posted', AmountInterest,0)) OVER (PARTITION BY ASWP.LoanID ORDER BY ASWP.LoanID, MonthNumber ROWS UNBOUNDED PRECEDING) 
	, PrincipalReceivedToDate = sum(iif(status = 'posted', AmountPrincipal,0)) OVER (PARTITION BY ASWP.LoanID ORDER BY ASWP.LoanID, MonthNumber ROWS UNBOUNDED PRECEDING) 
	, InterestReceivedToDate= sum(iif(status = 'posted', AmountInterest,0)) OVER (PARTITION BY ASWP.LoanID ORDER BY ASWP.LoanID, MonthNumber ROWS UNBOUNDED PRECEDING) 
	, ScheduledPrincipalReceivedToDate = sum(AmountPrincipal) OVER (PARTITION BY ASWP.LoanID ORDER BY ASWP.LoanID, MonthNumber ROWS UNBOUNDED PRECEDING) --billhistory?
	, ScheduledInterestReceivedToDate = sum(AmountInterest) OVER (PARTITION BY ASWP.LoanID ORDER BY ASWP.LoanID, MonthNumber ROWS UNBOUNDED PRECEDING) --billhistory?
	, NumberOfStatementPastDue = sum(iif(Status = 'past_due', 1, 0)) OVER (PARTITION BY ASWP.LoanID ORDER BY ASWP.LoanID, MonthNumber ROWS UNBOUNDED PRECEDING)
	, Status
	,RIGHT(L.Classification,1) AS Tier
	,CB.TermsDuration AS Term
	,L.OriginalAmount AS LoanAmount
	,CONVERT(decimal(9,4), CONVERT(decimal(9,4), CASE WHEN CB.AccountStatus= '97' THEN L.PAInterestRate 
	                                                  --WHEN @AsOfDate BETWEEN L2.U_LoanModRateEffDt AND L2.ETL_LoanModRateEndDt THEN L.PAInterestRate 
	                                                  ELSE L.Rate 
	                                             END)
							  / 100.0) AS InterestRate
	from (
			SELECT 
				[LoanID]
				,min(AmountPrincipalRemaining) as AmountPrincipalRemaining
				,min(OriginalAmount) as OriginalAmount
				,min(PaymentDate) as PaymentDate
				,max([EffectiveDate]) as [EffectiveDate]
				,sum(isnull(AmountPrincipal, 0)) as AmountPrincipal
				,sum(isnull(AmountInterest, 0)) as AmountInterest
				,sum(isnull(Amount, 0)) as Amount
				,status
				,min(MonthReal) as monthnumber
				,sum(isnull(PrincipalWaived, 0)) as PrincipalWaived
			from
				(select PH.*, BH.PaymentNumber as MonthReal from AmortizationScheduleWithPaymentHistory PH, 
					(select isnull(LEAD(PaymentDate) over (partition by loanid order by PaymentNumber),'9999-12-31') as PaymentDateNext , * from AmortizationScheduleWithBillHistory) BH 
						where PH.loanid = BH.loanid and PH.loanid = @loanid
							and PH.PaymentDate < BH.PaymentDateNext and PH.PaymentDate >= BH.PaymentDate 
					) PHBH
			group by LoanID, MonthReal, Status
		) ASWP
		LEFT outer JOIN LAPro.CREDITBUREAU CB ON CB.LoanID = ASWP.LoanID
		LEFT outer JOIN LAPro.Loan2 L2 ON L2.LoanID = ASWP.LoanID
		LEFT outer join LAPro.Loan L on L.LoanID = ASWP.LoanID
	where ASWP.loanid = @loanid
ORDER BY ASWP.LOANID, MonthNumber, PaymentDate, EffectiveDate
/*
select loanid, monthnumber, sum(1) from AmortizationScheduleWithPaymentHistory group by LoanId, MonthNumber having sum(1) > 1
select loanid, monthnumber, PaymentDate, sum(1) from AmortizationScheduleWithPaymentHistory group by LoanId, MonthNumber, PaymentDate having sum(1) > 1 order by loanid, monthnumber, paymentdate
select a.loanid, a.monthnumber, a.paymentdate from AmortizationScheduleWithPaymentHistory A, AmortizationScheduleWithPaymentHistory B where a.loanid = b.loanid and a.MonthNumber = b.MonthNumber and a.paymentdate <> b.PaymentDate
select * from AmortizationScheduleWithPaymentHistory where loanid = 'P457BD28E64BE' and monthnumber  = 16
select a.loanid, a.monthnumber, b.PaymentNumber, a.paymentdate, b.paymentdate from AmortizationScheduleWithPaymentHistory A, AmortizationScheduleWithBillHistory B where a.loanid = b.loanid and a.MonthNumber = b.PaymentNumber and a.paymentdate <> b.PaymentDate
	order by a.loanid, a.monthnumber, b.PaymentNumber, a.PaymentDate, b.PaymentDate
*/
select a.loanid, a.monthnumber, a.paymentdate from AmortizationScheduleWithPaymentHistory A
	where A.paymentDate not in (select z.paymentDate from AmortizationScheduleWithBillHistory z where a.loanid = z.loanid)
	order by a.loanid, a.monthnumber, a.PaymentDate

--declare @loanid varchar(20) = '39CC15DB4DE5'
select * from AmortizationScheduleWithBillHistory where loanid = @loanid
select * from AmortizationScheduleWithPaymentHistory where loanid = @loanid


select PH.*, BH.PaymentNumber as MonthReal from AmortizationScheduleWithPaymentHistory PH, 
	(select isnull(LEAD(PaymentDate) over (partition by loanid order by PaymentNumber),'9999-12-31') as PaymentDateNext , * from AmortizationScheduleWithBillHistory) BH 
	where PH.loanid = BH.loanid and PH.loanid = @loanid
	and PH.PaymentDate < BH.PaymentDateNext and PH.PaymentDate >= BH.PaymentDate
	
--003B5F453022
/*


		SELECT LoanId, SUM(ISNULL(PrincipalWaived, 0)) AS PrincipalWaived
		FROM LAPro.ViewHistLoanWaivers
	where loanid = @loanid
		GROUP BY LoanId


select a.loanid, max(a.paymentnumber), max(b.MonthNumber) from AmortizationScheduleWithBillHistory a, AmortizationScheduleWithPaymentHistory b
	where a.loanid = b.loanid
	group by a.loanid  
	having max(a.paymentnumber) <> max(b.MonthNUmber)

declare @loanid varchar(20) = '39CC15DB4DE5'
select * from AmortizationScheduleWithBillHistory where loanid = @loanid
select * from AmortizationScheduleWithPaymentHistory where loanid = @loanid
select isnull(LEAD(PaymentDate) over (partition by loanid order by PaymentNumber),'9999-12-31') as PaymentDateNext , * from AmortizationScheduleWithBillHistory 
where loanid = 'P864D87BE3ABA' 
order by loanid, paymentnumber
*/
select * from laprodb.dbo.HISTBILLACTIVITY where loanid = '3FC5207643A2' order by activitydate desc