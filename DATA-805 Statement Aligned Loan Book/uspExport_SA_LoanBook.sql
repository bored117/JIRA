USE [OdsLapro]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[uspExport_SA_LoanBook]
--***************************************************************************
--  Desc : Generates Statement Aligned Loanbook.
--
--         Generate Statement Aligned Loanbook.
--    
--  Call Ex:  Declare @AsOfDate DateTime=GetDate()
--            EXEC dbo.uspExport_LoanBook  @AsOfDate, 4
--
--  Date		Author      Jira		Change
--  5/31/17		J Park		DATA-805	First Cumulative Loanbook Statement Aligned.
--***************************************************************************
     /* INPUTS */
     @AsOfDate        DateTime    = NULL    -- if NULL, then use current date
--    ,@PortfolioID     int         = NULL    -- if NULL, then all Portfolios
AS
BEGIN

set @AsOfDate = isnull(@AsOfDate,getdate())

select ASWP.LoanID, MonthNUmber -- StatementNumber using paymentnumber?
	, PaymentDate as StatementDueDate, EffectiveDate
	, case when status in ('posted','scheduled') then AmountPrincipal else 0.0 end as AmountPrincipal
	, case when status in ('posted','scheduled') then AmountInterest else 0.0 end as AmountInterest
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
						where PH.loanid = BH.loanid
							and PH.PaymentDate < BH.PaymentDateNext and PH.PaymentDate >= BH.PaymentDate 
					) PHBH
			group by LoanID, MonthReal, Status
		) ASWP
		LEFT outer JOIN LAPro.CREDITBUREAU CB ON CB.LoanID = ASWP.LoanID
		LEFT outer JOIN LAPro.Loan2 L2 ON L2.LoanID = ASWP.LoanID
		LEFT outer join LAPro.Loan L on L.LoanID = ASWP.LoanID
	where PaymentDate < @AsOfDate
ORDER BY ASWP.LOANID, MonthNumber, PaymentDate, EffectiveDate	
END