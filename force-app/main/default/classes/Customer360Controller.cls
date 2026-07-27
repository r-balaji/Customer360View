/**
 * Apex Controller for Customer 360 LWC Components
 * Provides methods to retrieve customer and loan data for Lightning Web Components
 */
public with sharing class Customer360Controller {
    private static final Integer VISUALFORCE_FIELD_ID_LENGTH = 15;
    private static final String CUSTOM_FIELD_PARAMETER_PREFIX = 'CF';
    private static final String PAYMENT_TRANSACTION_OBJECT = 'Loan_Payment_Transaction__c';
    private static final String CHARGE_OBJECT = 'Charge__c';
    private static String orgNamespaceForQueryCache;
    private static Map<String, String> visualforceFieldParameterByKey = new Map<String, String>();

    /**
     * Search accounts by customer name, phone, or contact email.
     * @param accountName Account name search text.
     * @param phone Account phone search text.
     * @param email Contact email search text.
     * @return List of matching accounts (max 20)
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountWrapper> searchAccountsWithFilters(String accountName, String phone, String email) {
        List<String> accountSearchFilters = new List<String>();
        Map<String, Object> bindVariables = new Map<String, Object>();

        if (String.isNotBlank(accountName)) {
            bindVariables.put('accountNamePattern', toContainsPattern(accountName));
            accountSearchFilters.add('Name LIKE :accountNamePattern');
        }
        if (String.isNotBlank(phone)) {
            bindVariables.put('phonePattern', toContainsPattern(phone));
            accountSearchFilters.add('Phone LIKE :phonePattern');
        }
        if (String.isNotBlank(email)) {
            bindVariables.put('emailPattern', toContainsPattern(email));
            accountSearchFilters.add('Id IN (SELECT AccountId FROM Contact WHERE Email LIKE :emailPattern)');
        }
        if (accountSearchFilters.isEmpty()) {
            return new List<AccountWrapper>();
        }

        String accountSearchQuery =
            'SELECT Id, Name, AccountNumber, Phone, ' +
            '(SELECT Id, Email FROM Contacts LIMIT 1) ' +
            'FROM Account ' +
            'WHERE (' + String.join(accountSearchFilters, ' OR ') + ') ' +
            'ORDER BY Name ' +
            'LIMIT 20';

        List<Account> accounts = Database.queryWithBinds(
            accountSearchQuery,
            bindVariables,
            AccessLevel.USER_MODE
        );
        return toAccountWrappers(accounts);
    }

    private static String toContainsPattern(String searchValue) {
        return '%' + searchValue.trim() + '%';
    }

    private static List<AccountWrapper> toAccountWrappers(List<Account> accounts) {
        List<AccountWrapper> results = new List<AccountWrapper>();
        for (Account accountRecord : accounts) {
            AccountWrapper wrapper = new AccountWrapper();
            wrapper.id = accountRecord.Id;
            wrapper.name = accountRecord.Name;
            wrapper.accountNumber = accountRecord.AccountNumber;
            wrapper.phone = accountRecord.Phone;
            wrapper.email = accountRecord.Contacts != null && !accountRecord.Contacts.isEmpty()
                ? accountRecord.Contacts[0].Email : null;
            results.add(wrapper);
        }
        return results;
    }

    /**
     * Get recent payment transactions for a loan account
     * @param loanAccountId Loan Account ID
     * @return List of payment transaction wrappers (max 6 most recent)
     */
    @AuraEnabled
    public static List<PaymentTransactionWrapper> getRecentPaymentTransactions(String loanAccountId) {
        if (String.isBlank(loanAccountId)) {
            throw new AuraHandledException('Loan Account ID is required');
        }

        List<PaymentTransactionWrapper> wrappers = new List<PaymentTransactionWrapper>();
        String transactionObjectApiName = getReadableLoanObjectApiName(PAYMENT_TRANSACTION_OBJECT);
        if (String.isBlank(transactionObjectApiName)) {
            return wrappers;
        }

        String query = 'SELECT Id, Name, ' +
            l('Payment_Mode__r') + '.Name, ' +
            l('Transaction_Date__c') + ', ' +
            l('Transaction_Amount__c') + ', ' +
            l('Principal__c') + ', ' +
            l('Interest__c') + ', ' +
            l('Fees__c') + ', ' +
            l('Cleared__c') + ', ' +
            l('Reversed__c') + ', ' +
            l('Excess__c') +
            ' FROM ' + transactionObjectApiName +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' AND ' + l('Reversed__c') + ' = false' +
            ' ORDER BY ' + l('Transaction_Date__c') + ' DESC, CreatedDate DESC' +
            ' LIMIT 6';

        for (SObject txn : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId
        }, AccessLevel.USER_MODE)) {
            SObject paymentMode = txn.getSObject(l('Payment_Mode__r'));
            PaymentTransactionWrapper wrapper = new PaymentTransactionWrapper();
            wrapper.id = stringValue(txn, 'Id');
            wrapper.transactionId = stringValue(txn, 'Name');
            wrapper.paymentMode = stringValue(paymentMode, 'Name');
            wrapper.transactionDate = dateValue(txn, l('Transaction_Date__c'));
            wrapper.transactionAmount = decimalValue(txn, l('Transaction_Amount__c'));
            wrapper.principal = decimalValue(txn, l('Principal__c'));
            wrapper.interest = decimalValue(txn, l('Interest__c'));
            wrapper.fees = decimalValue(txn, l('Fees__c'));
            wrapper.cleared = booleanValue(txn, l('Cleared__c'));
            wrapper.reversed = booleanValue(txn, l('Reversed__c'));
            wrapper.excess = decimalValue(txn, l('Excess__c'));
            wrappers.add(wrapper);
        }

        return wrappers;
    }

    @AuraEnabled
    public static List<ChargeWrapper> getUnpaidCharges(String loanAccountId) {
        if (String.isBlank(loanAccountId)) {
            throw new AuraHandledException('Loan Account ID is required');
        }

        List<ChargeWrapper> wrappers = new List<ChargeWrapper>();
        String chargeObjectApiName = getReadableLoanObjectApiName(CHARGE_OBJECT);
        if (String.isBlank(chargeObjectApiName)) {
            return wrappers;
        }

        String query = 'SELECT Id, Name, CreatedDate, ' +
            l('Date__c') + ', ' +
            l('Fee__r') + '.Name, ' +
            l('Total_Amount_Due__c') + ', ' +
            l('Paid_Amount__c') + ', ' +
            l('Paid__c') + ', ' +
            l('Waive__c') +
            ' FROM ' + chargeObjectApiName +
            ' WHERE ' + l('Loan_Account__c') + ' = :loanAccountId' +
            ' AND ' + l('Paid__c') + ' = false' +
            ' AND (' + l('Waive__c') + ' = false OR ' + l('Waive__c') + ' = null)' +
            ' ORDER BY ' + l('Date__c') + ' DESC, CreatedDate DESC';

        for (SObject charge : Database.queryWithBinds(query, new Map<String, Object>{
            'loanAccountId' => loanAccountId
        }, AccessLevel.USER_MODE)) {
            SObject fee = charge.getSObject(l('Fee__r'));
            ChargeWrapper wrapper = new ChargeWrapper();
            wrapper.id = stringValue(charge, 'Id');
            wrapper.chargeId = stringValue(charge, 'Name');
            wrapper.chargeName = stringValue(charge, 'Name');
            wrapper.chargeType = stringValue(fee, 'Name');
            wrapper.amount = decimalValue(charge, l('Total_Amount_Due__c'));
            wrapper.totalAmountDue = decimalValue(charge, l('Total_Amount_Due__c'));
            wrapper.paidAmount = decimalValue(charge, l('Paid_Amount__c'));
            wrapper.paid = booleanValue(charge, l('Paid__c'));
            wrapper.waived = booleanValue(charge, l('Waive__c'));
            wrapper.chargeDate = dateValue(charge, l('Date__c')) != null ? String.valueOf(dateValue(charge, l('Date__c'))) : '';
            wrapper.createdDate = rawValue(charge, 'CreatedDate') != null ? String.valueOf(rawValue(charge, 'CreatedDate')) : '';
            wrapper.status = wrapper.paid ? 'Paid' : (wrapper.waived ? 'Waived' : 'Unpaid');
            wrapper.billId = stringValue(charge, 'Id');
            wrapper.billName = stringValue(charge, 'Name');
            wrappers.add(wrapper);
        }

        return wrappers;
    }

    /**
     * Get the org namespace prefix for generated metadata names.
     * @return Namespace prefix, or null for unmanaged orgs
     */
    @AuraEnabled(cacheable=true)
    public static String getOrgNamespacePrefix() {
        String namespaceForQuery = getOrgNamespaceForQuery();
        if (String.isBlank(namespaceForQuery)) {
            return null;
        }

        if (namespaceForQuery.endsWith('__')) {
            return namespaceForQuery.substring(0, namespaceForQuery.length() - 2);
        }

        return namespaceForQuery;
    }

    private static String getOrgNamespaceForQuery() {
        if (orgNamespaceForQueryCache != null) {
            return orgNamespaceForQueryCache;
        }

        orgNamespaceForQueryCache = Customer360NamespaceUtil.getLoanNamespaceForQuery();
        return orgNamespaceForQueryCache;
    }

    @TestVisible
    private static String getOrgQualifiedApiName(String apiName) {
        if (String.isBlank(apiName) || (!apiName.endsWith('__c') && !apiName.endsWith('__r'))) {
            return apiName;
        }

        return Customer360NamespaceUtil.qualifyLoanApiName(apiName);
    }

    private static String getReadableLoanObjectApiName(String apiName) {
        String objectApiName = Customer360NamespaceUtil.qualifyLoanApiName(apiName);
        return Customer360NamespaceUtil.isObjectAccessible(objectApiName) ? objectApiName : '';
    }

    private static String l(String apiName) {
        return Customer360NamespaceUtil.qualifyLoanApiName(apiName);
    }

    private static Object rawValue(SObject record, String fieldApiName) {
        return record == null || String.isBlank(fieldApiName) ? null : record.get(fieldApiName);
    }

    private static String stringValue(SObject record, String fieldApiName) {
        Object value = rawValue(record, fieldApiName);
        return value == null ? '' : String.valueOf(value);
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

    /**
     * Get the Loan Payment Transaction field ID for Repayment Transaction Adjustment Visualforce page URL parameters
     * This field ID is org-specific and used in the repaymentReversal Visualforce page
     * Format: CF00N + 15-character field ID
     * Uses Tooling API to query FieldDefinition and extract the field ID
     * @return Visualforce custom field parameter key
     */
    @AuraEnabled(cacheable=true)
    public static String getRepaymentTransactionAdjustmentFieldId() {
        return getVisualforceFieldParameterName(
            'Repayment_Transaction_Adjustment__c',
            'Loan_Payment_Transaction__c'
        );
    }

    /**
     * Get the Loan Account field ID for Visualforce page URL parameters
     * This field ID is org-specific and used in the regularPayment Visualforce page
     * Format: CF00N + 15-character field ID
     * Uses Tooling API to query FieldDefinition and extract the field ID
     * @return Visualforce custom field parameter key
     */
    @AuraEnabled(cacheable=true)
    public static String getLoanAccountFieldId() {
        return getVisualforceFieldParameterName(
            'Loan_Payment_Transaction__c',
            'Loan_Account__c'
        );
    }

    /**
     * Get the Loan Account field ID for Payoff Quote Visualforce page URL parameters
     * This field ID is org-specific and used to pre-populate the Loan Account field
     * Format: CF00N + 15-character field ID
     * Uses Tooling API to query FieldDefinition and extract the field ID
     * @return Visualforce custom field parameter key
     */
    @AuraEnabled(cacheable=true)
    public static String getPayoffQuoteLoanAccountFieldId() {
        return getVisualforceFieldParameterName(
            'Payoff_Quote__c',
            'Loan_Account__c'
        );
    }

    private static String getVisualforceFieldParameterName(String entityApiName, String fieldApiName) {
        String qualifiedEntityApiName = getOrgQualifiedApiName(entityApiName);
        String qualifiedFieldApiName = getOrgQualifiedApiName(fieldApiName);
        String cacheKey = qualifiedEntityApiName + '.' + qualifiedFieldApiName;
        if (visualforceFieldParameterByKey.containsKey(cacheKey)) {
            return visualforceFieldParameterByKey.get(cacheKey);
        }

        List<FieldDefinition> fieldDefs = [
            SELECT DurableId
            FROM FieldDefinition
            WHERE QualifiedApiName = :qualifiedFieldApiName
              AND EntityDefinition.QualifiedApiName = :qualifiedEntityApiName
            WITH USER_MODE
            LIMIT 1
        ];

        if (fieldDefs.isEmpty() || String.isBlank(fieldDefs[0].DurableId)) {
            throw new AuraHandledException('Field ' + qualifiedFieldApiName + ' not found on ' + qualifiedEntityApiName + ' object');
        }

        List<String> durableIdParts = fieldDefs[0].DurableId.split('\\.');
        if (durableIdParts.size() <= 1 || String.isBlank(durableIdParts[1])) {
            throw new AuraHandledException('Invalid DurableId format for field ' + qualifiedFieldApiName + '. Expected format: EntityDefinitionId.FieldDefinitionId');
        }

        String fieldId = durableIdParts[1];
        if (fieldId.length() < VISUALFORCE_FIELD_ID_LENGTH) {
            throw new AuraHandledException('Field ID length is invalid. Expected at least ' + VISUALFORCE_FIELD_ID_LENGTH + ' characters, got: ' + fieldId.length());
        }

        String parameterName = CUSTOM_FIELD_PARAMETER_PREFIX + fieldId.substring(0, VISUALFORCE_FIELD_ID_LENGTH);
        visualforceFieldParameterByKey.put(cacheKey, parameterName);
        return parameterName;
    }

    /**
     * Get customer summary data.
     * @param accountId Account ID.
     * @return Customer summary data.
     */
    @AuraEnabled
    public static Customer360DataService.CustomerSummaryData getCustomerSummary(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account ID is required');
        }

        try {
            Customer360DataService.CustomerSummaryData summary = Customer360DataService.getCustomerSummary(accountId, null);
            if (summary == null) {
                throw new AuraHandledException('Account not found');
            }
            return summary;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load customer summary');
        }
    }

    /**
     * Get detailed loan information.
     * @param loanAccountId Loan Account ID.
     * @return Loan details.
     */
    @AuraEnabled
    public static Customer360DataService.LoanDetailsData getLoanDetails(String loanAccountId) {
        if (String.isBlank(loanAccountId)) {
            throw new AuraHandledException('Loan Account ID is required');
        }

        try {
            Customer360DataService.LoanDetailsData details = Customer360DataService.getLoanDetailsByLoanAccountId(loanAccountId);
            if (details == null) {
                throw new AuraHandledException('Loan account not found');
            }
            return details;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load loan details');
        }
    }

    /**
     * Get origination application details for the selected customer account.
     * @param accountId Account ID.
     * @return Application 360 data.
     */
    @AuraEnabled(cacheable=true)
    public static Customer360ApplicationService.Application360Data getApplication360(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account ID is required');
        }

        try {
            return Customer360ApplicationService.getApplication360(accountId);
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load application details');
        }
    }

    /**
     * Gets current and proposed exposure across installed lending modules.
     * @param accountId Account ID.
     * @return Cross-product account exposure data.
     */
    @AuraEnabled(cacheable=true)
    public static Customer360ExposureService.ExposureSummary getExposureSummary(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account ID is required');
        }

        try {
            return Customer360ExposureService.getExposureSummary(accountId);
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load customer exposure');
        }
    }

    // Wrapper Classes
    public class AccountWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
    }

    public class ChargeWrapper {
        @AuraEnabled public String chargeId;
        @AuraEnabled public String chargeName;
        @AuraEnabled public String chargeType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String chargeDate;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public String billId;
        @AuraEnabled public String billName;
        @AuraEnabled public String id; // Salesforce ID
        @AuraEnabled public String createdDate;
        @AuraEnabled public Decimal totalAmountDue;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public Boolean paid;
        @AuraEnabled public Boolean waived;
    }

    public class PaymentTransactionWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String transactionId;
        @AuraEnabled public String paymentMode;
        @AuraEnabled public Date transactionDate;
        @AuraEnabled public Decimal transactionAmount;
        @AuraEnabled public Decimal principal;
        @AuraEnabled public Decimal interest;
        @AuraEnabled public Decimal fees;
        @AuraEnabled public Boolean cleared;
        @AuraEnabled public Boolean reversed;
        @AuraEnabled public Decimal excess;
    }
}
