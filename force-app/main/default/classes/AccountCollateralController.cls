/**
 * Supplies collateral owned by Accounts displayed in Customer 360.
 */
public with sharing class AccountCollateralController {
  /**
   * Returns collateral details grouped by the owning Account.
   *
   * @param accountIds Accounts currently displayed in the relationship graph.
   * @return Account collateral details keyed by Account Id.
   */
  @AuraEnabled(cacheable=true)
  public static Map<Id, AccountCollateralView> getAccountCollateralDetails(
    List<Id> accountIds
  ) {
    Set<Id> ownerAccountIds = accountIds == null
      ? new Set<Id>()
      : new Set<Id>(accountIds);
    ownerAccountIds.remove(null);
    if (ownerAccountIds.isEmpty()) {
      return new Map<Id, AccountCollateralView>();
    }

    try {
      Map<Id, AccountCollateralView> detailsByAccountId = new Map<Id, AccountCollateralView>();
      Map<Id, List<CollateralView>> viewsByCollateralId = new Map<Id, List<CollateralView>>();
      Map<String, CollateralView> viewByOwnerAndCollateral = new Map<String, CollateralView>();

      for (clcommon__Collateral_Owner__c ownerRecord : [
        SELECT
          Id,
          clcommon__Account__c,
          clcommon__Account__r.Name,
          clcommon__Collateral__c,
          clcommon__Collateral__r.Name,
          clcommon__Collateral__r.clcommon__Collateral_Name__c,
          clcommon__Collateral__r.clcommon__Collateral_Type__r.Name,
          clcommon__Collateral__r.clcommon__Value__c,
          clcommon__Collateral__r.clcommon__Value_Date__c,
          clcommon__Ownership__c
        FROM clcommon__Collateral_Owner__c
        WHERE
          clcommon__Account__c IN :ownerAccountIds
          AND clcommon__Collateral__c != NULL
        WITH USER_MODE
        ORDER BY clcommon__Account__r.Name, CreatedDate
      ]) {
        String ownerCollateralKey =
          ownerRecord.clcommon__Account__c +
          ':' +
          ownerRecord.clcommon__Collateral__c;
        if (viewByOwnerAndCollateral.containsKey(ownerCollateralKey)) {
          continue;
        }

        if (!detailsByAccountId.containsKey(ownerRecord.clcommon__Account__c)) {
          detailsByAccountId.put(
            ownerRecord.clcommon__Account__c,
            new AccountCollateralView(
              ownerRecord.clcommon__Account__c,
              ownerRecord.clcommon__Account__r.Name
            )
          );
        }

        CollateralView collateral = new CollateralView();
        collateral.ownerRecordId = ownerRecord.Id;
        collateral.id = ownerRecord.clcommon__Collateral__c;
        collateral.name = String.isBlank(
            ownerRecord.clcommon__Collateral__r.clcommon__Collateral_Name__c
          )
          ? ownerRecord.clcommon__Collateral__r.Name
          : ownerRecord.clcommon__Collateral__r.clcommon__Collateral_Name__c;
        collateral.type = ownerRecord.clcommon__Collateral__r.clcommon__Collateral_Type__r
          ?.Name;
        collateral.ownershipPercentage = ownerRecord.clcommon__Ownership__c;
        collateral.recordedValue = ownerRecord.clcommon__Collateral__r.clcommon__Value__c;
        collateral.valueDate = ownerRecord.clcommon__Collateral__r.clcommon__Value_Date__c;
        detailsByAccountId.get(ownerRecord.clcommon__Account__c)
          .collaterals.add(collateral);
        viewByOwnerAndCollateral.put(ownerCollateralKey, collateral);

        if (!viewsByCollateralId.containsKey(collateral.id)) {
          viewsByCollateralId.put(collateral.id, new List<CollateralView>());
        }
        viewsByCollateralId.get(collateral.id).add(collateral);
      }

      if (!viewsByCollateralId.isEmpty()) {
        applyLatestValuations(viewsByCollateralId);
        applyLiens(viewsByCollateralId);
        applyApplications(viewsByCollateralId);
      }
      return detailsByAccountId;
    } catch (Exception exceptionValue) {
      throw new AuraHandledException(
        'Unable to load collateral owned by the selected accounts.'
      );
    }
  }

  private static void applyLatestValuations(
    Map<Id, List<CollateralView>> viewsByCollateralId
  ) {
    Set<Id> valuedCollateralIds = new Set<Id>();
    for (clcommon__Collateral_Valuation__c valuation : [
      SELECT
        clcommon__Collateral__c,
        clcommon__Appraised_Value__c,
        clcommon__Appraisal_Date__c,
        clcommon__Valuation_Type__c
      FROM clcommon__Collateral_Valuation__c
      WHERE
        clcommon__Collateral__c IN :viewsByCollateralId.keySet()
        AND clcommon__Active__c = TRUE
      WITH USER_MODE
      ORDER BY
        clcommon__Collateral__c,
        clcommon__Appraisal_Date__c DESC,
        CreatedDate DESC
    ]) {
      if (!valuedCollateralIds.add(valuation.clcommon__Collateral__c)) {
        continue;
      }
      for (
        CollateralView collateral : viewsByCollateralId.get(
          valuation.clcommon__Collateral__c
        )
      ) {
        collateral.appraisedValue = valuation.clcommon__Appraised_Value__c;
        collateral.appraisalDate = valuation.clcommon__Appraisal_Date__c;
        collateral.valuationType = valuation.clcommon__Valuation_Type__c;
      }
    }
  }

  private static void applyLiens(
    Map<Id, List<CollateralView>> viewsByCollateralId
  ) {
    for (clcommon__CollateralLien__c lienRecord : [
      SELECT
        Id,
        Name,
        clcommon__Collateral__c,
        clcommon__Bank_Name__c,
        clcommon__Internal__c,
        clcommon__Lien_Amount__c,
        clcommon__Loan_Amount__c,
        clcommon__Lien_Position__c,
        clcommon__Lien_Nature__c,
        clcommon__Status__c,
        clcommon__Pledge_Date__c,
        genesis__Application__c,
        genesis__Application__r.Name,
        genesis__Application__r.genesis__Account__r.Name,
        loan__Loan_Account__c,
        loan__Loan_Account__r.Name
      FROM clcommon__CollateralLien__c
      WHERE
        clcommon__Collateral__c IN :viewsByCollateralId.keySet()
        AND (clcommon__Status__c = NULL
        OR clcommon__Status__c != 'Satisfied')
      WITH USER_MODE
      ORDER BY clcommon__Lien_Position__c, CreatedDate
    ]) {
      LienView lien = new LienView();
      lien.id = lienRecord.Id;
      lien.name = lienRecord.Name;
      lien.holder = firstPopulated(
        new List<String>{
          lienRecord.clcommon__Bank_Name__c,
          lienRecord.genesis__Application__r?.genesis__Account__r?.Name,
          lienRecord.loan__Loan_Account__r?.Name,
          'Prior lien'
        }
      );
      lien.internalLien = lienRecord.clcommon__Internal__c;
      lien.amount = lienRecord.clcommon__Lien_Amount__c == null
        ? lienRecord.clcommon__Loan_Amount__c
        : lienRecord.clcommon__Lien_Amount__c;
      lien.position = lienRecord.clcommon__Lien_Position__c;
      lien.nature = lienRecord.clcommon__Lien_Nature__c;
      lien.status = lienRecord.clcommon__Status__c;
      lien.pledgeDate = lienRecord.clcommon__Pledge_Date__c;
      lien.applicationId = lienRecord.genesis__Application__c;
      lien.applicationName = lienRecord.genesis__Application__r?.Name;
      lien.loanAccountId = lienRecord.loan__Loan_Account__c;
      lien.loanAccountName = lienRecord.loan__Loan_Account__r?.Name;
      lien.kind = lien.applicationId != null
        ? 'APPLICATION'
        : (lien.loanAccountId != null ? 'CONTRACT' : 'EXTERNAL');

      for (
        CollateralView collateral : viewsByCollateralId.get(
          lienRecord.clcommon__Collateral__c
        )
      ) {
        collateral.liens.add(lien);
      }
    }
  }

  private static void applyApplications(
    Map<Id, List<CollateralView>> viewsByCollateralId
  ) {
    Set<String> collateralApplicationKeys = new Set<String>();
    for (genesis__Application_Collateral__c junction : [
      SELECT
        Id,
        genesis__Collateral__c,
        genesis__Application__c,
        genesis__Application__r.Name,
        genesis__Application__r.genesis__Status__c,
        genesis__Advance_Rate__c,
        genesis__Advance_Value__c
      FROM genesis__Application_Collateral__c
      WHERE
        genesis__Collateral__c IN :viewsByCollateralId.keySet()
        AND genesis__Application__c != NULL
        AND genesis__Active__c = TRUE
      WITH USER_MODE
      ORDER BY CreatedDate
    ]) {
      String collateralApplicationKey =
        junction.genesis__Collateral__c +
        ':' +
        junction.genesis__Application__c;
      if (!collateralApplicationKeys.add(collateralApplicationKey)) {
        continue;
      }

      ApplicationView application = new ApplicationView();
      application.junctionId = junction.Id;
      application.id = junction.genesis__Application__c;
      application.name = junction.genesis__Application__r.Name;
      application.status = junction.genesis__Application__r.genesis__Status__c;
      application.advanceRate = junction.genesis__Advance_Rate__c;
      application.advanceValue = junction.genesis__Advance_Value__c;
      for (
        CollateralView collateral : viewsByCollateralId.get(
          junction.genesis__Collateral__c
        )
      ) {
        collateral.applications.add(application);
        collateral.crossCollateralized = collateral.applications.size() > 1;
      }
    }
  }

  private static String firstPopulated(List<String> values) {
    for (String value : values) {
      if (!String.isBlank(value)) {
        return value;
      }
    }
    return null;
  }

  public class AccountCollateralView {
    @AuraEnabled
    public Id accountId { get; set; }
    @AuraEnabled
    public String accountName { get; set; }
    @AuraEnabled
    public List<CollateralView> collaterals { get; set; }

    public AccountCollateralView(Id accountId, String accountName) {
      this.accountId = accountId;
      this.accountName = accountName;
      this.collaterals = new List<CollateralView>();
    }
  }

  public class CollateralView {
    @AuraEnabled
    public Id ownerRecordId { get; set; }
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String type { get; set; }
    @AuraEnabled
    public Decimal ownershipPercentage { get; set; }
    @AuraEnabled
    public Decimal recordedValue { get; set; }
    @AuraEnabled
    public Date valueDate { get; set; }
    @AuraEnabled
    public Decimal appraisedValue { get; set; }
    @AuraEnabled
    public Date appraisalDate { get; set; }
    @AuraEnabled
    public String valuationType { get; set; }
    @AuraEnabled
    public Boolean crossCollateralized { get; set; }
    @AuraEnabled
    public List<LienView> liens { get; set; }
    @AuraEnabled
    public List<ApplicationView> applications { get; set; }

    public CollateralView() {
      crossCollateralized = false;
      liens = new List<LienView>();
      applications = new List<ApplicationView>();
    }
  }

  public class LienView {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String kind { get; set; }
    @AuraEnabled
    public String holder { get; set; }
    @AuraEnabled
    public Boolean internalLien { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
    @AuraEnabled
    public Decimal position { get; set; }
    @AuraEnabled
    public String nature { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public Date pledgeDate { get; set; }
    @AuraEnabled
    public Id applicationId { get; set; }
    @AuraEnabled
    public String applicationName { get; set; }
    @AuraEnabled
    public Id loanAccountId { get; set; }
    @AuraEnabled
    public String loanAccountName { get; set; }
  }

  public class ApplicationView {
    @AuraEnabled
    public Id junctionId { get; set; }
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public Decimal advanceRate { get; set; }
    @AuraEnabled
    public Decimal advanceValue { get; set; }
  }
}