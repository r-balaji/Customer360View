/**
 * Populates Customer 360 REST response envelopes and HTTP status codes.
 */
public with sharing class Customer360RestResponseFactory {
    /**
     * Populates a success response.
     * @param response Response envelope to populate.
     * @param message Response message.
     * @param data Response payload.
     */
    public static void applySuccess(Customer360ApiResponse response, String message, Object data) {
        setStatusCode(200);
        response.success = true;
        response.message = message;
        response.data = data;
        response.timestamp = currentTimestamp();
    }

    /**
     * Populates an error response.
     * @param response Response envelope to populate.
     * @param statusCode HTTP status code.
     * @param errorCode Stable API error code.
     * @param message User-safe error message.
     */
    public static void applyError(
        Customer360ApiResponse response,
        Integer statusCode,
        String errorCode,
        String message
    ) {
        setStatusCode(statusCode);
        response.success = false;
        response.errorCode = errorCode;
        response.message = message;
        response.timestamp = currentTimestamp();
    }

    private static void setStatusCode(Integer statusCode) {
        if (RestContext.response != null) {
            RestContext.response.statusCode = statusCode;
        }
    }

    private static String currentTimestamp() {
        return Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }
}
