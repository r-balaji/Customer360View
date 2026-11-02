/**
 * REST Service for Customer 360 Loan Details API.
 * Endpoint: /services/apexrest/Customer360/v1/loan-details
 */
@RestResource(urlMapping='/Customer360/v1/loan-details')
global with sharing class Customer360LoanDetailsService {
    private static final String LOAN_ID_PATTERN = 'LAI-[0-9]{8}';
    private static final String SALESFORCE_ID_PATTERN = '[a-zA-Z0-9]{15,18}';

    /**
     * Retrieves the same loan detail read model used by the Customer 360 LWC.
     * Query parameters:
     * - loanId: Public loan id in LAI-XXXXXXXX format.
     * - loanAccountId: Salesforce Loan Account Id.
     * @return Standard Customer 360 REST response.
     */
    @HttpGet
    global static ResponseWrapper getLoanDetails() {
        RestRequest request = RestContext.request;
        String loanId = request.params.get('loanId');
        String loanAccountId = request.params.get('loanAccountId');

        if (String.isBlank(loanId) && String.isBlank(loanAccountId)) {
            return errorResponse(
                400,
                'INVALID_PARAMETER',
                'Either loanId (format: LAI-XXXXXXXX) or loanAccountId (Salesforce ID) parameter is required'
            );
        }
        if (String.isNotBlank(loanId) && !Pattern.matches(LOAN_ID_PATTERN, loanId.trim().toUpperCase())) {
            return errorResponse(400, 'INVALID_LOAN_ID_FORMAT', 'Loan ID must be in format LAI-XXXXXXXX (8 digits)');
        }
        if (String.isNotBlank(loanAccountId) && !Pattern.matches(SALESFORCE_ID_PATTERN, loanAccountId.trim())) {
            return errorResponse(400, 'INVALID_LOAN_ACCOUNT_ID', 'Invalid loan account ID format');
        }
        if (!Customer360NamespaceUtil.isObjectAccessible(Customer360NamespaceUtil.getLoanObjectApiName())) {
            return errorResponse(403, 'FORBIDDEN', 'Access denied to Loan Account object');
        }

        try {
            Customer360DataService.LoanDetailsData loanDetails =
                Customer360DataService.getLoanDetails(loanId, loanAccountId);
            if (loanDetails == null) {
                return errorResponse(404, 'LOAN_NOT_FOUND', 'No loan found with the provided identifier');
            }

            return successResponse('Loan details retrieved successfully', loanDetails);
        } catch (Exception unexpectedException) {
            return errorResponse(500, 'SERVER_ERROR', 'An error occurred while processing the request');
        }
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