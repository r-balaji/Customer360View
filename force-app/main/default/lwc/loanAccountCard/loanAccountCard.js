import { LightningElement, api, track } from 'lwc';
import getLoanDetails from '@salesforce/apex/Customer360Controller.getLoanDetails';

export default class LoanAccountCard extends LightningElement {
    @api loanData;
    @track isExpanded = false;
    @track loanDetails;
    @track isLoading = false;
    @track activeTab = 'overview';

    get statusBadgeClass() {
        if (this.loanData?.status === 'Active - Good Standing') {
            return 'slds-badge status-badge-good-standing';
        } else if (this.loanData?.status === 'Active - Bad Standing') {
            return 'slds-badge status-badge-bad-standing';
        } else if (this.loanData?.status && this.loanData.status.startsWith('Closed')) {
            return 'slds-badge slds-badge_inverse';
        }
        return 'slds-badge';
    }

    get statusBadgeClassWithMargin() {
        return this.statusBadgeClass + ' slds-m-left_small';
    }

    // Getter for loan record URL
    get loanRecordUrl() {
        if (this.loanData?.loanAccountId) {
            const baseUrl = window.location.origin;
            return `${baseUrl}/lightning/r/Loan_Account__c/${this.loanData.loanAccountId}/view`;
        }
        return '#';
    }

    // Navigate to loan record page in new tab
    navigateToLoan(event) {
        event.preventDefault();
        if (this.loanData?.loanAccountId) {
            const baseUrl = window.location.origin;
            const recordUrl = `${baseUrl}/lightning/r/Loan_Account__c/${this.loanData.loanAccountId}/view`;
            window.open(recordUrl, '_blank');
        }
    }

    get standingBadgeClass() {
        if (this.loanData.standing === 'Good Standing') {
            return 'slds-badge slds-badge_success';
        } else if (this.loanData.standing === 'Bad Standing') {
            return 'slds-badge slds-badge_warning';
        }
        return 'slds-badge';
    }

    get progressPercentage() {
        if (this.loanData.loanAmount && this.loanData.principalRemaining) {
            const paid = this.loanData.loanAmount - this.loanData.principalRemaining;
            return ((paid / this.loanData.loanAmount) * 100).toFixed(1);
        }
        return 0;
    }

    get progressBarStyle() {
        return `width: ${this.progressPercentage}%`;
    }

    // Getters for formatted values (LWC templates don't allow function calls)
    get formattedLoanAmount() {
        if (this.loanData?.loanAmount == null) return '$0.00';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(this.loanData.loanAmount);
    }

    get formattedPrincipalRemaining() {
        if (this.loanData?.principalRemaining == null) return '$0.00';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(this.loanData.principalRemaining);
    }

    get formattedLoanEffectiveDate() {
        return this.formatDate(this.loanData?.loanEffectiveDate);
    }

    get formattedNextPaymentDate() {
        return this.formatDate(this.loanData?.nextPaymentDate);
    }

    handleToggleExpand() {
        this.isExpanded = !this.isExpanded;
        
        if (this.isExpanded && !this.loanDetails) {
            this.loadLoanDetails();
        }
        
        // Dispatch event to parent
        this.dispatchEvent(new CustomEvent('loanexpand', {
            detail: {
                loanId: this.loanData.loanId,
                isExpanded: this.isExpanded
            }
        }));
    }

    loadLoanDetails() {
        if (!this.loanData.loanAccountId) {
            return;
        }

        this.isLoading = true;
        
        getLoanDetails({ loanAccountId: this.loanData.loanAccountId })
            .then(result => {
                // Format the data to avoid function calls in templates
                this.loanDetails = this.formatLoanDetails(result);
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading loan details:', error);
                this.isLoading = false;
            });
    }

