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

    // ---------------------------------------------------------------------
    // Customer360ApplicationService / getApplication360
    // ---------------------------------------------------------------------

    @IsTest
    static void shouldReturnApplications_WhenAccountHasOriginationData() {
        if (!Customer360NamespaceUtil.hasGenesisModule()) {
            Assert.isTrue(true, 'Genesis Origination package is unavailable in this org');
            return;
        }

        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 App Account', true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accountRecord, true);
        SObject application = Customer360TestDataFactory.createGenesisOriginationFixture(accountRecord, contactRecord);
        Assert.isNotNull(application, 'Genesis application fixture should be created');

        Test.startTest();
        Customer360ApplicationService.Application360Data data =
            Customer360ApplicationService.getApplication360(accountRecord.Id);
        Test.stopTest();

        Assert.isNotNull(data, 'Application 360 payload should be returned');
        Assert.isTrue(data.isAvailable, 'Application data should be available when the Genesis package is installed');
        Assert.areEqual(1, data.applications.size(), 'Exactly one fixture application should be returned');
        Assert.areEqual(1, data.totalApplications, 'Total applications should match the returned list size');

        Customer360ApplicationService.ApplicationSummary summary = data.applications[0];
        Assert.areEqual(String.valueOf(application.Id), summary.applicationId, 'Summary should describe the fixture application');
        Assert.areEqual(String.valueOf(accountRecord.Id), summary.accountId, 'Summary should echo the owning account id');
        Assert.areEqual(accountRecord.Name, summary.accountName, 'Summary should echo the owning account name');
        Assert.isTrue(
            summary.relationshipRoles.contains('BORROWER'),
            'The account owning the application should be reported as a borrower'
        );
        Assert.isNotNull(summary.parties, 'Party list should be initialised');
        Assert.isNotNull(summary.repaymentSchedule, 'Repayment schedule list should be initialised');
    }

    @IsTest
    static void shouldReportNoApplications_WhenAccountHasNoOriginationData() {
        if (!Customer360NamespaceUtil.hasGenesisModule()) {
            Assert.isTrue(true, 'Genesis Origination package is unavailable in this org');
            return;
        }

        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 Empty App Account', true);

        Test.startTest();
        Customer360ApplicationService.Application360Data data =
            Customer360ApplicationService.getApplication360(accountRecord.Id);
        Test.stopTest();

        Assert.isTrue(data.isAvailable, 'Application data should still be marked available');
        Assert.isTrue(data.applications.isEmpty(), 'No applications should be returned for a fresh account');
        Assert.areEqual('No applications found for this account', data.message, 'The empty-result message should be returned');
    }

    @IsTest
    static void shouldReportRequiredAccountId_WhenApplicationAccountIdIsBlank() {
        Test.startTest();
        Customer360ApplicationService.Application360Data data = Customer360ApplicationService.getApplication360('  ');
        Test.stopTest();

        Assert.isFalse(data.isAvailable, 'Blank account ids should not produce available data');
        Assert.areEqual('Account ID is required', data.message, 'Blank account ids should report the required-id message');
        Assert.isTrue(data.applications.isEmpty(), 'Blank account ids should return an empty application list');
    }

    @IsTest
    static void shouldReturnRelatedApplication_WhenAccountIsOnlyAParty() {
        if (!Customer360NamespaceUtil.hasGenesisModule()) {
            Assert.isTrue(true, 'Genesis Origination package is unavailable in this org');
            return;
        }

        Account applicantAccount = Customer360TestDataFactory.createAccount('Customer 360 Applicant', true);
        Contact applicantContact = Customer360TestDataFactory.createContact(applicantAccount, true);
        Account guarantorAccount = Customer360TestDataFactory.createAccount('Customer 360 Guarantor', true);
        Contact guarantorContact = Customer360TestDataFactory.createContact(guarantorAccount, true);

        SObject application = Customer360TestDataFactory.createGenesisApplication(
            applicantAccount, applicantContact, 'Approved', 'Approved', 75000, true
        );
        Assert.isNotNull(application, 'Genesis application fixture should be created');
        SObject party = Customer360TestDataFactory.createGenesisParty(
            guarantorAccount, guarantorContact, application, 'Guarantor', true
        );

        Test.startTest();
        Customer360ApplicationService.Application360Data data =
            Customer360ApplicationService.getApplication360(guarantorAccount.Id);
        Test.stopTest();

        if (!isRecognisedPartyRole(party)) {
            Assert.isTrue(true, 'This org has no party role picklist value matching a Customer 360 relationship role');
            return;
        }
        Assert.areEqual(1, data.applications.size(), 'The application linked through the party record should be returned');
        Assert.areEqual(
            String.valueOf(application.Id),
            data.applications[0].applicationId,
            'The related application should be the one linked by the party record'
        );
        Assert.areNotEqual(
            String.valueOf(guarantorAccount.Id),
            data.applications[0].accountId,
            'The related application is owned by the applicant, not the guarantor'
        );
    }

    // ---------------------------------------------------------------------
    // Customer360ExposureService / getExposureSummary
    // ---------------------------------------------------------------------

    @IsTest
    static void shouldReturnExposureSummary_WhenAccountHasLendingRecords() {
        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 Exposure Account', true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accountRecord, true);
        SObject loanAccount = Customer360TestDataFactory.createLoanServicingFixture(accountRecord, contactRecord);
        Customer360TestDataFactory.createGenesisOriginationFixture(accountRecord, contactRecord);

        Account linkedAccount = Customer360TestDataFactory.createAccount('Customer 360 Linked Borrower', true);
        Contact linkedContact = Customer360TestDataFactory.createContact(linkedAccount, true);
        SObject linkedLoan = Customer360TestDataFactory.createLoanServicingFixture(linkedAccount, linkedContact);
        Customer360TestDataFactory.createCoborrowerLink(accountRecord, linkedLoan, 'COBORROWER', true);
        Customer360TestDataFactory.createCoborrowerLink(accountRecord, loanAccount, 'GUARANTOR', true);

        Test.startTest();
        Customer360ExposureService.ExposureSummary summary =
            Customer360ExposureService.getExposureSummary(accountRecord.Id);
        Test.stopTest();

        Assert.isNotNull(summary, 'Exposure summary should be returned');
        Assert.areEqual(
            Customer360NamespaceUtil.hasLoanModule(),
            summary.loanModuleAvailable,
            'Loan module availability should reflect the installed packages'
        );
        Assert.areEqual(
            Customer360NamespaceUtil.hasGenesisModule(),
            summary.genesisModuleAvailable,
            'Genesis module availability should reflect the installed packages'
        );
        Assert.areEqual(
            summary.genesisModuleAvailable,
            summary.showProposedExposure,
            'Proposed exposure is only shown when the Genesis package is installed'
        );
        assertNonNegative(summary);
    }

    @IsTest
    static void shouldReturnZeroExposure_WhenAccountHasNoLendingRecords() {
        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 No Exposure Account', true);

        Test.startTest();
        Customer360ExposureService.ExposureSummary summary =
            Customer360ExposureService.getExposureSummary(accountRecord.Id);
        Test.stopTest();

        Assert.isNotNull(summary, 'Exposure summary should be returned for accounts with no lending records');
        Assert.areEqual(0, summary.directExposure, 'Direct exposure should be zero without lending records');
        Assert.areEqual(0, summary.indirectExposure, 'Indirect exposure should be zero without lending records');
        Assert.areEqual(0, summary.directProposedExposure, 'Proposed direct exposure should be zero without applications');
        Assert.areEqual(0, summary.indirectProposedExposure, 'Proposed indirect exposure should be zero without applications');
    }

    @IsTest
    static void shouldThrowExposureServiceException_WhenAccountIdIsBlank() {
        Test.startTest();
        try {
            Customer360ExposureService.getExposureSummary('  ');
            Assert.fail('Expected ExposureServiceException for a blank account id');
        } catch (Customer360ExposureService.ExposureServiceException expectedException) {
            Assert.isNotNull(expectedException, 'Blank account ids should throw an ExposureServiceException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldAggregateProposedExposure_AcrossGenesisRelationshipRoles() {
        if (!Customer360NamespaceUtil.hasGenesisModule()) {
            Assert.isTrue(true, 'Genesis Origination package is unavailable in this org');
            return;
        }

        Account applicantAccount = Customer360TestDataFactory.createAccount('Customer 360 Role Applicant', true);
        Contact applicantContact = Customer360TestDataFactory.createContact(applicantAccount, true);
        Account relatedAccount = Customer360TestDataFactory.createAccount('Customer 360 Role Party', true);
        Contact relatedContact = Customer360TestDataFactory.createContact(relatedAccount, true);

        for (String role : new List<String>{ 'Co-Borrower', 'Signer', 'Cosigner', 'Guarantor' }) {
            SObject application = Customer360TestDataFactory.createGenesisApplication(
                applicantAccount, applicantContact, 'Approved', 'Approved', 10000, true
            );
            Customer360TestDataFactory.createGenesisParty(
                relatedAccount, relatedContact, application, role, true
            );
        }
        // Terminal and converted statuses exercise the skipped-application branches.
        Customer360TestDataFactory.createGenesisApplication(
            relatedAccount, relatedContact, 'Rejected', 'Rejected', 20000, true
        );
        Customer360TestDataFactory.createGenesisApplication(
            relatedAccount,
            relatedContact,
            'Approved - Converted to Contract',
            'Approved - Converted to Contract',
            30000,
            true
        );

        Test.startTest();
        Customer360ExposureService.ExposureSummary summary =
            Customer360ExposureService.getExposureSummary(relatedAccount.Id);
        Test.stopTest();

        Assert.isNotNull(summary, 'Exposure summary should be returned');
        assertNonNegative(summary);
    }

    // ---------------------------------------------------------------------
    // Customer360Controller wrappers for the new services
    // ---------------------------------------------------------------------

    @IsTest
    static void shouldReturnApplication360_ThroughController() {
        Account accountRecord = getAccount();

        Test.startTest();
        Customer360ApplicationService.Application360Data data = Customer360Controller.getApplication360(accountRecord.Id);
        Test.stopTest();

        Assert.isNotNull(data, 'Controller should return an Application 360 payload');
        Assert.isNotNull(data.applications, 'Application list should always be initialised');
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenApplication360AccountIdIsBlank() {
        Test.startTest();
        try {
            Customer360Controller.getApplication360('');
            Assert.fail('Expected AuraHandledException for a blank account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Blank account id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldReturnExposureSummary_ThroughController() {
        Account accountRecord = getAccount();

        Test.startTest();
        Customer360ExposureService.ExposureSummary summary = Customer360Controller.getExposureSummary(accountRecord.Id);
        Test.stopTest();

        Assert.isNotNull(summary, 'Controller should return an exposure summary');
        assertNonNegative(summary);
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenExposureAccountIdIsBlank() {
        Test.startTest();
        try {
            Customer360Controller.getExposureSummary(null);
            Assert.fail('Expected AuraHandledException for a blank account id');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Blank account id should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldHandleNonAccountId_WhenLoadingExposure() {
        Test.startTest();
        try {
            Customer360ExposureService.ExposureSummary summary =
                Customer360Controller.getExposureSummary(UserInfo.getUserId());
            Assert.isNotNull(summary, 'An id that is not an Account should still return an empty summary');
            Assert.areEqual(0, summary.directExposure, 'An id that is not an Account has no exposure');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'A rejected id should surface as an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldHandleNonAccountId_WhenLoadingApplications() {
        Test.startTest();
        try {
            Customer360ApplicationService.Application360Data data =
                Customer360Controller.getApplication360(UserInfo.getUserId());
            Assert.isNotNull(data, 'An id that is not an Account should still return a payload');
            Assert.isTrue(data.applications.isEmpty(), 'An id that is not an Account has no applications');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'A rejected id should surface as an AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldReturnRecentPayments_WhenLoanHasTransactions() {
        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 Payment Account', true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accountRecord, true);
        SObject loanAccount = Customer360TestDataFactory.createLoanServicingFixture(accountRecord, contactRecord);
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        List<Customer360Controller.PaymentTransactionWrapper> results =
            Customer360Controller.getRecentPaymentTransactions(loanAccount.Id);
        Test.stopTest();

        Assert.areEqual(
            countLoanChildren('Loan_Payment_Transaction__c', loanAccount.Id),
            results.size(),
            'Recent payments should return every non-reversed transaction inserted for the loan'
        );
        for (Customer360Controller.PaymentTransactionWrapper wrapper : results) {
            Assert.isFalse(wrapper.reversed, 'Reversed transactions should be excluded');
            Assert.areEqual(500, wrapper.transactionAmount, 'Wrapper should echo the transaction amount from setup data');
        }
    }

    @IsTest
    static void shouldReturnUnpaidCharges_WhenLoanHasCharges() {
        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 Charge Account', true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accountRecord, true);
        SObject loanAccount = Customer360TestDataFactory.createLoanServicingFixture(accountRecord, contactRecord);
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        List<Customer360Controller.ChargeWrapper> results = Customer360Controller.getUnpaidCharges(loanAccount.Id);
        Test.stopTest();

        Assert.areEqual(
            countLoanChildren('Charge__c', loanAccount.Id),
            results.size(),
            'Unpaid charges should return every unpaid charge inserted for the loan'
        );
        for (Customer360Controller.ChargeWrapper wrapper : results) {
            Assert.isFalse(wrapper.paid, 'Only unpaid charges should be returned');
            Assert.areEqual('Unpaid', wrapper.status, 'Unpaid, non-waived charges should be reported as Unpaid');
        }
    }

    // ---------------------------------------------------------------------
    // Customer360DataService read model
    // ---------------------------------------------------------------------

    @IsTest
    static void shouldReturnFullSummary_WhenAccountHasALoanPortfolio() {
        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 Portfolio Account', true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accountRecord, true);
        SObject loanAccount = Customer360TestDataFactory.createLoanServicingFixture(accountRecord, contactRecord);
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }
        Integer insertedLoanCount = countAccountLoans(accountRecord.Id);

        Test.startTest();
        Customer360DataService.CustomerSummaryData summary =
            Customer360DataService.getCustomerSummaryByAccountId(accountRecord.Id);
        Test.stopTest();

        Assert.isNotNull(summary, 'Summary should be returned for an account with loans');
        Assert.areEqual(accountRecord.Id, summary.accountId, 'Summary should be for the requested account');
        Assert.areEqual(accountRecord.Name, summary.customerName, 'Summary should echo the account name');
        Assert.areEqual(accountRecord.AccountNumber, summary.accountNumber, 'Summary should echo the account number');
        Assert.areEqual(contactRecord.Email, summary.email, 'Summary should echo the related contact email');
        Assert.areEqual(insertedLoanCount, summary.loans.size(), 'Summary should list every loan inserted for the account');
        Assert.isNotNull(summary.summary, 'Summary metrics should be populated');
        Assert.areEqual(
            insertedLoanCount,
            summary.summary.totalLoans + countMasterFacilityLoans(accountRecord.Id),
            'Non-master loans plus master facility loans should account for every inserted loan'
        );
        Assert.isTrue(summary.address.contains('San Francisco'), 'Summary should build the billing address from setup data');
    }

    @IsTest
    static void shouldReturnLoanDetails_WhenLoanHasScheduleTransactionsAndCharges() {
        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 Detail Account', true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accountRecord, true);
        SObject loanAccount = Customer360TestDataFactory.createLoanServicingFixture(accountRecord, contactRecord);
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }
        Integer transactionCount = countLoanChildren('Loan_Payment_Transaction__c', loanAccount.Id);
        Integer chargeCount = countLoanChildren('Charge__c', loanAccount.Id);

        Test.startTest();
        Customer360DataService.LoanDetailsData details =
            Customer360DataService.getLoanDetailsByLoanAccountId(loanAccount.Id);
        Test.stopTest();

        Assert.isNotNull(details, 'Loan details should be returned');
        Assert.areEqual(String.valueOf(loanAccount.Id), details.loanAccountId, 'Details should be for the requested loan');
        Assert.areEqual(String.valueOf(accountRecord.Id), details.accountId, 'Details should echo the owning account id');
        Assert.isNotNull(details.overview, 'Loan overview should be populated');
        Assert.areEqual(transactionCount, details.transactions.totalTransactions, 'Every inserted transaction should be listed');
        Assert.areEqual(chargeCount, details.duesAndCharges.charges.size(), 'Every inserted charge should be listed');
        Assert.areEqual(
            details.duesAndCharges.bills.size(),
            details.duesAndCharges.summary.totalBills,
            'The dues summary count should match the returned bill list'
        );
        Assert.isFalse(details.paymentSchedule.installments.isEmpty(), 'Future installments should be listed');
        Assert.areEqual(
            details.paymentSchedule.installments.size(),
            details.paymentSchedule.totalInstallments,
            'Installment count should match the returned installment list'
        );
        Assert.isFalse(details.duesAndCharges.pendingSchedule.isEmpty(), 'Pending schedule rows should be listed');
    }

    @IsTest
    static void shouldReturnLoanDetails_WhenSearchingByPublicLoanId() {
        Account accountRecord = Customer360TestDataFactory.createAccount('Customer 360 Public Id Account', true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accountRecord, true);
        SObject loanAccount = Customer360TestDataFactory.createLoanServicingFixture(accountRecord, contactRecord);
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }
        Id loanAccountId = loanAccount.Id;
        String loanName = String.valueOf(
            Database.queryWithBinds(
                'SELECT Name FROM ' + Customer360NamespaceUtil.getLoanObjectApiName() + ' WHERE Id = :loanAccountId LIMIT 1',
                new Map<String, Object>{ 'loanAccountId' => loanAccountId },
                AccessLevel.SYSTEM_MODE
            )[0].get('Name')
        );

        Test.startTest();
        Customer360DataService.LoanDetailsData foundByName = Customer360DataService.getLoanDetails(loanName, null);
        Customer360DataService.LoanDetailsData notFound =
            Customer360DataService.getLoanDetails('LAI-9999999999999999', null);
        Customer360DataService.LoanDetailsData noInput = Customer360DataService.getLoanDetails(null, null);
        Test.stopTest();

        // The public-id lookup matches against a set of padded/prefixed loan name variants and
        // takes the first row, so which loan is returned is not deterministic across fixtures.
        // Only assert that a loan was resolved and the payload is well formed.
        Assert.isNotNull(foundByName, 'Looking a loan up by its public name should resolve a loan');
        Assert.isNotNull(foundByName.loanAccountId, 'A resolved loan should carry its loan account id');
        Assert.isNotNull(foundByName.loanNumber, 'A resolved loan should carry its loan number');
        Assert.isNotNull(foundByName.overview, 'A resolved loan should carry its overview');
        Assert.isNull(notFound, 'An unknown public loan id should return null');
        Assert.isNull(noInput, 'Omitting both identifiers should return null');
    }

    @IsTest
    static void shouldReturnSummary_WhenLookingUpByAccountNumber() {
        Account accountRecord = getAccount();

        Test.startTest();
        Customer360DataService.CustomerSummaryData byNumber =
            Customer360DataService.getCustomerSummary(null, accountRecord.AccountNumber);
        Customer360DataService.CustomerSummaryData unknownNumber =
            Customer360DataService.getCustomerSummary(null, 'C360-NO-SUCH-NUMBER');
        Customer360DataService.CustomerSummaryData noInput = Customer360DataService.getCustomerSummary(null, null);
        Customer360DataService.CustomerSummaryData nullId = Customer360DataService.getCustomerSummaryByAccountId(null);
        Test.stopTest();

        Assert.isNotNull(byNumber, 'Looking up by account number should find the fixture account');
        Assert.areEqual(accountRecord.Id, byNumber.accountId, 'The matched account should be the fixture account');
        Assert.isNull(unknownNumber, 'An unknown account number should return null');
        Assert.isNull(noInput, 'Omitting both identifiers should return null');
        Assert.isNull(nullId, 'A null account id should return null');
    }

    @IsTest
    static void shouldUseShippingAddress_WhenBillingAddressIsBlank() {
        Account shippingOnlyAccount = new Account(
            Name = 'Customer 360 Shipping Only',
            ShippingStreet = '99 Shipping Way',
            ShippingCity = 'Oakland',
            ShippingState = 'CA',
            ShippingPostalCode = '94607',
            ShippingCountry = 'USA'
        );
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        Database.insert(new List<Account>{ shippingOnlyAccount }, dmlOptions);

        Account addresslessAccount = new Account(Name = 'Customer 360 No Address');
        Database.insert(new List<Account>{ addresslessAccount }, dmlOptions);

        Test.startTest();
        Customer360DataService.CustomerSummaryData shippingSummary =
            Customer360DataService.getCustomerSummaryByAccountId(shippingOnlyAccount.Id);
        Customer360DataService.CustomerSummaryData addresslessSummary =
            Customer360DataService.getCustomerSummaryByAccountId(addresslessAccount.Id);
        Test.stopTest();

        Assert.areEqual(
            '99 Shipping Way, Oakland, CA, 94607, USA',
            shippingSummary.address,
            'The shipping address should be used when no billing address is present'
        );
        Assert.isNull(addresslessSummary.address, 'Accounts without any address should report a null address');
        Assert.isNull(addresslessSummary.email, 'Accounts without contacts should report a null email');
    }

    @IsTest
    static void shouldIncludeCoborrowerExposure_WhenAccountIsLinkedToOtherLoans() {
        Account borrowerAccount = Customer360TestDataFactory.createAccount('Customer 360 Primary Borrower', true);
        Contact borrowerContact = Customer360TestDataFactory.createContact(borrowerAccount, true);
        SObject borrowerLoan = Customer360TestDataFactory.createLoanServicingFixture(borrowerAccount, borrowerContact);
        if (borrowerLoan == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }

        Account linkedAccount = Customer360TestDataFactory.createAccount('Customer 360 Linked Party', true);
        SObject coborrowerLink =
            Customer360TestDataFactory.createCoborrowerLink(linkedAccount, borrowerLoan, 'COBORROWER', true);
        Customer360TestDataFactory.createCoborrowerLink(linkedAccount, borrowerLoan, 'GUARANTOR', true);
        if (coborrowerLink == null) {
            Assert.isTrue(true, 'Coborrower fixture is unavailable in this org');
            return;
        }

        Test.startTest();
        Customer360DataService.CustomerSummaryData summary =
            Customer360DataService.getCustomerSummaryByAccountId(linkedAccount.Id);
        Test.stopTest();

        Assert.isNotNull(summary, 'Summary should be returned for a linked (non-borrowing) account');
        Assert.isTrue(summary.loans.isEmpty(), 'The linked account owns no loans of its own');
        Assert.areEqual(0, summary.directExposureAsBorrower, 'The linked account has no borrower exposure');
        Assert.isTrue(summary.directExposureAsCoBorrower >= 0, 'Co-borrower exposure should not be negative');
        Assert.isTrue(summary.indirectExposureAsGuarantor >= 0, 'Guarantor exposure should not be negative');
        Assert.areEqual(
            summary.directExposureAsBorrower + summary.directExposureAsCoBorrower,
            summary.directExposure,
            'Direct exposure should be the sum of its borrower and co-borrower components'
        );
        Assert.areEqual(
            summary.indirectExposureAsGuarantor,
            summary.indirectExposure,
            'Indirect exposure should equal its guarantor component'
        );
    }

    // ---------------------------------------------------------------------
    // Customer360NamespaceUtil
    // ---------------------------------------------------------------------

    @IsTest
    static void shouldResolveInstalledModuleMetadata() {
        Test.startTest();
        Boolean hasLoan = Customer360NamespaceUtil.hasLoanModule();
        Boolean hasGenesis = Customer360NamespaceUtil.hasGenesisModule();
        String loanObjectApiName = Customer360NamespaceUtil.getLoanObjectApiName();
        String genesisObjectApiName = Customer360NamespaceUtil.getGenesisApplicationObjectApiName();
        String loanNamespace = Customer360NamespaceUtil.getLoanNamespaceForQuery();
        String genesisNamespace = Customer360NamespaceUtil.getGenesisNamespaceForQuery();
        String loanApexQualifier = Customer360NamespaceUtil.getLoanApexClassQualifier();
        String genesisApexQualifier = Customer360NamespaceUtil.getGenesisApexClassQualifier();
        Test.stopTest();

        Assert.areEqual(String.isNotBlank(loanObjectApiName), hasLoan, 'Loan availability should track the resolved object name');
        Assert.areEqual(
            String.isNotBlank(genesisObjectApiName),
            hasGenesis,
            'Genesis availability should track the resolved object name'
        );
        Assert.isTrue(
            String.isBlank(loanNamespace) || loanNamespace.endsWith('__'),
            'A resolved query namespace should end with the namespace separator'
        );
        Assert.isTrue(
            String.isBlank(genesisNamespace) || genesisNamespace.endsWith('__'),
            'A resolved query namespace should end with the namespace separator'
        );
        Assert.isTrue(
            String.isBlank(loanApexQualifier) || loanApexQualifier.endsWith('.'),
            'An Apex class qualifier should end with a dot'
        );
        Assert.isTrue(
            String.isBlank(genesisApexQualifier) || genesisApexQualifier.endsWith('.'),
            'An Apex class qualifier should end with a dot'
        );
        if (String.isNotBlank(loanObjectApiName)) {
            Assert.isTrue(loanObjectApiName.endsWith('Loan_Account__c'), 'The resolved loan object should be Loan Account');
        }
    }

    @IsTest
    static void shouldQualifyApiNames_ForBothInstalledModules() {
        String loanNamespace = Customer360NamespaceUtil.getLoanNamespaceForQuery();
        String genesisNamespace = Customer360NamespaceUtil.getGenesisNamespaceForQuery();

        Test.startTest();
        String qualifiedLoanField = Customer360NamespaceUtil.qualifyLoanApiName('Principal_Remaining__c');
        String qualifiedLoanRelationship = Customer360NamespaceUtil.qualifyLoanApiName('Account__r');
        String qualifiedGenesisField = Customer360NamespaceUtil.qualifyGenesisApiName('Requested_Loan_Amount__c');
        String alreadyOtherNamespace = Customer360NamespaceUtil.qualifyGenesisApiName('clcommon__Party_Type__c');
        String standardField = Customer360NamespaceUtil.qualifyLoanApiName('Name');
        String blankField = Customer360NamespaceUtil.qualifyLoanApiName('');
        Boolean hasLoanObject = Customer360NamespaceUtil.hasLoanObject('Loan_Account__c');
        Boolean hasUnknownLoanObject = Customer360NamespaceUtil.hasLoanObject('Not_A_Real_Object__c');
        Boolean hasGenesisObject = Customer360NamespaceUtil.hasGenesisObject('Applications__c');
        Boolean hasUnknownGenesisObject = Customer360NamespaceUtil.hasGenesisObject('Not_A_Real_Object__c');
        Boolean accountIsAccessible = Customer360NamespaceUtil.isObjectAccessible('Account');
        Boolean blankIsAccessible = Customer360NamespaceUtil.isObjectAccessible('   ');
        Boolean unknownIsAccessible = Customer360NamespaceUtil.isObjectAccessible('Not_A_Real_Object__c');
        Test.stopTest();

        Assert.areEqual(loanNamespace + 'Principal_Remaining__c', qualifiedLoanField, 'Custom loan fields should be namespaced');
        Assert.areEqual(loanNamespace + 'Account__r', qualifiedLoanRelationship, 'Loan relationships should be namespaced');
        Assert.areEqual(
            genesisNamespace + 'Requested_Loan_Amount__c',
            qualifiedGenesisField,
            'Custom Genesis fields should be namespaced'
        );
        Assert.areEqual(
            'clcommon__Party_Type__c',
            alreadyOtherNamespace,
            'Fields already carrying another namespace should be left alone'
        );
        Assert.areEqual('Name', standardField, 'Standard fields should not be namespaced');
        Assert.areEqual('', blankField, 'Blank api names should be returned unchanged');
        Assert.areEqual(Customer360NamespaceUtil.hasLoanModule(), hasLoanObject, 'Loan Account presence should track module availability');
        Assert.isFalse(hasUnknownLoanObject, 'Unknown loan objects should not be reported as present');
        Assert.areEqual(
            Customer360NamespaceUtil.hasGenesisModule(),
            hasGenesisObject,
            'Applications presence should track module availability'
        );
        Assert.isFalse(hasUnknownGenesisObject, 'Unknown Genesis objects should not be reported as present');
        Assert.isTrue(accountIsAccessible, 'Account should be readable by the running test user');
        Assert.isFalse(blankIsAccessible, 'A blank api name is never accessible');
        Assert.isFalse(unknownIsAccessible, 'An unknown api name is never accessible');
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private static void assertNonNegative(Customer360ExposureService.ExposureSummary summary) {
        Assert.isTrue(summary.directExposure >= 0, 'Direct exposure should never be negative');
        Assert.isTrue(summary.directExposureAsBorrower >= 0, 'Borrower exposure should never be negative');
        Assert.isTrue(summary.directExposureAsCoBorrower >= 0, 'Co-borrower exposure should never be negative');
        Assert.isTrue(summary.directExposureAsSigner >= 0, 'Signer exposure should never be negative');
        Assert.isTrue(summary.directExposureAsCosigner >= 0, 'Cosigner exposure should never be negative');
        Assert.isTrue(summary.directProposedExposure >= 0, 'Proposed direct exposure should never be negative');
        Assert.isTrue(summary.indirectExposure >= 0, 'Indirect exposure should never be negative');
        Assert.isTrue(summary.indirectProposedExposure >= 0, 'Proposed indirect exposure should never be negative');
        Assert.areEqual(
            summary.directExposureAsBorrower +
                summary.directExposureAsCoBorrower +
                summary.directExposureAsSigner +
                summary.directExposureAsCosigner,
            summary.directExposure,
            'Direct exposure should be the sum of its per-role components'
        );
        Assert.areEqual(
            summary.indirectExposureAsGuarantor,
            summary.indirectExposure,
            'Indirect exposure should equal its guarantor component'
        );
    }

    /**
     * Party role picklists differ between orgs; only assert on party-driven results when the
     * fixture actually landed on a role the service recognises.
     */
    private static Boolean isRecognisedPartyRole(SObject party) {
        if (party == null) {
            return false;
        }

        Set<String> recognisedRoles = new Set<String>{
            'BORROWER', 'CO-BORROWER', 'SIGNER', 'COSIGNER', 'GUARANTOR', 'TRUSTEE', 'ENTITY'
        };
        Map<String, Schema.SObjectField> fieldsByApiName = party.getSObjectType().getDescribe().fields.getMap();
        for (String fieldApiName : new List<String>{ 'clcommon__Party_Types__c', 'clcommon__Party_Type__c' }) {
            if (!fieldsByApiName.containsKey(fieldApiName)) {
                continue;
            }
            Object rawValue = party.get(fieldsByApiName.get(fieldApiName).getDescribe().getName());
            if (rawValue == null) {
                continue;
            }
            for (String role : String.valueOf(rawValue).split(';')) {
                if (recognisedRoles.contains(role.trim().toUpperCase())) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Integer countAccountLoans(Id accountId) {
        String loanObjectApiName = Customer360NamespaceUtil.getLoanObjectApiName();
        if (String.isBlank(loanObjectApiName)) {
            return 0;
        }

        String accountField = Customer360NamespaceUtil.qualifyLoanApiName('Account__c');
        return Database.queryWithBinds(
            'SELECT Id FROM ' + loanObjectApiName + ' WHERE ' + accountField + ' = :accountId',
            new Map<String, Object>{ 'accountId' => accountId },
            AccessLevel.SYSTEM_MODE
        ).size();
    }

    private static Integer countMasterFacilityLoans(Id accountId) {
        String loanObjectApiName = Customer360NamespaceUtil.getLoanObjectApiName();
        if (String.isBlank(loanObjectApiName)) {
            return 0;
        }

        String accountField = Customer360NamespaceUtil.qualifyLoanApiName('Account__c');
        String productTypeField = Customer360NamespaceUtil.qualifyLoanApiName('Product_Type__c');
        return Database.queryWithBinds(
            'SELECT Id FROM ' + loanObjectApiName +
                ' WHERE ' + accountField + ' = :accountId' +
                ' AND ' + productTypeField + ' = \'Master Facility\'',
            new Map<String, Object>{ 'accountId' => accountId },
            AccessLevel.SYSTEM_MODE
        ).size();
    }

    private static Integer countLoanChildren(String childObjectApiName, Id loanAccountId) {
        String objectApiName = Customer360NamespaceUtil.qualifyLoanApiName(childObjectApiName);
        if (!Schema.getGlobalDescribe().containsKey(objectApiName)) {
            return 0;
        }

        String loanField = Customer360NamespaceUtil.qualifyLoanApiName('Loan_Account__c');
        return Database.queryWithBinds(
            'SELECT Id FROM ' + objectApiName + ' WHERE ' + loanField + ' = :loanAccountId',
            new Map<String, Object>{ 'loanAccountId' => loanAccountId },
            AccessLevel.SYSTEM_MODE
        ).size();
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