@IsTest
private class Customer360LoanDetailsServiceTest {
    @TestSetup
    static void setupTestData() {
        Customer360TestDataFactory.createFullFixture();
    }

    @IsTest
    static void shouldReturnBadRequest_WhenIdentifierIsMissing() {
        setRestContext('/services/apexrest/Customer360/v1/loan-details', new Map<String, String>());

        Test.startTest();
        Customer360LoanDetailsService.ResponseWrapper response = Customer360LoanDetailsService.getLoanDetails();
        Test.stopTest();

        Assert.isFalse(response.success, 'Missing loan identifiers should produce an error response');
        Assert.areEqual('INVALID_PARAMETER', response.errorCode, 'Missing identifiers should return INVALID_PARAMETER');
        Assert.areEqual(400, RestContext.response.statusCode, 'HTTP status should be 400 for missing identifiers');
    }

    @IsTest
    static void shouldReturnBadRequest_WhenLoanIdFormatIsInvalid() {
        setRestContext('/services/apexrest/Customer360/v1/loan-details', new Map<String, String>{
            'loanId' => 'LA-123'
        });

        Test.startTest();
        Customer360LoanDetailsService.ResponseWrapper response = Customer360LoanDetailsService.getLoanDetails();
        Test.stopTest();

        Assert.isFalse(response.success, 'Invalid public loan id should produce an error response');
        Assert.areEqual('INVALID_LOAN_ID_FORMAT', response.errorCode, 'Invalid format should return INVALID_LOAN_ID_FORMAT');
        Assert.areEqual(400, RestContext.response.statusCode, 'HTTP status should be 400 for invalid public loan id');
    }

    @IsTest
    static void shouldReturnBadRequest_WhenLoanAccountIdFormatIsInvalid() {
        setRestContext('/services/apexrest/Customer360/v1/loan-details', new Map<String, String>{
            'loanAccountId' => 'not-an-id'
        });

        Test.startTest();
        Customer360LoanDetailsService.ResponseWrapper response = Customer360LoanDetailsService.getLoanDetails();
        Test.stopTest();

        Assert.isFalse(response.success, 'Invalid loan account id should produce an error response');
        Assert.areEqual('INVALID_LOAN_ACCOUNT_ID', response.errorCode, 'Invalid id should return INVALID_LOAN_ACCOUNT_ID');
        Assert.areEqual(400, RestContext.response.statusCode, 'HTTP status should be 400 for invalid loan account id');
    }

    @IsTest
    static void shouldReturnSuccess_WhenLoanAccountIdIsValid() {
        SObject loanAccount = getLoanAccount();
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }
        setRestContext('/services/apexrest/Customer360/v1/loan-details', new Map<String, String>{
            'loanAccountId' => loanAccount.Id
        });

        Test.startTest();
        Customer360LoanDetailsService.ResponseWrapper response = Customer360LoanDetailsService.getLoanDetails();
        Test.stopTest();

        Assert.isTrue(response.success, 'Valid loan account id should produce a success response');
        Assert.areEqual(200, RestContext.response.statusCode, 'HTTP status should be 200 for a valid loan account id');
        Customer360DataService.LoanDetailsData details =
            (Customer360DataService.LoanDetailsData) response.data;
        Assert.areEqual(loanAccount.Id, details.loanAccountId, 'Payload should be for the requested loan account');
        Assert.isNotNull(details.duesAndCharges, 'Payload should include dues and charges');
    }

    @IsTest
    static void shouldReturnSuccess_WhenLoanIdIsValid() {
        SObject loanAccount = getLoanAccount();
        if (loanAccount == null) {
            Assert.isTrue(true, 'Loan package fixture is unavailable in this org');
            return;
        }
        setRestContext('/services/apexrest/Customer360/v1/loan-details', new Map<String, String>{
            'loanId' => String.valueOf(loanAccount.get('Name'))
        });

        Test.startTest();
        Customer360LoanDetailsService.ResponseWrapper response = Customer360LoanDetailsService.getLoanDetails();
        Test.stopTest();

        Assert.isTrue(response.success, 'Valid public loan id should produce a success response');
        Customer360DataService.LoanDetailsData details =
            (Customer360DataService.LoanDetailsData) response.data;
        Assert.areEqual(loanAccount.Id, details.loanAccountId, 'Public loan id should resolve to the setup loan');
    }

    @IsTest
    static void shouldReturnNotFound_WhenLoanDoesNotExist() {
        Account accountRecord = getAccount();
        setRestContext('/services/apexrest/Customer360/v1/loan-details', new Map<String, String>{
            'loanAccountId' => accountRecord.Id
        });

        Test.startTest();
        Customer360LoanDetailsService.ResponseWrapper response = Customer360LoanDetailsService.getLoanDetails();
        Test.stopTest();

        Assert.isFalse(response.success, 'Unknown loan account id should produce an error response');
        if (Customer360NamespaceUtil.hasLoanModule()) {
            Assert.areEqual('LOAN_NOT_FOUND', response.errorCode, 'Unknown loan should return LOAN_NOT_FOUND');
            Assert.areEqual(404, RestContext.response.statusCode, 'HTTP status should be 404 for unknown loan account id');
        } else {
            Assert.areEqual('FORBIDDEN', response.errorCode, 'Missing loan module should return FORBIDDEN');
            Assert.areEqual(403, RestContext.response.statusCode, 'HTTP status should be 403 when loan object is unavailable');
        }
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
            SELECT Id
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

        List<SObject> loans = Database.query('SELECT Id, Name FROM ' + loanObjectApiName + ' LIMIT 1');
        return loans.isEmpty() ? null : loans[0];
    }
}
