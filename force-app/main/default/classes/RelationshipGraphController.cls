public with sharing class RelationshipGraphController {
    @AuraEnabled(cacheable=true)
    public static q2lwcc.LWCResponse getRelationshipGraphData(String applicationId, String accountId) {
        q2lwcc.LWCResponse res = new q2lwcc.LWCResponse();
        try {
            Boolean isApplicationContext = String.isNotBlank(applicationId);
            if (!isApplicationContext && String.isBlank(accountId)) {
                throw new q2lwcc.LWCException('Either applicationId or accountId is required.');
            }

            Set<Id> applicationPartyAccountIds = new Set<Id>();
            Set<Id> seedAccountIds = new Set<Id>();
            String selectedAccountId;

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
                    selectedAccountId = (String)applicationPartyAccountIds.iterator().next();
                }
            } else {
                seedAccountIds.add((Id)accountId);
                applicationPartyAccountIds.add((Id)accountId);
                selectedAccountId = accountId;
            }

            if (seedAccountIds.isEmpty()) {
                Map<String, Object> emptyResponse = new Map<String, Object>{
                    'graphByAccountId' => new Map<Id, SObject>(),
                    'applicationPartyAccountIds' => new List<Id>(),
                    'selectedAccountId' => null
                };
                res.response = emptyResponse;
                res.status = q2lwcc.LWCConstants.SUCCESS;
                return res;
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

            Map<String, Object> responseMap = new Map<String, Object>{
                'graphByAccountId' => graphByAccountId,
                'applicationPartyAccountIds' => new List<Id>(applicationPartyAccountIds),
                'selectedAccountId' => selectedAccountId
            };
            res.response = responseMap;
            res.status = q2lwcc.LWCConstants.SUCCESS;
        } catch (Exception ex) {
            res.status = q2lwcc.LWCConstants.ERROR;
            q2lwcc.LWCResponse.Message errorMessage = new q2lwcc.LWCResponse.Message();
            errorMessage.type = q2lwcc.LWCConstants.TYPE_ERROR;
            errorMessage.message = ex.getMessage();
            res.addMessage(errorMessage);
        }
        return res;
    }

    @AuraEnabled(cacheable=true)
    public static q2lwcc.LWCResponse getPartyAccountId(String partyId) {
        q2lwcc.LWCResponse response = new q2lwcc.LWCResponse();
        try {
            clcommon__Party__c party = [
                SELECT clcommon__Account__c
                FROM clcommon__Party__c
                WHERE Id = :partyId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            response.status = q2lwcc.LWCConstants.SUCCESS;
            response.response = party.clcommon__Account__c;
        } catch (Exception ex) {
            ResponseUtil.setErrorMessage(ex, response);
        }
        return response;
    }
}