/**
 * Builds account-level exposure across Loan Servicing and Genesis Origination.
 */
public with sharing class Customer360ExposureService {
    private static final String LOAN_ACCOUNT_OBJECT = 'Loan_Account__c';
    private static final String COBORROWER_OBJECT = 'Coborrower__c';
    private static final String PARTY_OBJECT = 'clcommon__Party__c';
    private static final String CLCOMMON_NAMESPACE = 'clcommon__';
    private static final String ACTIVE_LOAN_STATUS_PREFIX = 'ACTIVE -';
    private static final String MASTER_FACILITY_PRODUCT_TYPE = 'MASTER FACILITY';
    private static final String CONVERTED_APPLICATION_STATUS = 'APPROVED - CONVERTED TO CONTRACT';
    private static final String SOURCE_LOAN = 'LOAN';
    private static final String SOURCE_GENESIS = 'GENESIS';

    private static final List<String> DIRECT_ROLE_PRECEDENCE = new List<String>{
        'BORROWER',
        'CO-BORROWER',
        'COSIGNER',
        'SIGNER'
    };
    private static final Set<String> TERMINAL_APPLICATION_STATUS_MARKERS = new Set<String>{
        'REJECT',
        'WITHDRAW',
        'CANCEL',
        'DECLIN',
        'EXPIR'
    };

    /**
     * Calculates the exposure shown in Customer 360 for one Account.
     * @param accountId Salesforce Account Id.
     * @return Module availability and current/proposed exposure totals by relationship role.
     * @throws ExposureServiceException when the Account Id is blank.
     */
    public static ExposureSummary getExposureSummary(String accountId) {
        if (String.isBlank(accountId)) {
            throw new ExposureServiceException('Account ID is required');
        }

        ExposureSummary summary = initializeSummary();
        summary.loanModuleAvailable = Customer360NamespaceUtil.hasLoanModule();
        summary.genesisModuleAvailable = Customer360NamespaceUtil.hasGenesisModule();
        summary.showProposedExposure = summary.genesisModuleAvailable;
        summary.currentExposureSource = summary.loanModuleAvailable
            ? SOURCE_LOAN
            : (summary.genesisModuleAvailable ? SOURCE_GENESIS : null);
        summary.proposedExposureSource = summary.genesisModuleAvailable ? SOURCE_GENESIS : null;

        if (summary.loanModuleAvailable) {
            applyLoanExposure(accountId, summary);
        }
        if (summary.genesisModuleAvailable) {
            applyGenesisExposure(accountId, summary, summary.loanModuleAvailable);
        }

        finalizeTotals(summary);
        if (!summary.loanModuleAvailable && !summary.genesisModuleAvailable) {
            summary.message = 'No lending modules are available';
        }
        return summary;
    }

    private static ExposureSummary initializeSummary() {
        ExposureSummary summary = new ExposureSummary();
        summary.loanModuleAvailable = false;
        summary.genesisModuleAvailable = false;
        summary.showProposedExposure = false;
        summary.directExposure = 0;
        summary.directExposureAsBorrower = 0;
        summary.directExposureAsCoBorrower = 0;
        summary.directExposureAsSigner = 0;
        summary.directExposureAsCosigner = 0;
        summary.directProposedExposure = 0;
        summary.directProposedExposureAsBorrower = 0;
        summary.directProposedExposureAsCoBorrower = 0;
        summary.directProposedExposureAsSigner = 0;
        summary.directProposedExposureAsCosigner = 0;
        summary.indirectExposure = 0;
        summary.indirectExposureAsGuarantor = 0;
        summary.indirectProposedExposure = 0;
        summary.indirectProposedExposureAsGuarantor = 0;
        return summary;
    }

    private static void applyLoanExposure(String accountId, ExposureSummary summary) {
        Map<Id, Decimal> balancesByLoanId = new Map<Id, Decimal>();
        Set<Id> borrowerLoanIds = new Set<Id>();

        for (SObject loanRecord : queryBorrowerLoans(accountId)) {
            if (isActiveExposureLoan(loanRecord)) {
                Id loanId = idValue(loanRecord, 'Id');
                borrowerLoanIds.add(loanId);
                balancesByLoanId.put(loanId, decimalValue(loanRecord, l('Principal_Remaining__c')));
            }
        }
        borrowerLoanIds.remove(null);

        Map<String, Set<Id>> linkedLoanIdsByRole = queryLinkedLoanIdsByRole(accountId);
        Set<Id> coBorrowerLoanIds = linkedLoanIdsByRole.get('COBORROWER');
        Set<Id> guarantorLoanIds = linkedLoanIdsByRole.get('GUARANTOR');
        Set<Id> allLinkedLoanIds = new Set<Id>();
        allLinkedLoanIds.addAll(coBorrowerLoanIds);
        allLinkedLoanIds.addAll(guarantorLoanIds);

        for (SObject loanRecord : queryLoansById(allLinkedLoanIds)) {
            if (isActiveExposureLoan(loanRecord)) {
                balancesByLoanId.put(
                    idValue(loanRecord, 'Id'),
                    decimalValue(loanRecord, l('Principal_Remaining__c'))
                );
            }
        }

        coBorrowerLoanIds.retainAll(balancesByLoanId.keySet());
        guarantorLoanIds.retainAll(balancesByLoanId.keySet());
        coBorrowerLoanIds.removeAll(borrowerLoanIds);
        guarantorLoanIds.removeAll(borrowerLoanIds);
        guarantorLoanIds.removeAll(coBorrowerLoanIds);

        summary.directExposureAsBorrower = sumBalances(borrowerLoanIds, balancesByLoanId);
        summary.directExposureAsCoBorrower = sumBalances(coBorrowerLoanIds, balancesByLoanId);
        summary.indirectExposureAsGuarantor = sumBalances(guarantorLoanIds, balancesByLoanId);
    }

    private static List<SObject> queryBorrowerLoans(String accountId) {
        String objectApiName = Customer360NamespaceUtil.getLoanObjectApiName();
        List<String> fields = loanExposureFields();
        if (!isReadableObjectAndFields(objectApiName, fields)) {
            return new List<SObject>();
        }

        String query = 'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + objectApiName +
            ' WHERE ' + l('Account__c') + ' = :accountId';
        return Database.queryWithBinds(query, new Map<String, Object>{
            'accountId' => accountId
        }, AccessLevel.USER_MODE);
    }

    private static Map<String, Set<Id>> queryLinkedLoanIdsByRole(String accountId) {
        Map<String, Set<Id>> loanIdsByRole = new Map<String, Set<Id>>{
            'COBORROWER' => new Set<Id>(),
            'GUARANTOR' => new Set<Id>()
        };
        String objectApiName = l(COBORROWER_OBJECT);
        List<String> fields = new List<String>{ l('Loan__c'), l('Party_Type__c'), l('Account__c') };
        if (!isReadableObjectAndFields(objectApiName, fields)) {
            return loanIdsByRole;
        }

        String query = 'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + objectApiName +
            ' WHERE ' + l('Account__c') + ' = :accountId';
        for (SObject linkRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'accountId' => accountId
        }, AccessLevel.USER_MODE)) {
            String role = normalize(stringValue(linkRecord, l('Party_Type__c')));
            Id loanId = idValue(linkRecord, l('Loan__c'));
            if (loanId != null && loanIdsByRole.containsKey(role)) {
                loanIdsByRole.get(role).add(loanId);
            }
        }
        return loanIdsByRole;
    }

    private static List<SObject> queryLoansById(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) {
            return new List<SObject>();
        }

        String objectApiName = Customer360NamespaceUtil.getLoanObjectApiName();
        List<String> fields = loanExposureFields();
        if (!isReadableObjectAndFields(objectApiName, fields)) {
            return new List<SObject>();
        }

        String query = 'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + objectApiName +
            ' WHERE Id IN :loanIds';
        return Database.queryWithBinds(query, new Map<String, Object>{
            'loanIds' => loanIds
        }, AccessLevel.USER_MODE);
    }

    private static List<String> loanExposureFields() {
        return new List<String>{
            'Id',
            l('Account__c'),
            l('Principal_Remaining__c'),
            l('Loan_Status__c'),
            l('Product_Type__c')
        };
    }

    private static Boolean isActiveExposureLoan(SObject loanRecord) {
        String status = normalize(stringValue(loanRecord, l('Loan_Status__c')));
        String productType = normalize(stringValue(loanRecord, l('Product_Type__c')));
        return status.startsWith(ACTIVE_LOAN_STATUS_PREFIX) &&
            productType != MASTER_FACILITY_PRODUCT_TYPE;
    }

    private static Decimal sumBalances(Set<Id> loanIds, Map<Id, Decimal> balancesByLoanId) {
        Decimal total = 0;
        for (Id loanId : loanIds) {
            total += safeDecimal(balancesByLoanId.get(loanId));
        }
        return total;
    }

    private static void applyGenesisExposure(
        String accountId,
        ExposureSummary summary,
        Boolean loanIsAuthoritativeForCurrentExposure
    ) {
        Map<Id, Set<String>> rolesByApplicationId = queryGenesisRoles(accountId);
        for (SObject applicationRecord : queryGenesisApplications(accountId, rolesByApplicationId.keySet())) {
            Id applicationId = idValue(applicationRecord, 'Id');
            Set<String> roles = rolesByApplicationId.containsKey(applicationId)
                ? rolesByApplicationId.get(applicationId)
                : new Set<String>();
            if (idsEqual(applicationRecord.get(g('Account__c')), accountId)) {
                roles.add('BORROWER');
            }

            String status = normalize(stringValue(applicationRecord, g('Status__c')));
            if (isTerminalApplicationStatus(status)) {
                continue;
            }

            Decimal requestedAmount = decimalValue(applicationRecord, g('Requested_Loan_Amount__c'));
            String directRole = getDirectRole(roles);
            Boolean isGuarantor = roles.contains('GUARANTOR');
            if (status == CONVERTED_APPLICATION_STATUS) {
                if (!loanIsAuthoritativeForCurrentExposure) {
                    addGenesisExposure(summary, directRole, isGuarantor, requestedAmount, false);
                }
            } else {
                addGenesisExposure(summary, directRole, isGuarantor, requestedAmount, true);
            }
        }
    }

    private static Map<Id, Set<String>> queryGenesisRoles(String accountId) {
        Map<Id, Set<String>> rolesByApplicationId = new Map<Id, Set<String>>();
        List<String> fields = new List<String>{
            g('Application__c'),
            c('Account__c'),
            c('Party_Types__c'),
            c('Party_Type__c')
        };
        if (!isReadableObjectAndFields(PARTY_OBJECT, fields)) {
            return rolesByApplicationId;
        }

        String query = 'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + PARTY_OBJECT +
            ' WHERE ' + c('Account__c') + ' = :accountId' +
            ' AND ' + g('Application__c') + ' != null';
        for (SObject partyRecord : Database.queryWithBinds(query, new Map<String, Object>{
            'accountId' => accountId
        }, AccessLevel.USER_MODE)) {
            Id applicationId = idValue(partyRecord, g('Application__c'));
            if (applicationId == null) {
                continue;
            }
            if (!rolesByApplicationId.containsKey(applicationId)) {
                rolesByApplicationId.put(applicationId, new Set<String>());
            }
            addRoles(rolesByApplicationId.get(applicationId), stringValue(partyRecord, c('Party_Types__c')));
            addRoles(rolesByApplicationId.get(applicationId), stringValue(partyRecord, c('Party_Type__c')));
        }
        return rolesByApplicationId;
    }

    private static List<SObject> queryGenesisApplications(String accountId, Set<Id> partyApplicationIds) {
        String objectApiName = Customer360NamespaceUtil.getGenesisApplicationObjectApiName();
        List<String> fields = new List<String>{
            'Id',
            g('Account__c'),
            g('Status__c'),
            g('Requested_Loan_Amount__c')
        };
        if (!isReadableObjectAndFields(objectApiName, fields)) {
            return new List<SObject>();
        }

        String whereClause = g('Account__c') + ' = :accountId';
        Map<String, Object> bindVariables = new Map<String, Object>{ 'accountId' => accountId };
        if (partyApplicationIds != null && !partyApplicationIds.isEmpty()) {
            whereClause = '(' + whereClause + ' OR Id IN :partyApplicationIds)';
            bindVariables.put('partyApplicationIds', partyApplicationIds);
        }

        String query = 'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + objectApiName +
            ' WHERE ' + whereClause;
        return Database.queryWithBinds(query, bindVariables, AccessLevel.USER_MODE);
    }

    private static void addRoles(Set<String> roles, String rawRoles) {
        if (String.isBlank(rawRoles)) {
            return;
        }
        for (String role : rawRoles.split(';')) {
            String normalizedRole = normalize(role);
            if (String.isNotBlank(normalizedRole)) {
                roles.add(normalizedRole);
            }
        }
    }

    private static String getDirectRole(Set<String> roles) {
        for (String role : DIRECT_ROLE_PRECEDENCE) {
            if (roles.contains(role)) {
                return role;
            }
        }
        return null;
    }

    private static Boolean isTerminalApplicationStatus(String status) {
        for (String marker : TERMINAL_APPLICATION_STATUS_MARKERS) {
            if (status.contains(marker)) {
                return true;
            }
        }
        return false;
    }

    private static void addGenesisExposure(
        ExposureSummary summary,
        String directRole,
        Boolean isGuarantor,
        Decimal amount,
        Boolean proposed
    ) {
        Decimal exposureAmount = safeDecimal(amount);
        if (String.isNotBlank(directRole)) {
            addDirectExposureByRole(summary, directRole, exposureAmount, proposed);
        } else if (isGuarantor) {
            if (proposed) {
                summary.indirectProposedExposureAsGuarantor += exposureAmount;
            } else {
                summary.indirectExposureAsGuarantor += exposureAmount;
            }
        }
    }

    private static void addDirectExposureByRole(
        ExposureSummary summary,
        String role,
        Decimal amount,
        Boolean proposed
    ) {
        if (proposed) {
            if (role == 'BORROWER') {
                summary.directProposedExposureAsBorrower += amount;
            } else if (role == 'CO-BORROWER') {
                summary.directProposedExposureAsCoBorrower += amount;
            } else if (role == 'SIGNER') {
                summary.directProposedExposureAsSigner += amount;
            } else if (role == 'COSIGNER') {
                summary.directProposedExposureAsCosigner += amount;
            }
            return;
        }

        if (role == 'BORROWER') {
            summary.directExposureAsBorrower += amount;
        } else if (role == 'CO-BORROWER') {
            summary.directExposureAsCoBorrower += amount;
        } else if (role == 'SIGNER') {
            summary.directExposureAsSigner += amount;
        } else if (role == 'COSIGNER') {
            summary.directExposureAsCosigner += amount;
        }
    }

    private static void finalizeTotals(ExposureSummary summary) {
        summary.directExposure = scaleCurrency(
            summary.directExposureAsBorrower +
            summary.directExposureAsCoBorrower +
            summary.directExposureAsSigner +
            summary.directExposureAsCosigner
        );
        summary.directProposedExposure = scaleCurrency(
            summary.directProposedExposureAsBorrower +
            summary.directProposedExposureAsCoBorrower +
            summary.directProposedExposureAsSigner +
            summary.directProposedExposureAsCosigner
        );
        summary.indirectExposure = scaleCurrency(summary.indirectExposureAsGuarantor);
        summary.indirectProposedExposure = scaleCurrency(summary.indirectProposedExposureAsGuarantor);

        summary.directExposureAsBorrower = scaleCurrency(summary.directExposureAsBorrower);
        summary.directExposureAsCoBorrower = scaleCurrency(summary.directExposureAsCoBorrower);
        summary.directExposureAsSigner = scaleCurrency(summary.directExposureAsSigner);
        summary.directExposureAsCosigner = scaleCurrency(summary.directExposureAsCosigner);
        summary.directProposedExposureAsBorrower = scaleCurrency(summary.directProposedExposureAsBorrower);
        summary.directProposedExposureAsCoBorrower = scaleCurrency(summary.directProposedExposureAsCoBorrower);
        summary.directProposedExposureAsSigner = scaleCurrency(summary.directProposedExposureAsSigner);
        summary.directProposedExposureAsCosigner = scaleCurrency(summary.directProposedExposureAsCosigner);
        summary.indirectExposureAsGuarantor = scaleCurrency(summary.indirectExposureAsGuarantor);
        summary.indirectProposedExposureAsGuarantor = scaleCurrency(summary.indirectProposedExposureAsGuarantor);
    }

    private static Boolean isReadableObjectAndFields(String objectApiName, List<String> fieldApiNames) {
        if (String.isBlank(objectApiName)) {
            return false;
        }
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            return false;
        }

        Map<String, Schema.SObjectField> fieldsByApiName = objectType.getDescribe().fields.getMap();
        for (String fieldApiName : fieldApiNames) {
            Schema.SObjectField fieldToken = fieldsByApiName.get(fieldApiName);
            if (fieldToken == null || !fieldToken.getDescribe().isAccessible()) {
                return false;
            }
        }
        return true;
    }

    private static Boolean idsEqual(Object leftId, String rightId) {
        if (leftId == null || String.isBlank(rightId)) {
            return false;
        }
        String leftValue = String.valueOf(leftId);
        return leftValue == rightId ||
            (leftValue.length() >= 15 && rightId.length() >= 15 &&
                leftValue.substring(0, 15) == rightId.substring(0, 15));
    }

    private static String l(String apiName) {
        return Customer360NamespaceUtil.qualifyLoanApiName(apiName);
    }

    private static String g(String apiName) {
        return Customer360NamespaceUtil.qualifyGenesisApiName(apiName);
    }

    private static String c(String apiName) {
        return apiName.startsWith(CLCOMMON_NAMESPACE) ? apiName : CLCOMMON_NAMESPACE + apiName;
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toUpperCase();
    }

    private static Id idValue(SObject record, String fieldApiName) {
        Object value = record == null ? null : record.get(fieldApiName);
        return value == null ? null : (Id) value;
    }

    private static String stringValue(SObject record, String fieldApiName) {
        Object value = record == null ? null : record.get(fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalValue(SObject record, String fieldApiName) {
        Object value = record == null ? null : record.get(fieldApiName);
        return value == null ? 0 : (Decimal) value;
    }

    private static Decimal safeDecimal(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Decimal scaleCurrency(Decimal value) {
        return safeDecimal(value).setScale(2);
    }

    /**
     * Serializable account exposure read model for Lightning consumers.
     */
    public class ExposureSummary {
        @AuraEnabled public Boolean loanModuleAvailable;
        @AuraEnabled public Boolean genesisModuleAvailable;
        @AuraEnabled public Boolean showProposedExposure;
        @AuraEnabled public String currentExposureSource;
        @AuraEnabled public String proposedExposureSource;
        @AuraEnabled public String message;
        @AuraEnabled public Decimal directExposure;
        @AuraEnabled public Decimal directExposureAsBorrower;
        @AuraEnabled public Decimal directExposureAsCoBorrower;
        @AuraEnabled public Decimal directExposureAsSigner;
        @AuraEnabled public Decimal directExposureAsCosigner;
        @AuraEnabled public Decimal directProposedExposure;
        @AuraEnabled public Decimal directProposedExposureAsBorrower;
        @AuraEnabled public Decimal directProposedExposureAsCoBorrower;
        @AuraEnabled public Decimal directProposedExposureAsSigner;
        @AuraEnabled public Decimal directProposedExposureAsCosigner;
        @AuraEnabled public Decimal indirectExposure;
        @AuraEnabled public Decimal indirectExposureAsGuarantor;
        @AuraEnabled public Decimal indirectProposedExposure;
        @AuraEnabled public Decimal indirectProposedExposureAsGuarantor;
    }

    /**
     * Raised when exposure input cannot be processed.
     */
    public class ExposureServiceException extends Exception {
    }
}