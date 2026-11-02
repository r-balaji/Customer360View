@IsTest
private class Customer360RelatedRecordsServiceTest {
    @IsTest
    static void accountWithoutDocumentsReturnsAnEmptyList() {
        Account accountRecord = createAccounts('No Documents', 1)[0];

        Test.startTest();
        List<Customer360RelatedRecordsService.DocumentView> results =
            Customer360Controller.getAccountDocuments(accountRecord.Id);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'An account without uploaded files should return no documents');
    }

    @IsTest
    static void latestApplicationDocumentVersionIsReturned() {
        if (!Customer360NamespaceUtil.hasGenesisModule()) {
            Assert.isTrue(true, 'Genesis is not installed in this test org');
            return;
        }

        Account accountRecord = createAccounts('Document Account', 1)[0];
        SObject applicationRecord = createGenesisApplication(accountRecord);
        SObject categoryRecord = createDocumentCategory(accountRecord, applicationRecord);
        Assert.isNotNull(applicationRecord, 'The Genesis application fixture should be created');
        Assert.isNotNull(categoryRecord, 'The document category fixture should be created');

        ContentVersion versionRecord = new ContentVersion(
            Title = 'Bank Statements',
            PathOnClient = 'bank-statements.pdf',
            VersionData = Blob.valueOf('Customer 360 document test')
        );
        insert versionRecord;
        versionRecord = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionRecord.Id
        ];
        insert new ContentDocumentLink(
            ContentDocumentId = versionRecord.ContentDocumentId,
            LinkedEntityId = (Id) categoryRecord.get('Id'),
            ShareType = 'V'
        );
        ContentVersion applicationVersion = new ContentVersion(
            Title = 'Business Tax Return',
            PathOnClient = 'business-tax-return.pdf',
            VersionData = Blob.valueOf('Application-linked document test'),
            FirstPublishLocationId = (Id) applicationRecord.get('Id')
        );
        insert applicationVersion;

        Test.startTest();
        List<Customer360RelatedRecordsService.DocumentView> results =
            Customer360Controller.getAccountDocuments(accountRecord.Id);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Category-linked and application-linked documents should be returned');
        Customer360RelatedRecordsService.DocumentView categoryDocument = findDocument(
            results,
            'Bank Statements'
        );
        Customer360RelatedRecordsService.DocumentView applicationDocument = findDocument(
            results,
            'Business Tax Return'
        );
        Assert.isNotNull(categoryDocument, 'The category-linked document should be returned');
        Assert.isNotNull(applicationDocument, 'The application-linked document should be returned');
        Assert.areEqual(
            versionRecord.Id,
            categoryDocument.contentVersionId,
            'The latest ContentVersion id should be exposed for download'
        );
        Assert.areEqual(
            applicationRecord.Id,
            applicationDocument.applicationId,
            'The application should be identified for directly linked files'
        );
        Assert.areEqual(
            'Application File',
            applicationDocument.categoryName,
            'Directly linked files should have a useful fallback category'
        );
    }

    @IsTest
    static void blankDocumentAccountIdIsRejected() {
        Test.startTest();
        try {
            Customer360Controller.getAccountDocuments('');
            Assert.fail('A blank account id should be rejected');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'The controller should throw an AuraHandledException');
        }
        Test.stopTest();
    }

    private static List<Account> createAccounts(String namePrefix, Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer index = 0; index < count; index++) {
            accounts.add(new Account(Name = namePrefix + ' ' + index));
        }
        insert accounts;
        return accounts;
    }

    private static SObject createGenesisApplication(Account accountRecord) {
        Schema.SObjectType applicationType = Schema.getGlobalDescribe().get(
            Customer360NamespaceUtil.getGenesisApplicationObjectApiName()
        );
        SObject applicationRecord = applicationType.newSObject();
        putIfField(
            applicationRecord,
            Customer360NamespaceUtil.qualifyGenesisApiName('Account__c'),
            accountRecord.Id
        );
        putIfField(
            applicationRecord,
            Customer360NamespaceUtil.qualifyGenesisApiName('Requested_Loan_Amount__c'),
            25000
        );
        insert applicationRecord;
        return applicationRecord;
    }

    private static SObject createDocumentCategory(
        Account accountRecord,
        SObject applicationRecord
    ) {
        SObject categoryRecord = Schema.getGlobalDescribe()
            .get('clcommon__Document_Category__c')
            .newSObject();
        putIfField(categoryRecord, 'clcommon__Account__c', accountRecord.Id);
        putIfField(categoryRecord, 'clcommon__Category_Name__c', 'Business Bank Statement');
        putIfField(
            categoryRecord,
            Customer360NamespaceUtil.qualifyGenesisApiName('Application__c'),
            applicationRecord.Id
        );
        insert categoryRecord;
        return categoryRecord;
    }

    private static void putIfField(SObject record, String fieldApiName, Object value) {
        if (record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static Customer360RelatedRecordsService.DocumentView findDocument(
        List<Customer360RelatedRecordsService.DocumentView> documents,
        String title
    ) {
        for (Customer360RelatedRecordsService.DocumentView document : documents) {
            if (document.title == title) {
                return document;
            }
        }
        return null;
    }
}
