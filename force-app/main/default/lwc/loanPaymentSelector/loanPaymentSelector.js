import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import getLoanAccountFieldId from '@salesforce/apex/Customer360Controller.getLoanAccountFieldId';
import getRepaymentTransactionAdjustmentFieldId from '@salesforce/apex/Customer360Controller.getRepaymentTransactionAdjustmentFieldId';
import getPayoffQuoteLoanAccountFieldId from '@salesforce/apex/Customer360Controller.getPayoffQuoteLoanAccountFieldId';
import getOrgNamespacePrefix from '@salesforce/apex/Customer360Controller.getOrgNamespacePrefix';
import getRecentPaymentTransactions from '@salesforce/apex/Customer360Controller.getRecentPaymentTransactions';
import getUnpaidCharges from '@salesforce/apex/Customer360Controller.getUnpaidCharges';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/Account.Name';

const FIELDS = [ACCOUNT_NAME_FIELD];

export default class LoanPaymentSelector extends NavigationMixin(LightningElement) {
    @api accountId; // Can be passed as property or from FlexiPage
    @track internalAccountId = null;
    @track selectedLoan = null;
    @track accountName = '';
    @track loanAccountFieldId = null;
    @track repaymentTransactionAdjustmentFieldId = null;
    @track payoffQuoteLoanAccountFieldId = null;
    @track orgNamespacePrefix = null;
    @track action = 'takePayment'; // Default action: 'takePayment', 'reversePayment', 'waiveFee', 'promiseToPay', 'generatePayoffQuote', or 'changeDueDay'
    @track paymentTransactions = [];
    @track selectedTransaction = null;
    @track isLoadingTransactions = false;
    @track showTransactions = false;
    @track charges = [];
    @track isLoadingCharges = false;
    @track showCharges = false;

    // Get account record to display account name
    @wire(getRecord, { recordId: '$effectiveAccountId', fields: FIELDS })
    wiredAccount({ error, data }) {
        if (data) {
            this.accountName = data.fields.Name.value;
        } else if (error) {
            this.accountName = '';
        }
    }

    // Get accountId from URL using NavigationMixin
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            const urlAccountId = currentPageReference.state?.accountId ||
                                currentPageReference.state?.c__accountId ||
                                currentPageReference.attributes?.accountId;
            if (urlAccountId && !this.effectiveAccountId) {
                this.internalAccountId = urlAccountId;
            }

