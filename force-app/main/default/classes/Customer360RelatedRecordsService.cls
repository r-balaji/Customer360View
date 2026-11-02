/**
 * Loads account-level documents displayed by Customer 360.
 */
public with sharing class Customer360RelatedRecordsService {
    private static final String DOCUMENT_CATEGORY_OBJECT = 'clcommon__Document_Category__c';
    private static final String DOCUMENT_CATEGORY_ACCOUNT_FIELD = 'clcommon__Account__c';
    private static final String DOCUMENT_CATEGORY_NAME_FIELD = 'clcommon__Category_Name__c';
    private static final String DOCUMENT_CATEGORY_STATUS_FIELD = 'clcommon__Status__c';
    private static final String DOCUMENT_CATEGORY_PRIORITY_FIELD = 'clcommon__Priority__c';
    private static final Integer DOCUMENT_LIMIT = 500;

    public static List<DocumentView> getAccountDocuments(String accountId) {
        if (String.isBlank(accountId)) {
            throw new RelatedRecordsServiceException('Account ID is required');
        }
        if (!Customer360NamespaceUtil.hasGenesisModule() ||
            !Customer360NamespaceUtil.isObjectAccessible(DOCUMENT_CATEGORY_OBJECT)) {
            return new List<DocumentView>();
        }

        Schema.SObjectType categoryType = Schema.getGlobalDescribe().get(DOCUMENT_CATEGORY_OBJECT);
        Map<String, Schema.SObjectField> categoryFields = categoryType.getDescribe().fields.getMap();
        String applicationField = Customer360NamespaceUtil.qualifyGenesisApiName('Application__c');
        if (!hasReadableFields(categoryFields, new List<String>{
            DOCUMENT_CATEGORY_ACCOUNT_FIELD,
            applicationField
        })) {
            return new List<DocumentView>();
        }

        List<String> selectedFields = new List<String>{ 'Id', 'Name', 'LastModifiedDate' };
        addReadableField(selectedFields, categoryFields, DOCUMENT_CATEGORY_NAME_FIELD);
        addReadableField(selectedFields, categoryFields, DOCUMENT_CATEGORY_STATUS_FIELD);
        addReadableField(selectedFields, categoryFields, DOCUMENT_CATEGORY_PRIORITY_FIELD);
        selectedFields.add(applicationField);

        String categoryQuery =
            'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM ' + DOCUMENT_CATEGORY_OBJECT +
            ' WHERE ' + DOCUMENT_CATEGORY_ACCOUNT_FIELD + ' = :accountId' +
            ' AND ' + applicationField + ' != null' +
            ' ORDER BY LastModifiedDate DESC' +
            ' LIMIT ' + DOCUMENT_LIMIT;
        List<SObject> categoryRecords = Database.queryWithBinds(
            categoryQuery,
            new Map<String, Object>{ 'accountId' => accountId },
            AccessLevel.USER_MODE
        );
        if (categoryRecords.isEmpty()) {
            return new List<DocumentView>();
        }

        Map<Id, SObject> categoryById = new Map<Id, SObject>();
        Set<Id> applicationIds = new Set<Id>();
        for (SObject categoryRecord : categoryRecords) {
            categoryById.put((Id) categoryRecord.get('Id'), categoryRecord);
            Object applicationId = categoryRecord.get(applicationField);
            if (applicationId != null) {
                applicationIds.add((Id) applicationId);
            }
        }

        Map<Id, String> applicationNameById = getApplicationNames(applicationIds);
        Set<Id> categoryIds = categoryById.keySet();
        Set<Id> documentLinkEntityIds = new Set<Id>();
        documentLinkEntityIds.addAll(categoryIds);
        documentLinkEntityIds.addAll(applicationIds);
        List<ContentDocumentLink> documentLinks = [
            SELECT LinkedEntityId,
                   ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.ContentSize,
                   ContentDocument.LastModifiedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :documentLinkEntityIds
            WITH USER_MODE
            ORDER BY ContentDocument.LastModifiedDate DESC
        ];

        List<DocumentView> documents = new List<DocumentView>();
        Set<Id> includedDocumentIds = new Set<Id>();
        for (ContentDocumentLink documentLink : documentLinks) {
            if (categoryById.containsKey(documentLink.LinkedEntityId)) {
                addDocument(
                    documents,
                    includedDocumentIds,
                    documentLink,
                    categoryById.get(documentLink.LinkedEntityId),
                    applicationField,
                    applicationNameById
                );
            }
        }
        for (ContentDocumentLink documentLink : documentLinks) {
            if (!categoryById.containsKey(documentLink.LinkedEntityId)) {
                addDocument(
                    documents,
                    includedDocumentIds,
                    documentLink,
                    null,
                    applicationField,
                    applicationNameById
                );
            }
        }
        return documents;
    }

    private static void addDocument(
        List<DocumentView> documents,
        Set<Id> includedDocumentIds,
        ContentDocumentLink documentLink,
        SObject categoryRecord,
        String applicationField,
        Map<Id, String> applicationNameById
    ) {
        if (documentLink.ContentDocument == null ||
            documentLink.ContentDocument.LatestPublishedVersionId == null ||
            includedDocumentIds.contains(documentLink.ContentDocumentId)) {
            return;
        }

        Id applicationId = categoryRecord == null
            ? documentLink.LinkedEntityId
            : (Id) categoryRecord.get(applicationField);
        DocumentView document = new DocumentView();
        document.categoryId = categoryRecord == null ? null : documentLink.LinkedEntityId;
        document.categoryName = categoryRecord == null
            ? 'Application File'
            : firstNonBlank(
                getString(categoryRecord, DOCUMENT_CATEGORY_NAME_FIELD),
                getString(categoryRecord, 'Name')
            );
        document.categoryStatus = categoryRecord == null
            ? null
            : getString(categoryRecord, DOCUMENT_CATEGORY_STATUS_FIELD);
        document.priority = categoryRecord == null
            ? null
            : getString(categoryRecord, DOCUMENT_CATEGORY_PRIORITY_FIELD);
        document.applicationId = applicationId;
        document.applicationNumber = applicationNameById.get(applicationId);
        document.contentDocumentId = documentLink.ContentDocumentId;
        document.contentVersionId = documentLink.ContentDocument.LatestPublishedVersionId;
        document.title = documentLink.ContentDocument.Title;
        document.fileType = documentLink.ContentDocument.FileType;
        document.contentSize = documentLink.ContentDocument.ContentSize;
        document.lastModifiedDate = documentLink.ContentDocument.LastModifiedDate;
        documents.add(document);
        includedDocumentIds.add(documentLink.ContentDocumentId);
    }

    private static Map<Id, String> getApplicationNames(Set<Id> applicationIds) {
        Map<Id, String> applicationNameById = new Map<Id, String>();
        if (applicationIds.isEmpty()) {
            return applicationNameById;
        }

        String applicationObject = Customer360NamespaceUtil.getGenesisApplicationObjectApiName();
        Schema.SObjectType applicationType = Schema.getGlobalDescribe().get(applicationObject);
        if (applicationType == null || !applicationType.getDescribe().isAccessible() ||
            !applicationType.getDescribe().fields.getMap().get('Name').getDescribe().isAccessible()) {
            return applicationNameById;
        }

        String applicationQuery =
            'SELECT Id, Name FROM ' + applicationObject + ' WHERE Id IN :applicationIds';
        for (SObject applicationRecord : Database.queryWithBinds(
            applicationQuery,
            new Map<String, Object>{ 'applicationIds' => applicationIds },
            AccessLevel.USER_MODE
        )) {
            applicationNameById.put(
                (Id) applicationRecord.get('Id'),
                getString(applicationRecord, 'Name')
            );
        }
        return applicationNameById;
    }

    private static Boolean hasReadableFields(
        Map<String, Schema.SObjectField> fieldMap,
        List<String> fieldApiNames
    ) {
        for (String fieldApiName : fieldApiNames) {
            if (!fieldMap.containsKey(fieldApiName) ||
                !fieldMap.get(fieldApiName).getDescribe().isAccessible()) {
                return false;
            }
        }
        return true;
    }

    private static void addReadableField(
        List<String> selectedFields,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldApiName
    ) {
        if (fieldMap.containsKey(fieldApiName) &&
            fieldMap.get(fieldApiName).getDescribe().isAccessible()) {
            selectedFields.add(fieldApiName);
        }
    }

    private static String getString(SObject record, String fieldApiName) {
        if (record == null || !record.getPopulatedFieldsAsMap().containsKey(fieldApiName)) {
            return null;
        }
        Object value = record.get(fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static String firstNonBlank(String preferredValue, String fallbackValue) {
        return String.isNotBlank(preferredValue) ? preferredValue : fallbackValue;
    }

    public class DocumentView {
        @AuraEnabled public Id categoryId;
        @AuraEnabled public String categoryName;
        @AuraEnabled public String categoryStatus;
        @AuraEnabled public String priority;
        @AuraEnabled public Id applicationId;
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
        @AuraEnabled public Integer contentSize;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    public class RelatedRecordsServiceException extends Exception {
    }
}
