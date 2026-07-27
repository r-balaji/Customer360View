@IsTest
private class Customer360SummaryServiceTest {
    @TestSetup
    static void setupTestData() {
        Customer360TestDataFactory.createFullFixture();
    }

    @IsTest
    static void shouldReturnBadRequest_WhenIdentifierIsMissing() {
        setRestContext('/services/apexrest/Customer360/v1/customer-summary', new Map<String, String>());

        Test.startTest();
        Customer360SummaryService.ResponseWrapper response = Customer360SummaryService.getCustomerSummary();
        Test.stopTest();

        Assert.isFalse(response.success, 'Missing identifiers should produce an error response');
        Assert.areEqual('INVALID_PARAMETER', response.errorCode, 'Missing identifiers should return INVALID_PARAMETER');
        Assert.areEqual(400, RestContext.response.statusCode, 'HTTP status should be 400 for missing identifiers');
    }

    @IsTest
    static void shouldReturnSuccess_WhenAccountIdIsValid() {
        Account accountRecord = getAccount();
        setRestContext('/services/apexrest/Customer360/v1/customer-summary', new Map<String, String>{
            'accountId' => accountRecord.Id
        });

        Test.startTest();
        Customer360SummaryService.ResponseWrapper response = Customer360SummaryService.getCustomerSummary();
        Test.stopTest();

        Assert.isTrue(response.success, 'Valid account id should produce a success response');
        Assert.areEqual(200, RestContext.response.statusCode, 'HTTP status should be 200 for a valid account id');
        Customer360DataService.CustomerSummaryData summary =
            (Customer360DataService.CustomerSummaryData) response.data;
        Assert.areEqual(accountRecord.Id, summary.accountId, 'Response payload should be for the requested account');
    }

    @IsTest
    static void shouldReturnSuccess_WhenAccountNumberIsValid() {
        Account accountRecord = getAccount();
        setRestContext('/services/apexrest/Customer360/v1/customer-summary', new Map<String, String>{
            'accountNumber' => accountRecord.AccountNumber
        });

        Test.startTest();
        Customer360SummaryService.ResponseWrapper response = Customer360SummaryService.getCustomerSummary();
        Test.stopTest();

        Assert.isTrue(response.success, 'Valid account number should produce a success response');
        Assert.areEqual(200, RestContext.response.statusCode, 'HTTP status should be 200 for a valid account number');
        Customer360DataService.CustomerSummaryData summary =
            (Customer360DataService.CustomerSummaryData) response.data;
        Assert.areEqual(accountRecord.AccountNumber, summary.accountNumber, 'Payload should preserve account number');
    }

    @IsTest
    static void shouldReturnNotFound_WhenAccountDoesNotExist() {
        setRestContext('/services/apexrest/Customer360/v1/customer-summary', new Map<String, String>{
            'accountId' => UserInfo.getUserId()
        });

        Test.startTest();
        Customer360SummaryService.ResponseWrapper response = Customer360SummaryService.getCustomerSummary();
        Test.stopTest();

        Assert.isFalse(response.success, 'Unknown account id should produce an error response');
        Assert.areEqual('ACCOUNT_NOT_FOUND', response.errorCode, 'Unknown account id should return ACCOUNT_NOT_FOUND');
        Assert.areEqual(404, RestContext.response.statusCode, 'HTTP status should be 404 for unknown account id');
    }

    @IsTest
    static void shouldBuildSummaryForCreditCheck_WhenAccountIdIsValid() {
        Account accountRecord = getAccount();
        SObject loanAccount = getLoanAccount();

        Test.startTest();
        Customer360DataService.CustomerSummaryData summary =
            Customer360SummaryService.buildCustomerSummaryForCreditCheck(accountRecord.Id);
        Test.stopTest();

        Assert.areEqual(accountRecord.Id, summary.accountId, 'Credit check summary should use the shared read model');
        Assert.areEqual(loanAccount == null ? 0 : 1, summary.loans.size(), 'Credit check summary should reflect available loan fixture data');
    }

    private static void setRestContext(String requestUri, Map<String, String> parameters) {
        RestRequest request = new RestRequest();
        request.requestUri = requestUri;
        request.httpMethod = 'GET';
        for (String parameterName : parameters.keySet()) {
            request.params.put(parameterName, parameters.get(parameterName));
        }
        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static Account getAccount() {
        return [
            SELECT Id, AccountNumber
            FROM Account
            WHERE Name LIKE 'Customer 360 Test Account%'
            LIMIT 1
        ];
    }

    private static SObject getLoanAccount() {
        String loanObjectApiName = Customer360NamespaceUtil.getLoanObjectApiName();
        if (String.isBlank(loanObjectApiName)) {
            return null;
        }

        List<SObject> loans = Database.query('SELECT Id FROM ' + loanObjectApiName + ' LIMIT 1');
        return loans.isEmpty() ? null : loans[0];
    }
}
