import { LightningElement, api } from 'lwc';

export default class LoanDetailsPanel extends LightningElement {
    @api loanDetails;
    @api activeTab = 'overview';

    get overview() {
        return this.loanDetails?.overview;
    }

    get paymentSchedule() {
        return this.loanDetails?.paymentSchedule;
    }

    get transactions() {
        return this.loanDetails?.transactions;
    }

    get duesAndCharges() {
        return this.loanDetails?.duesAndCharges;
    }

    get bills() {
        if (this.duesAndCharges && this.duesAndCharges.bills && Array.isArray(this.duesAndCharges.bills)) {
            return this.duesAndCharges.bills.map(bill => ({
                ...bill,
                statusBadgeClass: this.getBillStatusBadgeClass(bill.status),
                formattedIsPrimary: bill.isPrimary ? 'Yes' : 'No'
            }));
        }
        return [];
    }

    get hasBills() {
        return this.bills && this.bills.length > 0;
    }

    get charges() {
        if (this.duesAndCharges && this.duesAndCharges.charges && Array.isArray(this.duesAndCharges.charges)) {
            return this.duesAndCharges.charges.map(charge => ({
                ...charge,
                displayChargeName: charge.chargeName || '-',
                displayChargeType: charge.chargeType || '-',
                displayChargeDate: charge.formattedChargeDate || charge.chargeDate || '-',
                displayBillName: charge.billName || '-',
                displayStatus: charge.status || '-',
                displayDescription: charge.description || '-'
            }));
        }
        return [];
    }

    get hasCharges() {
        return this.charges && this.charges.length > 0;
    }

    handleTabClick(event) {
        const tab = event.currentTarget.dataset.tab;
        this.dispatchEvent(new CustomEvent('tabchange', {
            detail: { tab }
        }));
    }

    // Formatting methods removed - data is now pre-formatted in loanAccountCard component

    get isOverviewActive() {
        return this.activeTab === 'overview';
    }

    get isBillsActive() {
        return this.activeTab === 'bills';
    }

    get isChargesActive() {
        return this.activeTab === 'charges';
    }

    get isScheduleActive() {
        return this.activeTab === 'schedule';
    }

    get isTransactionsActive() {
        return this.activeTab === 'transactions';
    }

    get pendingSchedule() {
        return this.duesAndCharges?.pendingSchedule || [];
    }

    get hasPendingSchedule() {
        return this.pendingSchedule && this.pendingSchedule.length > 0;
    }

    get isDuesActive() {
        return this.activeTab === 'dues';
    }

    get scheduleInstallments() {
        return this.paymentSchedule?.installments || [];
    }

    get hasScheduleInstallments() {
        return this.scheduleInstallments && this.scheduleInstallments.length > 0;
    }

    get overviewTabClass() {
        const baseClass = 'slds-tabs_default__link';
        return this.activeTab === 'overview' ? `${baseClass} slds-is-active` : baseClass;
    }

    get billsTabClass() {
        const baseClass = 'slds-tabs_default__link';
        return this.activeTab === 'bills' ? `${baseClass} slds-is-active` : baseClass;
    }

    get chargesTabClass() {
        const baseClass = 'slds-tabs_default__link';
        return this.activeTab === 'charges' ? `${baseClass} slds-is-active` : baseClass;
    }

    get scheduleTabClass() {
        const baseClass = 'slds-tabs_default__link';
        return this.activeTab === 'schedule' ? `${baseClass} slds-is-active` : baseClass;
    }

    get transactionsTabClass() {
        const baseClass = 'slds-tabs_default__link';
        return this.activeTab === 'transactions' ? `${baseClass} slds-is-active` : baseClass;
    }

    get duesTabClass() {
        const baseClass = 'slds-tabs_default__link';
        return this.activeTab === 'dues' ? `${baseClass} slds-is-active` : baseClass;
    }

    getBillStatusBadgeClass(status) {
        if (status === 'Paid') {
            return 'slds-badge slds-badge_success';
        } else if (status === 'Past Due') {
            return 'slds-badge slds-badge_warning';
        } else {
            return 'slds-badge slds-badge_info';
        }
    }

    get progressPercentageValue() {
        return this.overview?.progressPercentage || 0;
    }

    get progressBarStyle() {
        const percentage = this.overview?.progressPercentage || 0;
        return `width: ${percentage}%`;
    }

    get formattedClosedDate() {
        return this.overview?.formattedClosedDate || '-';
    }

    get summaryTotalBills() {
        return this.duesAndCharges?.summary?.totalBills || 0;
    }

    get summaryTotalBilledAmount() {
        return this.duesAndCharges?.summary?.totalBilledAmount || 0;
    }

    get summaryTotalCharges() {
        return this.duesAndCharges?.summary?.totalCharges || 0;
    }

    get summaryTotalChargesAmount() {
        return this.duesAndCharges?.summary?.totalChargesAmount || 0;
    }

    get summaryFormattedTotalBilledAmount() {
        return this.duesAndCharges?.summary?.formattedTotalBilledAmount || '$0.00';
    }

    get summaryFormattedTotalChargesAmount() {
        return this.duesAndCharges?.summary?.formattedTotalChargesAmount || '$0.00';
    }
}
