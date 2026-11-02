import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import getCustomerSummary from '@salesforce/apex/Customer360Controller.getCustomerSummary';

export default class LoanList extends LightningElement {
    @api accountId; // Can be passed as property
    @api showSelection = false; // Whether to show radio buttons for selection
    @api selectionMode = 'single'; // 'single' or 'multiple'
    @api selectedLoanIds = []; // Array of selected loan IDs
    @api filterActiveOnly = false; // Filter to show only active loans (default false, set to true via attribute)
    
    @track loans = [];
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    // Get accountId from URL parameter if not passed as property
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            // Try multiple possible parameter names
            const urlAccountId = currentPageReference.state?.accountId || 
                                 currentPageReference.state?.c__accountId ||
                                 currentPageReference.attributes?.accountId;
            if (urlAccountId && !this.accountId) {
                this.accountId = urlAccountId;
                if (!this.isLoading) {
                    this.loadLoans();
                }
            }
        }
    }

    connectedCallback() {
        // Priority 1: Check sessionStorage (set by parent component)
        if (!this.accountId) {
            const sessionAccountId = sessionStorage.getItem('loanPaymentAccountId');
            if (sessionAccountId) {
                this.accountId = sessionAccountId;
                sessionStorage.removeItem('loanPaymentAccountId');
                console.log('loanList: AccountId from sessionStorage:', sessionAccountId);
            }
        }
        
        // Priority 2: Read accountId from URL immediately (before it gets cleared by Salesforce)
        if (!this.accountId) {
            // Try multiple ways to get accountId from URL
            const urlParams = new URLSearchParams(window.location.search);
            let urlAccountId = urlParams.get('accountId') || 
                              urlParams.get('c__accountId');
            
            // Also try reading from the full URL using regex (more reliable)
            if (!urlAccountId) {
                const fullUrl = window.location.href;
                const accountIdMatch = fullUrl.match(/[?&]accountId=([^&]+)/);
                if (accountIdMatch) {
                    urlAccountId = decodeURIComponent(accountIdMatch[1]);
                }
            }
            
            // Try the helper method as fallback
            if (!urlAccountId) {
                urlAccountId = this.getUrlParameter('accountId') || this.getUrlParameter('c__accountId');
            }
            
            if (urlAccountId) {
                this.accountId = urlAccountId;
                console.log('loanList: AccountId from URL:', urlAccountId);
            }
        }
        
        // Load loans if we have accountId
        if (this.accountId) {
            this.loadLoans();
        } else {
            // Wait a bit for CurrentPageReference or parent component to provide accountId
            setTimeout(() => {
                if (this.accountId) {
                    this.loadLoans();
                } else {
                    this.hasError = true;
                    this.errorMessage = 'Account ID is required. Please provide an account ID.';
                    this.isLoading = false;
                    console.error('loanList: No accountId found after timeout');
                }
            }, 300);
        }
    }

    loadLoans() {
        if (!this.accountId) {
            this.hasError = true;
            this.errorMessage = 'Account ID is required.';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.hasError = false;

        getCustomerSummary({ accountId: this.accountId })
            .then(result => {
                // Filter loans based on filterActiveOnly setting
                let filteredLoans = result.loans || [];
                
                if (this.filterActiveOnly) {
                    filteredLoans = filteredLoans.filter(loan => {
                        const status = loan.status || '';
                        return status && !status.startsWith('Closed');
                    });
                }

                // Format loans with display properties
                this.loans = filteredLoans.map(loan => ({
                    ...loan,
                    formattedBalance: this.formatCurrency(loan.principalRemaining || 0),
                    formattedNextDue: this.formatCurrency(loan.nextPaymentAmount || 0),
                    formattedRate: this.formatPercent(loan.interestRate || 0),
                    statusBadgeClass: this.getStatusBadgeClass(loan.status || ''),
                    isSelected: this.selectedLoanIds.includes(loan.loanAccountId)
                }));

                if (this.loans.length === 0) {
                    this.hasError = true;
                    this.errorMessage = this.filterActiveOnly 
                        ? 'No active loans found for this account.' 
                        : 'No loans found for this account.';
                }

                this.isLoading = false;
                
                // Dispatch event with loaded loans
                this.dispatchEvent(new CustomEvent('loansloaded', {
                    detail: { loans: this.loans, count: this.loans.length }
                }));
            })
            .catch(error => {
                console.error('Error loading loans:', error);
                this.hasError = true;
                this.errorMessage = error.body?.message || error.message || 'Failed to load loans.';
                this.isLoading = false;
                this.showError('Error', 'Failed to load loans: ' + this.errorMessage);
            });
    }

    handleLoanSelection(event) {
        const loanId = event.target.value;
        
        if (this.selectionMode === 'single') {
            // For single selection, replace the array
            this.selectedLoanIds = [loanId];
        } else {
            // Multiple selection
            const index = this.selectedLoanIds.indexOf(loanId);
            if (index > -1) {
                this.selectedLoanIds.splice(index, 1);
            } else {
                this.selectedLoanIds.push(loanId);
            }
        }

        // Update isSelected property for all loans
        this.loans = this.loans.map(loan => ({
            ...loan,
            isSelected: this.selectedLoanIds.includes(loan.loanAccountId)
        }));

        // Dispatch selection change event
        this.dispatchEvent(new CustomEvent('selectionchange', {
            detail: { 
                selectedLoanIds: [...this.selectedLoanIds], // Create a copy
                selectedLoans: this.loans.filter(loan => this.selectedLoanIds.includes(loan.loanAccountId))
            }
        }));
    }

    formatCurrency(value) {
        if (value == null) return '$0.00';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    formatPercent(value) {
        if (value == null) return '0%';
        return value.toFixed(2) + '%';
    }

    getStatusBadgeClass(status) {
        if (!status) return 'slds-badge';
        if (status.includes('Good Standing')) {
            return 'slds-badge status-badge-good-standing';
        } else if (status.includes('Bad Standing')) {
            return 'slds-badge status-badge-bad-standing';
        } else if (status.startsWith('Closed')) {
            return 'slds-badge status-badge-closed';
        }
        return 'slds-badge';
    }

    getUrlParameter(name) {
        const url = window.location.href;
        const regex = new RegExp('[?&]' + name + '(=([^&#]*)|&|#|$)');
        const results = regex.exec(url);
        if (!results) return null;
        if (!results[2]) return '';
        return decodeURIComponent(results[2].replace(/\+/g, ' '));
    }

    showError(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
        });
        this.dispatchEvent(evt);
    }

    get hasActiveLoans() {
        return this.loans && this.loans.length > 0;
    }

    get selectedLoans() {
        return this.loans.filter(loan => this.selectedLoanIds.includes(loan.loanAccountId));
    }

    get isSingleSelectionMode() {
        return this.selectionMode === 'single';
    }

    // Public method to get selected loans (can be called by parent)
    @api
    getSelectedLoans() {
        return this.selectedLoans;
    }

    // Public method to clear selection
    @api
    clearSelection() {
        this.selectedLoanIds = [];
        this.loans = this.loans.map(loan => ({
            ...loan,
            isSelected: false
        }));
    }
}