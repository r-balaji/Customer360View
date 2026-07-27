@IsTest
public class Customer360TestDataFactory {
    private static Integer sequence = 0;

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
        if (!Customer360NamespaceUtil.hasLoanModule()) {
            return null;
        }

        SObject loanAccount = newLoanSObject('Loan_Account__c');
        if (loanAccount == null) {
            return null;
        }

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
        Account accountRecord = createAccount(true);
        Contact contactRecord = createContact(accountRecord, true);
        SObject loanAccount = createLoanAccount(accountRecord, true);
        createDueDetail(loanAccount, Date.today().addDays(-10), false, true);
        return new Customer360Fixture(accountRecord, contactRecord, loanAccount);
    }

    private static SObject newLoanSObject(String apiName) {
        String objectApiName = Customer360NamespaceUtil.qualifyLoanApiName(apiName);
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        return objectType == null ? null : objectType.newSObject();
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
