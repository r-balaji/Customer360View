@IsTest
private class RelationshipGraphControllerTest {
    @TestSetup
    static void createGraphFixture() {
        List<Account> accounts = Customer360TestDataFactory.createAccounts('Graph Account', 3, true);
        Contact contactRecord = Customer360TestDataFactory.createContact(accounts[0], true);
        SObject application = Customer360TestDataFactory.createGenesisApplication(
            accounts[0], contactRecord, 'UNDER REVIEW', 'UNDER REVIEW', 25000, false
        );
        insert application;

        List<SObject> parties = new List<SObject>();
        for (Integer index = 0; index < accounts.size(); index++) {
            SObject party = Customer360TestDataFactory.createGenesisParty(
                accounts[index], null, application, 'Borrower', false
            );
            party.put('clcommon__Active__c', index < 2);
            party.put('clcommon__isPrimary__c', index == 0);
            parties.add(party);
        }
        insert parties;

        insert new clcommon__Relationship__c(
            clcommon__Entity__c = accounts[0].Id,
            clcommon__Related_Entity__c = accounts[1].Id,
            clcommon__Ownership_Percentage__c = 50
        );
    }

    @IsTest
    static void shouldReturnAccountGraphWithRelatedAccounts() {
        List<Account> accounts = getAccounts();

        Test.startTest();
        RelationshipGraphController.GraphData result =
            RelationshipGraphController.getRelationshipGraphData(null, accounts[0].Id);
        Test.stopTest();

        Assert.areEqual(accounts[0].Id, result.selectedAccountId, 'The anchor should remain selected');
        Assert.areEqual(2, result.graphByAccountId.size(), 'The anchor and its related account should be returned');
        Assert.isTrue(result.graphByAccountId.containsKey(accounts[1].Id), 'The related account should be included');
        Assert.areEqual(new List<Id>{ accounts[0].Id }, result.applicationPartyAccountIds,
            'Account context should mark only the anchor as an application-party equivalent');
        Assert.areEqual(1,
            result.graphByAccountId.get(accounts[0].Id).getSObjects('clcommon__EntityRelationships__r').size(),
            'Relationship details should remain available to the renderer');
    }

    @IsTest
    static void shouldReturnOnlyActiveApplicationParties() {
        List<Account> accounts = getAccounts();
        Id applicationId = getApplicationId();

        Test.startTest();
        RelationshipGraphController.GraphData result =
            RelationshipGraphController.getRelationshipGraphData(applicationId, null);
        Test.stopTest();

        Assert.areEqual(new Set<Id>{ accounts[0].Id, accounts[1].Id },
            new Set<Id>(result.applicationPartyAccountIds), 'Only active parties should seed the graph');
        Assert.areEqual(2, result.graphByAccountId.size(), 'Inactive, unrelated parties should not enter the graph');
        Assert.isTrue(result.applicationPartyAccountIds.contains(result.selectedAccountId),
            'The default selection should be one of the active application parties');
    }

    @IsTest
    static void shouldHonorSelectedApplicationParty() {
        List<Account> accounts = getAccounts();
        Id applicationId = getApplicationId();

        Test.startTest();
        RelationshipGraphController.GraphData result =
            RelationshipGraphController.getRelationshipGraphData(applicationId, accounts[1].Id);
        Test.stopTest();

        Assert.areEqual(accounts[1].Id, result.selectedAccountId,
            'An explicitly selected active application party should remain selected');
    }

    @IsTest
    static void shouldReturnEmptyGraphWhenApplicationHasNoParties() {
        Test.startTest();
        RelationshipGraphController.GraphData result =
            RelationshipGraphController.getRelationshipGraphData(UserInfo.getUserId(), null);
        Test.stopTest();

        Assert.isTrue(result.graphByAccountId.isEmpty(), 'No matching parties should produce an empty account map');
        Assert.isTrue(result.applicationPartyAccountIds.isEmpty(), 'No matching parties should produce an empty party list');
        Assert.isNull(result.selectedAccountId, 'An empty graph should have no selection');
    }

    @IsTest
    static void shouldReturnPartyAccountIdDirectly() {
        clcommon__Party__c party = [SELECT Id, clcommon__Account__c FROM clcommon__Party__c LIMIT 1];

        Test.startTest();
        Id accountId = RelationshipGraphController.getPartyAccountId(party.Id);
        Test.stopTest();

        Assert.areEqual(party.clcommon__Account__c, accountId,
            'Party lookup should return the account id without a package response wrapper');
    }

    @IsTest
    static void shouldRejectMissingGraphContext() {
        Test.startTest();
        try {
            RelationshipGraphController.getRelationshipGraphData(null, null);
            Assert.fail('Missing graph context should be rejected');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Validation should use a native AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldHandleInvalidAccountId() {
        Test.startTest();
        try {
            RelationshipGraphController.getRelationshipGraphData(null, 'invalid-account-id');
            Assert.fail('An invalid account id should be rejected');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Query and conversion failures should use a native AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldRejectMissingPartyId() {
        Test.startTest();
        try {
            RelationshipGraphController.getPartyAccountId(null);
            Assert.fail('A missing party id should be rejected');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Validation should use a native AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldHandleUnknownPartyId() {
        Test.startTest();
        try {
            RelationshipGraphController.getPartyAccountId(UserInfo.getUserId());
            Assert.fail('An unknown party should be rejected');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'Missing records should use a native AuraHandledException');
        }
        Test.stopTest();
    }

    private static List<Account> getAccounts() {
        return [SELECT Id, Name FROM Account ORDER BY Name];
    }

    private static Id getApplicationId() {
        return [SELECT genesis__Application__c FROM clcommon__Party__c LIMIT 1].genesis__Application__c;
    }
}
