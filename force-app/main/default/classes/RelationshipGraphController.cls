/**
 * Loads the account and application relationships rendered by Customer 360.
 */
public with sharing class RelationshipGraphController {
    /**
     * @param applicationId Optional application whose active parties seed the graph.
     * @param accountId Account to select, or the anchor in Account context.
     * @return Accounts, application-party membership, and the selected account.
     */
    @AuraEnabled(cacheable=true)
    public static GraphData getRelationshipGraphData(String applicationId, String accountId) {
        Boolean isApplicationContext = String.isNotBlank(applicationId);
        if (!isApplicationContext && String.isBlank(accountId)) {
            throw new AuraHandledException('Either applicationId or accountId is required.');
        }

        try {
            Set<Id> applicationPartyAccountIds = new Set<Id>();
            Set<Id> seedAccountIds = new Set<Id>();
            Id selectedAccountId;

            if (isApplicationContext) {
                List<clcommon__Party__c> parties = [
                    SELECT clcommon__Account__c
                    FROM clcommon__Party__c
                    WHERE genesis__Application__c = :applicationId
                    AND clcommon__Active__c = true
                    AND clcommon__Account__c != null
                    WITH SECURITY_ENFORCED
                ];

                for (clcommon__Party__c party : parties) {
                    applicationPartyAccountIds.add(party.clcommon__Account__c);
                }
                seedAccountIds.addAll(applicationPartyAccountIds);

                if (String.isNotBlank(accountId) && applicationPartyAccountIds.contains((Id)accountId)) {
                    selectedAccountId = accountId;
                } else if (!applicationPartyAccountIds.isEmpty()) {
                    selectedAccountId = applicationPartyAccountIds.iterator().next();
                }
            } else {
                seedAccountIds.add((Id)accountId);
                applicationPartyAccountIds.add((Id)accountId);
                selectedAccountId = accountId;
            }

            if (seedAccountIds.isEmpty()) {
                return new GraphData();
            }

            List<clcommon__Relationship__c> firstHopRelations = [
                SELECT Id, clcommon__Entity__c, clcommon__Related_Entity__c
                FROM clcommon__Relationship__c
                WHERE (clcommon__Entity__c IN :seedAccountIds OR clcommon__Related_Entity__c IN :seedAccountIds)
                AND clcommon__Entity__c != null
                AND clcommon__Related_Entity__c != null
                WITH SECURITY_ENFORCED
            ];

            Set<Id> expandedAccountIds = new Set<Id>();
            expandedAccountIds.addAll(seedAccountIds);
            for (clcommon__Relationship__c relation : firstHopRelations) {
                expandedAccountIds.add(relation.clcommon__Entity__c);
                expandedAccountIds.add(relation.clcommon__Related_Entity__c);
            }

            List<Account> accounts = [
                SELECT Id, Name, clcommon__Legal_Entity_Type__c, clcommon__Legal_Entity_Type__r.Name,
                    (
                        SELECT Id, clcommon__Related_Entity__c,
                            clcommon__Related_Entity__r.Id,
                            clcommon__Related_Entity__r.Name,
                            clcommon__Related_Entity__r.clcommon__Legal_Entity_Type__c,
                            clcommon__Related_Entity__r.clcommon__Legal_Entity_Type__r.Name,
                            clcommon__Related_Entity_Role__c,
                            clcommon__Entity_Role__c,
                            clcommon__Ownership_Percentage__c
                        FROM clcommon__EntityRelationships__r
                    ),
                    (
                        SELECT Id, clcommon__Entity__c,
                            clcommon__Entity__r.Id,
                            clcommon__Entity__r.Name,
                            clcommon__Entity__r.clcommon__Legal_Entity_Type__c,
                            clcommon__Entity__r.clcommon__Legal_Entity_Type__r.Name,
                            clcommon__Related_Entity_Role__c,
                            clcommon__Entity_Role__c,
                            clcommon__Ownership_Percentage__c
                        FROM clcommon__RelatedEntityRelationships__r
                    )
                FROM Account
                WHERE Id IN :expandedAccountIds
                WITH SECURITY_ENFORCED
            ];

            Map<Id, SObject> graphByAccountId = new Map<Id, SObject>();
            for (Account accountRecord : accounts) {
                graphByAccountId.put(accountRecord.Id, accountRecord);
            }

            GraphData result = new GraphData();
            result.graphByAccountId = graphByAccountId;
            result.applicationPartyAccountIds = new List<Id>(applicationPartyAccountIds);
            result.selectedAccountId = selectedAccountId;
            return result;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load relationship graph.');
        }
    }

    /**
     * @param partyId Party whose account should be selected in the graph.
     * @return The account linked to the party.
     */
    @AuraEnabled(cacheable=true)
    public static Id getPartyAccountId(String partyId) {
        if (String.isBlank(partyId)) {
            throw new AuraHandledException('Party ID is required.');
        }

        try {
            clcommon__Party__c party = [
                SELECT clcommon__Account__c
                FROM clcommon__Party__c
                WHERE Id = :partyId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return party.clcommon__Account__c;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load the party account.');
        }
    }

    /** Graph payload shared with the relationship graph LWC. */
    public class GraphData {
        @AuraEnabled public Map<Id, SObject> graphByAccountId = new Map<Id, SObject>();
        @AuraEnabled public List<Id> applicationPartyAccountIds = new List<Id>();
        @AuraEnabled public Id selectedAccountId;
    }
}
