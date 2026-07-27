/**
 * REST Service for Customer 360 Summary API.
 * Endpoint: /services/apexrest/Customer360/v1/customer-summary
 */
@RestResource(urlMapping='/Customer360/v1/customer-summary')
global with sharing class Customer360SummaryService {
    /**
     * Retrieves the same customer summary read model used by the Customer 360 LWC.
     * Query parameters:
     * - accountId: Salesforce Account Id.
     * - accountNumber: Account Number alternative.
     * @return Standard Customer 360 REST response.
     */
    @HttpGet
    global static ResponseWrapper getCustomerSummary() {
        RestRequest request = RestContext.request;
        String accountId = request.params.get('accountId');
        String accountNumber = request.params.get('accountNumber');

        if (String.isBlank(accountId) && String.isBlank(accountNumber)) {
            return errorResponse(400, 'INVALID_PARAMETER', 'Either accountId or accountNumber is required');
        }
        if (!Schema.sObjectType.Account.isAccessible()) {
            return errorResponse(403, 'FORBIDDEN', 'Access denied to Account object');
        }

        try {
            Customer360DataService.CustomerSummaryData summary =
                Customer360DataService.getCustomerSummary(accountId, accountNumber);
            if (summary == null) {
                return errorResponse(404, 'ACCOUNT_NOT_FOUND', 'Account not found with the provided ID or number');
            }

            return successResponse('Customer summary retrieved successfully', summary);
        } catch (Exception unexpectedException) {
            return errorResponse(500, 'SERVER_ERROR', 'An error occurred while processing the request');
        }
    }

    /**
     * Builds the shared summary payload for internal Apex consumers such as credit checks.
     * @param accountId Salesforce Account Id.
     * @return Customer 360 summary payload, or null when no account is found.
     */
    global static Customer360DataService.CustomerSummaryData buildCustomerSummaryForCreditCheck(Id accountId) {
        return Customer360DataService.getCustomerSummaryByAccountId(accountId);
    }

    private static ResponseWrapper successResponse(String message, Object data) {
        ResponseWrapper response = new ResponseWrapper();
        Customer360RestResponseFactory.applySuccess(response, message, data);
        return response;
    }

    private static ResponseWrapper errorResponse(Integer statusCode, String errorCode, String message) {
        ResponseWrapper response = new ResponseWrapper();
        Customer360RestResponseFactory.applyError(response, statusCode, errorCode, message);
        return response;
    }

    /**
     * REST compiler requires the response type to be local to this resource.
     */
    global class ResponseWrapper extends Customer360ApiResponse {
    }
}
