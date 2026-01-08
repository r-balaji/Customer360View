/**
 * REST Service for Customer 360 Loan Details API
 * Endpoint: /services/apexrest/Customer360/v1/loan-details
 * 
 * Returns detailed information about a specific loan account
 */
@RestResource(urlMapping='/Customer360/v1/loan-details')
global with sharing class Customer360LoanDetailsService {
    
    /**
     * GET method to retrieve loan details
     * Query Parameters:
     * - loanId: Loan ID in format 'LAI-XXXXXXXX' OR
     * - loanAccountId: Direct Salesforce Loan Account ID (18-character)
     */
    @HttpGet
    global static ResponseWrapper getLoanDetails() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            String loanId = req.params.get('loanId');
            String loanAccountId = req.params.get('loanAccountId');
            
            // Validate input - need either loanId or loanAccountId
            if (String.isBlank(loanId) && String.isBlank(loanAccountId)) {
                return createErrorResponse('INVALID_PARAMETER', 
                    'Either loanId (format: LAI-XXXXXXXX) or loanAccountId (Salesforce ID) parameter is required');
            }
            
            loan__Loan_Account__c loanAccount = null;
            
            // If loanAccountId is provided, use it directly
            if (String.isNotBlank(loanAccountId)) {
                try {
                    loanAccount = [
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
                } catch (Exception e) {
                    return createErrorResponse('INVALID_LOAN_ACCOUNT_ID', 
                        'Invalid loan account ID format: ' + loanAccountId);
                }
            } else if (String.isNotBlank(loanId)) {
                // Validate loan ID format (LAI-XXXXXXXX - 8 digits)
                if (!loanId.startsWith('LAI-') || loanId.length() != 12) {
                    return createErrorResponse('INVALID_LOAN_ID_FORMAT', 
                        'Loan ID must be in format LAI-XXXXXXXX (8 digits)');
                }
                
                // Extract numeric part from loan ID (LAI-00000012 -> 00000012)
                String numericPart = loanId.substring(4); // Remove 'LAI-' prefix
                // Remove leading zeros to get the actual number (00000012 -> 12)
                // Handle case where all digits are zeros
                String numericValue;
                try {
                    Integer numValue = Integer.valueOf(numericPart);
                    numericValue = String.valueOf(numValue);
                } catch (Exception e) {
                    // If conversion fails, use the original padded value
                    numericValue = numericPart;
                }
                
                // Find loan account - try multiple formats
                loanAccount = findLoanAccount(numericValue, numericPart);
            }
            
            if (loanAccount == null) {
                return createErrorResponse('LOAN_NOT_FOUND', 
                    'No loan found with the provided identifier');
            }
            
            // Check access
            if (!Schema.sObjectType.loan__Loan_Account__c.isAccessible()) {
                return createErrorResponse('FORBIDDEN', 'Access denied to Loan Account object');
            }
            
            // Build loan details
            LoanDetailsData loanData = buildLoanDetails(loanAccount);
            
            ResponseWrapper response = new ResponseWrapper();
            response.success = true;
            response.message = 'Loan details retrieved successfully';
            response.data = loanData;
            response.timestamp = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            
            return response;
            
        } catch (Exception e) {
            System.debug('Error in getLoanDetails: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return createErrorResponse('SERVER_ERROR', 
                'An error occurred while processing the request: ' + e.getMessage());
        }
    }
    
    /**
     * Find loan account by numeric value
     * Tries multiple formats: LA-{numericValue}, LA-{paddedValue}, {numericValue}, {paddedValue}
     */
    private static loan__Loan_Account__c findLoanAccount(String numericValue, String paddedValue) {
        // Build list of possible name formats to search
        Set<String> searchNames = new Set<String>();
        
        // Add LA- prefix with numeric value (e.g., LA-12)
        searchNames.add('LA-' + numericValue);
        
        // Add LA- prefix with padded value (e.g., LA-00000012)
        searchNames.add('LA-' + paddedValue);
        
        // Add just numeric value (e.g., 12)
        searchNames.add(numericValue);
        
        // Add padded value (e.g., 00000012)
        searchNames.add(paddedValue);
        
        // Try different padding lengths (6, 7, 8 digits)
        if (paddedValue.length() >= 6) {
            String padded6 = numericValue.leftPad(6).replace(' ', '0');
            searchNames.add('LA-' + padded6);
            searchNames.add(padded6);
        }
        if (paddedValue.length() >= 7) {
            String padded7 = numericValue.leftPad(7).replace(' ', '0');
            searchNames.add('LA-' + padded7);
            searchNames.add(padded7);
        }
        
        List<loan__Loan_Account__c> loans = [
            SELECT Id, Name, loan__Account__c, loan__Account__r.Name, loan__Account__r.AccountNumber,
                   loan__Loan_Amount__c, loan__Principal_Remaining__c, loan__Loan_Status__c,
                   loan__Loan_Effective_Date__c, loan__Maturity_Date_Current__c, loan__Closed_Date__c,
                   loan__Next_Due_Generation_Date__c, loan__Interest_Rate__c, loan__Product_Type__c,
                   loan__Number_of_Installments__c, loan__Branch__r.Name, loan__Branch__c,
                   loan__Client__r.Name, loan__Client__c
            FROM loan__Loan_Account__c
            WHERE Name IN :searchNames
            LIMIT 1
        ];
        
        return loans != null && !loans.isEmpty() ? loans[0] : null;
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
     * Build comprehensive loan details
     */
    private static LoanDetailsData buildLoanDetails(loan__Loan_Account__c loanAccount) {
        LoanDetailsData data = new LoanDetailsData();
        
        // Basic loan info
        data.loanId = formatLoanId(loanAccount.Name);
        data.loanAccountId = loanAccount.Id;
        data.loanNumber = loanAccount.Name;
        data.accountId = loanAccount.loan__Account__c;
        data.accountNumber = loanAccount.loan__Account__r.AccountNumber;
        data.customerName = loanAccount.loan__Account__r.Name;
        
        // Build overview
        data.overview = buildLoanOverview(loanAccount);
        
        // Build payment schedule
        data.paymentSchedule = buildPaymentSchedule(loanAccount.Id);
        
        // Build transactions
        data.transactions = buildTransactions(loanAccount.Id);
        
        // Build dues and charges
        data.duesAndCharges = buildDuesAndCharges(loanAccount.Id);
        
        return data;
    }
    
    /**
     * Build loan overview
     */
    private static LoanOverview buildLoanOverview(loan__Loan_Account__c loan) {
        LoanOverview overview = new LoanOverview();
        
        overview.status = loan.loan__Loan_Status__c != null ? loan.loan__Loan_Status__c : 'Unknown';
        
        // Determine standing
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
        
        // Calculate remaining interest and fees (simplified - you may need to query actual values)
        overview.interestRemaining = (overview.principalRemaining * 0.05).setScale(2); // Estimate
        overview.feesRemaining = 500.00; // Placeholder
        
        overview.totalOutstanding = overview.principalRemaining + 
            overview.interestRemaining + overview.feesRemaining;
        
        // Calculate total paid
        if (loan.loan__Loan_Amount__c != null && loan.loan__Principal_Remaining__c != null) {
            overview.totalPaidToDate = (loan.loan__Loan_Amount__c - loan.loan__Principal_Remaining__c).setScale(2);
        } else {
            overview.totalPaidToDate = 0;
        }
        
        overview.interestRate = loan.loan__Interest_Rate__c != null ? loan.loan__Interest_Rate__c.setScale(2) : 0;
        overview.apr = overview.interestRate;
        overview.loanEffectiveDate = loan.loan__Loan_Effective_Date__c != null ? 
            loan.loan__Loan_Effective_Date__c.format() : null;
        overview.maturityDate = loan.loan__Maturity_Date_Current__c != null ? 
            loan.loan__Maturity_Date_Current__c.format() : null;
        overview.closedDate = loan.loan__Closed_Date__c != null ? 
            loan.loan__Closed_Date__c.format() : null;
        overview.branch = loan.loan__Branch__r.Name;
        overview.branchId = loan.loan__Branch__c;
        overview.loanOfficer = loan.loan__Client__r.Name;
        overview.loanOfficerId = loan.loan__Client__c;
        overview.paymentTerm = loan.loan__Number_of_Installments__c != null ? 
            Integer.valueOf(loan.loan__Number_of_Installments__c) : 0;
        overview.paymentFrequency = 'Monthly'; // You may need to get this from product or loan settings
        
        // Calculate payments made and remaining
        List<loan__Repayment_Schedule__c> paidSchedules = [
            SELECT Id FROM loan__Repayment_Schedule__c
            WHERE loan__Loan_Account__c = :loan.Id
            AND loan__isPaid__c = true
        ];
        overview.paymentsMade = paidSchedules.size();
        overview.paymentsRemaining = overview.paymentTerm - overview.paymentsMade;
        
        overview.nextPaymentDate = loan.loan__Next_Due_Generation_Date__c != null ? 
            loan.loan__Next_Due_Generation_Date__c.format() : null;
        
        // Calculate next payment amount (simplified)
        overview.nextPaymentAmount = overview.totalOutstanding / 
            (overview.paymentsRemaining > 0 ? overview.paymentsRemaining : 1);
        overview.nextPaymentAmount = overview.nextPaymentAmount.setScale(2);
        
        // Calculate days past due
        if (loan.loan__Next_Due_Generation_Date__c != null && loan.loan__Loan_Status__c == 'Active - Bad Standing') {
            // Calculate days past due: due date to today (positive number)
            overview.daysPastDue = loan.loan__Next_Due_Generation_Date__c.daysBetween(Date.today());
        } else {
            overview.daysPastDue = 0;
        }
        
        // Calculate progress percentage
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
    private static PaymentScheduleData buildPaymentSchedule(Id loanAccountId) {
        PaymentScheduleData schedule = new PaymentScheduleData();
        
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
        
        List<InstallmentDetail> installments = new List<InstallmentDetail>();
        
        Integer installmentCounter = 1;
        for (loan__Repayment_Schedule__c sched : schedules) {
            InstallmentDetail inst = new InstallmentDetail();
            // Use counter since there's no Installment_Number field
            inst.installmentNumber = installmentCounter++;
            inst.dueDate = sched.loan__Due_Date__c != null ? sched.loan__Due_Date__c.format() : null;
            inst.principalDue = sched.loan__Due_Principal__c != null ? 
                sched.loan__Due_Principal__c.setScale(2) : 0;
            inst.interestDue = sched.loan__Due_Interest__c != null ? 
                sched.loan__Due_Interest__c.setScale(2) : 0;
            inst.feesDue = sched.loan__Total_Due_Fees__c != null ? 
                sched.loan__Total_Due_Fees__c.setScale(2) : 0;
            inst.totalDue = sched.loan__Total_Installment__c != null ? 
                sched.loan__Total_Installment__c.setScale(2) : 0;
            inst.paidDate = sched.loan__Date_Paid__c != null ? sched.loan__Date_Paid__c.format() : null;
            inst.amountPaid = sched.loan__Paid_Total__c != null ? 
                sched.loan__Paid_Total__c.setScale(2) : 0;
            
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
            
            // Calculate days past due
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
     * Build transaction history
     */
    private static TransactionData buildTransactions(Id loanAccountId) {
        TransactionData transData = new TransactionData();
        
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
        
        List<TransactionDetail> transList = new List<TransactionDetail>();
        
        for (loan__Loan_Payment_Transaction__c trans : transactions) {
            TransactionDetail detail = new TransactionDetail();
            detail.transactionId = trans.Id;
            detail.transactionDate = trans.loan__Transaction_Date__c != null ? 
                trans.loan__Transaction_Date__c.format() : null;
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
    private static DuesAndChargesData buildDuesAndCharges(Id loanAccountId) {
        DuesAndChargesData duesData = new DuesAndChargesData();
        
        // Get current dues
        List<loan__Due_Payment__c> duePayments = [
            SELECT Id, loan__Principal__c, loan__Interest__c, loan__Fees__c,
                   loan__Due__r.loan__Due_Date__c
            FROM loan__Due_Payment__c
            WHERE loan__Due__r.loan__Loan_Account__c = :loanAccountId
            ORDER BY loan__Due__r.loan__Due_Date__c DESC NULLS LAST
            LIMIT 1
        ];
        
        CurrentDues currentDues = new CurrentDues();
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
                currentDues.nextPaymentDate = dueDate.format();
            } else {
                currentDues.daysPastDue = 0;
                currentDues.nextPaymentDate = null;
            }
        } else {
            currentDues.principalDue = 0;
            currentDues.interestDue = 0;
            currentDues.feesDue = 0;
            currentDues.totalDue = 0;
            currentDues.daysPastDue = 0;
            currentDues.nextPaymentDate = null;
        }
        
        duesData.currentDues = currentDues;
        
        // Note: Fee__c is a configuration object and doesn't have a direct relationship to Loan_Account__c
        // Fees are tracked through Due_Fee__c which relates to Repayment_Schedule__c
        // For now, returning empty list - can be enhanced to query Due_Fee__c if needed
        List<FeeDetail> feeList = new List<FeeDetail>();
        duesData.fees = feeList;
        
        // Get charges
        List<loan__Charge__c> charges = [
            SELECT Id, loan__Charge_Type__c, loan__Original_Amount__c, loan__Date__c,
                   loan__Reference__c, loan__Status__c
            FROM loan__Charge__c
            WHERE loan__Loan_Account__c = :loanAccountId
            ORDER BY loan__Date__c DESC
        ];
        
        List<ChargeDetail> chargeList = new List<ChargeDetail>();
        for (loan__Charge__c charge : charges) {
            ChargeDetail chargeDetail = new ChargeDetail();
            chargeDetail.chargeId = charge.Id;
            chargeDetail.chargeType = charge.loan__Charge_Type__c;
            chargeDetail.amount = charge.loan__Original_Amount__c != null ? 
                charge.loan__Original_Amount__c.setScale(2) : 0;
            chargeDetail.chargeDate = charge.loan__Date__c != null ? 
                charge.loan__Date__c.format() : null;
            chargeDetail.description = charge.loan__Reference__c;
            chargeDetail.status = charge.loan__Status__c != null ? charge.loan__Status__c : 'Unknown';
            chargeList.add(chargeDetail);
        }
        duesData.charges = chargeList;
        
        return duesData;
    }
    
    /**
     * Create error response
     */
    private static ResponseWrapper createErrorResponse(String errorCode, String message) {
        ResponseWrapper response = new ResponseWrapper();
        response.success = false;
        response.message = message;
        response.errorCode = errorCode;
        response.timestamp = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        return response;
    }
    
    // Wrapper Classes
    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public String errorCode;
        public LoanDetailsData data;
        public String timestamp;
        public List<ErrorDetail> errors;
    }
    
    global class LoanDetailsData {
        public String loanId;
        public String loanAccountId;
        public String loanNumber;
        public String accountId;
        public String accountNumber;
        public String customerName;
        public LoanOverview overview;
        public PaymentScheduleData paymentSchedule;
        public TransactionData transactions;
        public DuesAndChargesData duesAndCharges;
    }
    
    global class LoanOverview {
        public String status;
        public String standing;
        public String productType;
        public Decimal loanAmount;
        public Decimal principalRemaining;
        public Decimal interestRemaining;
        public Decimal feesRemaining;
        public Decimal totalOutstanding;
        public Decimal totalPaidToDate;
        public Decimal interestRate;
        public Decimal apr;
        public String loanEffectiveDate;
        public String maturityDate;
        public String closedDate;
        public String branch;
        public String branchId;
        public String loanOfficer;
        public String loanOfficerId;
        public Integer paymentTerm;
        public String paymentFrequency;
        public Integer paymentsMade;
        public Integer paymentsRemaining;
        public String nextPaymentDate;
        public Decimal nextPaymentAmount;
        public Integer daysPastDue;
        public Decimal progressPercentage;
    }
    
    global class PaymentScheduleData {
        public Integer totalInstallments;
        public Integer paidInstallments;
        public Integer pendingInstallments;
        public Integer pastDueInstallments;
        public List<InstallmentDetail> installments;
    }
    
    global class InstallmentDetail {
        public Integer installmentNumber;
        public String dueDate;
        public Decimal principalDue;
        public Decimal interestDue;
        public Decimal feesDue;
        public Decimal totalDue;
        public String paidDate;
        public Decimal amountPaid;
        public String status;
        public Integer daysPastDue;
    }
    
    global class TransactionData {
        public Integer totalTransactions;
        public Decimal totalAmount;
        public List<TransactionDetail> transactions;
    }
    
    global class TransactionDetail {
        public String transactionId;
        public String transactionDate;
        public Decimal amount;
        public Decimal principalApplied;
        public Decimal interestApplied;
        public Decimal feesApplied;
        public String paymentMethod;
        public String status;
        public String referenceNumber;
        public String description;
    }
    
    global class DuesAndChargesData {
        public CurrentDues currentDues;
        public List<FeeDetail> fees;
        public List<ChargeDetail> charges;
    }
    
    global class CurrentDues {
        public Decimal principalDue;
        public Decimal interestDue;
        public Decimal feesDue;
        public Decimal totalDue;
        public Integer daysPastDue;
        public String nextPaymentDate;
    }
    
    global class FeeDetail {
        public String feeId;
        public String feeType;
        public Decimal amount;
        public String dueDate;
        public String paidDate;
        public String status;
    }
    
    global class ChargeDetail {
        public String chargeId;
        public String chargeType;
        public Decimal amount;
        public String chargeDate; // Changed from 'date' (reserved word)
        public String description;
        public String status;
    }
    
    global class ErrorDetail {
        public String field;
        public String message;
    }
}

