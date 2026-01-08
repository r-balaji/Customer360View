/**
 * REST Service for Customer 360 Summary API
 * Endpoint: /services/apexrest/Customer360/v1/customer-summary
 * 
 * Returns overall customer summary including all loan statistics and metrics
 */
@RestResource(urlMapping='/Customer360/v1/customer-summary')
global with sharing class Customer360SummaryService {
    
    /**
     * GET method to retrieve customer summary
     * Query Parameters:
     * - accountId: Salesforce Account ID (18-character)
     * - accountNumber: Account Number (alternative)
     */
    @HttpGet
    global static ResponseWrapper getCustomerSummary() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            String accountId = req.params.get('accountId');
            String accountNumber = req.params.get('accountNumber');
            
            // Validate input
            if (String.isBlank(accountId) && String.isBlank(accountNumber)) {
                return createErrorResponse('INVALID_PARAMETER', 'Either accountId or accountNumber is required');
            }
            
            // Find account
            Account account = findAccount(accountId, accountNumber);
            if (account == null) {
                return createErrorResponse('ACCOUNT_NOT_FOUND', 'Account not found with the provided ID or number');
            }
            
            // Check access
            if (!Schema.sObjectType.Account.isAccessible()) {
                return createErrorResponse('FORBIDDEN', 'Access denied to Account object');
            }
            
            // Get customer summary data
            CustomerSummaryData summaryData = buildCustomerSummary(account);
            
            ResponseWrapper response = new ResponseWrapper();
            response.success = true;
            response.message = 'Customer summary retrieved successfully';
            response.data = summaryData;
            response.timestamp = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            
            return response;
            
        } catch (Exception e) {
            System.debug('Error in getCustomerSummary: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return createErrorResponse('SERVER_ERROR', 'An error occurred while processing the request: ' + e.getMessage());
        }
    }
    
    /**
     * Find account by ID or account number
     */
    private static Account findAccount(String accountId, String accountNumber) {
        List<Account> accounts;
        
        if (String.isNotBlank(accountId)) {
            accounts = [
                SELECT Id, Name, AccountNumber, Phone,
                       (SELECT Id, Name, Email FROM Contacts LIMIT 1)
                FROM Account 
                WHERE Id = :accountId
                LIMIT 1
            ];
        } else if (String.isNotBlank(accountNumber)) {
            accounts = [
                SELECT Id, Name, AccountNumber, Phone,
                       (SELECT Id, Name, Email FROM Contacts LIMIT 1)
                FROM Account 
                WHERE AccountNumber = :accountNumber
                LIMIT 1
            ];
        }
        
        return accounts != null && !accounts.isEmpty() ? accounts[0] : null;
    }
    
    /**
     * Build customer summary data
     */
    private static CustomerSummaryData buildCustomerSummary(Account account) {
        CustomerSummaryData data = new CustomerSummaryData();
        data.accountId = account.Id;
        data.accountNumber = account.AccountNumber;
        data.customerName = account.Name;
        // Get email from Contact if available (PersonEmail is only on Person Accounts)
        data.email = account.Contacts != null && !account.Contacts.isEmpty() ? 
            account.Contacts[0].Email : null;
        data.phone = account.Phone;
        
        // Get branch information if available
        // Assuming Branch__c is a lookup field on Account
        // You may need to adjust this based on your actual field structure
        
        // Query all loan accounts for this customer
        List<loan__Loan_Account__c> loanAccounts = [
            SELECT Id, Name, loan__Loan_Amount__c, loan__Principal_Remaining__c, 
                   loan__Loan_Status__c, loan__Loan_Effective_Date__c, loan__Maturity_Date_Current__c,
                   loan__Closed_Date__c, loan__Next_Due_Generation_Date__c, loan__Interest_Rate__c,
                   loan__Product_Type__c, loan__Number_of_Installments__c,
                   loan__Branch__r.Name, loan__Client__r.Name, loan__Delinquent_Amount__c,
                   loan__Payment_Amount__c
            FROM loan__Loan_Account__c
            WHERE loan__Account__c = :account.Id
            ORDER BY loan__Loan_Effective_Date__c DESC
        ];
        
        // Calculate summary metrics
        SummaryMetrics metrics = calculateSummaryMetrics(loanAccounts);
        data.summary = metrics;
        
        // Set calculated fields from metrics
        data.totalLoanAmount = metrics.totalLoanAmount;
        data.totalPrincipalRemaining = metrics.totalOutstandingBalance;
        data.totalDelinquentAmount = metrics.totalPastDueAmount;
        data.totalBilledAmount = metrics.totalBilledAmount;
        
        // Build loan list
        List<LoanSummary> loanList = new List<LoanSummary>();
        for (loan__Loan_Account__c loan : loanAccounts) {
            LoanSummary loanSummary = buildLoanSummary(loan);
            loanList.add(loanSummary);
        }
        data.loans = loanList;
        
        return data;
    }
    
    /**
     * Calculate summary metrics
     */
    private static SummaryMetrics calculateSummaryMetrics(List<loan__Loan_Account__c> loanAccounts) {
        SummaryMetrics metrics = new SummaryMetrics();
        
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
            // Determine if loan is active or closed
            Boolean isActive = loan.loan__Loan_Status__c != null && 
                             !loan.loan__Loan_Status__c.startsWith('Closed');
            Boolean isClosed = loan.loan__Loan_Status__c != null && 
                              loan.loan__Loan_Status__c.startsWith('Closed');
            
            if (isActive) {
                activeLoans++;
                
                // Check standing
                if (loan.loan__Loan_Status__c == 'Active - Good Standing') {
                    activeGoodStanding++;
                } else if (loan.loan__Loan_Status__c == 'Active - Bad Standing') {
                    activeBadStanding++;
                    pastDueCount++;
                }
            } else if (isClosed) {
                closedLoans++;
            }
            
            // Sum amounts
            if (loan.loan__Loan_Amount__c != null) {
                totalLoanAmount += loan.loan__Loan_Amount__c;
            }
            
            if (loan.loan__Principal_Remaining__c != null) {
                totalOutstanding += loan.loan__Principal_Remaining__c;
            }
            
            // Calculate paid amount (original - remaining)
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
     * Build loan summary object
     */
    private static LoanSummary buildLoanSummary(loan__Loan_Account__c loan) {
        LoanSummary summary = new LoanSummary();
        summary.loanId = formatLoanId(loan.Name); // Format: LAI-XXXXXXXX
        summary.loanAccountId = loan.Id;
        summary.loanNumber = loan.Name;
        summary.status = loan.loan__Loan_Status__c != null ? loan.loan__Loan_Status__c : 'Unknown';
        
        // Determine standing
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
        summary.principalRemaining = loan.loan__Principal_Remaining__c != null ? loan.loan__Principal_Remaining__c.setScale(2) : 0;
        summary.interestRate = loan.loan__Interest_Rate__c != null ? loan.loan__Interest_Rate__c.setScale(2) : 0;
        summary.loanEffectiveDate = loan.loan__Loan_Effective_Date__c != null ? 
            loan.loan__Loan_Effective_Date__c.format() : null;
        summary.maturityDate = loan.loan__Maturity_Date_Current__c != null ? 
            loan.loan__Maturity_Date_Current__c.format() : null;
        summary.nextPaymentDate = loan.loan__Next_Due_Generation_Date__c != null ? 
            loan.loan__Next_Due_Generation_Date__c.format() : null;
        
        // Calculate days past due
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
        public CustomerSummaryData data;
        public String timestamp;
        public List<ErrorDetail> errors;
    }
    
    global class CustomerSummaryData {
        public String accountId;
        public String accountNumber;
        public String customerName;
        public String email;
        public String phone;
        public String branch;
        public String branchId;
        public String status;
        public Decimal totalLoanAmount;
        public Decimal totalPrincipalRemaining;
        public Decimal totalDelinquentAmount;
        public Decimal totalBilledAmount;
        public SummaryMetrics summary;
        public List<LoanSummary> loans;
    }
    
    global class SummaryMetrics {
        public Integer totalLoans;
        public Integer activeLoans;
        public Integer closedLoans;
        public Integer activeGoodStandingLoans;
        public Integer activeBadStandingLoans;
        public Decimal loanToValueRatio;
        public Decimal debtRatio;
        public Decimal totalLoanAmount;
        public Decimal totalOutstandingBalance;
        public Decimal totalPaidAmount;
        public Decimal totalPastDueAmount;
        public Decimal totalBilledAmount;
        public Integer pastDueLoanCount;
    }
    
    global class LoanSummary {
        public String loanId;
        public String loanAccountId;
        public String loanNumber;
        public String status;
        public String standing;
        public Decimal loanAmount;
        public Decimal principalRemaining;
        public Decimal interestRate;
        public String loanEffectiveDate;
        public String maturityDate;
        public String nextPaymentDate;
        public Decimal nextPaymentAmount;
        public Integer daysPastDue;
        public String productType;
    }
    
    global class ErrorDetail {
        public String field;
        public String message;
    }
}

