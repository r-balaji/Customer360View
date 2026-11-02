/**
 * Resolves managed package namespaces from installed object API names.
 */
public with sharing class Customer360NamespaceUtil {
    private static final String LOAN_ACCOUNT_OBJECT_API_NAME = 'Loan_Account__c';
    private static final String GENESIS_APPLICATIONS_OBJECT_API_NAME = 'Applications__c';
    private static final String LEGACY_GENESIS_APPLICATION_OBJECT_API_NAME = 'Application__c';
    private static final String NAMESPACE_SEPARATOR = '__';
    private static final String APEX_NAMESPACE_SEPARATOR = '.';
    private static final String LOAN_PREFERRED_NAMESPACE_FOR_QUERY = 'loan__';
    private static final String GENESIS_PREFERRED_NAMESPACE_FOR_QUERY = 'genesis__';
    private static final List<String> LOAN_REQUIRED_FIELD_API_NAMES = new List<String>{
        'Account__c',
        'Loan_Amount__c',
        'Principal_Remaining__c',
        'Loan_Status__c'
    };
    private static final List<String> GENESIS_REQUIRED_FIELD_API_NAMES = new List<String>{
        'Account__c',
        'Requested_Loan_Amount__c',
        'Status__c'
    };

    private static String loanObjectApiNameCache;
    private static String genesisApplicationObjectApiNameCache;
    private static String loanNamespaceForQueryCache;
    private static String genesisNamespaceForQueryCache;

    /**
     * Checks whether Loan Servicing objects are installed.
     * @return True when Loan Account is present in describe metadata.
     */
    public static Boolean hasLoanModule() {
        return String.isNotBlank(getLoanObjectApiName());
    }

    /**
     * Checks whether Genesis Originate application objects are installed.
     * @return True when a Genesis application object is present in describe metadata.
     */
    public static Boolean hasGenesisModule() {
        return String.isNotBlank(getGenesisApplicationObjectApiName());
    }

    /**
     * Gets the installed Loan Account object API name.
     * @return Namespaced, unmanaged, or blank Loan Account object API name.
     */
    public static String getLoanObjectApiName() {
        if (loanObjectApiNameCache == null) {
            loanObjectApiNameCache = findInstalledObjectApiName(
                new List<String>{ LOAN_ACCOUNT_OBJECT_API_NAME },
                LOAN_PREFERRED_NAMESPACE_FOR_QUERY,
                LOAN_REQUIRED_FIELD_API_NAMES
            );
        }
        return loanObjectApiNameCache;
    }

    /**
     * Gets the installed Genesis application object API name.
     * @return Namespaced, unmanaged, or blank Genesis application object API name.
     */
    public static String getGenesisApplicationObjectApiName() {
        if (genesisApplicationObjectApiNameCache == null) {
            genesisApplicationObjectApiNameCache = findInstalledObjectApiName(
                new List<String>{
                    GENESIS_APPLICATIONS_OBJECT_API_NAME,
                    LEGACY_GENESIS_APPLICATION_OBJECT_API_NAME
                },
                GENESIS_PREFERRED_NAMESPACE_FOR_QUERY,
                GENESIS_REQUIRED_FIELD_API_NAMES
            );
        }
        return genesisApplicationObjectApiNameCache;
    }

    /**
     * Gets the Loan namespace for dynamic SOQL.
     * @return Namespace with trailing "__", or blank for unmanaged/unavailable Loan objects.
     */
    public static String getLoanNamespaceForQuery() {
        if (loanNamespaceForQueryCache == null) {
            loanNamespaceForQueryCache = extractNamespaceForQuery(
                getLoanObjectApiName(),
                LOAN_ACCOUNT_OBJECT_API_NAME
            );
        }
        return loanNamespaceForQueryCache;
    }

    /**
     * Gets the Genesis namespace for dynamic SOQL.
     * @return Namespace with trailing "__", or blank for unmanaged/unavailable Genesis objects.
     */
    public static String getGenesisNamespaceForQuery() {
        if (genesisNamespaceForQueryCache == null) {
            String objectApiName = getGenesisApplicationObjectApiName();
            genesisNamespaceForQueryCache = extractNamespaceForQuery(
                objectApiName,
                getGenesisBaseApiName(objectApiName)
            );
        }
        return genesisNamespaceForQueryCache;
    }

    /**
     * Gets the Loan namespace qualifier for Apex class names.
     * @return Namespace with trailing ".", or blank for unmanaged/unavailable Loan classes.
     */
    public static String getLoanApexClassQualifier() {
        return getApexClassQualifier(getLoanNamespaceForQuery());
    }

    /**
     * Gets the Genesis namespace qualifier for Apex class names.
     * @return Namespace with trailing ".", or blank for unmanaged/unavailable Genesis classes.
     */
    public static String getGenesisApexClassQualifier() {
        return getApexClassQualifier(getGenesisNamespaceForQuery());
    }

    /**
     * Qualifies a custom API name with the detected Loan namespace when needed.
     * @param apiName Unqualified or already-qualified API name.
     * @return API name qualified for the installed Loan module.
     */
    public static String qualifyLoanApiName(String apiName) {
        return qualifyApiName(apiName, getLoanNamespaceForQuery());
    }

    /**
     * Qualifies a custom API name with the detected Genesis namespace when needed.
     * @param apiName Unqualified or already-qualified API name.
     * @return API name qualified for the installed Genesis module.
     */
    public static String qualifyGenesisApiName(String apiName) {
        return qualifyApiName(apiName, getGenesisNamespaceForQuery());
    }

    /**
     * Checks whether a Loan module object is available in this org.
     * @param apiName Unqualified or already-qualified object API name.
     * @return True when the object exists in describe metadata.
     */
    public static Boolean hasLoanObject(String apiName) {
        return hasObject(qualifyLoanApiName(apiName));
    }

    /**
     * Checks whether a Genesis module object is available in this org.
     * @param apiName Unqualified or already-qualified object API name.
     * @return True when the object exists in describe metadata.
     */
    public static Boolean hasGenesisObject(String apiName) {
        return hasObject(qualifyGenesisApiName(apiName));
    }

    /**
     * Checks object-level read access through describe metadata.
     * @param apiName Installed object API name.
     * @return True when the object exists and is readable by the running user.
     */
    public static Boolean isObjectAccessible(String apiName) {
        if (String.isBlank(apiName)) {
            return false;
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(apiName);
        return objectType != null && objectType.getDescribe().isAccessible();
    }

    private static String findInstalledObjectApiName(List<String> baseApiNames) {
        return findInstalledObjectApiName(baseApiNames, '', new List<String>());
    }

    private static String findInstalledObjectApiName(
        List<String> baseApiNames,
        String preferredNamespaceForQuery,
        List<String> requiredFieldApiNames
    ) {
        Map<String, Schema.SObjectType> objectTypesByApiName = Schema.getGlobalDescribe();
        String directApiName = findDirectObjectApiName(
            objectTypesByApiName,
            baseApiNames,
            requiredFieldApiNames
        );
        if (String.isNotBlank(directApiName)) {
            return directApiName;
        }

        String preferredApiName = findPreferredObjectApiName(
            objectTypesByApiName,
            baseApiNames,
            preferredNamespaceForQuery,
            requiredFieldApiNames
        );
        if (String.isNotBlank(preferredApiName)) {
            return preferredApiName;
        }

        return findNamespacedObjectApiName(objectTypesByApiName, baseApiNames, requiredFieldApiNames);
    }

    private static String findDirectObjectApiName(
        Map<String, Schema.SObjectType> objectTypesByApiName,
        List<String> baseApiNames,
        List<String> requiredFieldApiNames
    ) {
        for (String baseApiName : baseApiNames) {
            if (isUsableObject(objectTypesByApiName, baseApiName, baseApiName, requiredFieldApiNames)) {
                return baseApiName;
            }
        }
        return '';
    }

    private static String findPreferredObjectApiName(
        Map<String, Schema.SObjectType> objectTypesByApiName,
        List<String> baseApiNames,
        String preferredNamespaceForQuery,
        List<String> requiredFieldApiNames
    ) {
        if (String.isBlank(preferredNamespaceForQuery)) {
            return '';
        }
        for (String baseApiName : baseApiNames) {
            String preferredApiName = preferredNamespaceForQuery + baseApiName;
            if (isUsableObject(objectTypesByApiName, preferredApiName, baseApiName, requiredFieldApiNames)) {
                return preferredApiName;
            }
        }
        return '';
    }

    private static String findNamespacedObjectApiName(
        Map<String, Schema.SObjectType> objectTypesByApiName,
        List<String> baseApiNames,
        List<String> requiredFieldApiNames
    ) {
        for (String baseApiName : baseApiNames) {
            List<String> matchingApiNames = getMatchingNamespacedApiNames(
                objectTypesByApiName,
                baseApiName,
                requiredFieldApiNames
            );
            if (!matchingApiNames.isEmpty()) {
                return matchingApiNames[0];
            }
        }
        return '';
    }

    private static List<String> getMatchingNamespacedApiNames(
        Map<String, Schema.SObjectType> objectTypesByApiName,
        String baseApiName,
        List<String> requiredFieldApiNames
    ) {
        List<String> matchingApiNames = new List<String>();
        String lowerNamespacedSuffix = (NAMESPACE_SEPARATOR + baseApiName).toLowerCase();

        for (String objectApiName : objectTypesByApiName.keySet()) {
            if (objectApiName != null && objectApiName.toLowerCase().endsWith(lowerNamespacedSuffix)) {
                String namespaceForQuery = objectApiName.substring(0, objectApiName.length() - baseApiName.length());
                String installedApiName = namespaceForQuery + baseApiName;
                if (hasRequiredFields(installedApiName, baseApiName, requiredFieldApiNames)) {
                    matchingApiNames.add(installedApiName);
                }
            }
        }

        matchingApiNames.sort();
        return matchingApiNames;
    }

    private static Boolean isUsableObject(
        Map<String, Schema.SObjectType> objectTypesByApiName,
        String objectApiName,
        String baseApiName,
        List<String> requiredFieldApiNames
    ) {
        return objectTypesByApiName.containsKey(objectApiName) &&
            hasRequiredFields(objectApiName, baseApiName, requiredFieldApiNames);
    }

    private static Boolean hasRequiredFields(
        String objectApiName,
        String baseApiName,
        List<String> requiredFieldApiNames
    ) {
        if (requiredFieldApiNames == null || requiredFieldApiNames.isEmpty()) {
            return true;
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return false;
        }

        Map<String, Schema.SObjectField> fieldsByApiName = objectType.getDescribe().fields.getMap();
        String namespaceForQuery = extractNamespaceForQuery(objectApiName, baseApiName);
        for (String fieldApiName : requiredFieldApiNames) {
            if (!hasField(fieldsByApiName, fieldApiName, namespaceForQuery)) {
                return false;
            }
        }
        return true;
    }

    private static Boolean hasField(
        Map<String, Schema.SObjectField> fieldsByApiName,
        String fieldApiName,
        String namespaceForQuery
    ) {
        return fieldsByApiName.containsKey(fieldApiName) ||
            (String.isNotBlank(namespaceForQuery) &&
                !fieldApiName.startsWith(namespaceForQuery) &&
                fieldsByApiName.containsKey(namespaceForQuery + fieldApiName));
    }

    private static String extractNamespaceForQuery(String objectApiName, String baseApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(baseApiName) || objectApiName == baseApiName) {
            return '';
        }

        String namespacedSuffix = NAMESPACE_SEPARATOR + baseApiName;
        return objectApiName.endsWith(namespacedSuffix)
            ? objectApiName.substring(0, objectApiName.length() - baseApiName.length())
            : '';
    }

    private static String getGenesisBaseApiName(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return GENESIS_APPLICATIONS_OBJECT_API_NAME;
        }
        if (objectApiName == LEGACY_GENESIS_APPLICATION_OBJECT_API_NAME ||
            objectApiName.endsWith(NAMESPACE_SEPARATOR + LEGACY_GENESIS_APPLICATION_OBJECT_API_NAME)) {
            return LEGACY_GENESIS_APPLICATION_OBJECT_API_NAME;
        }
        return GENESIS_APPLICATIONS_OBJECT_API_NAME;
    }

    private static String getApexClassQualifier(String namespaceForQuery) {
        if (String.isBlank(namespaceForQuery)) {
            return '';
        }

        String apexNamespace = namespaceForQuery.endsWith(NAMESPACE_SEPARATOR)
            ? namespaceForQuery.substring(0, namespaceForQuery.length() - NAMESPACE_SEPARATOR.length())
            : namespaceForQuery;
        return String.isBlank(apexNamespace) ? '' : apexNamespace + APEX_NAMESPACE_SEPARATOR;
    }

    private static String qualifyApiName(String apiName, String namespaceForQuery) {
        if (String.isBlank(apiName) ||
            String.isBlank(namespaceForQuery) ||
            (!apiName.endsWith('__c') && !apiName.endsWith('__r')) ||
            apiName.startsWith(namespaceForQuery) ||
            apiName.split(NAMESPACE_SEPARATOR).size() > 2) {
            return apiName;
        }

        return namespaceForQuery + apiName;
    }

    private static Boolean hasObject(String apiName) {
        return String.isNotBlank(apiName) && Schema.getGlobalDescribe().containsKey(apiName);
    }
}