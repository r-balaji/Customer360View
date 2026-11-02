@IsTest
public class Customer360TestDataFactory {
    private static final String CLCOMMON_NAMESPACE = 'clcommon__';
    private static Integer sequence = 0;

    /**
     * Managed package fixtures are best-effort: records that an org's configuration rejects are
     * skipped so the tests still run. The reasons are collected here for diagnosis.
     */
    public static List<String> insertErrors = new List<String>();

    public static Account createAccount(Boolean doInsert) {
        return createAccount('Customer 360 Test Account', doInsert);
    }

    public static Account createAccount(String namePrefix, Boolean doInsert) {
        sequence++;
        Account accountRecord = new Account(
            Name = namePrefix + ' ' + sequence,
            AccountNumber = 'C360-' + String.valueOf(sequence).leftPad(6, '0'),
            Phone = '415555' + String.valueOf(sequence).leftPad(4, '0'),
            BillingStreet = sequence + ' Market Street',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'USA'
        );

        if (doInsert) {
            insertAccountsWithDuplicateBypass(new List<Account>{ accountRecord });
        }
        return accountRecord;
    }

    public static List<Account> createAccounts(String namePrefix, Integer count, Boolean doInsert) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(createAccount(namePrefix, false));
        }

        if (doInsert) {
            insertAccountsWithDuplicateBypass(accounts);
        }
        return accounts;
    }

    public static Contact createContact(Account accountRecord, Boolean doInsert) {
        sequence++;
        Contact contactRecord = new Contact(
            FirstName = 'Customer360',
            LastName = 'Contact ' + sequence,
            Email = 'customer360.contact' + sequence + '@example.com',
            AccountId = accountRecord.Id
        );

        if (doInsert) {
            insert contactRecord;
        }
        return contactRecord;
    }

    public static SObject createLoanAccount(Account accountRecord, Boolean doInsert) {
        return createLoanAccount(accountRecord, null, doInsert);
    }

    public static SObject createLoanAccount(Account accountRecord, Id loanClientId, Boolean doInsert) {
        if (!Customer360NamespaceUtil.hasLoanModule()) {
            return null;
        }

        SObject loanAccount = newLoanSObject('Loan_Account__c');
        if (loanAccount == null) {
            return null;
        }

        putIfField(loanAccount, 'Client__c', loanClientId);
        putIfField(loanAccount, 'Account__c', accountRecord.Id);
        putIfField(loanAccount, 'Due_Day__c', 15);
        putIfField(loanAccount, 'Loan_Status__c', 'Active - Good Standing');
        putIfField(loanAccount, 'Product_Type__c', 'Loan');
        putIfField(loanAccount, 'Loan_Amount__c', 10000);
        putIfField(loanAccount, 'Principal_Remaining__c', 7000);
        putIfField(loanAccount, 'Delinquent_Amount__c', 250);
        putIfField(loanAccount, 'Payment_Amount__c', 500);
        putIfField(loanAccount, 'Interest_Rate__c', 9.5);
        putIfField(loanAccount, 'Number_of_Installments__c', 12);
        putIfField(loanAccount, 'Loan_Effective_Date__c', Date.today().addMonths(-2));
        putIfField(loanAccount, 'Disbursal_Date__c', Date.today().addMonths(-2));
        putIfField(loanAccount, 'Maturity_Date_Current__c', Date.today().addMonths(10));
        putIfField(loanAccount, 'Next_Due_Generation_Date__c', Date.today().addDays(15));
        putIfField(loanAccount, 'Disbursal_Amount__c', 10000);
        putIfField(loanAccount, 'Disbursed_Amount__c', 10000);
        putIfField(loanAccount, 'Total_Amount_Disbursed__c', 10000);
        putIfField(loanAccount, 'Funding_in_Tranches__c', false);
        putIfField(loanAccount, 'Revolving__c', false);

        if (doInsert && !tryInsert(loanAccount)) {
            return null;
        }
        return loanAccount;
    }

    public static SObject createDueDetail(SObject loanAccount, Date dueDate, Boolean paymentSatisfied, Boolean doInsert) {
        if (loanAccount == null) {
            return null;
        }

        SObject dueDetail = newLoanSObject('Loan_Account_Due_Details__c');
        if (dueDetail == null) {
            dueDetail = newLoanSObject('Loan_account_Due_Details__c');
        }
        if (dueDetail == null) {
            return null;
        }

        putIfField(dueDetail, 'Loan_Account__c', loanAccount.Id);
        putIfField(dueDetail, 'Due_Date__c', dueDate);
        putIfField(dueDetail, 'Due_Amt__c', 500);
        putIfField(dueDetail, 'DD_Primary_Flag__c', true);
        putIfField(dueDetail, 'Payment_Satisfied__c', paymentSatisfied);
        putIfField(dueDetail, 'Principal_Billed__c', 400);
        putIfField(dueDetail, 'Interest_Billed__c', 75);
        putIfField(dueDetail, 'Fees_Billed__c', 25);
        putIfField(dueDetail, 'Interest_Due__c', paymentSatisfied ? 0 : 75);
        putIfField(dueDetail, 'Fees_Due__c', paymentSatisfied ? 0 : 25);
        putIfField(dueDetail, 'Principal_Paid__c', paymentSatisfied ? 400 : 100);
        putIfField(dueDetail, 'Interest_Paid__c', paymentSatisfied ? 75 : 0);
        putIfField(dueDetail, 'Fees_Paid__c', paymentSatisfied ? 25 : 0);

        if (doInsert && !tryInsert(dueDetail)) {
            return null;
        }
        return dueDetail;
    }

    public static Customer360Fixture createFullFixture() {
        disableLoanModuleTriggers();
        Account accountRecord = createAccount(true);
        Contact contactRecord = createContact(accountRecord, true);
        SObject loanClient = createLoanClient(accountRecord, contactRecord, true);
        SObject loanAccount = createLoanAccount(
            accountRecord,
            loanClient == null ? null : loanClient.Id,
            true
        );
        createDueDetail(loanAccount, Date.today().addDays(-10), false, true);
        return new Customer360Fixture(accountRecord, contactRecord, loanAccount);
    }

    /**
     * Turns off the managed Loan Servicing triggers for the current test transaction.
     * The package triggers resolve a root branch from org configuration that test
     * contexts cannot see, so Loan Account inserts fail without this.
     */
    public static void disableLoanModuleTriggers() {
        Schema.SObjectType settingType = getSObjectType(
            Customer360NamespaceUtil.qualifyLoanApiName('Trigger_Parameters__c')
        );
        if (settingType == null) {
            return;
        }

        SObject setting = settingType.newSObject();
        Map<String, Schema.SObjectField> fieldsByApiName = settingType.getDescribe().fields.getMap();
        if (fieldsByApiName.containsKey('SetupOwnerId')) {
            setting.put('SetupOwnerId', UserInfo.getOrganizationId());
        } else {
            setting.put('Name', 'Customer360Test');
        }
        for (Schema.SObjectField field : fieldsByApiName.values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.getType() == Schema.DisplayType.BOOLEAN && fieldDescribe.isCreateable()) {
                setting.put(fieldDescribe.getName(), true);
            }
        }
        tryInsert(setting);
    }

    /**
     * Creates the Loan Servicing client record required by the Loan Account validation rules.
     */
    public static SObject createLoanClient(Account accountRecord, Contact contactRecord, Boolean doInsert) {
        SObject loanClient = newLoanSObject('Client__c');
        if (loanClient == null) {
            return null;
        }

        sequence++;
        putIfWritable(loanClient, 'Name', 'Customer 360 Client ' + sequence);
        putIfField(loanClient, 'Account__c', accountRecord == null ? null : accountRecord.Id);
        putIfField(loanClient, 'Contact__c', contactRecord == null ? null : contactRecord.Id);
        // Loan Servicing validates that client names contain letters only.
        putIfField(loanClient, 'First_Name__c', 'Customer');
        putIfField(loanClient, 'Last_Name__c', 'ThreeSixty');
        putIfField(loanClient, 'Address_1__c', sequence + ' Market Street');
        putIfField(loanClient, 'City__c', 'San Francisco');
        putIfField(loanClient, 'Date_of_Birth__c', Date.newInstance(1980, 1, 1));

        if (doInsert && !tryInsert(loanClient)) {
            return null;
        }
        return loanClient;
    }

    /**
     * Creates a Loan Account variant used to exercise the summary metric branches.
     */
    public static SObject createLoanAccountVariant(
        Account accountRecord,
        Id loanClientId,
        String productType,
        String loanStatus,
        Boolean fundingInTranches,
        Boolean doInsert
    ) {
        SObject loanAccount = createLoanAccount(accountRecord, loanClientId, false);
        if (loanAccount == null) {
            return null;
        }

        putIfField(loanAccount, 'Product_Type__c', productType);
        putIfField(loanAccount, 'Loan_Status__c', loanStatus);
        putIfField(loanAccount, 'Funding_in_Tranches__c', fundingInTranches);
        if (fundingInTranches == true) {
            putIfWritable(loanAccount, l('Draw_Period_End_Date__c'), Date.today().addYears(5));
        }

        if (doInsert && !tryInsert(loanAccount)) {
            return null;
        }
        return loanAccount;
    }

    public static SObject createRepaymentSchedule(
        SObject loanAccount,
        Date dueDate,
        Boolean isPaid,
        Boolean pastDue,
        Boolean doInsert
    ) {
        if (loanAccount == null || loanAccount.Id == null) {
            return null;
        }

        SObject schedule = newLoanSObject('Repayment_Schedule__c');
        if (schedule == null) {
            return null;
        }

        putIfWritable(schedule, l('Loan_Account__c'), loanAccount.Id);
        putIfWritable(schedule, l('Due_Date__c'), dueDate);
        putIfWritable(schedule, l('Due_Principal__c'), 400);
        putIfWritable(schedule, l('Due_Interest__c'), 75);
        putIfWritable(schedule, l('Total_Due_Fees__c'), 25);
        putIfWritable(schedule, l('Total_Installment__c'), 500);
        putIfWritable(schedule, l('Transaction_Amount__c'), 500);
        putIfWritable(schedule, l('isPaid__c'), isPaid);
        putIfWritable(schedule, l('Is_Archived__c'), false);
        putIfWritable(schedule, l('Past_Due_Date__c'), pastDue);
        if (isPaid == true) {
            putIfWritable(schedule, l('Date_Paid__c'), Date.today().addDays(-1));
            putIfWritable(schedule, l('Paid_Total__c'), 500);
        }

        if (doInsert && !tryInsert(schedule)) {
            return null;
        }
        return schedule;
    }

    /**
     * Creates a payment transaction. The managed package rejects transaction dates after the
     * configured company system date, which test contexts cannot read, so progressively older
     * dates are attempted until one is accepted.
     */
    public static SObject createPaymentTransaction(SObject loanAccount, Boolean doInsert) {
        if (loanAccount == null || loanAccount.Id == null) {
            return null;
        }

        for (Date transactionDate : new List<Date>{
            Date.today().addDays(-5),
            Date.newInstance(2000, 1, 1),
            Date.newInstance(1970, 1, 2)
        }) {
            SObject transactionRecord = newLoanSObject('Loan_Payment_Transaction__c');
            if (transactionRecord == null) {
                return null;
            }

            putIfWritable(transactionRecord, l('Loan_Account__c'), loanAccount.Id);
            putIfWritable(transactionRecord, l('Transaction_Date__c'), transactionDate);
            putIfWritable(transactionRecord, l('Transaction_Amount__c'), 500);
            putIfWritable(transactionRecord, l('Principal__c'), 400);
            putIfWritable(transactionRecord, l('Interest__c'), 75);
            putIfWritable(transactionRecord, l('Fees__c'), 25);
            putIfWritable(transactionRecord, l('Cleared__c'), true);
            putIfWritable(transactionRecord, l('Reversed__c'), false);
            putIfWritable(transactionRecord, l('Cheque_Number__c'), '10001');

            if (!doInsert || tryInsert(transactionRecord)) {
                return transactionRecord;
            }
        }
        return null;
    }

    public static SObject createCharge(SObject loanAccount, Boolean doInsert) {
        if (loanAccount == null || loanAccount.Id == null) {
            return null;
        }

        SObject charge = newLoanSObject('Charge__c');
        if (charge == null) {
            return null;
        }

        putIfWritable(charge, l('Loan_Account__c'), loanAccount.Id);
        putIfWritable(charge, l('Date__c'), Date.today().addDays(-3));
        putIfWritable(charge, l('Original_Amount__c'), 50);
        putIfWritable(charge, l('Paid__c'), false);
        putIfWritable(charge, l('Waive__c'), false);
        putIfWritable(charge, l('Reference__c'), 'Customer 360 test charge');

        if (doInsert && !tryInsert(charge)) {
            return null;
        }
        return charge;
    }

    public static SObject createCoborrowerLink(
        Account accountRecord,
        SObject loanAccount,
        String partyType,
        Boolean doInsert
    ) {
        if (accountRecord == null || loanAccount == null || loanAccount.Id == null) {
            return null;
        }

        SObject link = newLoanSObject('Coborrower__c');
        if (link == null) {
            return null;
        }

        putIfWritable(link, l('Account__c'), accountRecord.Id);
        putIfWritable(link, l('Loan__c'), loanAccount.Id);
        putIfWritable(link, l('Party_Type__c'), partyType);

        if (doInsert && !tryInsert(link)) {
            return null;
        }
        return link;
    }

    public static SObject createGenesisApplication(
        Account accountRecord,
        Contact contactRecord,
        String statusToken,
        String statusFallback,
        Decimal requestedAmount,
        Boolean doInsert
    ) {
        SObject application = newGenesisSObject('Applications__c');
        if (application == null) {
            return null;
        }

        putIfWritable(application, g('Account__c'), accountRecord == null ? null : accountRecord.Id);
        putIfWritable(application, g('Contact__c'), contactRecord == null ? null : contactRecord.Id);
        putIfWritable(application, g('Status__c'), pickValue(application, g('Status__c'), statusToken, statusFallback));
        putIfWritable(application, g('Requested_Loan_Amount__c'), requestedAmount);
        putIfWritable(application, g('Loan_Amount__c'), requestedAmount);
        putIfWritable(application, g('Financed_Amount__c'), requestedAmount);
        putIfWritable(application, g('Payment_Amount__c'), 500);
        putIfWritable(application, g('Interest_Rate__c'), 7.5);
        putIfWritable(application, g('APR__c'), 7.9);
        putIfWritable(application, g('Term__c'), 36);
        putIfWritable(application, g('Maturity_Date__c'), Date.today().addYears(3));
        putIfWritable(application, g('Application_Submission_Date__c'), Date.today().addDays(-30));
        putIfWritable(application, g('Expected_Close_Date__c'), Date.today().addDays(30));
        putIfWritable(application, g('Credit_Approval_Date__c'), Date.today().addDays(-20));

        if (doInsert && !tryInsert(application)) {
            return null;
        }
        return application;
    }

    public static SObject createGenesisParty(
        Account accountRecord,
        Contact contactRecord,
        SObject application,
        String roleToken,
        Boolean doInsert
    ) {
        SObject party = newClcommonSObject('Party__c');
        if (party == null) {
            return null;
        }

        putIfWritable(party, c('Account__c'), accountRecord == null ? null : accountRecord.Id);
        putIfWritable(party, c('Contact__c'), contactRecord == null ? null : contactRecord.Id);
        putIfWritable(party, g('Application__c'), application == null ? null : application.Id);
        putIfWritable(party, c('Party_Type__c'), pickValue(party, c('Party_Type__c'), roleToken, roleToken));
        putIfWritable(party, c('Party_Types__c'), pickValue(party, c('Party_Types__c'), roleToken, roleToken));
        putIfWritable(party, c('isPrimary__c'), true);
        putIfWritable(party, c('Percent_Ownership__c'), 100);
        putIfWritable(party, g('Party_Order__c'), 1);
        putIfWritable(party, g('Party_Name__c'), accountRecord == null ? 'Customer 360 Party' : accountRecord.Name);

        if (doInsert && !tryInsert(party)) {
            return null;
        }
        return party;
    }

    public static SObject createApplicationPricingDetail(SObject application, Boolean doInsert) {
        if (application == null || application.Id == null) {
            return null;
        }

        SObject pricing = newGenesisSObject('Application_Pricing_Detail__c');
        if (pricing == null) {
            return null;
        }

        putIfWritable(pricing, g('Application__c'), application.Id);
        putIfWritable(pricing, g('Selected__c'), true);
        putIfWritable(pricing, g('Payment_Amount_Per_Period__c'), 500);
        putIfWritable(pricing, g('Interest_Rate__c'), 7.5);
        putIfWritable(pricing, g('Term__c'), 36);
        putIfWritable(pricing, g('Total_Interest__c'), 5000);
        putIfWritable(pricing, g('Rate_Factor__c'), 1.05);
        putIfWritable(pricing, g('Yield_Percent__c'), 8);

        if (doInsert && !tryInsert(pricing)) {
            return null;
        }
        return pricing;
    }

    public static SObject createAmortizationSchedule(SObject application, Integer paymentNumber, Boolean doInsert) {
        if (application == null || application.Id == null) {
            return null;
        }

        SObject schedule = newGenesisSObject('Amortization_Schedule__c');
        if (schedule == null) {
            return null;
        }

        putIfWritable(schedule, g('Application__c'), application.Id);
        putIfWritable(schedule, g('Payment_Number__c'), paymentNumber);
        putIfWritable(schedule, g('Due_Date__c'), Date.today().addMonths(paymentNumber));
        putIfWritable(schedule, g('Due_Principal__c'), 400);
        putIfWritable(schedule, g('Due_Interest__c'), 75);
        putIfWritable(schedule, g('Fee__c'), 25);
        putIfWritable(schedule, g('Total_Due_Amount__c'), 500);
        putIfWritable(schedule, g('Opening_Principal_Balance__c'), 10000);
        putIfWritable(schedule, g('Closing_Principal_Balance__c'), 9600);
        putIfWritable(schedule, g('Is_Archived__c'), false);

        if (doInsert && !tryInsert(schedule)) {
            return null;
        }
        return schedule;
    }

    /**
     * Creates the richer Loan Servicing fixture used by the read-model coverage tests.
     * @return The primary (non-master, active good standing) loan account, or null when
     *         the Loan Servicing package is unavailable.
     */
    public static SObject createLoanServicingFixture(Account accountRecord, Contact contactRecord) {
        disableLoanModuleTriggers();
        SObject loanClient = createLoanClient(accountRecord, contactRecord, true);
        Id loanClientId = loanClient == null ? null : loanClient.Id;

        SObject primaryLoan = createLoanAccount(accountRecord, loanClientId, true);
        if (primaryLoan == null) {
            return null;
        }

        createLoanAccountVariant(accountRecord, loanClientId, 'Master Facility', 'Active - Good Standing', false, true);
        createLoanAccountVariant(accountRecord, loanClientId, 'Loan', 'Closed - Obligations met', false, true);
        createLoanAccountVariant(accountRecord, loanClientId, 'Loan', 'Active - Bad Standing', false, true);
        createLoanAccountVariant(accountRecord, loanClientId, 'Loan', 'Active - Good Standing', true, true);

        createDueDetail(primaryLoan, Date.today().addDays(-20), false, true);
        createDueDetail(primaryLoan, Date.today().addDays(-40), true, true);
        createRepaymentSchedule(primaryLoan, Date.today().addDays(30), false, false, true);
        createRepaymentSchedule(primaryLoan, Date.today().addDays(60), true, false, true);
        createRepaymentSchedule(primaryLoan, Date.today().addDays(90), false, true, true);
        createPaymentTransaction(primaryLoan, true);
        createCharge(primaryLoan, true);
        return primaryLoan;
    }

    /**
     * Creates a Genesis Origination application with its party, selected pricing and schedule.
     * @return The inserted application, or null when the Genesis package is unavailable.
     */
    public static SObject createGenesisOriginationFixture(Account accountRecord, Contact contactRecord) {
        SObject application = createGenesisApplication(
            accountRecord,
            contactRecord,
            'Approved',
            'Approved',
            50000,
            true
        );
        if (application == null) {
            return null;
        }

        createGenesisParty(accountRecord, contactRecord, application, 'Borrower', true);
        createApplicationPricingDetail(application, true);
        for (Integer paymentNumber = 1; paymentNumber <= 3; paymentNumber++) {
            createAmortizationSchedule(application, paymentNumber, true);
        }
        return application;
    }

    private static SObject newLoanSObject(String apiName) {
        String objectApiName = Customer360NamespaceUtil.qualifyLoanApiName(apiName);
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        return objectType == null ? null : objectType.newSObject();
    }

    private static SObject newGenesisSObject(String apiName) {
        Schema.SObjectType objectType = getSObjectType(Customer360NamespaceUtil.qualifyGenesisApiName(apiName));
        return objectType == null ? null : objectType.newSObject();
    }

    private static SObject newClcommonSObject(String apiName) {
        Schema.SObjectType objectType = getSObjectType(c(apiName));
        return objectType == null ? null : objectType.newSObject();
    }

    private static Schema.SObjectType getSObjectType(String objectApiName) {
        return String.isBlank(objectApiName) ? null : Schema.getGlobalDescribe().get(objectApiName);
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

    /**
     * Sets a field only when it exists on the object and the running user can write it.
     * Managed package layouts differ between orgs, and several of these fields are
     * formula or rollup fields in some installs.
     */
    private static void putIfWritable(SObject record, String fieldApiName, Object value) {
        Schema.DescribeFieldResult fieldDescribe = describeField(record, fieldApiName);
        if (fieldDescribe != null && fieldDescribe.isCreateable() && value != null) {
            record.put(fieldDescribe.getName(), value);
        }
    }

    /**
     * Resolves a picklist value for the supplied token so fixtures stay valid across orgs
     * with different picklist configurations.
     */
    private static Object pickValue(SObject record, String fieldApiName, String token, String fallbackValue) {
        Schema.DescribeFieldResult fieldDescribe = describeField(record, fieldApiName);
        if (fieldDescribe == null || String.isBlank(token)) {
            return fallbackValue;
        }

        Boolean isPicklist = fieldDescribe.getType() == Schema.DisplayType.PICKLIST ||
            fieldDescribe.getType() == Schema.DisplayType.MULTIPICKLIST;
        if (!isPicklist) {
            return fallbackValue;
        }

        List<Schema.PicklistEntry> entries = fieldDescribe.getPicklistValues();
        if (entries.isEmpty()) {
            return fallbackValue;
        }
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive() && entry.getValue().toUpperCase() == token.toUpperCase()) {
                return entry.getValue();
            }
        }
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive() && entry.getValue().toUpperCase().contains(token.toUpperCase())) {
                return entry.getValue();
            }
        }
        return fieldDescribe.isRestrictedPicklist() ? null : fallbackValue;
    }

    private static Schema.DescribeFieldResult describeField(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) {
            return null;
        }

        Schema.SObjectField field = record.getSObjectType().getDescribe().fields.getMap().get(fieldApiName);
        return field == null ? null : field.getDescribe();
    }

    private static void putIfField(SObject record, String apiName, Object value) {
        if (record == null) {
            return;
        }

        String fieldApiName = Customer360NamespaceUtil.qualifyLoanApiName(apiName);
        if (record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static Boolean tryInsert(SObject record) {
        if (record == null) {
            return false;
        }

        try {
            insert record;
            return true;
        } catch (DmlException ignoredException) {
            insertErrors.add(record.getSObjectType().getDescribe().getName() + ' :: ' + ignoredException.getMessage());
            return false;
        }
    }

    private static void insertAccountsWithDuplicateBypass(List<Account> records) {
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        Database.insert(records, dmlOptions);
    }

    public class Customer360Fixture {
        public Account accountRecord;
        public Contact contactRecord;
        public SObject loanAccount;

        public Customer360Fixture(Account accountRecord, Contact contactRecord, SObject loanAccount) {
            this.accountRecord = accountRecord;
            this.contactRecord = contactRecord;
            this.loanAccount = loanAccount;
        }
    }
}