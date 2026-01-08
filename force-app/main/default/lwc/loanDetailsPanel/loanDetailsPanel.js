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

    get isScheduleActive() {
        return this.activeTab === 'schedule';
    }

    get isTransactionsActive() {
        return this.activeTab === 'transactions';
    }

    get isDuesActive() {
        return this.activeTab === 'dues';
    }

    get overviewTabClass() {
        const baseClass = 'slds-tabs_default__link';
        return this.activeTab === 'overview' ? `${baseClass} slds-is-active` : baseClass;
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

    get progressBarStyle() {
        if (this.overview && this.overview.progressPercentage) {
            return `width: ${this.overview.progressPercentage}%`;
        }
        return 'width: 0%';
    }

    get formattedClosedDate() {
        return this.overview?.formattedClosedDate || '-';
    }
}

