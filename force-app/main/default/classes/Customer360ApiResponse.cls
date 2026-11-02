/**
 * Shared REST response envelope for Customer 360 APIs.
 */
global virtual class Customer360ApiResponse {
    public Boolean success;
    public String message;
    public String errorCode;
    public Object data;
    public String timestamp;
    public List<Customer360ErrorDetail> errors;
}