    handleTabChange(event) {
        this.activeTab = event.detail.tab;
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

    formatLoanDetails(details) {
        if (!details) return null;
        
        // Deep clone to avoid mutating original
        const formatted = JSON.parse(JSON.stringify(details));
        
        // Format overview dates and currency
        if (formatted.overview) {
            formatted.overview.formattedLoanEffectiveDate = this.formatDate(formatted.overview.loanEffectiveDate);
            formatted.overview.formattedMaturityDate = this.formatDate(formatted.overview.maturityDate);
            formatted.overview.formattedClosedDate = this.formatDate(formatted.overview.closedDate);
            formatted.overview.formattedNextPaymentDate = this.formatDate(formatted.overview.nextPaymentDate);
            formatted.overview.formattedLoanAmount = this.formatCurrency(formatted.overview.loanAmount);
            formatted.overview.formattedPrincipalRemaining = this.formatCurrency(formatted.overview.principalRemaining);
            formatted.overview.formattedInterestRemaining = this.formatCurrency(formatted.overview.interestRemaining);
            formatted.overview.formattedFeesRemaining = this.formatCurrency(formatted.overview.feesRemaining);
            formatted.overview.formattedTotalOutstanding = this.formatCurrency(formatted.overview.totalOutstanding);
            formatted.overview.formattedTotalPaidToDate = this.formatCurrency(formatted.overview.totalPaidToDate);
            formatted.overview.formattedNextPaymentAmount = this.formatCurrency(formatted.overview.nextPaymentAmount);
        }
        
        // Format payment schedule installments
        if (formatted.paymentSchedule && formatted.paymentSchedule.installments) {
            formatted.paymentSchedule.installments = formatted.paymentSchedule.installments.map(inst => ({
                ...inst,
                formattedDueDate: this.formatDate(inst.dueDate),
                formattedPaidDate: this.formatDate(inst.paidDate),
                formattedPrincipalDue: this.formatCurrency(inst.principalDue),
                formattedInterestDue: this.formatCurrency(inst.interestDue),
                formattedFeesDue: this.formatCurrency(inst.feesDue),
                formattedTotalDue: this.formatCurrency(inst.totalDue),
                formattedAmountPaid: this.formatCurrency(inst.amountPaid),
                statusBadgeClass: this.getStatusBadgeClass(inst.status)
            }));
        }
        
        // Format transactions
        if (formatted.transactions && formatted.transactions.transactions) {
            formatted.transactions.formattedTotalAmount = this.formatCurrency(formatted.transactions.totalAmount);
            formatted.transactions.transactions = formatted.transactions.transactions.map(trans => ({
                ...trans,
                formattedTransactionDate: this.formatDate(trans.transactionDate),
                formattedAmount: this.formatCurrency(trans.amount),
                formattedPrincipalApplied: this.formatCurrency(trans.principalApplied),
                formattedInterestApplied: this.formatCurrency(trans.interestApplied),
                formattedFeesApplied: this.formatCurrency(trans.feesApplied)
            }));
        }
        
        // Format dues and charges
        if (formatted.duesAndCharges) {
            // Format bills
            if (formatted.duesAndCharges.bills && Array.isArray(formatted.duesAndCharges.bills)) {
                formatted.duesAndCharges.bills = formatted.duesAndCharges.bills.map(bill => ({
                    ...bill,
                    formattedDueDate: this.formatDate(bill.dueDate),
                    formattedDueAmount: this.formatCurrency(bill.dueAmount),
                    formattedPrincipalBilled: this.formatCurrency(bill.principalBilled),
                    formattedInterestBilled: this.formatCurrency(bill.interestBilled),
                    formattedFeesBilled: this.formatCurrency(bill.feesBilled),
                    formattedPrincipalDue: this.formatCurrency(bill.principalDue),
                    formattedInterestDue: this.formatCurrency(bill.interestDue),
                    formattedFeesDue: this.formatCurrency(bill.feesDue),
                    formattedPrincipalPaid: this.formatCurrency(bill.principalPaid),
                    formattedInterestPaid: this.formatCurrency(bill.interestPaid),
                    formattedFeesPaid: this.formatCurrency(bill.feesPaid)
                }));
            }
            
            // Format charges
            if (formatted.duesAndCharges.charges && Array.isArray(formatted.duesAndCharges.charges)) {
                formatted.duesAndCharges.charges = formatted.duesAndCharges.charges.map(charge => ({
                    ...charge,
                    formattedAmount: this.formatCurrency(charge.amount),
                    formattedChargeDate: this.formatDate(charge.chargeDate)
                }));
            }
            
            // Format pending schedule
            if (formatted.duesAndCharges.pendingSchedule && Array.isArray(formatted.duesAndCharges.pendingSchedule)) {
                formatted.duesAndCharges.pendingSchedule = formatted.duesAndCharges.pendingSchedule.map(pending => ({
                    ...pending,
                    formattedDueDate: this.formatDate(pending.dueDate),
                    formattedPrincipalDue: this.formatCurrency(pending.principalDue),
                    formattedInterestDue: this.formatCurrency(pending.interestDue),
                    formattedFeesDue: this.formatCurrency(pending.feesDue),
                    formattedTotalDue: this.formatCurrency(pending.totalDue)
                }));
            }
            
            // Format summary
            if (formatted.duesAndCharges.summary) {
                formatted.duesAndCharges.summary.formattedTotalBilledAmount = this.formatCurrency(formatted.duesAndCharges.summary.totalBilledAmount || 0);
                formatted.duesAndCharges.summary.formattedTotalChargesAmount = this.formatCurrency(formatted.duesAndCharges.summary.totalChargesAmount || 0);
                formatted.duesAndCharges.summary.formattedTotalPendingAmount = this.formatCurrency(formatted.duesAndCharges.summary.totalPendingAmount || 0);
            }
        }
        
        return formatted;
    }

    getStatusBadgeClass(status) {
        if (status === 'Paid') {
            return 'slds-badge slds-badge_success';
        } else if (status === 'Past Due') {
            return 'slds-badge slds-badge_warning';
        }
        return 'slds-badge';
    }
}