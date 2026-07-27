/**
 * Shared read model for Customer 360 UI and REST APIs.
 * This class intentionally excludes servicing actions and Visualforce launch helpers.
 */
global with sharing class Customer360DataService {
    private static final String ACTIVE_GOOD_STANDING = 'Active - Good Standing';
    private static final String ACTIVE_BAD_STANDING = 'Active - Bad Standing';
    private static final String CLOSED_STATUS_PREFIX = 'Closed';
    private static final String MASTER_FACILITY_PRODUCT_TYPE = 'Master Facility';
    private static final Decimal DEFAULT_MONTHLY_INCOME = 10000;

    private static final String LOAN_ACCOUNT_OBJECT = 'Loan_Account__c';
    private static final String PAYMENT_TRANSACTION_OBJECT = 'Loan_Payment_Transaction__c';
    private static final String REPAYMENT_SCHEDULE_OBJECT = 'Repayment_Schedule__c';
    private static final String DUE_DETAILS_OBJECT = 'Loan_Account_Due_Details__c';
    private static final String LEGACY_DUE_DETAILS_OBJECT = 'Loan_account_Due_Details__c';
    private static final String CHARGE_OBJECT = 'Charge__c';
    private static final String COBORROWER_OBJECT = 'Coborrower__c';

    /**
     * Finds an account by Salesforce Id or Account Number and builds the Customer 360 summary.
     * @param accountId Salesforce Account Id.
     * @param accountNumber Account Number alternative.
     * @return Customer 360 summary, or null when no account is found.
     */
    global static CustomerSummaryData getCustomerSummary(String accountId, String accountNumber) {
        Account account = findAccount(accountId, accountNumber);
        if (account == null) {
            return null;
        }

        return buildCustomerSummary(account);
    }

    /**
     * Builds the Customer 360 summary for a known account Id.
     * @param accountId Salesforce Account Id.
     * @return Customer 360 summary, or null when no account is found.
     */
    global static CustomerSummaryData getCustomerSummaryByAccountId(Id accountId) {
        if (accountId == null) {
            return null;
        }

        return getCustomerSummary(String.valueOf(accountId), null);
    }

    /**
     * Builds loan details by public loan id or Salesforce Loan Account Id.
     * @param loanId Public loan id in LAI-XXXXXXXX format.
     * @param loanAccountId Salesforce Loan Account Id.
     * @return Loan detail payload, or null when no loan is found.
     */
    global static LoanDetailsData getLoanDetails(String loanId, String loanAccountId) {
        SObject loanAccount;
        if (String.isNotBlank(loanAccountId)) {
            loanAccount = findLoanAccountById(loanAccountId);
        } else if (String.isNotBlank(loanId)) {
            loanAccount = findLoanAccountByPublicId(loanId);
        }

        return loanAccount == null ? null : buildLoanDetails(loanAccount);
    }

    /**
     * Builds loan details by Salesforce Loan Account Id.
     * @param loanAccountId Salesforce Loan Account Id.
     * @return Loan detail payload, or null when no loan is found.
     */
    global static LoanDetailsData getLoanDetailsByLoanAccountId(String loanAccountId) {
        return getLoanDetails(null, loanAccountId);
    }

    private static Account findAccount(String accountId, String accountNumber) {
        List<Account> accounts = new List<Account>();

        if (String.isNotBlank(accountId)) {
            accounts = [
                SELECT Id, Name, AccountNumber, Phone,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                       ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                       (SELECT Id, Email FROM Contacts LIMIT 1)
                FROM Account
                WHERE Id = :accountId
                WITH USER_MODE
                LIMIT 1
            ];
        } else if (String.isNotBlank(accountNumber)) {
            accounts = [
                SELECT Id, Name, AccountNumber, Phone,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                       ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                       (SELECT Id, Email FROM Contacts LIMIT 1)
                FROM Account
                WHERE AccountNumber = :accountNumber
                WITH USER_MODE
                LIMIT 1
            ];
        }

        return accounts.isEmpty() ? null : accounts[0];
    }

    private static CustomerSummaryData buildCustomerSummary(Account account) {
        List<SObject> loanAccounts = queryLoanAccountsForAccount(account.Id);
        DueDetailsSummary dueDetailsSummary = getDueDetailsSummary(loanAccounts);
        SummaryMetrics metrics = calculateSummaryMetrics(loanAccounts, dueDetailsSummary);
        Map<Id, Date> nextScheduleDueDatesByLoanId = getNextScheduleDueDates(loanAccounts);

        List<LoanSummary> loanList = new List<LoanSummary>();
        for (SObject loan : loanAccounts) {
            loanList.add(buildLoanSummary(
                loan,
                nextScheduleDueDatesByLoanId,
                dueDetailsSummary.oldestUnpaidBillDatesByLoanId
            ));
        }

        CustomerSummaryData summary = new CustomerSummaryData();
        summary.accountId = account.Id;
        summary.accountNumber = account.AccountNumber;
        summary.customerName = account.Name;
        summary.email = account.Contacts != null && !account.Contacts.isEmpty()
            ? account.Contacts[0].Email : null;
        summary.phone = account.Phone;
        summary.address = getPreferredAddress(account);

        summary.totalLoanAmount = metrics.totalLoanAmount;
        summary.totalPrincipalRemaining = metrics.totalPrincipalRemaining;
        summary.totalDelinquentAmount = metrics.totalDelinquentAmount;
        summary.totalBilledAmount = metrics.totalBilledAmount;
        summary.totalMonthlyPayment = metrics.totalMonthlyPayment;
        summary.loanProgressTotalPrincipal = metrics.loanProgressTotalPrincipal;
        summary.loanProgressPrincipalPaid = metrics.loanProgressPrincipalPaid;
        summary.loanProgressPrincipalRemaining = metrics.loanProgressPrincipalRemaining;
        summary.utilization = metrics.utilization;
        summary.parentLoanUtilization = metrics.parentLoanUtilization;
        summary.fundingInTranchesUtilization = metrics.fundingInTranchesUtilization;

        ExposureMetrics exposureMetrics = calculateExposureMetrics(account.Id, loanAccounts);
        summary.directExposure = exposureMetrics.directExposure;
        summary.directExposureAsBorrower = exposureMetrics.directExposureAsBorrower;
        summary.directExposureAsCoBorrower = exposureMetrics.directExposureAsCoBorrower;
        summary.indirectExposure = exposureMetrics.indirectExposure;
        summary.indirectExposureAsGuarantor = exposureMetrics.indirectExposureAsGuarantor;

        summary.summary = metrics;
        summary.loans = loanList;
        return summary;
    }

    private static List<SObject> queryLoanAccountsForAccount(Id accountId) {
        if (!isReadableLoanObject(LOAN_ACCOUNT_OBJECT)) {
            return new List<SObject>();
        }

        String query = 'SELECT ' + String.join(getLoanAccountFieldList(), ', ') +
            ' FROM ' + Customer360NamespaceUtil.getLoanObjectApiName() +
            ' WHERE ' + l('Account__c') + ' = :accountId' +
            ' ORDER BY ' + l('Loan_Effective_Date__c') + ' DESC';

        return Database.queryWithBinds(query, new Map<String, Object>{
            'accountId' => accountId
        }, AccessLevel.USER_MODE);
    }

    private static SObject findLoanAccountById(String loanAccountId) {
        if (String.isBlank(loanAccountId)) {
            return null;
        }

        List<SObject> loans = queryLoanAccounts('Id = :loanAccountId', new Map<String, Object>{
            'loanAccountId' => loanAccountId
        });
        return loans.isEmpty() ? null : loans[0];
    }

    private static SObject findLoanAccountByPublicId(String loanId) {
        if (String.isBlank(loanId)) {
            return null;
        }

        String normalizedLoanId = loanId.trim().toUpperCase();
        String numericPart = normalizedLoanId.startsWith('LAI-') && normalizedLoanId.length() > 4
            ? normalizedLoanId.substring(4) : normalizedLoanId.replaceAll('[^0-9]', '');

        String numericValue = numericPart;
        try {
            numericValue = String.valueOf(Integer.valueOf(numericPart));
        } catch (Exception ignoredException) {
            numericValue = numericPart;
        }

        Set<String> searchNames = new Set<String>{
            normalizedLoanId,
            'LAI-' + numericPart,
            'LAI-' + numericValue.leftPad(8).replace(' ', '0'),
            'LA-' + numericValue,
            'LA-' + numericPart,
            numericValue,
            numericPart
        };

        if (String.isNotBlank(numericValue)) {
            String padded6 = numericValue.leftPad(6).replace(' ', '0');
            String padded7 = numericValue.leftPad(7).replace(' ', '0');
            searchNames.add('LA-' + padded6);
            searchNames.add('LA-' + padded7);
            searchNames.add(padded6);
            searchNames.add(padded7);
        }

        List<SObject> loans = queryLoanAccounts('Name IN :searchNames', new Map<String, Object>{
            'searchNames' => searchNames
        });
        return loans.isEmpty() ? null : loans[0];
    }

    private static List<SObject> queryLoanAccounts(String whereClause, Map<String, Object> bindVariables) {
        if (!isReadableLoanObject(LOAN_ACCOUNT_OBJECT)) {
            return new List<SObject>();
        }

        String query = 'SELECT ' + String.join(getLoanAccountFieldList(), ', ') +
            ' FROM ' + Customer360NamespaceUtil.getLoanObjectApiName() +
            ' WHERE ' + whereClause +
            ' LIMIT 1';

        return Database.queryWithBinds(query, bindVariables, AccessLevel.USER_MODE);
    }

    private static List<String> getLoanAccountFieldList() {
        return new List<String>{
            'Id',
            'Name',
            l('Account__c'),
            l('Account__r') + '.Name',
            l('Account__r') + '.AccountNumber',
            l('Loan_Amount__c'),
            l('Principal_Remaining__c'),
            l('Loan_Status__c'),
            l('Loan_Effective_Date__c'),
            l('Maturity_Date_Current__c'),
            l('Closed_Date__c'),
            l('Next_Due_Generation_Date__c'),
            l('Interest_Rate__c'),
            l('Product_Type__c'),
            l('Number_of_Installments__c'),
            l('Branch__r') + '.Name',
            l('Branch__r') + '.' + l('Current_System_Date__c'),
            l('Branch__c'),
            l('Client__r') + '.Name',
            l('Client__c'),
            l('Delinquent_Amount__c'),
            l('Payment_Amount__c'),
            l('Disbursal_Amount__c'),
            l('Disbursed_Amount__c'),
            l('Total_Amount_Disbursed__c'),
            l('Funding_in_Tranches__c'),
            l('Revolving__c')
        };
    }

    private static LoanDetailsData buildLoanDetails(SObject loanAccount) {
        SObject account = loanAccount.getSObject(l('Account__r'));

        LoanDetailsData data = new LoanDetailsData();
        data.loanId = formatLoanId(stringValue(loanAccount, 'Name'));
        data.loanAccountId = stringValue(loanAccount, 'Id');
        data.loanNumber = stringValue(loanAccount, 'Name');
        data.accountId = stringValue(loanAccount, l('Account__c'));
        data.accountNumber = stringValue(account, 'AccountNumber');
        data.customerName = stringValue(account, 'Name');
        data.overview = buildLoanOverview(loanAccount);
        data.paymentSchedule = buildPaymentSchedule(idValue(loanAccount, 'Id'), getCompanySystemDate(loanAccount));
        data.transactions = buildTransactions(idValue(loanAccount, 'Id'));
        data.duesAndCharges = buildDuesAndCharges(idValue(loanAccount, 'Id'));
        return data;
    }

    private static SummaryMetrics calculateSummaryMetrics(
        List<SObject> loanAccounts,
        DueDetailsSummary dueDetailsSummary
    ) {
        SummaryMetrics metrics = new SummaryMetrics();

        Integer totalLoans = 0;
        Integer activeLoans = 0;
        Integer closedLoans = 0;
        Integer activeGoodStanding = 0;
        Integer activeBadStanding = 0;
        Decimal totalLoanAmount = 0;
        Decimal totalOutstanding = 0;
        Decimal totalPaid = 0;
        Decimal totalPastDue = 0;
        Decimal totalMonthlyPayments = 0;
        Decimal totalMonthlyPayment = 0;
        Decimal loanProgressTotalPrincipal = 0;
        Decimal utilizationFundedAmount = 0;
        Decimal utilizationFinancedAmount = 0;
        Decimal parentLoanFundedAmount = 0;
        Decimal parentLoanFinancedAmount = 0;
        Decimal fundingInTranchesDisbursedAmount = 0;
        Decimal fundingInTranchesFinancedAmount = 0;
        Integer pastDueCount = 0;

        Set<Id> loanProgressLoanAccountIds = new Set<Id>();
        for (SObject loan : loanAccounts) {
            Boolean isMasterFacilityLoan = stringValue(loan, l('Product_Type__c')) == MASTER_FACILITY_PRODUCT_TYPE;
            Boolean isActive = isActiveLoan(loan);
            Boolean isClosed = isClosedLoan(loan);

            if (!isMasterFacilityLoan) {
                totalLoans++;
                loanProgressLoanAccountIds.add(idValue(loan, 'Id'));
                loanProgressTotalPrincipal += decimalValue(loan, l('Loan_Amount__c'));

                if (isActive) {
                    activeLoans++;
                    if (stringValue(loan, l('Loan_Status__c')) == ACTIVE_GOOD_STANDING) {
                        activeGoodStanding++;
                    } else if (stringValue(loan, l('Loan_Status__c')) == ACTIVE_BAD_STANDING) {
                        activeBadStanding++;
                        pastDueCount++;
                    }
                } else if (isClosed) {
                    closedLoans++;
                }
            }

            Decimal financedAmount = decimalValue(loan, l('Disbursal_Amount__c'));
            if (isMasterFacilityLoan) {
                Decimal amountFunded = decimalValue(loan, l('Disbursed_Amount__c'));
                parentLoanFundedAmount += amountFunded;
                parentLoanFinancedAmount += financedAmount;
                utilizationFundedAmount += amountFunded;
                utilizationFinancedAmount += financedAmount;
            } else if (booleanValue(loan, l('Funding_in_Tranches__c')) && !booleanValue(loan, l('Revolving__c'))) {
                Decimal totalDisbursed = decimalValue(loan, l('Total_Amount_Disbursed__c'));
                fundingInTranchesDisbursedAmount += totalDisbursed;
                fundingInTranchesFinancedAmount += financedAmount;
                utilizationFundedAmount += totalDisbursed;
                utilizationFinancedAmount += financedAmount;
            }

            Decimal loanAmount = decimalValue(loan, l('Loan_Amount__c'));
            Decimal principalRemaining = decimalValue(loan, l('Principal_Remaining__c'));
            totalLoanAmount += loanAmount;
            totalOutstanding += principalRemaining;
            if (rawValue(loan, l('Loan_Amount__c')) != null && rawValue(loan, l('Principal_Remaining__c')) != null) {
                totalPaid += (loanAmount - principalRemaining);
            }
            totalPastDue += decimalValue(loan, l('Delinquent_Amount__c'));
            totalMonthlyPayment += decimalValue(loan, l('Payment_Amount__c'));
            if (isActive) {
                totalMonthlyPayments += decimalValue(loan, l('Payment_Amount__c'));
            }
        }

        Decimal loanProgressPrincipalPaid = getPrincipalPaidAmount(loanProgressLoanAccountIds);
        Decimal loanProgressPrincipalRemaining = loanProgressTotalPrincipal - loanProgressPrincipalPaid;
        if (loanProgressPrincipalRemaining < 0) {
            loanProgressPrincipalRemaining = 0;
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
        metrics.totalBilledAmount = dueDetailsSummary.totalBilledAmount.setScale(2);
        metrics.totalMonthlyPayment = totalMonthlyPayment.setScale(2);
        metrics.loanProgressTotalPrincipal = loanProgressTotalPrincipal.setScale(2);
        metrics.loanProgressPrincipalPaid = loanProgressPrincipalPaid.setScale(2);
        metrics.loanProgressPrincipalRemaining = loanProgressPrincipalRemaining.setScale(2);
        metrics.utilization = calculatePercentage(utilizationFundedAmount, utilizationFinancedAmount);
        metrics.parentLoanUtilization = calculatePercentage(parentLoanFundedAmount, parentLoanFinancedAmount);
        metrics.fundingInTranchesUtilization = calculatePercentage(
            fundingInTranchesDisbursedAmount,
            fundingInTranchesFinancedAmount
        );
        metrics.pastDueLoanCount = pastDueCount;
        metrics.loanToValueRatio = totalLoanAmount > 0
            ? ((totalOutstanding / totalLoanAmount) * 100).setScale(2) : 0;
        metrics.debtRatio = DEFAULT_MONTHLY_INCOME > 0
            ? ((totalMonthlyPayments / DEFAULT_MONTHLY_INCOME) * 100).setScale(2) : 0;

        return metrics;
    }

    private static Decimal calculatePercentage(Decimal numerator, Decimal denominator) {
        if (denominator == null || denominator <= 0) {
            return 0;
        }

        return ((getDecimal(numerator) / denominator) * 100).setScale(2);
    }

    private static Decimal getPrincipalPaidAmount(Set<Id> loanAccountIds) {
        if (loanAccountIds.isEmpty() || !isReadableLoanObject(PAYMENT_TRANSACTION_OBJECT)) {
            return 0;
        }

        String transactionObject = loanObjectApiName(PAYMENT_TRANSACTION_OBJECT);
        String query = 'SELECT ' + l('Principal__c') +
            ' FROM ' + transactionObject +
            ' WHERE ' + l('Loan_Account__c') + ' IN :loanAccountIds' +
            ' AND ' + l('Reversed__c') + ' = false';

        Decimal totalPrincipalPaid = 0;
        for (SObject transactionRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountIds' => loanAccountIds
        }, AccessLevel.USER_MODE)) {
            totalPrincipalPaid += decimalValue(transactionRecord, l('Principal__c'));
        }
        return totalPrincipalPaid;
    }

    private static DueDetailsSummary getDueDetailsSummary(List<SObject> loanAccounts) {
        DueDetailsSummary summary = new DueDetailsSummary();
        Set<Id> loanAccountIds = getLoanAccountIds(loanAccounts);
        String dueDetailsObject = getDueDetailsObjectApiName();
        if (loanAccountIds.isEmpty() || String.isBlank(dueDetailsObject)) {
            return summary;
        }

        String query = 'SELECT ' + l('Loan_Account__c') + ', ' +
            l('Due_Amt__c') + ', ' +
            l('Due_Date__c') +
            ' FROM ' + dueDetailsObject +
            ' WHERE ' + l('Loan_Account__c') + ' IN :loanAccountIds' +
            ' AND ' + l('DD_Primary_Flag__c') + ' = true' +
            ' AND ' + l('Payment_Satisfied__c') + ' = false';

        for (SObject dueDetails : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountIds' => loanAccountIds
        }, AccessLevel.USER_MODE)) {
            Id loanAccountId = idValue(dueDetails, l('Loan_Account__c'));
            Date dueDate = dateValue(dueDetails, l('Due_Date__c'));
            summary.totalBilledAmount += decimalValue(dueDetails, l('Due_Amt__c'));
            if (dueDate != null &&
                (!summary.oldestUnpaidBillDatesByLoanId.containsKey(loanAccountId) ||
                    dueDate < summary.oldestUnpaidBillDatesByLoanId.get(loanAccountId))) {
                summary.oldestUnpaidBillDatesByLoanId.put(loanAccountId, dueDate);
            }
        }

        return summary;
    }

    private static LoanSummary buildLoanSummary(
        SObject loan,
        Map<Id, Date> nextScheduleDueDatesByLoanId,
        Map<Id, Date> oldestUnpaidBillDatesByLoanId
    ) {
        Id loanId = idValue(loan, 'Id');
        LoanSummary summary = new LoanSummary();
        summary.loanId = formatLoanId(stringValue(loan, 'Name'));
        summary.loanAccountId = stringValue(loan, 'Id');
        summary.loanNumber = stringValue(loan, 'Name');
        summary.status = getStatus(loan);
        summary.standing = getStanding(loan);
        summary.loanAmount = scaleCurrency(decimalValue(loan, l('Loan_Amount__c')));
        summary.principalRemaining = scaleCurrency(decimalValue(loan, l('Principal_Remaining__c')));
        summary.interestRate = scaleCurrency(decimalValue(loan, l('Interest_Rate__c')));
        summary.loanEffectiveDate = formatDate(dateValue(loan, l('Loan_Effective_Date__c')));
        summary.maturityDate = formatDate(dateValue(loan, l('Maturity_Date_Current__c')));
        summary.nextPaymentDate = formatDate(nextScheduleDueDatesByLoanId?.get(loanId));
        summary.oldestUnpaidBillDate = formatDate(oldestUnpaidBillDatesByLoanId?.get(loanId));
        summary.daysPastDue = getDaysPastDue(dateValue(loan, l('Next_Due_Generation_Date__c')), getStatus(loan));
        summary.productType = getProductType(loan);
        return summary;
    }

    private static Map<Id, Date> getNextScheduleDueDates(List<SObject> loanAccounts) {
        Map<Id, Date> nextDueDatesByLoanId = new Map<Id, Date>();
        Map<Id, Date> scheduleStartDatesByLoanId = new Map<Id, Date>();
        Set<Id> loanAccountIds = new Set<Id>();
        Date earliestScheduleStartDate;

        for (SObject loan : loanAccounts) {
            Id loanId = idValue(loan, 'Id');
            loanAccountIds.add(loanId);
            Date scheduleStartDate = getCompanySystemDate(loan);
            scheduleStartDatesByLoanId.put(loanId, scheduleStartDate);
            if (earliestScheduleStartDate == null || scheduleStartDate < earliestScheduleStartDate) {
                earliestScheduleStartDate = scheduleStartDate;
            }
        }

        if (loanAccountIds.isEmpty() || !isReadableLoanObject(REPAYMENT_SCHEDULE_OBJECT)) {
            return nextDueDatesByLoanId;
        }

        String query = 'SELECT ' + l('Loan_Account__c') + ', ' + l('Due_Date__c') +
            ' FROM ' + loanObjectApiName(REPAYMENT_SCHEDULE_OBJECT) +
            ' WHERE ' + l('Loan_Account__c') + ' IN :loanAccountIds' +
            ' AND ' + l('Due_Date__c') + ' > :earliestScheduleStartDate' +
            ' AND ' + l('Is_Archived__c') + ' = false' +
            ' ORDER BY ' + l('Loan_Account__c') + ', ' + l('Due_Date__c') + ' ASC';

        for (SObject schedule : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountIds' => loanAccountIds,
            'earliestScheduleStartDate' => earliestScheduleStartDate
        }, AccessLevel.USER_MODE)) {
            Id loanAccountId = idValue(schedule, l('Loan_Account__c'));
            Date dueDate = dateValue(schedule, l('Due_Date__c'));
            Date scheduleStartDate = scheduleStartDatesByLoanId.get(loanAccountId);
            if (!nextDueDatesByLoanId.containsKey(loanAccountId) &&
                dueDate != null &&
                scheduleStartDate != null &&
                dueDate > scheduleStartDate) {
                nextDueDatesByLoanId.put(loanAccountId, dueDate);
            }
        }

        return nextDueDatesByLoanId;
    }

    private static LoanOverview buildLoanOverview(SObject loan) {
        SObject branch = loan.getSObject(l('Branch__r'));
        SObject officer = loan.getSObject(l('Client__r'));

        Decimal loanAmount = decimalValue(loan, l('Loan_Amount__c'));
        Decimal principalRemaining = decimalValue(loan, l('Principal_Remaining__c'));
        LoanOverview overview = new LoanOverview();
        overview.status = getStatus(loan);
        overview.standing = getStanding(loan);
        overview.productType = getProductType(loan);
        overview.loanAmount = scaleCurrency(loanAmount);
        overview.principalRemaining = scaleCurrency(principalRemaining);
        overview.interestRemaining = (overview.principalRemaining * 0.05).setScale(2);
        overview.feesRemaining = 500.00;
        overview.totalOutstanding = (
            overview.principalRemaining +
            overview.interestRemaining +
            overview.feesRemaining
        ).setScale(2);
        overview.totalPaidToDate = rawValue(loan, l('Loan_Amount__c')) != null &&
            rawValue(loan, l('Principal_Remaining__c')) != null
            ? (loanAmount - principalRemaining).setScale(2) : 0;
        overview.interestRate = scaleCurrency(decimalValue(loan, l('Interest_Rate__c')));
        overview.apr = overview.interestRate;
        overview.loanEffectiveDate = formatDate(dateValue(loan, l('Loan_Effective_Date__c')));
        overview.maturityDate = formatDate(dateValue(loan, l('Maturity_Date_Current__c')));
        overview.closedDate = formatDate(dateValue(loan, l('Closed_Date__c')));
        overview.branch = stringValue(branch, 'Name');
        overview.branchId = stringValue(loan, l('Branch__c'));
        overview.loanOfficer = stringValue(officer, 'Name');
        overview.loanOfficerId = stringValue(loan, l('Client__c'));
        overview.paymentTerm = rawValue(loan, l('Number_of_Installments__c')) != null
            ? Integer.valueOf(decimalValue(loan, l('Number_of_Installments__c'))) : 0;
        overview.paymentFrequency = 'Monthly';
        overview.paymentsMade = getPaidScheduleCount(idValue(loan, 'Id'));
        overview.paymentsRemaining = overview.paymentTerm > overview.paymentsMade
            ? overview.paymentTerm - overview.paymentsMade : 0;
        overview.nextPaymentDate = formatDate(dateValue(loan, l('Next_Due_Generation_Date__c')));
        overview.nextPaymentAmount = (overview.totalOutstanding /
            (overview.paymentsRemaining > 0 ? overview.paymentsRemaining : 1)).setScale(2);
        overview.daysPastDue = getDaysPastDue(dateValue(loan, l('Next_Due_Generation_Date__c')), getStatus(loan));
        overview.progressPercentage = overview.paymentTerm > 0
            ? ((Decimal.valueOf(overview.paymentsMade) / Decimal.valueOf(overview.paymentTerm)) * 100).setScale(1)
            : 0;
        return overview;
    }

    private static Integer getPaidScheduleCount(Id loanAccountId) {
        if (loanAccountId == null || !isReadableLoanObject(REPAYMENT_SCHEDULE_OBJECT)) {
            return 0;
        }

        String query = 'SELECT Id' +
            ' FROM ' + loanObjectApiName(REPAYMENT_SCHEDULE_OBJECT) +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' AND ' + l('isPaid__c') + ' = true' +
            ' AND ' + l('Is_Archived__c') + ' = false';

        return Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId
        }, AccessLevel.USER_MODE).size();
    }

    private static PaymentScheduleData buildPaymentSchedule(Id loanAccountId, Date companySystemDate) {
        PaymentScheduleData schedule = new PaymentScheduleData();
        schedule.totalInstallments = 0;
        schedule.paidInstallments = 0;
        schedule.pendingInstallments = 0;
        schedule.pastDueInstallments = 0;
        schedule.installments = new List<InstallmentDetail>();
        if (loanAccountId == null || !isReadableLoanObject(REPAYMENT_SCHEDULE_OBJECT)) {
            return schedule;
        }

        Date scheduleStartDate = companySystemDate != null ? companySystemDate : Date.today();
        String query = 'SELECT Id, ' +
            l('Due_Date__c') + ', ' +
            l('Due_Principal__c') + ', ' +
            l('Due_Interest__c') + ', ' +
            l('Total_Due_Fees__c') + ', ' +
            l('Total_Installment__c') + ', ' +
            l('isPaid__c') + ', ' +
            l('Date_Paid__c') + ', ' +
            l('Paid_Total__c') + ', ' +
            l('Past_Due_Date__c') + ', ' +
            l('Transaction_Amount__c') +
            ' FROM ' + loanObjectApiName(REPAYMENT_SCHEDULE_OBJECT) +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' AND ' + l('Due_Date__c') + ' > :scheduleStartDate' +
            ' AND ' + l('Is_Archived__c') + ' = false' +
            ' ORDER BY ' + l('Due_Date__c') + ' ASC' +
            ' LIMIT 6';

        List<SObject> schedules = Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId,
            'scheduleStartDate' => scheduleStartDate
        }, AccessLevel.USER_MODE);

        schedule.totalInstallments = schedules.size();
        Integer installmentCounter = 1;
        for (SObject scheduleRecord : schedules) {
            InstallmentDetail installment = new InstallmentDetail();
            installment.installmentNumber = installmentCounter++;
            installment.dueDate = formatDate(dateValue(scheduleRecord, l('Due_Date__c')));
            installment.principalDue = scaleCurrency(decimalValue(scheduleRecord, l('Due_Principal__c')));
            installment.interestDue = scaleCurrency(decimalValue(scheduleRecord, l('Due_Interest__c')));
            installment.feesDue = scaleCurrency(decimalValue(scheduleRecord, l('Total_Due_Fees__c')));
            installment.totalDue = scaleCurrency(decimalValue(scheduleRecord, l('Total_Installment__c')));
            installment.paidDate = formatDate(dateValue(scheduleRecord, l('Date_Paid__c')));
            installment.amountPaid = scaleCurrency(decimalValue(scheduleRecord, l('Paid_Total__c')));

            if (booleanValue(scheduleRecord, l('isPaid__c'))) {
                installment.status = 'Paid';
                schedule.paidInstallments++;
            } else if (booleanValue(scheduleRecord, l('Past_Due_Date__c'))) {
                installment.status = 'Past Due';
                schedule.pastDueInstallments++;
            } else {
                installment.status = 'Pending';
                schedule.pendingInstallments++;
            }

            Date dueDate = dateValue(scheduleRecord, l('Due_Date__c'));
            installment.daysPastDue = dueDate != null && booleanValue(scheduleRecord, l('Past_Due_Date__c'))
                ? dueDate.daysBetween(Date.today()) : 0;
            schedule.installments.add(installment);
        }

        return schedule;
    }

    private static TransactionData buildTransactions(Id loanAccountId) {
        TransactionData transactionData = new TransactionData();
        transactionData.totalAmount = 0;
        transactionData.totalTransactions = 0;
        transactionData.transactions = new List<TransactionDetail>();
        if (loanAccountId == null || !isReadableLoanObject(PAYMENT_TRANSACTION_OBJECT)) {
            return transactionData;
        }

        String query = 'SELECT Id, ' +
            l('Transaction_Date__c') + ', ' +
            l('Transaction_Amount__c') + ', ' +
            l('Principal__c') + ', ' +
            l('Interest__c') + ', ' +
            l('Fees__c') + ', ' +
            l('Payment_Mode__c') + ', ' +
            l('Cleared__c') + ', ' +
            l('Cheque_Number__c') +
            ' FROM ' + loanObjectApiName(PAYMENT_TRANSACTION_OBJECT) +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' ORDER BY ' + l('Transaction_Date__c') + ' DESC' +
            ' LIMIT 100';

        List<SObject> transactions = Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId
        }, AccessLevel.USER_MODE);

        transactionData.totalTransactions = transactions.size();
        for (SObject transactionRecord : transactions) {
            TransactionDetail detail = new TransactionDetail();
            detail.transactionId = stringValue(transactionRecord, 'Id');
            detail.transactionDate = formatDate(dateValue(transactionRecord, l('Transaction_Date__c')));
            detail.amount = scaleCurrency(decimalValue(transactionRecord, l('Transaction_Amount__c')));
            detail.principalApplied = scaleCurrency(decimalValue(transactionRecord, l('Principal__c')));
            detail.interestApplied = scaleCurrency(decimalValue(transactionRecord, l('Interest__c')));
            detail.feesApplied = scaleCurrency(decimalValue(transactionRecord, l('Fees__c')));
            detail.paymentMethod = stringValue(transactionRecord, l('Payment_Mode__c'));
            detail.status = booleanValue(transactionRecord, l('Cleared__c')) ? 'Cleared' : 'Pending';
            detail.referenceNumber = stringValue(transactionRecord, l('Cheque_Number__c'));
            detail.description = null;
            transactionData.totalAmount += detail.amount;
            transactionData.transactions.add(detail);
        }

        transactionData.totalAmount = transactionData.totalAmount.setScale(2);
        return transactionData;
    }

    private static DuesAndChargesData buildDuesAndCharges(Id loanAccountId) {
        DuesAndChargesData duesData = new DuesAndChargesData();
        duesData.bills = buildBills(loanAccountId);
        duesData.charges = buildCharges(loanAccountId);
        duesData.pendingSchedule = buildPendingSchedule(loanAccountId);
        duesData.summary = buildDuesChargesSummary(duesData);
        return duesData;
    }

    private static List<BillDetail> buildBills(Id loanAccountId) {
        List<BillDetail> billDetails = new List<BillDetail>();
        String dueDetailsObject = getDueDetailsObjectApiName();
        if (loanAccountId == null || String.isBlank(dueDetailsObject)) {
            return billDetails;
        }

        String query = 'SELECT Id, Name, ' +
            l('Due_Date__c') + ', ' +
            l('Due_Amt__c') + ', ' +
            l('DD_Primary_Flag__c') + ', ' +
            l('Payment_Satisfied__c') + ', ' +
            l('Principal_Billed__c') + ', ' +
            l('Interest_Billed__c') + ', ' +
            l('Fees_Billed__c') + ', ' +
            l('Interest_Due__c') + ', ' +
            l('Fees_Due__c') + ', ' +
            l('Principal_Paid__c') + ', ' +
            l('Interest_Paid__c') + ', ' +
            l('Fees_Paid__c') +
            ' FROM ' + dueDetailsObject +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' ORDER BY ' + l('Due_Date__c') + ' DESC, CreatedDate DESC' +
            ' LIMIT 6';

        for (SObject bill : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId
        }, AccessLevel.USER_MODE)) {
            BillDetail detail = new BillDetail();
            Decimal principalBilled = decimalValue(bill, l('Principal_Billed__c'));
            Decimal principalPaid = decimalValue(bill, l('Principal_Paid__c'));
            Date dueDate = dateValue(bill, l('Due_Date__c'));
            detail.billId = stringValue(bill, 'Id');
            detail.billName = stringValue(bill, 'Name');
            detail.dueDate = formatDate(dueDate);
            detail.dueAmount = scaleCurrency(decimalValue(bill, l('Due_Amt__c')));
            detail.principalBilled = principalBilled.setScale(2);
            detail.interestBilled = scaleCurrency(decimalValue(bill, l('Interest_Billed__c')));
            detail.feesBilled = scaleCurrency(decimalValue(bill, l('Fees_Billed__c')));
            detail.principalDue = (principalBilled - principalPaid).setScale(2);
            detail.interestDue = scaleCurrency(decimalValue(bill, l('Interest_Due__c')));
            detail.feesDue = scaleCurrency(decimalValue(bill, l('Fees_Due__c')));
            detail.principalPaid = principalPaid.setScale(2);
            detail.interestPaid = scaleCurrency(decimalValue(bill, l('Interest_Paid__c')));
            detail.feesPaid = scaleCurrency(decimalValue(bill, l('Fees_Paid__c')));
            detail.isPrimary = booleanValue(bill, l('DD_Primary_Flag__c'));
            detail.isPaymentSatisfied = booleanValue(bill, l('Payment_Satisfied__c'));
            detail.status = detail.isPaymentSatisfied ? 'Paid' :
                (dueDate != null && dueDate < Date.today() ? 'Past Due' : 'Pending');
            detail.daysPastDue = dueDate != null && dueDate < Date.today() && !detail.isPaymentSatisfied
                ? dueDate.daysBetween(Date.today()) : 0;
            billDetails.add(detail);
        }
        return billDetails;
    }

    private static List<ChargeDetail> buildCharges(Id loanAccountId) {
        List<ChargeDetail> chargeDetails = new List<ChargeDetail>();
        if (loanAccountId == null || !isReadableLoanObject(CHARGE_OBJECT)) {
            return chargeDetails;
        }

        String query = 'SELECT Id, Name, ' +
            l('Charge_Type__c') + ', ' +
            l('Original_Amount__c') + ', ' +
            l('Date__c') + ', ' +
            l('Reference__c') + ', ' +
            l('Status__c') + ', ' +
            l('Dues_Details__c') + ', ' +
            l('Dues_Details__r') + '.Name' +
            ' FROM ' + loanObjectApiName(CHARGE_OBJECT) +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' ORDER BY ' + l('Date__c') + ' DESC';

        for (SObject charge : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId
        }, AccessLevel.USER_MODE)) {
            SObject duesDetails = charge.getSObject(l('Dues_Details__r'));
            String chargeId = stringValue(charge, 'Id');
            ChargeDetail detail = new ChargeDetail();
            detail.chargeId = chargeId;
            detail.chargeName = String.isNotBlank(stringValue(charge, 'Name'))
                ? stringValue(charge, 'Name') : 'Charge-' + chargeId.substring(0, 8);
            detail.chargeType = stringValue(charge, l('Charge_Type__c'));
            detail.amount = scaleCurrency(decimalValue(charge, l('Original_Amount__c')));
            detail.chargeDate = formatDate(dateValue(charge, l('Date__c')));
            detail.description = stringValue(charge, l('Reference__c'));
            detail.status = String.isNotBlank(stringValue(charge, l('Status__c')))
                ? stringValue(charge, l('Status__c')) : 'Unknown';
            detail.billId = stringValue(charge, l('Dues_Details__c'));
            detail.billName = stringValue(duesDetails, 'Name');
            chargeDetails.add(detail);
        }
        return chargeDetails;
    }

    private static List<PendingScheduleDetail> buildPendingSchedule(Id loanAccountId) {
        List<PendingScheduleDetail> pendingDetails = new List<PendingScheduleDetail>();
        if (loanAccountId == null || !isReadableLoanObject(REPAYMENT_SCHEDULE_OBJECT)) {
            return pendingDetails;
        }

        Date today = Date.today();
        String query = 'SELECT Id, ' +
            l('Due_Date__c') + ', ' +
            l('Due_Principal__c') + ', ' +
            l('Due_Interest__c') + ', ' +
            l('Total_Due_Fees__c') + ', ' +
            l('Total_Installment__c') +
            ' FROM ' + loanObjectApiName(REPAYMENT_SCHEDULE_OBJECT) +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' AND ' + l('Due_Date__c') + ' > :today' +
            ' AND ' + l('isPaid__c') + ' = false' +
            ' AND ' + l('Is_Archived__c') + ' = false' +
            ' ORDER BY ' + l('Due_Date__c') + ' ASC';

        for (SObject scheduleRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId,
            'today' => today
        }, AccessLevel.USER_MODE)) {
            PendingScheduleDetail detail = new PendingScheduleDetail();
            detail.scheduleId = stringValue(scheduleRecord, 'Id');
            detail.dueDate = formatDate(dateValue(scheduleRecord, l('Due_Date__c')));
            detail.principalDue = scaleCurrency(decimalValue(scheduleRecord, l('Due_Principal__c')));
            detail.interestDue = scaleCurrency(decimalValue(scheduleRecord, l('Due_Interest__c')));
            detail.feesDue = scaleCurrency(decimalValue(scheduleRecord, l('Total_Due_Fees__c')));
            detail.totalDue = scaleCurrency(decimalValue(scheduleRecord, l('Total_Installment__c')));
            pendingDetails.add(detail);
        }
        return pendingDetails;
    }

    private static DuesChargesSummary buildDuesChargesSummary(DuesAndChargesData duesData) {
        DuesChargesSummary summary = new DuesChargesSummary();
        Decimal totalBilledAmount = 0;
        Decimal totalChargesAmount = 0;
        Decimal totalPendingAmount = 0;

        for (BillDetail bill : duesData.bills) {
            totalBilledAmount += getDecimal(bill.dueAmount);
        }
        for (ChargeDetail charge : duesData.charges) {
            totalChargesAmount += getDecimal(charge.amount);
        }
        for (PendingScheduleDetail pending : duesData.pendingSchedule) {
            totalPendingAmount += getDecimal(pending.totalDue);
        }

        summary.totalBills = duesData.bills.size();
        summary.totalBilledAmount = totalBilledAmount.setScale(2);
        summary.totalCharges = duesData.charges.size();
        summary.totalChargesAmount = totalChargesAmount.setScale(2);
        summary.totalPendingSchedule = duesData.pendingSchedule.size();
        summary.totalPendingAmount = totalPendingAmount.setScale(2);
        return summary;
    }

    private static ExposureMetrics calculateExposureMetrics(Id accountId, List<SObject> borrowerLoanAccounts) {
        ExposureMetrics exposure = new ExposureMetrics();
        exposure.directExposure = 0;
        exposure.directExposureAsBorrower = 0;
        exposure.directExposureAsCoBorrower = 0;
        exposure.indirectExposure = 0;
        exposure.indirectExposureAsGuarantor = 0;

        for (SObject loan : borrowerLoanAccounts) {
            exposure.directExposureAsBorrower += decimalValue(loan, l('Principal_Remaining__c'));
        }

        if (!isReadableLoanObject(COBORROWER_OBJECT)) {
            return finalizeExposureMetrics(exposure);
        }

        String query = 'SELECT ' + l('Loan__c') + ', ' + l('Party_Type__c') +
            ' FROM ' + loanObjectApiName(COBORROWER_OBJECT) +
            ' WHERE ' + l('Account__c') + ' = :accountId';

        List<SObject> coborrowerLinks = Database.queryWithBinds(query, new Map<String, Object>{
            'accountId' => accountId
        }, AccessLevel.USER_MODE);
        if (coborrowerLinks.isEmpty()) {
            return finalizeExposureMetrics(exposure);
        }

        Set<Id> coBorrowerLoanIds = new Set<Id>();
        Set<Id> guarantorLoanIds = new Set<Id>();
        for (SObject linkRecord : coborrowerLinks) {
            Id linkedLoanId = idValue(linkRecord, l('Loan__c'));
            if (linkedLoanId == null) {
                continue;
            }
            if (stringValue(linkRecord, l('Party_Type__c')) == 'COBORROWER') {
                coBorrowerLoanIds.add(linkedLoanId);
            } else if (stringValue(linkRecord, l('Party_Type__c')) == 'GUARANTOR') {
                guarantorLoanIds.add(linkedLoanId);
            }
        }

        Set<Id> allLinkedLoanIds = new Set<Id>();
        allLinkedLoanIds.addAll(coBorrowerLoanIds);
        allLinkedLoanIds.addAll(guarantorLoanIds);
        if (allLinkedLoanIds.isEmpty() || !isReadableLoanObject(LOAN_ACCOUNT_OBJECT)) {
            return finalizeExposureMetrics(exposure);
        }

        String loanQuery = 'SELECT Id, ' + l('Principal_Remaining__c') +
            ' FROM ' + loanObjectApiName(LOAN_ACCOUNT_OBJECT) +
            ' WHERE Id IN :allLinkedLoanIds';

        Map<Id, SObject> linkedLoansById = new Map<Id, SObject>();
        for (SObject linkedLoan : Database.queryWithBinds(loanQuery, new Map<String, Object>{
            'allLinkedLoanIds' => allLinkedLoanIds
        }, AccessLevel.USER_MODE)) {
            linkedLoansById.put(idValue(linkedLoan, 'Id'), linkedLoan);
        }

        for (Id loanId : coBorrowerLoanIds) {
            exposure.directExposureAsCoBorrower += decimalValue(linkedLoansById.get(loanId), l('Principal_Remaining__c'));
        }
        for (Id loanId : guarantorLoanIds) {
            exposure.indirectExposureAsGuarantor += decimalValue(linkedLoansById.get(loanId), l('Principal_Remaining__c'));
        }

        return finalizeExposureMetrics(exposure);
    }

    private static ExposureMetrics finalizeExposureMetrics(ExposureMetrics exposure) {
        exposure.directExposureAsBorrower = exposure.directExposureAsBorrower.setScale(2);
        exposure.directExposureAsCoBorrower = exposure.directExposureAsCoBorrower.setScale(2);
        exposure.indirectExposureAsGuarantor = exposure.indirectExposureAsGuarantor.setScale(2);
        exposure.directExposure = (
            exposure.directExposureAsBorrower + exposure.directExposureAsCoBorrower
        ).setScale(2);
        exposure.indirectExposure = exposure.indirectExposureAsGuarantor.setScale(2);
        return exposure;
    }

    private static Set<Id> getLoanAccountIds(List<SObject> loanAccounts) {
        Set<Id> loanAccountIds = new Set<Id>();
        for (SObject loan : loanAccounts) {
            loanAccountIds.add(idValue(loan, 'Id'));
        }
        loanAccountIds.remove(null);
        return loanAccountIds;
    }

    private static String formatLoanId(String loanName) {
        if (String.isBlank(loanName)) {
            return null;
        }

        String numericPart = loanName.replaceAll('[^0-9]', '');
        if (numericPart.length() > 8) {
            numericPart = numericPart.right(8);
        } else {
            numericPart = numericPart.leftPad(8).replace(' ', '0');
        }
        return 'LAI-' + numericPart;
    }

    private static Date getCompanySystemDate(SObject loan) {
        SObject branch = loan == null ? null : loan.getSObject(l('Branch__r'));
        Date branchSystemDate = dateValue(branch, l('Current_System_Date__c'));
        return branchSystemDate != null ? branchSystemDate : Date.today();
    }

    private static String getPreferredAddress(Account account) {
        if (String.isNotBlank(account.BillingStreet) || String.isNotBlank(account.BillingCity)) {
            return buildAddressString(
                account.BillingStreet,
                account.BillingCity,
                account.BillingState,
                account.BillingPostalCode,
                account.BillingCountry
            );
        }
        if (String.isNotBlank(account.ShippingStreet) || String.isNotBlank(account.ShippingCity)) {
            return buildAddressString(
                account.ShippingStreet,
                account.ShippingCity,
                account.ShippingState,
                account.ShippingPostalCode,
                account.ShippingCountry
            );
        }
        return null;
    }

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

    private static String getStatus(SObject loan) {
        return String.isNotBlank(stringValue(loan, l('Loan_Status__c')))
            ? stringValue(loan, l('Loan_Status__c')) : 'Unknown';
    }

    private static String getStanding(SObject loan) {
        String loanStatus = stringValue(loan, l('Loan_Status__c'));
        if (loanStatus == ACTIVE_GOOD_STANDING) {
            return 'Good Standing';
        }
        if (loanStatus == ACTIVE_BAD_STANDING) {
            return 'Bad Standing';
        }
        if (isClosedLoan(loan)) {
            return 'Closed';
        }
        return 'Unknown';
    }

    private static String getProductType(SObject loan) {
        return String.isNotBlank(stringValue(loan, l('Product_Type__c')))
            ? stringValue(loan, l('Product_Type__c')) : 'Unknown';
    }

    private static Boolean isActiveLoan(SObject loan) {
        String loanStatus = stringValue(loan, l('Loan_Status__c'));
        return loanStatus != null && !loanStatus.startsWith(CLOSED_STATUS_PREFIX);
    }

    private static Boolean isClosedLoan(SObject loan) {
        String loanStatus = stringValue(loan, l('Loan_Status__c'));
        return loanStatus != null && loanStatus.startsWith(CLOSED_STATUS_PREFIX);
    }

    private static Integer getDaysPastDue(Date dueDate, String loanStatus) {
        return dueDate != null && loanStatus == ACTIVE_BAD_STANDING ? dueDate.daysBetween(Date.today()) : 0;
    }

    private static String formatDate(Date dateValue) {
        return dateValue != null ? String.valueOf(dateValue) : null;
    }

    private static Decimal scaleCurrency(Decimal value) {
        return getDecimal(value).setScale(2);
    }

    private static Decimal getDecimal(Decimal value) {
        return value != null ? value : 0;
    }

    private static Decimal decimalValue(SObject record, String fieldApiName) {
        Object value = rawValue(record, fieldApiName);
        return value == null ? 0 : (Decimal) value;
    }

    private static Date dateValue(SObject record, String fieldApiName) {
        Object value = rawValue(record, fieldApiName);
        return value == null ? null : (Date) value;
    }

    private static Boolean booleanValue(SObject record, String fieldApiName) {
        Object value = rawValue(record, fieldApiName);
        return value == null ? false : (Boolean) value;
    }

    private static Id idValue(SObject record, String fieldApiName) {
        Object value = rawValue(record, fieldApiName);
        return value == null ? null : (Id) value;
    }

    private static String stringValue(SObject record, String fieldApiName) {
        Object value = rawValue(record, fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static Object rawValue(SObject record, String fieldApiName) {
        return record == null || String.isBlank(fieldApiName) ? null : record.get(fieldApiName);
    }

    private static String l(String apiName) {
        return Customer360NamespaceUtil.qualifyLoanApiName(apiName);
    }

    private static Boolean isReadableLoanObject(String apiName) {
        String objectApiName = loanObjectApiName(apiName);
        return String.isNotBlank(objectApiName) && Customer360NamespaceUtil.isObjectAccessible(objectApiName);
    }

    private static String loanObjectApiName(String apiName) {
        String objectApiName = Customer360NamespaceUtil.qualifyLoanApiName(apiName);
        return Schema.getGlobalDescribe().containsKey(objectApiName) ? objectApiName : '';
    }

    private static String getDueDetailsObjectApiName() {
        for (String apiName : new List<String>{ DUE_DETAILS_OBJECT, LEGACY_DUE_DETAILS_OBJECT }) {
            String objectApiName = loanObjectApiName(apiName);
            if (String.isNotBlank(objectApiName) && Customer360NamespaceUtil.isObjectAccessible(objectApiName)) {
                return objectApiName;
            }
        }
        return '';
    }

    private class DueDetailsSummary {
        Decimal totalBilledAmount = 0;
        Map<Id, Date> oldestUnpaidBillDatesByLoanId = new Map<Id, Date>();
    }

    /**
     * Customer 360 summary payload.
     */
    global class CustomerSummaryData {
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
        @AuraEnabled public Decimal totalMonthlyPayment;
        @AuraEnabled public Decimal loanProgressTotalPrincipal;
        @AuraEnabled public Decimal loanProgressPrincipalPaid;
        @AuraEnabled public Decimal loanProgressPrincipalRemaining;
        @AuraEnabled public Decimal utilization;
        @AuraEnabled public Decimal parentLoanUtilization;
        @AuraEnabled public Decimal fundingInTranchesUtilization;
        @AuraEnabled public Decimal directExposure;
        @AuraEnabled public Decimal directExposureAsBorrower;
        @AuraEnabled public Decimal directExposureAsCoBorrower;
        @AuraEnabled public Decimal indirectExposure;
        @AuraEnabled public Decimal indirectExposureAsGuarantor;
        @AuraEnabled public SummaryMetrics summary;
        @AuraEnabled public List<LoanSummary> loans;
    }

    global class ExposureMetrics {
        @AuraEnabled public Decimal directExposure;
        @AuraEnabled public Decimal directExposureAsBorrower;
        @AuraEnabled public Decimal directExposureAsCoBorrower;
        @AuraEnabled public Decimal indirectExposure;
        @AuraEnabled public Decimal indirectExposureAsGuarantor;
    }

    global class SummaryMetrics {
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
        @AuraEnabled public Decimal totalMonthlyPayment;
        @AuraEnabled public Decimal loanProgressTotalPrincipal;
        @AuraEnabled public Decimal loanProgressPrincipalPaid;
        @AuraEnabled public Decimal loanProgressPrincipalRemaining;
        @AuraEnabled public Decimal utilization;
        @AuraEnabled public Decimal parentLoanUtilization;
        @AuraEnabled public Decimal fundingInTranchesUtilization;
        @AuraEnabled public Integer pastDueLoanCount;
    }

    global class LoanSummary {
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
        @AuraEnabled public Decimal nextPaymentAmount;
        @AuraEnabled public String oldestUnpaidBillDate;
        @AuraEnabled public Integer daysPastDue;
        @AuraEnabled public String productType;
    }

    /**
     * Loan details payload.
     */
    global class LoanDetailsData {
        @AuraEnabled public String loanId;
        @AuraEnabled public String loanAccountId;
        @AuraEnabled public String loanNumber;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public LoanOverview overview;
        @AuraEnabled public PaymentScheduleData paymentSchedule;
        @AuraEnabled public TransactionData transactions;
        @AuraEnabled public DuesAndChargesData duesAndCharges;
    }

    global class LoanOverview {
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

    global class PaymentScheduleData {
        @AuraEnabled public Integer totalInstallments;
        @AuraEnabled public Integer paidInstallments;
        @AuraEnabled public Integer pendingInstallments;
        @AuraEnabled public Integer pastDueInstallments;
        @AuraEnabled public List<InstallmentDetail> installments;
    }

    global class InstallmentDetail {
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

    global class TransactionData {
        @AuraEnabled public Integer totalTransactions;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public List<TransactionDetail> transactions;
    }

    global class TransactionDetail {
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

    global class DuesAndChargesData {
        @AuraEnabled public DuesChargesSummary summary;
        @AuraEnabled public List<BillDetail> bills;
        @AuraEnabled public List<ChargeDetail> charges;
        @AuraEnabled public List<PendingScheduleDetail> pendingSchedule;
    }

    global class DuesChargesSummary {
        @AuraEnabled public Integer totalBills;
        @AuraEnabled public Decimal totalBilledAmount;
        @AuraEnabled public Integer totalCharges;
        @AuraEnabled public Decimal totalChargesAmount;
        @AuraEnabled public Integer totalPendingSchedule;
        @AuraEnabled public Decimal totalPendingAmount;
    }

    global class BillDetail {
        @AuraEnabled public String billId;
        @AuraEnabled public String billName;
        @AuraEnabled public String dueDate;
        @AuraEnabled public Decimal dueAmount;
        @AuraEnabled public Decimal principalBilled;
        @AuraEnabled public Decimal interestBilled;
        @AuraEnabled public Decimal feesBilled;
        @AuraEnabled public Decimal principalDue;
        @AuraEnabled public Decimal interestDue;
        @AuraEnabled public Decimal feesDue;
        @AuraEnabled public Decimal principalPaid;
        @AuraEnabled public Decimal interestPaid;
        @AuraEnabled public Decimal feesPaid;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public Boolean isPaymentSatisfied;
        @AuraEnabled public String status;
        @AuraEnabled public Integer daysPastDue;
    }

    global class ChargeDetail {
        @AuraEnabled public String chargeId;
        @AuraEnabled public String chargeName;
        @AuraEnabled public String chargeType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String chargeDate;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public String billId;
        @AuraEnabled public String billName;
    }

    global class PendingScheduleDetail {
        @AuraEnabled public String scheduleId;
        @AuraEnabled public String dueDate;
        @AuraEnabled public Decimal principalDue;
        @AuraEnabled public Decimal interestDue;
        @AuraEnabled public Decimal feesDue;
        @AuraEnabled public Decimal totalDue;
    }
}
