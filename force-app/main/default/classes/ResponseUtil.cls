/**
 * @description       : This class is used to provide LWC API response related utility functions
 * @author            : paras
 * @group             : 
 * @last modified on  : 01-04-2024
 * @last modified by  : paras
**/
global inherited sharing class ResponseUtil {

    /**
     * Converts the genesis Reponse to LWC Response.
     * @param (genesis.Response) genesisResponse - The response coming from any genesis API.
     * @returns {q2lwcc.LWCResponse} - The converted Response.
     */
    global static q2lwcc.LWCResponse convertToLWCResponse(genesis.Response genesisResponse) {
        q2lwcc.LWCResponse response = new q2lwcc.LWCResponse();
        response.status = genesisResponse.status;
        response.content = genesisResponse.content;
        response.response = genesisResponse.response;
        if (String.isNotBlank(genesisResponse.errorMessage)) {
            response.addMessage(q2lwcc.LWCConstants.TYPE_ERROR, genesisResponse.errorCode, genesisResponse.errorMessage);
        }
        return response;
    }

    /**
     * Converts the common Reponse to LWC Response.
     * @param (clcommon.Response) commonResponse - The response coming from any clcommon API.
     * @returns {q2lwcc.LWCResponse} - The converted Response.
     */
    global static q2lwcc.LWCResponse convertToLWCResponse(clcommon.Response commonResponse) {
        q2lwcc.LWCResponse response = new q2lwcc.LWCResponse();
        response.status = commonResponse.status;
        response.content = commonResponse.content;
        response.response = commonResponse.response;
        if (String.isNotBlank(commonResponse.errorMessage)) {
            response.addMessage(q2lwcc.LWCConstants.TYPE_ERROR, commonResponse.errorCode, commonResponse.errorMessage);
        }
        return response;
    }

    /**
     * This method will set the Error message to the API response passed into it.
     * @param (Exception) ex - The exception thrown from the API.
     * @param (q2lwcc.LWCResponse) response - The response coming from any LWC Originate API.
     */
    global static void setErrorMessage(Exception ex, q2lwcc.LWCResponse response) {
        response.status = q2lwcc.LWCConstants.ERROR;
        q2lwcc.LWCResponse.Message errorMessage = new q2lwcc.LWCResponse.Message();
        errorMessage.type = q2lwcc.LWCConstants.TYPE_ERROR;
        errorMessage.message = ex.getMessage();
        response.addMessage(errorMessage);
    }

}