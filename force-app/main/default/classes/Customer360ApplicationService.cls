/**
 * Read model for Customer 360 origination application details.
 */
public with sharing class Customer360ApplicationService {
    private static final Integer APPLICATION_LIMIT = 20;
    private static final Integer SCHEDULE_LIMIT_PER_APPLICATION = 12;
    private static final String CLCOMMON_NAMESPACE = 'clcommon__';
    private static final String PARTY_OBJECT_API_NAME = 'clcommon__Party__c';
    private static final List<String> CUSTOMER_RELATIONSHIP_ROLES = new List<String>{
        'BORROWER',
        'CO-BORROWER',
        'SIGNER',
        'COSIGNER',
        'GUARANTOR',
        'TRUSTEE',
        'ENTITY'
    };

    /**
     * Builds application summaries for a customer account.
     * @param accountId Salesforce Account Id.
     * @return Application 360 payload with applications, parties, selected pricing, and schedule rows.
     */
    @AuraEnabled(cacheable=true)
    public static Application360Data getApplication360(String accountId) {
        Application360Data data = new Application360Data();
        data.applications = new List<ApplicationSummary>();
        data.isAvailable = false;

        if (String.isBlank(accountId)) {
            data.message = 'Account ID is required';
            return data;
        }
        if (!Customer360NamespaceUtil.hasGenesisModule()) {
            data.message = 'Genesis Origination module is not available';
            return data;
        }

        String applicationObjectApiName = Customer360NamespaceUtil.getGenesisApplicationObjectApiName();
        if (!Customer360NamespaceUtil.isObjectAccessible(applicationObjectApiName)) {
            data.message = 'Access denied to Application object';
            return data;
        }

        data.isAvailable = true;
        Map<Id, Set<String>> relationshipRolesByApplicationId =
            queryRelationshipRolesByApplicationId(accountId);
        List<SObject> applicationRecords = queryApplications(
            accountId,
            applicationObjectApiName,
            relationshipRolesByApplicationId.keySet()
        );
        if (applicationRecords.isEmpty()) {
            data.message = 'No applications found for this account';
            return data;
        }

        Set<Id> applicationIds = new Set<Id>();
        Map<Id, ApplicationSummary> applicationsById = new Map<Id, ApplicationSummary>();
        for (SObject applicationRecord : applicationRecords) {
            Id applicationId = (Id) applicationRecord.get('Id');
            ApplicationSummary summary = toApplicationSummary(applicationRecord);
            summary.relationshipRoles = getRelationshipRoles(
                applicationRecord,
                accountId,
                relationshipRolesByApplicationId
            );
            applicationIds.add(applicationId);
            applicationsById.put(applicationId, summary);
            data.applications.add(summary);
            rollupApplication(data, summary);
        }

        attachSelectedPricing(applicationIds, applicationsById);
        attachParties(applicationIds, applicationsById);
        attachRepaymentSchedule(applicationIds, applicationsById);
        data.totalApplications = data.applications.size();
        data.totalProposedExposure = safeDecimal(data.totalDirectProposedExposure) +
            safeDecimal(data.totalIndirectProposedExposure);
        data.message = null;
        return data;
    }

    private static Map<Id, Set<String>> queryRelationshipRolesByApplicationId(String accountId) {
        Map<Id, Set<String>> rolesByApplicationId = new Map<Id, Set<String>>();
        if (!hasObject(PARTY_OBJECT_API_NAME) ||
            !Customer360NamespaceUtil.isObjectAccessible(PARTY_OBJECT_API_NAME)) {
            return rolesByApplicationId;
        }

        String query = 'SELECT ' + g('Application__c') + ', ' +
            c('Party_Types__c') + ', ' + c('Party_Type__c') +
            ' FROM ' + PARTY_OBJECT_API_NAME +
            ' WHERE ' + c('Account__c') + ' = :accountId' +
            ' AND ' + g('Application__c') + ' != null';
        for (SObject partyRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'accountId' => accountId
        }, AccessLevel.USER_MODE)) {
            Id applicationId = (Id) partyRecord.get(g('Application__c'));
            Set<String> roles = new Set<String>();
            addCustomerRelationshipRoles(roles, stringValue(partyRecord, c('Party_Types__c')));
            addCustomerRelationshipRoles(roles, stringValue(partyRecord, c('Party_Type__c')));
            if (roles.isEmpty()) {
                continue;
            }
            if (!rolesByApplicationId.containsKey(applicationId)) {
                rolesByApplicationId.put(applicationId, new Set<String>());
            }
            rolesByApplicationId.get(applicationId).addAll(roles);
        }
        return rolesByApplicationId;
    }

    private static void addCustomerRelationshipRoles(Set<String> roles, String rawRoles) {
        if (String.isBlank(rawRoles)) {
            return;
        }
        for (String rawRole : rawRoles.split(';')) {
            String normalizedRole = rawRole.trim().toUpperCase();
            if (CUSTOMER_RELATIONSHIP_ROLES.contains(normalizedRole)) {
                roles.add(normalizedRole);
            }
        }
    }

    private static List<String> getRelationshipRoles(
        SObject applicationRecord,
        String selectedAccountId,
        Map<Id, Set<String>> rolesByApplicationId
    ) {
        Id applicationId = (Id) applicationRecord.get('Id');
        Set<String> roles = rolesByApplicationId.containsKey(applicationId)
            ? new Set<String>(rolesByApplicationId.get(applicationId))
            : new Set<String>();
        if (idsEqual(stringValue(applicationRecord, g('Account__c')), selectedAccountId)) {
            roles.add('BORROWER');
        }

        List<String> orderedRoles = new List<String>();
        for (String role : CUSTOMER_RELATIONSHIP_ROLES) {
            if (roles.contains(role)) {
                orderedRoles.add(role);
            }
        }
        return orderedRoles;
    }

    private static List<SObject> queryApplications(
        String accountId,
        String applicationObjectApiName,
        Set<Id> relatedApplicationIds
    ) {
        List<String> fields = new List<String>{
            'Id',
            'Name',
            g('Account__c'),
            g('Account__r') + '.Name',
            g('Contact__c'),
            g('Contact__r') + '.Name',
            g('Status__c'),
            g('Overall_Status__c'),
            g('Product_Type__c'),
            g('CL_Product__c'),
            g('CL_Product__r') + '.Name',
            g('Loan_Application_Type__c'),
            g('Requested_Loan_Amount__c'),
            g('Loan_Amount__c'),
            g('Financed_Amount__c'),
            g('Payment_Amount__c'),
            g('Payment_Frequency__c'),
            g('Interest_Rate__c'),
            g('APR__c'),
            g('Term__c'),
            g('Maturity_Date__c'),
            g('Application_Submission_Date__c'),
            g('Expected_Close_Date__c'),
            g('Credit_Approval_Status__c'),
            g('Credit_Approval_Date__c'),
            g('Manual_Approval_Status__c'),
            g('Manual_Review_Status__c'),
            g('Credit_Verification_Status__c'),
            g('KYC_Verification_Status__c'),
            g('KYB_Verification_Status__c'),
            g('VOI_Verification_Status__c'),
            g('VOE_Verification_Status__c'),
            g('Global_Direct_Exposure__c'),
            g('Global_Indirect_Exposure__c'),
            g('Global_Direct_Proposed_Exposure__c'),
            g('Global_Indirect_Proposed_Exposure__c')
        };

        String whereClause = g('Account__c') + ' = :accountId';
        Map<String, Object> bindVariables = new Map<String, Object>{ 'accountId' => accountId };
        if (relatedApplicationIds != null && !relatedApplicationIds.isEmpty()) {
            whereClause = '(' + whereClause + ' OR Id IN :relatedApplicationIds)';
            bindVariables.put('relatedApplicationIds', relatedApplicationIds);
        }

        String query = 'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + applicationObjectApiName +
            ' WHERE ' + whereClause +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT ' + APPLICATION_LIMIT;
        return Database.queryWithBinds(query, bindVariables, AccessLevel.USER_MODE);
    }

    private static ApplicationSummary toApplicationSummary(SObject applicationRecord) {
        SObject account = applicationRecord.getSObject(g('Account__r'));
        SObject contact = applicationRecord.getSObject(g('Contact__r'));
        SObject product = applicationRecord.getSObject(g('CL_Product__r'));

        ApplicationSummary summary = new ApplicationSummary();
        summary.applicationId = stringValue(applicationRecord, 'Id');
        summary.applicationNumber = stringValue(applicationRecord, 'Name');
        summary.accountId = stringValue(applicationRecord, g('Account__c'));
        summary.accountName = stringValue(account, 'Name');
        summary.contactId = stringValue(applicationRecord, g('Contact__c'));
        summary.contactName = stringValue(contact, 'Name');
        summary.status = stringValue(applicationRecord, g('Status__c'));
        summary.stage = stringValue(applicationRecord, g('Overall_Status__c'));
        summary.productType = stringValue(applicationRecord, g('Product_Type__c'));
        summary.productId = stringValue(applicationRecord, g('CL_Product__c'));
        summary.productName = stringValue(product, 'Name');
        summary.applicationType = stringValue(applicationRecord, g('Loan_Application_Type__c'));
        summary.requestedAmount = decimalValue(applicationRecord, g('Requested_Loan_Amount__c'));
        summary.approvedAmount = decimalValue(applicationRecord, g('Loan_Amount__c'));
        summary.financedAmount = decimalValue(applicationRecord, g('Financed_Amount__c'));
        summary.paymentAmount = decimalValue(applicationRecord, g('Payment_Amount__c'));
        summary.paymentFrequency = stringValue(applicationRecord, g('Payment_Frequency__c'));
        summary.interestRate = decimalValue(applicationRecord, g('Interest_Rate__c'));
        summary.apr = decimalValue(applicationRecord, g('APR__c'));
        summary.term = decimalValue(applicationRecord, g('Term__c'));
        summary.maturityDate = dateValue(applicationRecord, g('Maturity_Date__c'));
        summary.submittedDate = dateValue(applicationRecord, g('Application_Submission_Date__c'));
        summary.expectedCloseDate = dateValue(applicationRecord, g('Expected_Close_Date__c'));
        summary.creditApprovalStatus = stringValue(applicationRecord, g('Credit_Approval_Status__c'));
        summary.creditApprovalDate = dateValue(applicationRecord, g('Credit_Approval_Date__c'));
        summary.manualApprovalStatus = stringValue(applicationRecord, g('Manual_Approval_Status__c'));
        summary.manualReviewStatus = stringValue(applicationRecord, g('Manual_Review_Status__c'));
        summary.creditVerificationStatus = stringValue(applicationRecord, g('Credit_Verification_Status__c'));
        summary.kycVerificationStatus = stringValue(applicationRecord, g('KYC_Verification_Status__c'));
        summary.kybVerificationStatus = stringValue(applicationRecord, g('KYB_Verification_Status__c'));
        summary.voiVerificationStatus = stringValue(applicationRecord, g('VOI_Verification_Status__c'));
        summary.voeVerificationStatus = stringValue(applicationRecord, g('VOE_Verification_Status__c'));
        summary.directExposure = decimalValue(applicationRecord, g('Global_Direct_Exposure__c'));
        summary.indirectExposure = decimalValue(applicationRecord, g('Global_Indirect_Exposure__c'));
        summary.directProposedExposure = decimalValue(applicationRecord, g('Global_Direct_Proposed_Exposure__c'));
        summary.indirectProposedExposure = decimalValue(applicationRecord, g('Global_Indirect_Proposed_Exposure__c'));
        summary.parties = new List<PartyDetail>();
        summary.repaymentSchedule = new List<RepaymentScheduleItem>();
        return summary;
    }

    private static void rollupApplication(Application360Data data, ApplicationSummary summary) {
        data.totalRequestedAmount = safeDecimal(data.totalRequestedAmount) + safeDecimal(summary.requestedAmount);
        data.totalApprovedAmount = safeDecimal(data.totalApprovedAmount) + safeDecimal(summary.approvedAmount);
        data.totalDirectProposedExposure = safeDecimal(data.totalDirectProposedExposure) +
            safeDecimal(summary.directProposedExposure);
        data.totalIndirectProposedExposure = safeDecimal(data.totalIndirectProposedExposure) +
            safeDecimal(summary.indirectProposedExposure);

        String normalizedStatus = String.isBlank(summary.status) ? '' : summary.status.toUpperCase();
        String normalizedStage = String.isBlank(summary.stage) ? '' : summary.stage.toUpperCase();
        if (normalizedStatus.contains('ACCEPTED') || normalizedStatus.contains('APPROVED')) {
            data.approvedApplications++;
        } else if (!normalizedStatus.contains('WITHDRAWN') &&
            !normalizedStatus.contains('REJECTED') &&
            !normalizedStage.contains('BOOKED')) {
            data.inProcessApplications++;
        }
    }

    private static void attachSelectedPricing(Set<Id> applicationIds, Map<Id, ApplicationSummary> applicationsById) {
        if (applicationIds.isEmpty() ||
            !Customer360NamespaceUtil.hasGenesisObject('Application_Pricing_Detail__c')) {
            return;
        }

        String pricingObjectApiName = Customer360NamespaceUtil.qualifyGenesisApiName('Application_Pricing_Detail__c');
        if (!Customer360NamespaceUtil.isObjectAccessible(pricingObjectApiName)) {
            return;
        }

        String query = 'SELECT Id, Name, ' +
            g('Application__c') + ', ' +
            g('Selected__c') + ', ' +
            g('Payment_Amount_Derived__c') + ', ' +
            g('Payment_Amount_Per_Period__c') + ', ' +
            g('Payment_Frequency__c') + ', ' +
            g('Interest_Rate__c') + ', ' +
            g('Term__c') + ', ' +
            g('Total_Interest__c') + ', ' +
            g('Total_Payments_Derived__c') + ', ' +
            g('Pricing_Method__c') + ', ' +
            g('Rate_Factor__c') + ', ' +
            g('Yield_Percent__c') +
            ' FROM ' + pricingObjectApiName +
            ' WHERE ' + g('Application__c') + ' IN :applicationIds' +
            ' AND ' + g('Selected__c') + ' = true' +
            ' ORDER BY CreatedDate DESC';

        for (SObject pricingRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'applicationIds' => applicationIds
        }, AccessLevel.USER_MODE)) {
            Id applicationId = (Id) pricingRecord.get(g('Application__c'));
            if (!applicationsById.containsKey(applicationId) ||
                applicationsById.get(applicationId).selectedPricing != null) {
                continue;
            }

            PricingDetail pricing = new PricingDetail();
            pricing.pricingId = stringValue(pricingRecord, 'Id');
            pricing.pricingName = stringValue(pricingRecord, 'Name');
            pricing.selected = booleanValue(pricingRecord, g('Selected__c'));
            pricing.paymentAmount = firstDecimal(pricingRecord, g('Payment_Amount_Derived__c'), g('Payment_Amount_Per_Period__c'));
            pricing.paymentFrequency = stringValue(pricingRecord, g('Payment_Frequency__c'));
            pricing.interestRate = decimalValue(pricingRecord, g('Interest_Rate__c'));
            pricing.term = decimalValue(pricingRecord, g('Term__c'));
            pricing.totalInterest = decimalValue(pricingRecord, g('Total_Interest__c'));
            pricing.totalPayments = decimalValue(pricingRecord, g('Total_Payments_Derived__c'));
            pricing.pricingMethod = stringValue(pricingRecord, g('Pricing_Method__c'));
            pricing.rateFactor = decimalValue(pricingRecord, g('Rate_Factor__c'));
            pricing.yieldPercent = decimalValue(pricingRecord, g('Yield_Percent__c'));
            applicationsById.get(applicationId).selectedPricing = pricing;
        }
    }

    private static void attachParties(Set<Id> applicationIds, Map<Id, ApplicationSummary> applicationsById) {
        if (applicationIds.isEmpty() ||
            !hasObject(PARTY_OBJECT_API_NAME) ||
            !Customer360NamespaceUtil.isObjectAccessible(PARTY_OBJECT_API_NAME)) {
            return;
        }

        String query = 'SELECT Id, Name, ' +
            g('Application__c') + ', ' +
            c('Account__c') + ', ' +
            c('Account__r') + '.Name, ' +
            c('Contact__c') + ', ' +
            c('Contact__r') + '.Name, ' +
            c('Party_Types__c') + ', ' +
            c('Party_Type__c') + ', ' +
            c('isPrimary__c') + ', ' +
            c('Percent_Ownership__c') + ', ' +
            c('Direct_Exposure__c') + ', ' +
            c('Direct_Proposed_Exposure__c') + ', ' +
            c('Indirect_Exposure__c') + ', ' +
            c('Indirect_Proposed_Exposure__c') + ', ' +
            g('Party_Name__c') + ', ' +
            g('Party_Order__c') + ', ' +
            g('KYC_Verification_Status__c') + ', ' +
            g('KYB_Verification_Status__c') + ', ' +
            g('Credit_Verification_Status__c') +
            ' FROM ' + PARTY_OBJECT_API_NAME +
            ' WHERE ' + g('Application__c') + ' IN :applicationIds' +
            ' ORDER BY ' + g('Party_Order__c') + ' ASC NULLS LAST, Name ASC';

        for (SObject partyRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'applicationIds' => applicationIds
        }, AccessLevel.USER_MODE)) {
            Id applicationId = (Id) partyRecord.get(g('Application__c'));
            if (!applicationsById.containsKey(applicationId)) {
                continue;
            }

            SObject account = partyRecord.getSObject(c('Account__r'));
            SObject contact = partyRecord.getSObject(c('Contact__r'));
            PartyDetail party = new PartyDetail();
            party.partyId = stringValue(partyRecord, 'Id');
            party.partyNumber = stringValue(partyRecord, 'Name');
            party.partyName = firstString(partyRecord, g('Party_Name__c'), c('Account__r') + '.Name');
            party.accountId = stringValue(partyRecord, c('Account__c'));
            party.accountName = stringValue(account, 'Name');
            party.contactId = stringValue(partyRecord, c('Contact__c'));
            party.contactName = stringValue(contact, 'Name');
            party.partyType = firstString(partyRecord, c('Party_Types__c'), c('Party_Type__c'));
            party.primary = booleanValue(partyRecord, c('isPrimary__c'));
            party.percentOwnership = decimalValue(partyRecord, c('Percent_Ownership__c'));
            party.directExposure = decimalValue(partyRecord, c('Direct_Exposure__c'));
            party.directProposedExposure = decimalValue(partyRecord, c('Direct_Proposed_Exposure__c'));
            party.indirectExposure = decimalValue(partyRecord, c('Indirect_Exposure__c'));
            party.indirectProposedExposure = decimalValue(partyRecord, c('Indirect_Proposed_Exposure__c'));
            party.kycStatus = stringValue(partyRecord, g('KYC_Verification_Status__c'));
            party.kybStatus = stringValue(partyRecord, g('KYB_Verification_Status__c'));
            party.creditStatus = stringValue(partyRecord, g('Credit_Verification_Status__c'));
            applicationsById.get(applicationId).parties.add(party);
        }
    }

    private static void attachRepaymentSchedule(Set<Id> applicationIds, Map<Id, ApplicationSummary> applicationsById) {
        if (applicationIds.isEmpty() ||
            !Customer360NamespaceUtil.hasGenesisObject('Amortization_Schedule__c')) {
            return;
        }

        String scheduleObjectApiName = Customer360NamespaceUtil.qualifyGenesisApiName('Amortization_Schedule__c');
        if (!Customer360NamespaceUtil.isObjectAccessible(scheduleObjectApiName)) {
            return;
        }

        String query = 'SELECT Id, Name, ' +
            g('Application__c') + ', ' +
            g('Payment_Number__c') + ', ' +
            g('Due_Date__c') + ', ' +
            g('Due_Principal__c') + ', ' +
            g('Due_Interest__c') + ', ' +
            g('Fee__c') + ', ' +
            g('Total_Due_Amount__c') + ', ' +
            g('Opening_Principal_Balance__c') + ', ' +
            g('Closing_Principal_Balance__c') + ', ' +
            g('Schedule_Type__c') +
            ' FROM ' + scheduleObjectApiName +
            ' WHERE ' + g('Application__c') + ' IN :applicationIds' +
            ' AND ' + g('Is_Archived__c') + ' = false' +
            ' ORDER BY ' + g('Application__c') + ', ' + g('Payment_Number__c') + ' ASC';

        Map<Id, Integer> scheduleCountsByApplicationId = new Map<Id, Integer>();
        for (SObject scheduleRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'applicationIds' => applicationIds
        }, AccessLevel.USER_MODE)) {
            Id applicationId = (Id) scheduleRecord.get(g('Application__c'));
            Integer currentCount = scheduleCountsByApplicationId.containsKey(applicationId)
                ? scheduleCountsByApplicationId.get(applicationId) : 0;
            if (!applicationsById.containsKey(applicationId) || currentCount >= SCHEDULE_LIMIT_PER_APPLICATION) {
                continue;
            }

            RepaymentScheduleItem item = new RepaymentScheduleItem();
            item.scheduleId = stringValue(scheduleRecord, 'Id');
            item.scheduleName = stringValue(scheduleRecord, 'Name');
            item.paymentNumber = decimalValue(scheduleRecord, g('Payment_Number__c'));
            item.dueDate = dateValue(scheduleRecord, g('Due_Date__c'));
            item.principal = decimalValue(scheduleRecord, g('Due_Principal__c'));
            item.interest = decimalValue(scheduleRecord, g('Due_Interest__c'));
            item.fee = decimalValue(scheduleRecord, g('Fee__c'));
            item.totalDue = decimalValue(scheduleRecord, g('Total_Due_Amount__c'));
            item.openingBalance = decimalValue(scheduleRecord, g('Opening_Principal_Balance__c'));
            item.closingBalance = decimalValue(scheduleRecord, g('Closing_Principal_Balance__c'));
            item.scheduleType = stringValue(scheduleRecord, g('Schedule_Type__c'));
            applicationsById.get(applicationId).repaymentSchedule.add(item);
            scheduleCountsByApplicationId.put(applicationId, currentCount + 1);
        }
    }
    private static String g(String apiName) {
        return Customer360NamespaceUtil.qualifyGenesisApiName(apiName);
    }
    private static String c(String apiName) {
        return apiName.startsWith(CLCOMMON_NAMESPACE) ? apiName : CLCOMMON_NAMESPACE + apiName;
    }
    private static Boolean hasObject(String apiName) {
        return Schema.getGlobalDescribe().containsKey(apiName);
    }
    private static Boolean idsEqual(String leftId, String rightId) {
        if (String.isBlank(leftId) || String.isBlank(rightId)) {
            return false;
        }
        return leftId == rightId ||
            (leftId.length() >= 15 && rightId.length() >= 15 &&
                leftId.substring(0, 15) == rightId.substring(0, 15));
    }
    private static String stringValue(SObject record, String fieldApiName) {
        Object value = record == null ? null : record.get(fieldApiName);
        return value == null ? null : String.valueOf(value);
    }
    private static Decimal decimalValue(SObject record, String fieldApiName) {
        Object value = record == null ? null : record.get(fieldApiName);
        return value == null ? null : (Decimal) value;
    }
    private static Date dateValue(SObject record, String fieldApiName) {
        Object value = record == null ? null : record.get(fieldApiName);
        return value == null ? null : (Date) value;
    }
    private static Boolean booleanValue(SObject record, String fieldApiName) {
        Object value = record == null ? null : record.get(fieldApiName);
        return value == null ? false : (Boolean) value;
    }
    private static Decimal safeDecimal(Decimal value) {
        return value == null ? 0 : value;
    }
    private static Decimal firstDecimal(SObject record, String primaryFieldApiName, String fallbackFieldApiName) {
        Decimal primaryValue = decimalValue(record, primaryFieldApiName);
        return primaryValue != null && primaryValue != 0 ? primaryValue : decimalValue(record, fallbackFieldApiName);
    }
    private static String firstString(SObject record, String primaryFieldApiName, String fallbackFieldApiName) {
        String primaryValue = primaryFieldApiName.contains('.')
            ? null : stringValue(record, primaryFieldApiName);
        if (String.isNotBlank(primaryValue)) {
            return primaryValue;
        }
        if (!fallbackFieldApiName.contains('.')) {
            return stringValue(record, fallbackFieldApiName);
        }

        List<String> relationshipParts = fallbackFieldApiName.split('\\.');
        SObject parentRecord = record.getSObject(relationshipParts[0]);
        return relationshipParts.size() == 2 ? stringValue(parentRecord, relationshipParts[1]) : null;
    }
    public class Application360Data {
        @AuraEnabled public Boolean isAvailable;
        @AuraEnabled public String message;
        @AuraEnabled public Integer totalApplications = 0;
        @AuraEnabled public Integer inProcessApplications = 0;
        @AuraEnabled public Integer approvedApplications = 0;
        @AuraEnabled public Decimal totalRequestedAmount = 0;
        @AuraEnabled public Decimal totalApprovedAmount = 0;
        @AuraEnabled public Decimal totalDirectProposedExposure = 0;
        @AuraEnabled public Decimal totalIndirectProposedExposure = 0;
        @AuraEnabled public Decimal totalProposedExposure = 0;
        @AuraEnabled public List<ApplicationSummary> applications;
    }
    public class ApplicationSummary {
        @AuraEnabled public String applicationId;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String status;
        @AuraEnabled public String stage;
        @AuraEnabled public String productType;
        @AuraEnabled public String productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String applicationType;
        @AuraEnabled public Decimal requestedAmount;
        @AuraEnabled public Decimal approvedAmount;
        @AuraEnabled public Decimal financedAmount;
        @AuraEnabled public Decimal paymentAmount;
        @AuraEnabled public String paymentFrequency;
        @AuraEnabled public Decimal interestRate;
        @AuraEnabled public Decimal apr;
        @AuraEnabled public Decimal term;
        @AuraEnabled public Date maturityDate;
        @AuraEnabled public Date submittedDate;
        @AuraEnabled public Date expectedCloseDate;
        @AuraEnabled public String creditApprovalStatus;
        @AuraEnabled public Date creditApprovalDate;
        @AuraEnabled public String manualApprovalStatus;
        @AuraEnabled public String manualReviewStatus;
        @AuraEnabled public String creditVerificationStatus;
        @AuraEnabled public String kycVerificationStatus;
        @AuraEnabled public String kybVerificationStatus;
        @AuraEnabled public String voiVerificationStatus;
        @AuraEnabled public String voeVerificationStatus;
        @AuraEnabled public Decimal directExposure;
        @AuraEnabled public Decimal indirectExposure;
        @AuraEnabled public Decimal directProposedExposure;
        @AuraEnabled public Decimal indirectProposedExposure;
        @AuraEnabled public List<String> relationshipRoles;
        @AuraEnabled public PricingDetail selectedPricing;
        @AuraEnabled public List<PartyDetail> parties;
        @AuraEnabled public List<RepaymentScheduleItem> repaymentSchedule;
    }
    public class PricingDetail {
        @AuraEnabled public String pricingId;
        @AuraEnabled public String pricingName;
        @AuraEnabled public Boolean selected;
        @AuraEnabled public Decimal paymentAmount;
        @AuraEnabled public String paymentFrequency;
        @AuraEnabled public Decimal interestRate;
        @AuraEnabled public Decimal term;
        @AuraEnabled public Decimal totalInterest;
        @AuraEnabled public Decimal totalPayments;
        @AuraEnabled public String pricingMethod;
        @AuraEnabled public Decimal rateFactor;
        @AuraEnabled public Decimal yieldPercent;
    }
    public class PartyDetail {
        @AuraEnabled public String partyId;
        @AuraEnabled public String partyNumber;
        @AuraEnabled public String partyName;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String partyType;
        @AuraEnabled public Boolean primary;
        @AuraEnabled public Decimal percentOwnership;
        @AuraEnabled public Decimal directExposure;
        @AuraEnabled public Decimal directProposedExposure;
        @AuraEnabled public Decimal indirectExposure;
        @AuraEnabled public Decimal indirectProposedExposure;
        @AuraEnabled public String kycStatus;
        @AuraEnabled public String kybStatus;
        @AuraEnabled public String creditStatus;
    }
    public class RepaymentScheduleItem {
        @AuraEnabled public String scheduleId;
        @AuraEnabled public String scheduleName;
        @AuraEnabled public Decimal paymentNumber;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Decimal principal;
        @AuraEnabled public Decimal interest;
        @AuraEnabled public Decimal fee;
        @AuraEnabled public Decimal totalDue;
        @AuraEnabled public Decimal openingBalance;
        @AuraEnabled public Decimal closingBalance;
        @AuraEnabled public String scheduleType;
    }
}
