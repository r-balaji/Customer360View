@IsTest
private class Customer360ControllerTest {
    @TestSetup
    static void setupTestData() {
        Customer360TestDataFactory.createFullFixture();
    }

    @IsTest
    static void shouldReturnAccount_WhenSearchingByName() {
        Account accountRecord = getAccount();

        Test.startTest();
        List<Customer360Controller.AccountWrapper> results =
            Customer360Controller.searchAccountsWithFilters(accountRecord.Name, null, null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Search by exact account name should return the test account');
        Assert.areEqual(accountRecord.Id, results[0].id, 'Returned wrapper should contain the matching account id');
    }

    @IsTest
    static void shouldReturnAccount_WhenSearchingByPhone() {
        Account accountRecord = getAccount();

        Test.startTest();
        List<Customer360Controller.AccountWrapper> results =
            Customer360Controller.searchAccountsWithFilters(null, accountRecord.Phone, null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Search by phone should return the test account');
        Assert.areEqual(accountRecord.Phone, results[0].phone, 'Returned wrapper should include the matching phone');
    }

    @IsTest
    static void shouldReturnAccount_WhenSearchingByEmail() {
        Contact contactRecord = getContact();

        Test.startTest();
        List<Customer360Controller.AccountWrapper> results =
            Customer360Controller.searchAccountsWithFilters(null, null, contactRecord.Email);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Search by contact email should return the owning account');
        Assert.areEqual(contactRecord.Email, results[0].email, 'Returned wrapper should include the matching email');
    }

    @IsTest
    static void shouldReturnEmptyList_WhenSearchFiltersAreBlank() {
        Test.startTest();
        List<Customer360Controller.AccountWrapper> results =
            Customer360Controller.searchAccountsWithFilters(null, '', '   ');
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Blank search filters should not query or return accounts');
    }

    @IsTest
    static void shouldLimitAccountSearchResults_WhenMoreThanTwentyMatch() {
        Customer360TestDataFactory.createAccounts('Bulk Search Customer', 25, true);

        Test.startTest();
        List<Customer360Controller.AccountWrapper> results =
            Customer360Controller.searchAccountsWithFilters('Bulk Search Customer', null, null);
        Test.stopTest();

        Assert.areEqual(20, results.size(), 'Account search should enforce the 20 row limit');
    }

    @IsTest
    static void shouldReturnCustomerSummary_WhenAccountIdIsValid() {
        Account accountRecord = getAccount();
        SObject loanAccount = getLoanAccount();

        Test.startTest();
        Customer360DataService.CustomerSummaryData summary = Customer360Controller.getCustomerSummary(accountRecord.Id);
        Test.stopTest();

        Assert.areEqual(accountRecord.Id, summary.accountId, 'Summary should be for the requested account');
        Assert.areEqual(loanAccount == null ? 0 : 1, summary.loans.size(), 'Summary should reflect available loan fixture data');
        if (loanAccount != null) {
            Assert.areEqual(10000, summary.totalLoanAmount, 'Summary should total the loan amount from setup data');
            Assert.areEqual(1, summary.summary.totalLoans, 'Summary metrics should count one non-master loan');
        }
    }

    @IsTest
    static void shouldReturnLoanDetails_WhenLoanAccountIdIsValid() {
        SObject loanAccount = getLoanAccount();
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        Customer360DataService.LoanDetailsData details = Customer360Controller.getLoanDetails(loanAccount.Id);
        Test.stopTest();

        Assert.areEqual(loanAccount.Id, details.loanAccountId, 'Loan details should be for the requested loan account');
        Assert.isNotNull(details.overview, 'Loan details should include overview data');
        Assert.areEqual(0, details.transactions.totalTransactions, 'Loan details should handle loans without payment transactions');
        Assert.areEqual(1, details.duesAndCharges.bills.size(), 'Loan details should include the setup bill');
        Assert.areEqual(0, details.duesAndCharges.charges.size(), 'Loan details should handle loans without charges');
    }

    @IsTest
    static void shouldReturnEmptyRecentPayments_WhenLoanHasNoTransactions() {
        SObject loanAccount = getLoanAccount();
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        List<Customer360Controller.PaymentTransactionWrapper> results =
            Customer360Controller.getRecentPaymentTransactions(loanAccount.Id);
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Recent payments should be empty when the loan has no transactions');
    }

    @IsTest
    static void shouldReturnEmptyUnpaidCharges_WhenLoanHasNoCharges() {
        SObject loanAccount = getLoanAccount();
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        List<Customer360Controller.ChargeWrapper> results = Customer360Controller.getUnpaidCharges(loanAccount.Id);
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Unpaid charges should be empty when the loan has no charges');
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenRecentPaymentsLoanIdIsBlank() {
        Test.startTest();
        try {
            Customer360Controller.getRecentPaymentTransactions('');
            Assert.fail('Expected AuraHandledException for blank loan account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Blank loan id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenUnpaidChargesLoanIdIsBlank() {
        Test.startTest();
        try {
            Customer360Controller.getUnpaidCharges(' ');
            Assert.fail('Expected AuraHandledException for blank loan account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Blank loan id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenSummaryAccountIdIsBlank() {
        Test.startTest();
        try {
            Customer360Controller.getCustomerSummary(' ');
            Assert.fail('Expected AuraHandledException for blank account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Blank account id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenSummaryAccountDoesNotExist() {
        Test.startTest();
        try {
            Customer360Controller.getCustomerSummary(UserInfo.getUserId());
            Assert.fail('Expected AuraHandledException for unknown account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Unknown account id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenLoanAccountIdIsBlank() {
        Test.startTest();
        try {
            Customer360Controller.getLoanDetails(null);
            Assert.fail('Expected AuraHandledException for blank loan account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Blank loan account id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenLoanAccountDoesNotExist() {
        Account accountRecord = getAccount();

        Test.startTest();
        try {
            Customer360Controller.getLoanDetails(accountRecord.Id);
            Assert.fail('Expected AuraHandledException for unknown loan account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Unknown loan account id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldReturnOrgNamespacePrefix_WhenAvailable() {
        Test.startTest();
        String namespacePrefix = Customer360Controller.getOrgNamespacePrefix();
        Test.stopTest();

        Assert.isTrue(namespacePrefix == null || !namespacePrefix.endsWith('__'), 'Namespace prefix should be display-safe');
    }

    @IsTest
    static void shouldQualifyCustomApiNames_ForNamespaceAwareQueries() {
        String namespacePrefix = Customer360Controller.getOrgNamespacePrefix();
        String qualifiedLoanAccountApiName = namespacePrefix == null
            ? 'Loan_Account__c'
            : namespacePrefix + '__Loan_Account__c';

        Test.startTest();
        String blankApiName = Customer360Controller.getOrgQualifiedApiName('');
        String standardApiName = Customer360Controller.getOrgQualifiedApiName('Account');
        String alreadyQualifiedApiName = Customer360Controller.getOrgQualifiedApiName(qualifiedLoanAccountApiName);
        Test.stopTest();

        Assert.areEqual('', blankApiName, 'Blank api names should not be changed');
        Assert.areEqual('Account', standardApiName, 'Standard object api names should not be namespaced');
        Assert.areEqual(qualifiedLoanAccountApiName, alreadyQualifiedApiName, 'Already-qualified custom api names should not be changed');
    }

    @IsTest
    static void shouldReturnFieldParameter_WhenLoanPaymentFieldExists() {
        if (!Customer360NamespaceUtil.hasLoanModule()) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        String parameterName = Customer360Controller.getLoanAccountFieldId();
        String cachedParameterName = Customer360Controller.getLoanAccountFieldId();
        Test.stopTest();

        Assert.isTrue(parameterName.startsWith('CF'), 'Visualforce field parameter should use the CF prefix');
        Assert.areEqual(17, parameterName.length(), 'Visualforce field parameter should include CF plus a 15-character field id');
        Assert.areEqual(parameterName, cachedParameterName, 'Repeated field id lookups should return the cached parameter name');
    }

    @IsTest
    static void shouldReturnFieldParameter_WhenRepaymentAdjustmentFieldExists() {
        if (!Customer360NamespaceUtil.hasLoanModule()) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        String parameterName = Customer360Controller.getRepaymentTransactionAdjustmentFieldId();
        Test.stopTest();

        Assert.isTrue(parameterName.startsWith('CF'), 'Repayment adjustment field parameter should use the CF prefix');
        Assert.areEqual(17, parameterName.length(), 'Repayment adjustment parameter should include CF plus a field id');
    }

    @IsTest
    static void shouldReturnFieldParameter_WhenPayoffQuoteFieldExists() {
        if (!Customer360NamespaceUtil.hasLoanModule()) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        String parameterName = Customer360Controller.getPayoffQuoteLoanAccountFieldId();
        Test.stopTest();

        Assert.isTrue(parameterName.startsWith('CF'), 'Payoff quote field parameter should use the CF prefix');
        Assert.areEqual(17, parameterName.length(), 'Payoff quote parameter should include CF plus a field id');
    }

    private static Account getAccount() {
        return [
            SELECT Id, Name, AccountNumber, Phone
            FROM Account
            WHERE Name LIKE 'Customer 360 Test Account%'
            LIMIT 1
        ];
    }

    private static Contact getContact() {
        return [
            SELECT Id, Email, AccountId
            FROM Contact
            WHERE Email LIKE 'customer360.contact%@example.com'
            LIMIT 1
        ];
    }

    private static SObject getLoanAccount() {
        String loanObjectApiName = Customer360NamespaceUtil.getLoanObjectApiName();
        if (String.isBlank(loanObjectApiName)) {
            return null;
        }

        List<SObject> loans = Database.query('SELECT Id, Name FROM ' + loanObjectApiName + ' LIMIT 1');
        return loans.isEmpty() ? null : loans[0];
    }
}
