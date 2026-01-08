/**
 * Apex Controller for Customer 360 LWC Components
 * Provides methods to retrieve customer and loan data for Lightning Web Components
 */
public with sharing class Customer360Controller {
    
    /**
     * Search for accounts by name or account number
     * @param searchTerm Search term (name or account number)
     * @return List of matching accounts
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountWrapper> searchAccounts(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return new List<AccountWrapper>();
        }
        
        String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        
        List<Account> accounts = [
            SELECT Id, Name, AccountNumber, Phone,
                   (SELECT Id, Email FROM Contacts LIMIT 1)
            FROM Account
            WHERE Name LIKE :searchPattern 
               OR AccountNumber LIKE :searchPattern
            ORDER BY Name
            LIMIT 20
        ];
        
        List<AccountWrapper> results = new List<AccountWrapper>();
        for (Account acc : accounts) {
            AccountWrapper wrapper = new AccountWrapper();
            wrapper.id = acc.Id;
            wrapper.name = acc.Name;
            wrapper.accountNumber = acc.AccountNumber;
            wrapper.phone = acc.Phone;
            // Get email from Contact if available
            wrapper.email = acc.Contacts != null && !acc.Contacts.isEmpty() ? 
                acc.Contacts[0].Email : null;
            results.add(wrapper);
        }
        
        return results;
    }
    
    /**
     * Get customer summary data
     * @param accountId Account ID
     * @return Customer summary data
     */
    @AuraEnabled
    public static CustomerSummaryWrapper getCustomerSummary(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account ID is required');
        }
        
        Account account = [
            SELECT Id, Name, AccountNumber, Phone,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                   (SELECT Id, Email FROM Contacts LIMIT 1)
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        
        // Get all loan accounts
        List<loan__Loan_Account__c> loanAccounts = [
            SELECT Id, Name, loan__Loan_Amount__c, loan__Principal_Remaining__c, 
                   loan__Loan_Status__c, loan__Loan_Effective_Date__c, loan__Maturity_Date_Current__c,
                   loan__Closed_Date__c, loan__Next_Due_Generation_Date__c, loan__Interest_Rate__c,
                   loan__Product_Type__c, loan__Number_of_Installments__c,
                   loan__Branch__r.Name, loan__Client__r.Name, loan__Delinquent_Amount__c,
                   loan__Payment_Amount__c
            FROM loan__Loan_Account__c
            WHERE loan__Account__c = :accountId
            ORDER BY loan__Loan_Effective_Date__c DESC
        ];
        
        // Calculate summary metrics
        SummaryMetricsWrapper metrics = calculateSummaryMetrics(loanAccounts);
        
        // Build loan list
        List<LoanSummaryWrapper> loanList = new List<LoanSummaryWrapper>();
        for (loan__Loan_Account__c loan : loanAccounts) {
            LoanSummaryWrapper loanSummary = buildLoanSummary(loan);
            loanList.add(loanSummary);
        }
        
        CustomerSummaryWrapper summary = new CustomerSummaryWrapper();
        summary.accountId = account.Id;
        summary.accountNumber = account.AccountNumber;
        summary.customerName = account.Name;
        // Get email from Contact if available
        summary.email = account.Contacts != null && !account.Contacts.isEmpty() ? 
            account.Contacts[0].Email : null;
        summary.phone = account.Phone;
        
        // Build address (prefer Billing, fallback to Shipping)
        if (String.isNotBlank(account.BillingStreet) || String.isNotBlank(account.BillingCity)) {
            summary.address = buildAddressString(
                account.BillingStreet, account.BillingCity, 
                account.BillingState, account.BillingPostalCode, account.BillingCountry
            );
        } else if (String.isNotBlank(account.ShippingStreet) || String.isNotBlank(account.ShippingCity)) {
            summary.address = buildAddressString(
                account.ShippingStreet, account.ShippingCity, 
                account.ShippingState, account.ShippingPostalCode, account.ShippingCountry
            );
        } else {
            summary.address = null;
        }
        
        // Set calculated fields from metrics
        summary.totalLoanAmount = metrics.totalLoanAmount;
        summary.totalPrincipalRemaining = metrics.totalPrincipalRemaining;
        summary.totalDelinquentAmount = metrics.totalDelinquentAmount;
        summary.totalBilledAmount = metrics.totalBilledAmount;
        
        summary.summary = metrics;
        summary.loans = loanList;
        
        return summary;
    }
    
    /**
     * Format loan ID as LAI-XXXXXXXX (8 digits with leading zeros)
     */
    private static String formatLoanId(String loanName) {
        // Extract numeric part from loan name (e.g., "LA-000012" -> "000012" or "12" -> "12")
        String numericPart = loanName.replaceAll('[^0-9]', '');
        // Pad to 8 digits with leading zeros
        if (numericPart.length() > 8) {
            numericPart = numericPart.right(8);
        } else {
            numericPart = numericPart.leftPad(8).replace(' ', '0');
        }
        return 'LAI-' + numericPart;
    }
    
    /**
     * Get detailed loan information
     * @param loanAccountId Loan Account ID
     * @return Loan details
     */
    @AuraEnabled
    public static LoanDetailsWrapper getLoanDetails(String loanAccountId) {
        if (String.isBlank(loanAccountId)) {
            throw new AuraHandledException('Loan Account ID is required');
        }
        
        loan__Loan_Account__c loan = [
            SELECT Id, Name, loan__Account__c, loan__Account__r.Name, loan__Account__r.AccountNumber,
                   loan__Loan_Amount__c, loan__Principal_Remaining__c, loan__Loan_Status__c,
                   loan__Loan_Effective_Date__c, loan__Maturity_Date_Current__c, loan__Closed_Date__c,
                   loan__Next_Due_Generation_Date__c, loan__Interest_Rate__c, loan__Product_Type__c,
                   loan__Number_of_Installments__c, loan__Branch__r.Name, loan__Branch__c,
                   loan__Client__r.Name, loan__Client__c
            FROM loan__Loan_Account__c
            WHERE Id = :loanAccountId
            LIMIT 1
        ];
        
        LoanDetailsWrapper details = new LoanDetailsWrapper();
        details.loanId = formatLoanId(loan.Name);
        details.loanAccountId = loan.Id;
        details.loanNumber = loan.Name;
        details.accountId = loan.loan__Account__c;
        details.accountNumber = loan.loan__Account__r.AccountNumber;
        details.customerName = loan.loan__Account__r.Name;
        
        // Build overview
        details.overview = buildLoanOverview(loan);
        
        // Build payment schedule
        details.paymentSchedule = buildPaymentSchedule(loan.Id);
        
        // Build transactions
        details.transactions = buildTransactions(loan.Id);
        
        // Build dues and charges
        details.duesAndCharges = buildDuesAndCharges(loan.Id);
        
        return details;
    }
    
    /**
     * Calculate summary metrics
     */
    private static SummaryMetricsWrapper calculateSummaryMetrics(List<loan__Loan_Account__c> loanAccounts) {
        SummaryMetricsWrapper metrics = new SummaryMetricsWrapper();
        
        Integer totalLoans = loanAccounts.size();
        Integer activeLoans = 0;
        Integer closedLoans = 0;
        Integer activeGoodStanding = 0;
        Integer activeBadStanding = 0;
        Decimal totalLoanAmount = 0;
        Decimal totalOutstanding = 0;
        Decimal totalPaid = 0;
        Decimal totalPastDue = 0;
        Decimal totalMonthlyPayments = 0;
        Integer pastDueCount = 0;
        
        // Collect loan account IDs for querying due details
        Set<Id> loanAccountIds = new Set<Id>();
        for (loan__Loan_Account__c loan : loanAccounts) {
            loanAccountIds.add(loan.Id);
        }
        
        // Query total billed amount from Due Details where primary = true and payment_satisfied = false
        Decimal totalBilledAmount = 0;
        List<AggregateResult> dueDetailsAggregate = [
            SELECT SUM(loan__Due_Amt__c) totalDue
            FROM loan__Loan_Account_Due_Details__c
            WHERE loan__Loan_Account__c IN :loanAccountIds
            AND loan__DD_Primary_Flag__c = true
            AND loan__Payment_Satisfied__c = false
        ];
        if (!dueDetailsAggregate.isEmpty() && dueDetailsAggregate[0].get('totalDue') != null) {
            totalBilledAmount = (Decimal)dueDetailsAggregate[0].get('totalDue');
        }
        
        for (loan__Loan_Account__c loan : loanAccounts) {
            Boolean isActive = loan.loan__Loan_Status__c != null && 
                             !loan.loan__Loan_Status__c.startsWith('Closed');
            Boolean isClosed = loan.loan__Loan_Status__c != null && 
                              loan.loan__Loan_Status__c.startsWith('Closed');
            
            if (isActive) {
                activeLoans++;
                if (loan.loan__Loan_Status__c == 'Active - Good Standing') {
                    activeGoodStanding++;
                } else if (loan.loan__Loan_Status__c == 'Active - Bad Standing') {
                    activeBadStanding++;
                    pastDueCount++;
                }
            } else if (isClosed) {
                closedLoans++;
            }
            
            if (loan.loan__Loan_Amount__c != null) {
                totalLoanAmount += loan.loan__Loan_Amount__c;
            }
            if (loan.loan__Principal_Remaining__c != null) {
                totalOutstanding += loan.loan__Principal_Remaining__c;
            }
            if (loan.loan__Loan_Amount__c != null && loan.loan__Principal_Remaining__c != null) {
                totalPaid += (loan.loan__Loan_Amount__c - loan.loan__Principal_Remaining__c);
            }
            // Sum delinquent amount from loan account field
            if (loan.loan__Delinquent_Amount__c != null) {
                totalPastDue += loan.loan__Delinquent_Amount__c;
            }
            
            // Sum monthly payment amounts for active loans only (for debt ratio)
            if (isActive && loan.loan__Payment_Amount__c != null) {
                totalMonthlyPayments += loan.loan__Payment_Amount__c;
            }
        }
        
        metrics.totalLoans = totalLoans;
        metrics.activeLoans = activeLoans;
        metrics.closedLoans = closedLoans;
        metrics.activeGoodStandingLoans = activeGoodStanding;
        metrics.activeBadStandingLoans = activeBadStanding;
        metrics.totalLoanAmount = totalLoanAmount.setScale(2);
        metrics.totalOutstandingBalance = totalOutstanding.setScale(2);
        metrics.totalPrincipalRemaining = totalOutstanding.setScale(2);
        metrics.totalDelinquentAmount = totalPastDue.setScale(2);
        metrics.totalPaidAmount = totalPaid.setScale(2);
        metrics.totalPastDueAmount = totalPastDue.setScale(2);
        metrics.totalBilledAmount = totalBilledAmount.setScale(2);
        metrics.pastDueLoanCount = pastDueCount;
        
        // Calculate LTV and Debt Ratio
        metrics.loanToValueRatio = totalOutstanding > 0 ? 
            ((totalOutstanding / totalLoanAmount) * 100).setScale(2) : 0;
        
        // Debt Ratio = (Total Monthly Payments / Monthly Income) × 100
        // Monthly Income is set to $10,000 as per requirement
        Decimal monthlyIncome = 10000;
        metrics.debtRatio = monthlyIncome > 0 ? 
            ((totalMonthlyPayments / monthlyIncome) * 100).setScale(2) : 0;
        
        return metrics;
    }
    
    /**
     * Build loan summary wrapper
     */
    private static LoanSummaryWrapper buildLoanSummary(loan__Loan_Account__c loan) {
        LoanSummaryWrapper summary = new LoanSummaryWrapper();
        summary.loanId = formatLoanId(loan.Name);
        summary.loanAccountId = loan.Id;
        summary.loanNumber = loan.Name;
        summary.status = loan.loan__Loan_Status__c != null ? loan.loan__Loan_Status__c : 'Unknown';
        
        if (loan.loan__Loan_Status__c == 'Active - Good Standing') {
            summary.standing = 'Good Standing';
        } else if (loan.loan__Loan_Status__c == 'Active - Bad Standing') {
            summary.standing = 'Bad Standing';
        } else if (loan.loan__Loan_Status__c != null && loan.loan__Loan_Status__c.startsWith('Closed')) {
            summary.standing = 'Closed';
        } else {
            summary.standing = 'Unknown';
        }
        
        summary.loanAmount = loan.loan__Loan_Amount__c != null ? loan.loan__Loan_Amount__c.setScale(2) : 0;
        summary.principalRemaining = loan.loan__Principal_Remaining__c != null ? 
            loan.loan__Principal_Remaining__c.setScale(2) : 0;
        summary.interestRate = loan.loan__Interest_Rate__c != null ? loan.loan__Interest_Rate__c.setScale(2) : 0;
        summary.loanEffectiveDate = loan.loan__Loan_Effective_Date__c != null ? 
            String.valueOf(loan.loan__Loan_Effective_Date__c) : null;
        summary.maturityDate = loan.loan__Maturity_Date_Current__c != null ? 
            String.valueOf(loan.loan__Maturity_Date_Current__c) : null;
        summary.nextPaymentDate = loan.loan__Next_Due_Generation_Date__c != null ? 
            String.valueOf(loan.loan__Next_Due_Generation_Date__c) : null;
        
        if (loan.loan__Next_Due_Generation_Date__c != null && loan.loan__Loan_Status__c == 'Active - Bad Standing') {
            // Calculate days past due: due date to today (positive number)
            summary.daysPastDue = loan.loan__Next_Due_Generation_Date__c.daysBetween(Date.today());
        } else {
            summary.daysPastDue = 0;
        }
        
        summary.productType = loan.loan__Product_Type__c != null ? loan.loan__Product_Type__c : 'Unknown';
        
        return summary;
    }
    
    /**
     * Build loan overview
     */
    private static LoanOverviewWrapper buildLoanOverview(loan__Loan_Account__c loan) {
        LoanOverviewWrapper overview = new LoanOverviewWrapper();
        
        overview.status = loan.loan__Loan_Status__c != null ? loan.loan__Loan_Status__c : 'Unknown';
        
        if (loan.loan__Loan_Status__c == 'Active - Good Standing') {
            overview.standing = 'Good Standing';
        } else if (loan.loan__Loan_Status__c == 'Active - Bad Standing') {
            overview.standing = 'Bad Standing';
        } else if (loan.loan__Loan_Status__c != null && loan.loan__Loan_Status__c.startsWith('Closed')) {
            overview.standing = 'Closed';
        } else {
            overview.standing = 'Unknown';
        }
        
        overview.productType = loan.loan__Product_Type__c != null ? loan.loan__Product_Type__c : 'Unknown';
        overview.loanAmount = loan.loan__Loan_Amount__c != null ? loan.loan__Loan_Amount__c.setScale(2) : 0;
        overview.principalRemaining = loan.loan__Principal_Remaining__c != null ? 
            loan.loan__Principal_Remaining__c.setScale(2) : 0;
        overview.interestRemaining = (overview.principalRemaining * 0.05).setScale(2);
        overview.feesRemaining = 500.00;
        overview.totalOutstanding = overview.principalRemaining + 
            overview.interestRemaining + overview.feesRemaining;
        
        if (loan.loan__Loan_Amount__c != null && loan.loan__Principal_Remaining__c != null) {
            overview.totalPaidToDate = (loan.loan__Loan_Amount__c - loan.loan__Principal_Remaining__c).setScale(2);
        } else {
            overview.totalPaidToDate = 0;
        }
        
        overview.interestRate = loan.loan__Interest_Rate__c != null ? loan.loan__Interest_Rate__c.setScale(2) : 0;
        overview.apr = overview.interestRate;
        overview.loanEffectiveDate = loan.loan__Loan_Effective_Date__c != null ? 
            String.valueOf(loan.loan__Loan_Effective_Date__c) : null;
        overview.maturityDate = loan.loan__Maturity_Date_Current__c != null ? 
            String.valueOf(loan.loan__Maturity_Date_Current__c) : null;
        overview.closedDate = loan.loan__Closed_Date__c != null ? 
            String.valueOf(loan.loan__Closed_Date__c) : null;
        overview.branch = loan.loan__Branch__r.Name;
        overview.branchId = loan.loan__Branch__c;
        overview.loanOfficer = loan.loan__Client__r.Name;
        overview.loanOfficerId = loan.loan__Client__c;
        overview.paymentTerm = loan.loan__Number_of_Installments__c != null ? 
            Integer.valueOf(loan.loan__Number_of_Installments__c) : 0;
        overview.paymentFrequency = 'Monthly';
        
        List<loan__Repayment_Schedule__c> paidSchedules = [
            SELECT Id FROM loan__Repayment_Schedule__c
            WHERE loan__Loan_Account__c = :loan.Id AND loan__isPaid__c = true
        ];
        overview.paymentsMade = paidSchedules.size();
        overview.paymentsRemaining = overview.paymentTerm - overview.paymentsMade;
        
        overview.nextPaymentDate = loan.loan__Next_Due_Generation_Date__c != null ? 
            String.valueOf(loan.loan__Next_Due_Generation_Date__c) : null;
        
        overview.nextPaymentAmount = overview.totalOutstanding / 
            (overview.paymentsRemaining > 0 ? overview.paymentsRemaining : 1);
        overview.nextPaymentAmount = overview.nextPaymentAmount.setScale(2);
        
        if (loan.loan__Next_Due_Generation_Date__c != null && loan.loan__Loan_Status__c == 'Active - Bad Standing') {
            // Calculate days past due: due date to today (positive number)
            overview.daysPastDue = loan.loan__Next_Due_Generation_Date__c.daysBetween(Date.today());
        } else {
            overview.daysPastDue = 0;
        }
        
        if (overview.paymentTerm > 0) {
            overview.progressPercentage = ((Decimal.valueOf(overview.paymentsMade) / 
                Decimal.valueOf(overview.paymentTerm)) * 100).setScale(1);
        } else {
            overview.progressPercentage = 0;
        }
        
        return overview;
    }
    
    /**
     * Build payment schedule
     */
    private static PaymentScheduleWrapper buildPaymentSchedule(Id loanAccountId) {
        PaymentScheduleWrapper schedule = new PaymentScheduleWrapper();
        
        List<loan__Repayment_Schedule__c> schedules = [
            SELECT Id, loan__Due_Date__c, loan__Due_Principal__c,
                   loan__Due_Interest__c, loan__Total_Due_Fees__c, loan__Total_Installment__c, 
                   loan__isPaid__c, loan__Date_Paid__c, loan__Paid_Total__c, 
                   loan__Past_Due_Date__c, loan__Transaction_Amount__c
            FROM loan__Repayment_Schedule__c
            WHERE loan__Loan_Account__c = :loanAccountId
            ORDER BY loan__Due_Date__c ASC
        ];
        
        schedule.totalInstallments = schedules.size();
        schedule.paidInstallments = 0;
        schedule.pendingInstallments = 0;
        schedule.pastDueInstallments = 0;
        
        List<InstallmentWrapper> installments = new List<InstallmentWrapper>();
        
        Integer installmentCounter = 1;
        for (loan__Repayment_Schedule__c sched : schedules) {
            InstallmentWrapper inst = new InstallmentWrapper();
            // Use counter since there's no Installment_Number field - number by order
            inst.installmentNumber = installmentCounter++;
            inst.dueDate = sched.loan__Due_Date__c != null ? String.valueOf(sched.loan__Due_Date__c) : null;
            inst.principalDue = sched.loan__Due_Principal__c != null ? sched.loan__Due_Principal__c.setScale(2) : 0;
            inst.interestDue = sched.loan__Due_Interest__c != null ? sched.loan__Due_Interest__c.setScale(2) : 0;
            inst.feesDue = sched.loan__Total_Due_Fees__c != null ? sched.loan__Total_Due_Fees__c.setScale(2) : 0;
            inst.totalDue = sched.loan__Total_Installment__c != null ? sched.loan__Total_Installment__c.setScale(2) : 0;
            inst.paidDate = sched.loan__Date_Paid__c != null ? String.valueOf(sched.loan__Date_Paid__c) : null;
            inst.amountPaid = sched.loan__Paid_Total__c != null ? sched.loan__Paid_Total__c.setScale(2) : 0;
            
            if (sched.loan__isPaid__c == true) {
                inst.status = 'Paid';
                schedule.paidInstallments++;
            } else if (sched.loan__Past_Due_Date__c == true) {
                inst.status = 'Past Due';
                schedule.pastDueInstallments++;
            } else {
                inst.status = 'Pending';
                schedule.pendingInstallments++;
            }
            
            if (sched.loan__Due_Date__c != null && sched.loan__Past_Due_Date__c == true) {
                // Calculate days past due: due date to today (positive number)
                inst.daysPastDue = sched.loan__Due_Date__c.daysBetween(Date.today());
            } else {
                inst.daysPastDue = 0;
            }
            
            installments.add(inst);
        }
        
        schedule.installments = installments;
        return schedule;
    }
    
    /**
     * Build transactions
     */
    private static TransactionWrapper buildTransactions(Id loanAccountId) {
        TransactionWrapper transData = new TransactionWrapper();
        
        List<loan__Loan_Payment_Transaction__c> transactions = [
            SELECT Id, loan__Transaction_Date__c, loan__Transaction_Amount__c,
                   loan__Principal__c, loan__Interest__c, loan__Fees__c,
                   loan__Payment_Mode__c, loan__Cleared__c, loan__Cheque_Number__c
            FROM loan__Loan_Payment_Transaction__c
            WHERE loan__Loan_Account__c = :loanAccountId
            ORDER BY loan__Transaction_Date__c DESC
            LIMIT 100
        ];
        
        transData.totalTransactions = transactions.size();
        transData.totalAmount = 0;
        
        List<TransactionDetailWrapper> transList = new List<TransactionDetailWrapper>();
        
        for (loan__Loan_Payment_Transaction__c trans : transactions) {
            TransactionDetailWrapper detail = new TransactionDetailWrapper();
            detail.transactionId = trans.Id;
            detail.transactionDate = trans.loan__Transaction_Date__c != null ? 
                String.valueOf(trans.loan__Transaction_Date__c) : null;
            detail.amount = trans.loan__Transaction_Amount__c != null ? 
                trans.loan__Transaction_Amount__c.setScale(2) : 0;
            detail.principalApplied = trans.loan__Principal__c != null ? 
                trans.loan__Principal__c.setScale(2) : 0;
            detail.interestApplied = trans.loan__Interest__c != null ? 
                trans.loan__Interest__c.setScale(2) : 0;
            detail.feesApplied = trans.loan__Fees__c != null ? 
                trans.loan__Fees__c.setScale(2) : 0;
            detail.paymentMethod = trans.loan__Payment_Mode__c;
            // Cleared__c is a checkbox - convert to status string
            detail.status = trans.loan__Cleared__c == true ? 'Cleared' : 'Pending';
            detail.referenceNumber = trans.loan__Cheque_Number__c;
            detail.description = null; // Description field doesn't exist on Loan_Payment_Transaction__c
            
            transData.totalAmount += detail.amount;
            transList.add(detail);
        }
        
        transData.totalAmount = transData.totalAmount.setScale(2);
        transData.transactions = transList;
        
        return transData;
    }
    
    /**
     * Build dues and charges
     */
    private static DuesAndChargesWrapper buildDuesAndCharges(Id loanAccountId) {
        DuesAndChargesWrapper duesData = new DuesAndChargesWrapper();
        
        List<loan__Due_Payment__c> duePayments = [
            SELECT Id, loan__Principal__c, loan__Interest__c, loan__Fees__c,
                   loan__Due__r.loan__Due_Date__c
            FROM loan__Due_Payment__c
            WHERE loan__Due__r.loan__Loan_Account__c = :loanAccountId
            ORDER BY loan__Due__r.loan__Due_Date__c DESC NULLS LAST
            LIMIT 1
        ];
        
        CurrentDuesWrapper currentDues = new CurrentDuesWrapper();
        if (!duePayments.isEmpty()) {
            loan__Due_Payment__c due = duePayments[0];
            currentDues.principalDue = due.loan__Principal__c != null ? 
                due.loan__Principal__c.setScale(2) : 0;
            currentDues.interestDue = due.loan__Interest__c != null ? 
                due.loan__Interest__c.setScale(2) : 0;
            currentDues.feesDue = due.loan__Fees__c != null ? 
                due.loan__Fees__c.setScale(2) : 0;
            // Calculate total due from components
            currentDues.totalDue = (currentDues.principalDue + currentDues.interestDue + currentDues.feesDue).setScale(2);
            
            // Calculate days past due from due date
            if (due.loan__Due__r != null && due.loan__Due__r.loan__Due_Date__c != null) {
                Date dueDate = due.loan__Due__r.loan__Due_Date__c;
                currentDues.daysPastDue = dueDate < Date.today() ? dueDate.daysBetween(Date.today()) : 0;
                currentDues.nextPaymentDate = String.valueOf(dueDate);
            } else {
                currentDues.daysPastDue = 0;
                currentDues.nextPaymentDate = null;
            }
        }
        
        duesData.currentDues = currentDues;
        
        // Note: Fee__c is a configuration object and doesn't have a direct relationship to Loan_Account__c
        // Fees are tracked through Due_Fee__c which relates to Repayment_Schedule__c
        // For now, returning empty list - can be enhanced to query Due_Fee__c if needed
        List<FeeWrapper> feeList = new List<FeeWrapper>();
        duesData.fees = feeList;
        
        List<loan__Charge__c> charges = [
            SELECT Id, loan__Charge_Type__c, loan__Original_Amount__c, loan__Date__c,
                   loan__Reference__c, loan__Status__c
            FROM loan__Charge__c
            WHERE loan__Loan_Account__c = :loanAccountId
            ORDER BY loan__Date__c DESC
        ];
        
        List<ChargeWrapper> chargeList = new List<ChargeWrapper>();
        for (loan__Charge__c charge : charges) {
            ChargeWrapper chargeDetail = new ChargeWrapper();
            chargeDetail.chargeId = charge.Id;
            chargeDetail.chargeType = charge.loan__Charge_Type__c;
            chargeDetail.amount = charge.loan__Original_Amount__c != null ? 
                charge.loan__Original_Amount__c.setScale(2) : 0;
            chargeDetail.chargeDate = charge.loan__Date__c != null ? 
                String.valueOf(charge.loan__Date__c) : null;
            chargeDetail.description = charge.loan__Reference__c;
            chargeDetail.status = charge.loan__Status__c != null ? charge.loan__Status__c : 'Unknown';
            chargeList.add(chargeDetail);
        }
        duesData.charges = chargeList;
        
        return duesData;
    }
    
    /**
     * Build address string from address components
     */
    private static String buildAddressString(String street, String city, String state, String postalCode, String country) {
        List<String> addressParts = new List<String>();
        
        if (String.isNotBlank(street)) {
            addressParts.add(street);
        }
        if (String.isNotBlank(city)) {
            addressParts.add(city);
        }
        if (String.isNotBlank(state)) {
            addressParts.add(state);
        }
        if (String.isNotBlank(postalCode)) {
            addressParts.add(postalCode);
        }
        if (String.isNotBlank(country)) {
            addressParts.add(country);
        }
        
        return addressParts.isEmpty() ? null : String.join(addressParts, ', ');
    }
    
    // Wrapper Classes
    public class AccountWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
    }
    
    public class CustomerSummaryWrapper {
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String address;
        @AuraEnabled public Decimal totalLoanAmount;
        @AuraEnabled public Decimal totalPrincipalRemaining;
        @AuraEnabled public Decimal totalDelinquentAmount;
        @AuraEnabled public Decimal totalBilledAmount;
        @AuraEnabled public SummaryMetricsWrapper summary;
        @AuraEnabled public List<LoanSummaryWrapper> loans;
    }
    
    public class SummaryMetricsWrapper {
        @AuraEnabled public Integer totalLoans;
        @AuraEnabled public Integer activeLoans;
        @AuraEnabled public Integer closedLoans;
        @AuraEnabled public Integer activeGoodStandingLoans;
        @AuraEnabled public Integer activeBadStandingLoans;
        @AuraEnabled public Decimal loanToValueRatio;
        @AuraEnabled public Decimal debtRatio;
        @AuraEnabled public Decimal totalLoanAmount;
        @AuraEnabled public Decimal totalOutstandingBalance;
        @AuraEnabled public Decimal totalPrincipalRemaining;
        @AuraEnabled public Decimal totalDelinquentAmount;
        @AuraEnabled public Decimal totalPaidAmount;
        @AuraEnabled public Decimal totalPastDueAmount;
        @AuraEnabled public Decimal totalBilledAmount;
        @AuraEnabled public Integer pastDueLoanCount;
    }
    
    public class LoanSummaryWrapper {
        @AuraEnabled public String loanId;
        @AuraEnabled public String loanAccountId;
        @AuraEnabled public String loanNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String standing;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public Decimal principalRemaining;
        @AuraEnabled public Decimal interestRate;
        @AuraEnabled public String loanEffectiveDate;
        @AuraEnabled public String maturityDate;
        @AuraEnabled public String nextPaymentDate;
        @AuraEnabled public Integer daysPastDue;
        @AuraEnabled public String productType;
    }
    
    public class LoanDetailsWrapper {
        @AuraEnabled public String loanId;
        @AuraEnabled public String loanAccountId;
        @AuraEnabled public String loanNumber;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public LoanOverviewWrapper overview;
        @AuraEnabled public PaymentScheduleWrapper paymentSchedule;
        @AuraEnabled public TransactionWrapper transactions;
        @AuraEnabled public DuesAndChargesWrapper duesAndCharges;
    }
    
    public class LoanOverviewWrapper {
        @AuraEnabled public String status;
        @AuraEnabled public String standing;
        @AuraEnabled public String productType;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public Decimal principalRemaining;
        @AuraEnabled public Decimal interestRemaining;
        @AuraEnabled public Decimal feesRemaining;
        @AuraEnabled public Decimal totalOutstanding;
        @AuraEnabled public Decimal totalPaidToDate;
        @AuraEnabled public Decimal interestRate;
        @AuraEnabled public Decimal apr;
        @AuraEnabled public String loanEffectiveDate;
        @AuraEnabled public String maturityDate;
        @AuraEnabled public String closedDate;
        @AuraEnabled public String branch;
        @AuraEnabled public String branchId;
        @AuraEnabled public String loanOfficer;
        @AuraEnabled public String loanOfficerId;
        @AuraEnabled public Integer paymentTerm;
        @AuraEnabled public String paymentFrequency;
        @AuraEnabled public Integer paymentsMade;
        @AuraEnabled public Integer paymentsRemaining;
        @AuraEnabled public String nextPaymentDate;
        @AuraEnabled public Decimal nextPaymentAmount;
        @AuraEnabled public Integer daysPastDue;
        @AuraEnabled public Decimal progressPercentage;
    }
    
    public class PaymentScheduleWrapper {
        @AuraEnabled public Integer totalInstallments;
        @AuraEnabled public Integer paidInstallments;
        @AuraEnabled public Integer pendingInstallments;
        @AuraEnabled public Integer pastDueInstallments;
        @AuraEnabled public List<InstallmentWrapper> installments;
    }
    
    public class InstallmentWrapper {
        @AuraEnabled public Integer installmentNumber;
        @AuraEnabled public String dueDate;
        @AuraEnabled public Decimal principalDue;
        @AuraEnabled public Decimal interestDue;
        @AuraEnabled public Decimal feesDue;
        @AuraEnabled public Decimal totalDue;
        @AuraEnabled public String paidDate;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public String status;
        @AuraEnabled public Integer daysPastDue;
    }
    
    public class TransactionWrapper {
        @AuraEnabled public Integer totalTransactions;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public List<TransactionDetailWrapper> transactions;
    }
    
    public class TransactionDetailWrapper {
        @AuraEnabled public String transactionId;
        @AuraEnabled public String transactionDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal principalApplied;
        @AuraEnabled public Decimal interestApplied;
        @AuraEnabled public Decimal feesApplied;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public String status;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public String description;
    }
    
    public class DuesAndChargesWrapper {
        @AuraEnabled public CurrentDuesWrapper currentDues;
        @AuraEnabled public List<FeeWrapper> fees;
        @AuraEnabled public List<ChargeWrapper> charges;
    }
    
    public class CurrentDuesWrapper {
        @AuraEnabled public Decimal principalDue;
        @AuraEnabled public Decimal interestDue;
        @AuraEnabled public Decimal feesDue;
        @AuraEnabled public Decimal totalDue;
        @AuraEnabled public Integer daysPastDue;
        @AuraEnabled public String nextPaymentDate;
    }
    
    public class FeeWrapper {
        @AuraEnabled public String feeId;
        @AuraEnabled public String feeType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String dueDate;
        @AuraEnabled public String paidDate;
        @AuraEnabled public String status;
    }
    
    public class ChargeWrapper {
        @AuraEnabled public String chargeId;
        @AuraEnabled public String chargeType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String chargeDate; // Changed from 'date' (reserved word)
        @AuraEnabled public String description;
        @AuraEnabled public String status;
    }
}