            const urlAction = currentPageReference.state?.action ||
                              currentPageReference.state?.c__action;
            if (urlAction) {
                this.action = urlAction;
            }
        }
    }

    connectedCallback() {
        // Load org-specific Visualforce configuration dynamically.
        this.configurationPromise = this.loadConfiguration();

        // Priority 1: Check sessionStorage first (set by parent component - most reliable)
        if (!this.effectiveAccountId) {
            const sessionAccountId = sessionStorage.getItem('loanPaymentAccountId');
            if (sessionAccountId) {
                this.internalAccountId = sessionAccountId;
                // Clear it after reading
                sessionStorage.removeItem('loanPaymentAccountId');
            }
        }

        // Get action from sessionStorage
        const sessionAction = sessionStorage.getItem('loanAction');
        if (sessionAction) {
            this.action = sessionAction;
            sessionStorage.removeItem('loanAction');
        }

        // Priority 2: Read accountId and action from URL immediately (before it gets cleared)
        if (!this.effectiveAccountId) {
            // Try multiple ways to get accountId from URL
            const urlParams = new URLSearchParams(window.location.search);
            let urlAccountId = urlParams.get('accountId') ||
                              urlParams.get('c__accountId');

            // Also try reading from the full URL using regex (before Salesforce clears it)
            if (!urlAccountId) {
                const fullUrl = window.location.href;
                const accountIdMatch = fullUrl.match(/[?&]accountId=([^&]+)/);
                if (accountIdMatch) {
                    urlAccountId = decodeURIComponent(accountIdMatch[1]);
                }
            }

            if (urlAccountId) {
                this.internalAccountId = urlAccountId;
            }
        }

        // Get action from URL if not already set
        if (this.action === 'takePayment') {
            const urlParams = new URLSearchParams(window.location.search);
            const urlAction = urlParams.get('action') ||
                              urlParams.get('c__action');
            if (urlAction) {
                this.action = urlAction;
            }
        }
    }

    loadConfiguration() {
        return this.loadOrgNamespacePrefix();
    }

    loadOrgNamespacePrefix() {
        return getOrgNamespacePrefix()
            .then(result => {
                this.orgNamespacePrefix = result || null;
            })
            .catch(() => {
                this.orgNamespacePrefix = null;
            });
    }

    async ensureConfigurationLoaded() {
        if (this.configurationPromise) {
            await this.configurationPromise;
        }
    }

    handleSelectionChange(event) {
        const selectedLoans = event.detail.selectedLoans;
        const previousLoanId = this.selectedLoan ? this.selectedLoan.loanAccountId : null;

        if (selectedLoans && selectedLoans.length > 0) {
            const newSelectedLoan = selectedLoans[0]; // For single selection
            const newLoanId = newSelectedLoan.loanAccountId;

            // If a different loan is selected, reset the transaction/charge list
            if (previousLoanId !== newLoanId) {
                this.resetTransactionList();
                this.resetChargeList();
            }

            this.selectedLoan = newSelectedLoan;
        } else {
            this.selectedLoan = null;
            // If loan selection is cleared, also reset transaction/charge list
            this.resetTransactionList();
            this.resetChargeList();
        }
    }

    resetTransactionList() {
        // Hide the transaction list
        this.showTransactions = false;
        // Clear transactions
        this.paymentTransactions = [];
        // Clear selected transaction
        this.selectedTransaction = null;
        // Reset loading state
        this.isLoadingTransactions = false;
    }

    resetChargeList() {
        // Hide the charge list
        this.showCharges = false;
        // Clear charges
        this.charges = [];
        // Reset loading state
        this.isLoadingCharges = false;
    }

    getSalesforceBaseUrl() {
        const host = window.location.hostname || '';
        const lightningDomain = '.lightning.force.com';
        if (host.endsWith(lightningDomain)) {
            return `https://${host.slice(0, -lightningDomain.length)}.my.salesforce.com`;
        }

        return window.location.origin;
    }

    getVisualforcePageName(pageName) {
        return this.orgNamespacePrefix ? `${this.orgNamespacePrefix}__${pageName}` : pageName;
    }

    getVisualforcePageUrl(pageName, params = {}) {
        const url = new URL(`${this.getSalesforceBaseUrl()}/apex/${this.getVisualforcePageName(pageName)}`);
        Object.entries(params).forEach(([key, value]) => {
            if (value !== undefined && value !== null) {
                url.searchParams.set(key, value);
            }
        });
        return url.toString();
    }

    getObjectApiName(apiName) {
        return this.orgNamespacePrefix ? `${this.orgNamespacePrefix}__${apiName}` : apiName;
    }

    async loadRequiredFieldId(apexMethod, propertyName, fieldLabel) {
        if (this[propertyName]) {
            return this[propertyName];
        }

        try {
            this[propertyName] = await apexMethod();
        } catch (error) {
            this.showError('Configuration Error', this.getConfigurationErrorMessage(fieldLabel, error));
            return null;
        }

        if (!this[propertyName]) {
            this.showError(
                'Configuration Error',
                `${fieldLabel} field ID could not be resolved. Verify FieldDefinition access in this org and refresh the page.`
            );
            return null;
        }

        return this[propertyName];
    }

    getConfigurationErrorMessage(fieldLabel, error) {
        const message = error?.body?.message || error?.message;
        const suffix = message ? ` ${message}` : '';
        return `${fieldLabel} field ID could not be resolved.${suffix}`;
    }

    async handlePay() {
        if (!this.selectedLoan) {
            this.showError('Selection Required', 'Please select a loan to make a payment.');
            return;
        }
        await this.ensureConfigurationLoaded();

        // Construct the payment URL in the correct format
        const baseUrl = window.location.origin;
        const loanId = this.selectedLoan.loanId || ''; // Format: LAI-00000007
        const loanAccountId = this.selectedLoan.loanAccountId || ''; // Salesforce ID

        // Build the Visualforce page URL with loan parameters
        // Use the dynamically loaded field ID (org-specific)
        const fieldId = await this.loadRequiredFieldId(getLoanAccountFieldId, 'loanAccountFieldId', 'Loan Account');
        if (!fieldId) {
            return;
        }
        const vfPageUrl = this.getVisualforcePageUrl('regularPayment', {
            [fieldId]: loanId,
            [`${fieldId}_lkid`]: loanAccountId
        });

        // Build the final Lightning page URL with originalUrl parameter
        const loanPaymentTransactionObjectApiName = this.getObjectApiName('Loan_Payment_Transaction__c');
        const paymentUrl = `${baseUrl}/lightning/o/${loanPaymentTransactionObjectApiName}/new?` +
            `originalUrl=${encodeURIComponent(vfPageUrl)}`;

        // Open payment page in new tab
        window.open(paymentUrl, '_blank');
    }

    handleListPaymentTransaction() {
        if (!this.selectedLoan) {
            this.showError('Selection Required', 'Please select a loan to view payment transactions.');
            return;
        }

        const loanAccountId = this.selectedLoan.loanAccountId || '';

        if (!loanAccountId) {
            this.showError('Invalid Loan', 'Loan Account ID is missing.');
            return;
        }

        // Fetch payment transactions for the selected loan
        this.isLoadingTransactions = true;
        this.showTransactions = true;
        this.selectedTransaction = null; // Reset selection

        getRecentPaymentTransactions({ loanAccountId: loanAccountId })
            .then(result => {
                this.paymentTransactions = result || [];
                this.isLoadingTransactions = false;

                // No need to show toast here - the UI will display the message
            })
            .catch(error => {
                this.isLoadingTransactions = false;
                this.paymentTransactions = []; // Clear transactions on error
                this.showError('Error', 'Failed to load payment transactions: ' + (error.body?.message || error.message));
            });
    }

    handleTransactionSelection(event) {
        const transactionId = event.target.value;
        this.selectedTransaction = this.paymentTransactions.find(txn => txn.id === transactionId) || null;
    }

    handleListCharges() {
        if (!this.selectedLoan) {
            this.showError('Selection Required', 'Please select a loan to view charges.');
            return;
        }

        const loanAccountId = this.selectedLoan.loanAccountId || '';

        if (!loanAccountId) {
            this.showError('Invalid Loan', 'Loan Account ID is missing.');
            return;
        }

        // Fetch unpaid charges for the selected loan
        this.isLoadingCharges = true;
        this.showCharges = true;

        getUnpaidCharges({ loanAccountId: loanAccountId })
            .then(result => {
                this.charges = result || [];
                this.isLoadingCharges = false;
            })
            .catch(error => {
                this.isLoadingCharges = false;
                this.charges = []; // Clear charges on error
                this.showError('Error', 'Failed to load charges: ' + (error.body?.message || error.message));
            });
    }

    async handleWaiveFee() {
        if (!this.selectedLoan) {
            this.showError('Selection Required', 'Please select a loan to waive fees.');
            return;
        }
        await this.ensureConfigurationLoaded();

        // Construct the waive fee URL to open the Visualforce page
        const loanAccountId = this.selectedLoan.loanAccountId || ''; // Salesforce ID of the loan account

        if (!loanAccountId) {
            this.showError('Invalid Loan', 'Loan Account ID is missing.');
            return;
        }

        // Build the Visualforce page URL with Loan Account ID
        // The page uses standardController="Loan_Account__c", so we pass the Loan Account ID as 'id' parameter
        // Pass modal=false to ensure it opens as a full page, not a modal
        const vfPageUrl = this.getVisualforcePageUrl('waiver', {
            id: loanAccountId,
            modal: 'false'
        });

        // Open the Visualforce page directly in a new tab (full page, not modal)
        window.open(vfPageUrl, '_blank');
    }

    async handlePromiseToPay() {
        if (!this.selectedLoan) {
            this.showError('Selection Required', 'Please select a loan to setup promise to pay.');
            return;
        }
        await this.ensureConfigurationLoaded();

        // Construct the Promise to Pay URL to open the Automated Payment Setup creation page
        const baseUrl = window.location.origin;
        const loanAccountId = this.selectedLoan.loanAccountId || ''; // Salesforce ID of the loan account

        if (!loanAccountId) {
            this.showError('Invalid Loan', 'Loan Account ID is missing.');
            return;
        }

        // For Lightning record creation pages, use defaultFieldValues parameter
        // Format: defaultFieldValues=fieldApiName%3DrecordId (URL encoded)
        // The format is: fieldApiName=recordId (encoded as fieldApiName%3DrecordId)
        const automatedPaymentSetupObjectApiName = this.getObjectApiName('Automated_Payment_Setup__c');
        const clContractFieldApiName = this.getObjectApiName('CL_Contract__c');
        const defaultFieldValue = `${clContractFieldApiName}=${loanAccountId}`;
        const encodedFieldValue = encodeURIComponent(defaultFieldValue);

        // Build URL with defaultFieldValues parameter
        // IMPORTANT: Do NOT include navigationLocation, inContextOfRef, or backgroundContext
        // These parameters cause modal behavior. Use only defaultFieldValues to open as full page.
        const promiseToPayUrl = `${baseUrl}/lightning/o/${automatedPaymentSetupObjectApiName}/new?defaultFieldValues=${encodedFieldValue}`;

        // Open in new tab as full page (not modal)
        // The simple URL without context parameters will open as a full page
        window.open(promiseToPayUrl, '_blank');
    }

    async handleGeneratePayoffQuote() {
        if (!this.selectedLoan) {
            this.showError('Selection Required', 'Please select a loan to generate a payoff quote.');
            return;
        }
        await this.ensureConfigurationLoaded();

        // Construct the Payoff Quote URL similar to payment URL
        const baseUrl = window.location.origin;
        const loanId = this.selectedLoan.loanId || ''; // Format: LAI-00000007
        const loanAccountId = this.selectedLoan.loanAccountId || ''; // Salesforce ID

        // Build the Visualforce page URL with loan parameters
        // Use the dynamically loaded field ID (org-specific)
        const fieldId = await this.loadRequiredFieldId(
            getPayoffQuoteLoanAccountFieldId,
            'payoffQuoteLoanAccountFieldId',
            'Payoff Quote Loan Account'
        );
        if (!fieldId) {
            return;
        }
        const vfPageUrl = this.getVisualforcePageUrl('payOffQuoteNew', {
            [fieldId]: loanId,
            [`${fieldId}_lkid`]: loanAccountId
        });

        // Build the final Lightning page URL with originalUrl parameter
        const payoffQuoteObjectApiName = this.getObjectApiName('Payoff_Quote__c');
        const payoffQuoteUrl = `${baseUrl}/lightning/o/${payoffQuoteObjectApiName}/new?` +
            `originalUrl=${encodeURIComponent(vfPageUrl)}`;

        // Open payoff quote page in new tab
        window.open(payoffQuoteUrl, '_blank');
    }

    async handleChangeDueDay() {
        if (!this.selectedLoan) {
            this.showError('Selection Required', 'Please select a loan to change due day.');
            return;
        }
        await this.ensureConfigurationLoaded();

        // Construct the Change Due Day URL
        const loanAccountId = this.selectedLoan.loanAccountId || ''; // Salesforce ID

        if (!loanAccountId) {
            this.showError('Invalid Loan', 'Loan Account ID is missing.');
            return;
        }

        // Build the Visualforce page URL
        // The page uses standardController="Loan_Account__c", so passing id parameter will automatically
        // load the loan account record and pre-populate:
        // - CL Contract ID (loanAccount.Name)
        // - Transaction Date (dueDayChange.Txn_Date__c - set in initialize)
        // - Current Due Day (loanAccount.Due_Day__c)
        // - Payment Frequency (loanAccount.Frequency_of_Loan_Payment__c)
        // Format: /apex/dueDayChange?scontrolCaching=1&id={loanAccountId}&modal=true
        const vfPageUrl = this.getVisualforcePageUrl('dueDayChange', {
            scontrolCaching: '1',
            id: loanAccountId,
            modal: 'true'
        });

        // Open the Visualforce page directly in a new tab
        // The standard controller will automatically load the Loan_Account__c record with the provided ID
        // and the controller's initialize() method will set up all the fields
        window.open(vfPageUrl, '_blank');
    }

    async handleReversePayment() {
        if (!this.selectedTransaction) {
            this.showError('Selection Required', 'Please select a payment transaction to reverse.');
            return;
        }
        await this.ensureConfigurationLoaded();

        // Construct the reversal URL in the correct format
        const baseUrl = window.location.origin;
        const transactionId = this.selectedTransaction.transactionId || ''; // Format: LPT-000000002
        const transactionSalesforceId = this.selectedTransaction.id || ''; // Salesforce ID (15 or 18 char)

        // Build the Visualforce page URL with transaction parameters
        // Use the dynamically loaded field ID (org-specific)
        const fieldId = await this.loadRequiredFieldId(
            getRepaymentTransactionAdjustmentFieldId,
            'repaymentTransactionAdjustmentFieldId',
            'Repayment Transaction Adjustment'
        );
        if (!fieldId) {
            return;
        }
        const loanPaymentTransactionObjectApiName = this.getObjectApiName('Loan_Payment_Transaction__c');
        const repaymentTransactionAdjustmentObjectApiName = this.getObjectApiName('Repayment_Transaction_Adjustment__c');
        const saveNewUrlParams = new URLSearchParams({
            [fieldId]: transactionId,
            [`${fieldId}_lkid`]: transactionSalesforceId
        });
        const vfPageUrl = this.getVisualforcePageUrl('repaymentReversal', {
            [fieldId]: transactionId,
            [`${fieldId}_lkid`]: transactionSalesforceId,
            sObjectName: repaymentTransactionAdjustmentObjectApiName,
            save_new_url: `/aFc/e?${saveNewUrlParams.toString()}`,
            navigationLocation: 'RELATED_LIST',
            lexiSObjectName: repaymentTransactionAdjustmentObjectApiName,
            lexiActionName: 'new',
            'sfdc.override': '1'
        });

        // Build the inContextOfRef parameter (base64 encoded JSON)
        // This provides context about the parent record (Loan Payment Transaction)
        const contextRef = {
            type: 'standard__recordPage',
            attributes: {
                objectApiName: loanPaymentTransactionObjectApiName,
                recordId: transactionSalesforceId,
                actionName: 'view'
            },
            state: {}
        };
        const contextRefEncoded = btoa(JSON.stringify(contextRef));

        // Build the final Lightning page URL with originalUrl and inContextOfRef parameters
        const reversalUrl = `${baseUrl}/lightning/o/${repaymentTransactionAdjustmentObjectApiName}/new?` +
            `originalUrl=${encodeURIComponent(vfPageUrl)}&` +
            `inContextOfRef=1.${contextRefEncoded}&` +
            `count=1`;

        // Open reversal page in new tab
        window.open(reversalUrl, '_blank');
    }

    showError(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
        });
        this.dispatchEvent(evt);
    }

    showInfo(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'info',
        });
        this.dispatchEvent(evt);
    }

    formatCurrency(value) {
        if (value == null) return '$0.00';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    formatDate(dateValue) {
        if (!dateValue) return '';

        const rawDate = String(dateValue);
        const dateOnlyMatch = rawDate.match(/^(\d{4})-(\d{2})-(\d{2})(?:$|T|\s)/);
        if (dateOnlyMatch) {
            const year = Number(dateOnlyMatch[1]);
            const month = Number(dateOnlyMatch[2]) - 1;
            const day = Number(dateOnlyMatch[3]);
            return this.formatDateObject(new Date(year, month, day));
        }

        const date = new Date(dateValue);
        if (Number.isNaN(date.getTime())) {
            return rawDate;
        }

        return this.formatDateObject(date);
    }

    formatDateObject(date) {
        return date.toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        });
    }

    get isPayDisabled() {
        return !this.selectedLoan;
    }

    get isPromiseToPayDisabled() {
        return !this.selectedLoan;
    }

    get isListPaymentTransactionDisabled() {
        return !this.selectedLoan;
    }

    get isGeneratePayoffQuoteDisabled() {
        return !this.selectedLoan;
    }

    get isChangeDueDayDisabled() {
        return !this.selectedLoan;
    }

    get isTakePaymentAction() {
        return this.action === 'takePayment';
    }

    get isReversePaymentAction() {
        return this.action === 'reversePayment';
    }

    get isWaiveFeeAction() {
        return this.action === 'waiveFee';
    }

    get isPromiseToPayAction() {
        return this.action === 'promiseToPay';
    }

    get isGeneratePayoffQuoteAction() {
        return this.action === 'generatePayoffQuote';
    }

    get isChangeDueDayAction() {
        return this.action === 'changeDueDay';
    }

    get actionButtonLabel() {
        if (this.isReversePaymentAction) {
            return 'List Payment Transaction';
        } else if (this.isWaiveFeeAction) {
            return 'List Charges';
        } else if (this.isPromiseToPayAction) {
            return 'Setup Promise to Pay ACH';
        } else if (this.isGeneratePayoffQuoteAction) {
            return 'Generate Payoff Quote';
        } else if (this.isChangeDueDayAction) {
            return 'Change Due Day';
        } else {
            return 'Pay';
        }
    }

    get cardTitle() {
        if (this.isReversePaymentAction) {
            return 'Select Loan for Reverse Payment';
        } else if (this.isWaiveFeeAction) {
            return 'Select Loan to Waive Fee';
        } else if (this.isPromiseToPayAction) {
            return 'Select Loan for Promise to Pay';
        } else if (this.isGeneratePayoffQuoteAction) {
            return 'Select Loan for Payoff Quote';
        } else if (this.isChangeDueDayAction) {
            return 'Select Loan to Change Due Day';
        } else {
            return 'Select Loan for Payment';
        }
    }

    get cardIcon() {
        if (this.isReversePaymentAction) {
            return 'utility:undo';
        } else if (this.isWaiveFeeAction) {
            return 'utility:ban';
        } else if (this.isPromiseToPayAction) {
            return 'utility:date_time';
        } else if (this.isGeneratePayoffQuoteAction) {
            return 'utility:file';
        } else if (this.isChangeDueDayAction) {
            return 'utility:date_input';
        } else {
            return 'utility:money';
        }
    }

    get instructionText() {
        if (this.isReversePaymentAction) {
            return 'Please select a loan to view payment transactions:';
        } else if (this.isWaiveFeeAction) {
            return 'Please select a loan to view unpaid charges:';
        } else if (this.isPromiseToPayAction) {
            return 'Please select a loan to setup promise to pay ACH:';
        } else if (this.isGeneratePayoffQuoteAction) {
            return 'Please select a loan to generate a payoff quote:';
        } else if (this.isChangeDueDayAction) {
            return 'Please select a loan to change due day:';
        } else {
            return 'Please select a loan to make a payment:';
        }
    }

    get effectiveAccountId() {
        return this.internalAccountId || this.accountId;
    }

    get hasAccountId() {
        return !!this.effectiveAccountId;
    }

    get isReversePaymentDisabled() {
        return !this.selectedTransaction;
    }

    get hasTransactions() {
        return this.paymentTransactions && this.paymentTransactions.length > 0;
    }

    get isListChargesDisabled() {
        return !this.selectedLoan || this.showCharges;
    }

    get isWaiveFeeDisabled() {
        return !this.selectedLoan;
    }

    get hasCharges() {
        return this.charges && this.charges.length > 0;
    }

    get formattedCharges() {
        return this.charges.map(charge => ({
            ...charge,
            formattedTotalAmountDue: this.formatCurrency(charge.totalAmountDue),
            formattedPaidAmount: this.formatCurrency(charge.paidAmount),
            formattedChargeDate: this.formatDate(charge.chargeDate),
            formattedCreatedDate: this.formatDate(charge.createdDate),
            paidText: charge.paid ? 'Yes' : 'No',
            waivedText: charge.waived ? 'Yes' : 'No'
        }));
    }

    get formattedTransactions() {
        return this.paymentTransactions.map(txn => ({
            ...txn,
            formattedTransactionAmount: this.formatCurrency(txn.transactionAmount),
            formattedPrincipal: this.formatCurrency(txn.principal),
            formattedInterest: this.formatCurrency(txn.interest),
            formattedFees: this.formatCurrency(txn.fees),
            formattedExcess: this.formatCurrency(txn.excess),
            formattedTransactionDate: this.formatDate(txn.transactionDate),
            clearedText: txn.cleared ? 'Yes' : 'No',
            reversedText: txn.reversed ? 'Yes' : 'No',
            isSelected: this.isTransactionSelected(txn.id)
        }));
    }

    isTransactionSelected(transactionId) {
        return this.selectedTransaction && this.selectedTransaction.id === transactionId;
    }
}
