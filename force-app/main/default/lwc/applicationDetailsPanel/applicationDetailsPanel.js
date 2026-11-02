import { LightningElement, api, track } from 'lwc';

export default class ApplicationDetailsPanel extends LightningElement {
    @api application;
    @track activeTab = 'overview';

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    get isOverviewActive() {
        return this.activeTab === 'overview';
    }

    get isPartiesActive() {
        return this.activeTab === 'parties';
    }

    get isPricingActive() {
        return this.activeTab === 'pricing';
    }

    get isScheduleActive() {
        return this.activeTab === 'schedule';
    }

    get isVerificationActive() {
        return this.activeTab === 'verification';
    }

    get overviewTabClass() {
        return this.tabClass('overview');
    }

    get partiesTabClass() {
        return this.tabClass('parties');
    }

    get pricingTabClass() {
        return this.tabClass('pricing');
    }

    get scheduleTabClass() {
        return this.tabClass('schedule');
    }

    get verificationTabClass() {
        return this.tabClass('verification');
    }

    get parties() {
        return this.application?.parties || [];
    }

    get hasParties() {
        return this.parties.length > 0;
    }

    get selectedPricing() {
        return this.application?.selectedPricing;
    }

    get hasSelectedPricing() {
        return !!this.selectedPricing;
    }

    get repaymentSchedule() {
        return this.application?.repaymentSchedule || [];
    }

    get hasRepaymentSchedule() {
        return this.repaymentSchedule.length > 0;
    }

    get applicationTitle() {
        return this.application?.applicationNumber || 'Application';
    }

    tabClass(tabName) {
        const baseClass = 'slds-tabs_default__link application-tab-link';
        return this.activeTab === tabName ? `${baseClass} slds-is-active` : baseClass;
    }
}