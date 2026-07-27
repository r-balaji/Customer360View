import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getCustomerSummary from '@salesforce/apex/Customer360Controller.getCustomerSummary';
import getOrgNamespacePrefix from '@salesforce/apex/Customer360Controller.getOrgNamespacePrefix';
import getApplication360 from '@salesforce/apex/Customer360Controller.getApplication360';
import getExposureSummary from '@salesforce/apex/Customer360Controller.getExposureSummary';
import searchAccountsWithFilters from '@salesforce/apex/Customer360Controller.searchAccountsWithFilters';

const LOAN_PAYMENT_SELECTOR_COMPONENT = 'loanPaymentSelector';
const APPLICATION_RELATIONSHIP_FILTERS = [
    { value: 'ALL', label: 'All' },
    { value: 'BORROWER', label: 'Borrower' },
    { value: 'CO-BORROWER', label: 'Co-Borrower' },
    { value: 'SIGNER', label: 'Signer' },
    { value: 'COSIGNER', label: 'Co-Signer' },
    { value: 'GUARANTOR', label: 'Guarantor' },
    { value: 'TRUSTEE', label: 'Trustee' },
    { value: 'ENTITY', label: 'Entity' }
];
const APPLICATION_RELATIONSHIP_LABELS = {
    'BORROWER': 'Borrower',
    'CO-BORROWER': 'Co-Borrower',
    'SIGNER': 'Signer',
    'COSIGNER': 'Co-Signer',
    'GUARANTOR': 'Guarantor',
    'TRUSTEE': 'Trustee',
    'ENTITY': 'Entity'
};

export default class Customer360View extends NavigationMixin(LightningElement) {
    @track searchByLookupId = null; // Account from record picker (overrides filter fields when set)
    @track searchAccountName = '';
    @track searchPhone = '';
    @track searchEmail = '';
    @track searchResultAccounts = [];
    @track showNoAccountsMessage = false;
    @track isSearchCollapsed = false;
    @track selectedAccountId;
    @track customerSummary;
    @track allLoanAccounts = []; // Store all loans for filtering
    @track summaryMetrics;
    @track isLoading = false;
    @track currentFilter = 'all'; // Track active filter: 'all', 'active', 'closed', 'goodStanding', 'badStanding'

    // Account information
    @track accountInfo = {
        accountId: null,
        customerName: null,
        email: null,
        phone: null,
        address: null,
        accountNumber: null
    };

    // Summary card data
    @track totalLoans = 0;
    @track activeLoans = 0;
    @track closedLoans = 0;
    @track activeGoodStanding = 0;
    @track activeBadStanding = 0;
    @track loanToValueRatio = 0;
    @track debtRatio = 0;

    // Financial Health metrics
    @track paymentConsistency = 0;
    @track utilization = 0;
    @track riskSignals = 'Low';
    @track monthlyDue = 0;
    @track expandedLoanId = null; // Track which loan row is expanded
    @track activeWorkspaceTab = 'application';
    @track applicationSummary;
    @track allApplications = [];
    @track currentApplicationRelationshipFilter = 'ALL';
    @track isApplicationLoading = false;
    @track expandedApplicationId = null;
    @track exposureSummary;
    @track isExposureLoading = false;
    @track isRelationshipGraphCollapsed = false;
    orgNamespacePrefix = null;
    namespacePromise = null;

    connectedCallback() {
        this.namespacePromise = getOrgNamespacePrefix()
            .then(result => {
                this.orgNamespacePrefix = result || null;
            })
            .catch(() => {
                this.orgNamespacePrefix = null;
            });
    }

    get isSearchDisabled() {
        if (this.searchByLookupId) return false;
        return !this.hasSearchFilterValue;
    }

    get hasSearchFilterValue() {
        return [this.searchAccountName, this.searchPhone, this.searchEmail].some(value => value && value.trim());
    }

    get hasMultipleSearchResults() {
        return this.searchResultAccounts && this.searchResultAccounts.length > 1;
    }

    get searchSectionClass() {
        return this.isSearchCollapsed
            ? 'search-section search-section-collapsed'
            : 'search-section';
    }

    get searchToggleIcon() {
        return this.isSearchCollapsed ? 'utility:chevrondown' : 'utility:chevronup';
    }

    get searchToggleAlternativeText() {
        return this.isSearchCollapsed ? 'Expand customer search' : 'Collapse customer search';
    }

    get isSearchExpanded() {
        return !this.isSearchCollapsed;
    }

    get relationshipGraphToggleIcon() {
        return this.isRelationshipGraphCollapsed ? 'utility:chevrondown' : 'utility:chevronup';
    }

    get relationshipGraphToggleAlternativeText() {
        return this.isRelationshipGraphCollapsed
            ? 'Expand relationship graph'
            : 'Minimize relationship graph';
    }

    get isRelationshipGraphExpanded() {
        return !this.isRelationshipGraphCollapsed;
    }

    // Getter for filtered loan accounts based on current filter
    get filteredLoanAccounts() {
        if (!this.allLoanAccounts || this.allLoanAccounts.length === 0) {
            return [];
        }

        // Exclude Master Facility loans from the Loans & Products list.
        const visibleLoans = this.allLoanAccounts.filter(loan => loan.productType !== 'Master Facility');

        if (this.currentFilter === 'all') {
            return visibleLoans;
        }

        return visibleLoans.filter(loan => {
            const status = loan.status || '';
            const standing = loan.standing || '';

            switch (this.currentFilter) {
                case 'active':
                    // Active loans: status doesn't start with "Closed"
                    return status && !status.startsWith('Closed');
                case 'closed':
                    // Closed loans: status starts with "Closed"
                    return status && status.startsWith('Closed');
                case 'goodStanding':
                    // Good standing: standing === 'Good Standing' or status === 'Active - Good Standing'
                    return standing === 'Good Standing' || status === 'Active - Good Standing';
                case 'badStanding':
                    // Bad standing: standing === 'Bad Standing' or status === 'Active - Bad Standing'
                    return standing === 'Bad Standing' || status === 'Active - Bad Standing';
                default:
                    return true;
            }
        });
    }

    // Getter for filtered loan count
    get filteredLoanCount() {
        return this.filteredLoanAccounts.length;
    }

    // Getter to check if a filter is active
    get isFiltered() {
        return this.currentFilter && this.currentFilter !== 'all';
    }

    // Getter for filter label
    get filterLabel() {
        const labels = {
            'active': 'Active Loans',
            'closed': 'Closed Loans',
            'goodStanding': 'Good Standing',
            'badStanding': 'Bad Standing'
        };
        return labels[this.currentFilter] || this.currentFilter;
    }

    // Getter for filter options (for filter badges)
    get filterOptions() {
        return [
            { value: 'all', label: 'All', class: this.currentFilter === 'all' ? 'filter-badge filter-badge-active' : 'filter-badge' },
            { value: 'active', label: 'Active', class: this.currentFilter === 'active' ? 'filter-badge filter-badge-active' : 'filter-badge' },
            { value: 'closed', label: 'Closed', class: this.currentFilter === 'closed' ? 'filter-badge filter-badge-active' : 'filter-badge' },
            { value: 'goodStanding', label: 'Good Standing', class: this.currentFilter === 'goodStanding' ? 'filter-badge filter-badge-active' : 'filter-badge' },
            { value: 'badStanding', label: 'Bad Standing', class: this.currentFilter === 'badStanding' ? 'filter-badge filter-badge-active' : 'filter-badge' }
        ];
    }

    get isLoanDetailsTabActive() {
        return this.activeWorkspaceTab === 'loan' && this.showLoanDetailsTab;
    }

    get isApplicationDetailsTabActive() {
        return this.activeWorkspaceTab === 'application' && this.showApplicationDetailsTab;
    }

    get loanDetailsTabClass() {
        return this.isLoanDetailsTabActive ? 'workspace-tab workspace-tab-active' : 'workspace-tab';
    }

    get applicationDetailsTabClass() {
        return this.isApplicationDetailsTabActive ? 'workspace-tab workspace-tab-active' : 'workspace-tab';
    }

    get showLoanDetailsTab() {
        return Boolean(this.exposureSummary?.loanModuleAvailable);
    }

    get showApplicationDetailsTab() {
        return Boolean(this.exposureSummary?.genesisModuleAvailable);
    }

    get hasAvailableModules() {
        return this.showLoanDetailsTab || this.showApplicationDetailsTab;
    }

    get showProposedExposure() {
        return Boolean(this.exposureSummary?.showProposedExposure);
    }

    get showCurrentGenesisDirectRoles() {
        return this.exposureSummary?.currentExposureSource === 'GENESIS';
    }

    get exposureEmptyMessage() {
        return this.exposureSummary?.message || 'Exposure is unavailable.';
    }

    get hasApplications() {
        return this.allApplications && this.allApplications.length > 0;
    }

    get filteredApplications() {
        if (this.currentApplicationRelationshipFilter === 'ALL') {
            return this.allApplications || [];
        }
        return (this.allApplications || []).filter(application =>
            application.relationshipRoleValues.includes(this.currentApplicationRelationshipFilter)
        );
    }

    get hasFilteredApplications() {
        return this.filteredApplications.length > 0;
    }

    get expandedApplication() {
        return (this.allApplications || []).find(
            application => application.applicationId === this.expandedApplicationId
        ) || null;
    }

    get hasExpandedApplication() {
        return Boolean(this.expandedApplication);
    }

    get applicationRelationshipFilterOptions() {
        const applications = this.allApplications || [];
        return APPLICATION_RELATIONSHIP_FILTERS.map(filter => {
            const count = filter.value === 'ALL'
                ? applications.length
                : applications.filter(application =>
                    application.relationshipRoleValues.includes(filter.value)
                ).length;
            return {
                ...filter,
                count,
                selected: this.currentApplicationRelationshipFilter === filter.value,
                class: this.currentApplicationRelationshipFilter === filter.value
                    ? 'filter-badge filter-badge-active'
                    : 'filter-badge'
            };
        });
    }

    get filteredApplicationEmptyMessage() {
        const selectedFilter = APPLICATION_RELATIONSHIP_FILTERS.find(
            filter => filter.value === this.currentApplicationRelationshipFilter
        );
        return `No applications found for the ${selectedFilter?.label || 'selected'} relationship.`;
    }

    get applicationCount() {
        return this.allApplications?.length || 0;
    }

    get inProcessApplicationCount() {
        return this.applicationSummary?.inProcessApplications || 0;
    }

    get approvedApplicationCount() {
        return this.applicationSummary?.approvedApplications || 0;
    }

    get applicationEmptyMessage() {
        return this.applicationSummary?.message || 'No applications found for this account.';
    }

    get formattedApplicationRequestedAmount() {
        return this.formatCurrency(this.applicationSummary?.totalRequestedAmount || 0);
    }

    get formattedApplicationApprovedAmount() {
        return this.formatCurrency(this.applicationSummary?.totalApprovedAmount || 0);
    }

    handleAccountLookupChange(event) {
        const recordId = event.detail?.recordId || event.detail?.value || (event.detail && typeof event.detail === 'string' ? event.detail : null) || null;
        this.searchByLookupId = recordId || null;
        if (this.searchByLookupId) {
            this.clearSearchFilters();
        }
        this.showNoAccountsMessage = false;
        this.searchResultAccounts = [];
    }

    handleSearchFilterChange(event) {
        const value = event.target.value || '';
        switch (event.target.dataset.field) {
            case 'accountName':
                this.searchAccountName = value;
                break;
            case 'phone':
                this.searchPhone = value;
                break;
            case 'email':
                this.searchEmail = value;
                break;
            default:
                break;
        }
        this.searchByLookupId = null; // Clear lookup when using filter fields
        this.showNoAccountsMessage = false;
        this.searchResultAccounts = [];
    }

    clearSearchFilters() {
        this.searchAccountName = '';
        this.searchPhone = '';
        this.searchEmail = '';
    }

    handleSearch() {
        // If account lookup is provided, use it and ignore filter fields
        if (this.searchByLookupId) {
            this.isSearchCollapsed = true;
            this.selectedAccountId = this.searchByLookupId;
            this.searchResultAccounts = [];
            this.showNoAccountsMessage = false;
            this.loadCustomerSummary();
            return;
        }
        const accountName = (this.searchAccountName || '').trim();
        const phone = (this.searchPhone || '').trim();
        const email = (this.searchEmail || '').trim();
        if (!accountName && !phone && !email) {
            this.showError('Validation Error', 'Select an account from the lookup above or enter a name, phone, or email.');
            return;
        }
        this.isSearchCollapsed = true;
        this.showNoAccountsMessage = false;
        this.searchResultAccounts = [];
        this.isLoading = true;
        searchAccountsWithFilters({
            accountName,
            phone,
            email
        })
            .then((result) => {
                this.isLoading = false;
                if (!result || result.length === 0) {
                    this.showNoAccountsMessage = true;
                    return;
                }
                if (result.length === 1) {
                    this.selectedAccountId = result[0].id;
                    this.searchResultAccounts = [];
                    this.loadCustomerSummary();
                    return;
                }
                this.searchResultAccounts = result;
                this.selectedAccountId = null;
                this.customerSummary = null;
                this.allLoanAccounts = [];
                this.resetApplicationState();
                this.currentFilter = 'all';
                this.accountInfo = {
                    accountId: null,
                    customerName: null,
                    email: null,
                    phone: null,
                    address: null,
                    accountNumber: null,
                    totalLoanAmount: 0,
                    totalPrincipalRemaining: 0,
                    totalDelinquentAmount: 0,
                    loanProgressTotalPrincipal: 0,
                    loanProgressPrincipalPaid: 0,
                    loanProgressPrincipalRemaining: 0,
                    utilization: 0,
                    parentLoanUtilization: 0,
                    fundingInTranchesUtilization: 0,
                    directExposure: 0,
                    directExposureAsBorrower: 0,
                    directExposureAsCoBorrower: 0,
                    indirectExposure: 0,
                    indirectExposureAsGuarantor: 0
                };
                this.totalLoans = 0;
                this.activeLoans = 0;
                this.closedLoans = 0;
                this.activeGoodStanding = 0;
                this.activeBadStanding = 0;
                this.loanToValueRatio = 0;
                this.debtRatio = 0;
            })
            .catch((error) => {
                this.isLoading = false;
                const msg = error.body?.message || error.message || 'Search failed';
                this.showError('Error', msg);
            });
    }

    handleSearchSectionToggle() {
        this.isSearchCollapsed = !this.isSearchCollapsed;
    }

    handleRelationshipGraphToggle() {
        this.isRelationshipGraphCollapsed = !this.isRelationshipGraphCollapsed;
    }

    handleSelectAccount(event) {
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId) return;
        this.selectedAccountId = accountId;
        this.searchResultAccounts = [];
        this.showNoAccountsMessage = false;
        this.loadCustomerSummary();
    }

    handleWorkspaceTabClick(event) {
        const selectedTab = event.currentTarget.dataset.tab;
        if ((selectedTab === 'loan' && !this.showLoanDetailsTab) ||
            (selectedTab === 'application' && !this.showApplicationDetailsTab)) {
            return;
        }
        this.activeWorkspaceTab = selectedTab || 'application';
        if (this.isApplicationDetailsTabActive && !this.applicationSummary && this.selectedAccountId) {
            this.loadApplicationSummary();
        }
    }

    resetApplicationState() {
        this.applicationSummary = null;
        this.allApplications = [];
        this.currentApplicationRelationshipFilter = 'ALL';
        this.expandedApplicationId = null;
        this.isApplicationLoading = false;
    }

    resetExposureState() {
        this.exposureSummary = null;
        this.isExposureLoading = false;
    }

    syncWorkspaceTab() {
        if ((this.isLoanDetailsTabActive && this.showLoanDetailsTab) ||
            (this.isApplicationDetailsTabActive && this.showApplicationDetailsTab)) {
            return;
        }
        this.activeWorkspaceTab = this.showApplicationDetailsTab
            ? 'application'
            : (this.showLoanDetailsTab ? 'loan' : null);
    }

    loadCustomerSummary() {
        if (!this.selectedAccountId) {
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        this.isLoading = true;
        this.activeWorkspaceTab = 'application';
        this.resetApplicationState();
        this.resetExposureState();
        this.loadExposureSummary();

        getCustomerSummary({ accountId: this.selectedAccountId })
            .then(result => {
                this.customerSummary = result;
                // Format loan accounts with display values
                this.allLoanAccounts = (result.loans || []).map(loan => ({
                    ...loan,
                    formattedBalance: this.formatCurrency(loan.principalRemaining || 0),
                    formattedNextDue: this.formatDate(loan.nextPaymentDate) || '-',
                    formattedOldestUnpaidBillDate: this.formatDate(loan.oldestUnpaidBillDate) || '-',
                    formattedRate: this.formatPercent(loan.interestRate || 0),
                    statusBadgeClass: this.getStatusBadgeClass(loan.status || ''),
                    expandIcon: 'utility:chevrondown', // Default to down arrow
                    detailRowKey: loan.loanAccountId + '-detail', // Unique key for detail row
                    isExpanded: false // Track expansion state
                }));
                this.currentFilter = 'all'; // Reset filter to 'all'
                this.summaryMetrics = result.summary;

                // Store account information
                this.accountInfo = {
                    accountId: result.accountId || null,
                    customerName: result.customerName || null,
                    email: result.email || null,
                    phone: result.phone || null,
                    address: result.address || null,
                    accountNumber: result.accountNumber || null,
                    totalLoanAmount: result.totalLoanAmount || 0,
                    totalPrincipalRemaining: result.totalPrincipalRemaining || 0,
                    totalDelinquentAmount: result.totalDelinquentAmount || 0,
                    totalBilledAmount: result.totalBilledAmount || 0,
                    totalMonthlyPayment: result.totalMonthlyPayment || 0,
                    loanProgressTotalPrincipal: result.loanProgressTotalPrincipal || 0,
                    loanProgressPrincipalPaid: result.loanProgressPrincipalPaid || 0,
                    loanProgressPrincipalRemaining: result.loanProgressPrincipalRemaining || 0,
                    utilization: result.utilization || 0,
                    parentLoanUtilization: result.parentLoanUtilization || 0,
                    fundingInTranchesUtilization: result.fundingInTranchesUtilization || 0
                };

                // Update summary cards
                this.totalLoans = result.summary.totalLoans || 0;
                this.activeLoans = result.summary.activeLoans || 0;
                this.closedLoans = result.summary.closedLoans || 0;
                this.activeGoodStanding = result.summary.activeGoodStandingLoans || 0;
                this.activeBadStanding = result.summary.activeBadStandingLoans || 0;
                this.loanToValueRatio = result.summary.loanToValueRatio || 0;
                this.debtRatio = result.summary.debtRatio || 0;

                // Calculate additional metrics
                this.calculateFinancialHealthMetrics();

                this.isLoading = false;
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'Unknown error occurred';
                this.showError('Error', 'Failed to load customer summary: ' + errorMessage);
                this.isLoading = false;
            });
    }

    loadExposureSummary() {
        if (!this.selectedAccountId) {
            return;
        }

        this.isExposureLoading = true;
        getExposureSummary({ accountId: this.selectedAccountId })
            .then(result => {
                this.exposureSummary = result;
                this.isExposureLoading = false;
                this.syncWorkspaceTab();
                if (this.showApplicationDetailsTab) {
                    this.loadApplicationSummary();
                }
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'Unknown error occurred';
                this.isExposureLoading = false;
                this.showError('Error', 'Failed to load customer exposure: ' + errorMessage);
            });
    }

    loadApplicationSummary() {
        if (!this.selectedAccountId || !this.showApplicationDetailsTab ||
            this.isApplicationLoading || this.applicationSummary) {
            return;
        }

        this.isApplicationLoading = true;
        getApplication360({ accountId: this.selectedAccountId })
            .then(result => {
                this.applicationSummary = result;
                this.allApplications = this.formatApplications(result?.applications || []);
                this.isApplicationLoading = false;
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'Unknown error occurred';
                this.showError('Error', 'Failed to load application details: ' + errorMessage);
                this.resetApplicationState();
            });
    }

    formatApplications(applications) {
        return applications.map(application => {
            const directProposedExposure = application.directProposedExposure || 0;
            const indirectProposedExposure = application.indirectProposedExposure || 0;
            const proposedExposure = directProposedExposure + indirectProposedExposure;
            const relationshipRoleValues = (application.relationshipRoles || []).filter(
                role => APPLICATION_RELATIONSHIP_LABELS[role]
            );

            return {
                ...application,
                relationshipRoleValues,
                relationshipBadges: relationshipRoleValues.map(role => ({
                    value: role,
                    label: APPLICATION_RELATIONSHIP_LABELS[role]
                })),
                formattedRequestedAmount: this.formatCurrency(application.requestedAmount || 0),
                formattedApprovedAmount: this.formatCurrency(application.approvedAmount || 0),
                formattedFinancedAmount: this.formatCurrency(application.financedAmount || 0),
                formattedPaymentAmount: this.formatCurrency(application.paymentAmount || 0),
                formattedInterestRate: this.formatPercent(application.interestRate || 0),
                formattedApr: this.formatPercent(application.apr || 0),
                formattedSubmittedDate: this.formatDate(application.submittedDate) || '-',
                formattedExpectedCloseDate: this.formatDate(application.expectedCloseDate) || '-',
                formattedMaturityDate: this.formatDate(application.maturityDate) || '-',
                formattedProposedExposure: this.formatCurrency(proposedExposure),
                displayPaymentFrequency: application.paymentFrequency || '-',
                displayTerm: application.term ? `${application.term} months` : '-',
                displayManualReviewStatus: application.manualReviewStatus || '-',
                displayManualApprovalStatus: application.manualApprovalStatus || '-',
                displayCreditVerificationStatus: application.creditVerificationStatus || '-',
                displayKycVerificationStatus: application.kycVerificationStatus || '-',
                displayKybVerificationStatus: application.kybVerificationStatus || '-',
                displayVoiVerificationStatus: application.voiVerificationStatus || '-',
                displayVoeVerificationStatus: application.voeVerificationStatus || '-',
                displayCreditApprovalStatus: application.creditApprovalStatus || '-',
                statusBadgeClass: this.getApplicationStatusBadgeClass(application.status || ''),
                expandIcon: this.isApplicationExpanded(application.applicationId)
                    ? 'utility:chevronup' : 'utility:chevrondown',
                expandAlternativeText: this.isApplicationExpanded(application.applicationId)
                    ? 'Hide application details' : 'Show application details',
                isExpanded: this.isApplicationExpanded(application.applicationId),
                selectedPricing: this.formatSelectedPricing(application.selectedPricing),
                parties: this.formatApplicationParties(application.parties || []),
                repaymentSchedule: this.formatRepaymentSchedule(application.repaymentSchedule || [])
            };
        });
    }

    formatSelectedPricing(pricing) {
        if (!pricing) {
            return null;
        }

        return {
            ...pricing,
            formattedPaymentAmount: this.formatCurrency(pricing.paymentAmount || 0),
            formattedInterestRate: this.formatPercent(pricing.interestRate || 0),
            formattedTotalInterest: this.formatCurrency(pricing.totalInterest || 0),
            formattedTotalPayments: this.formatCurrency(pricing.totalPayments || 0),
            formattedRateFactor: this.formatPercent(pricing.rateFactor || 0),
            formattedYieldPercent: this.formatPercent(pricing.yieldPercent || 0),
            displayPaymentFrequency: pricing.paymentFrequency || '-',
            displayPricingMethod: pricing.pricingMethod || '-',
            displayTerm: pricing.term ? `${pricing.term} months` : '-'
        };
    }

    formatApplicationParties(parties) {
        return parties.map(party => {
            const formattedPercentOwnership = party.percentOwnership == null
                ? '-'
                : `${party.percentOwnership}%`;

            return {
                ...party,
                displayPartyName: party.partyName || party.accountName || party.contactName || party.partyNumber || '-',
                displayPartyType: party.partyType || '-',
                displayAccountName: party.accountName || '-',
                displayContactName: party.contactName || '-',
                formattedPercentOwnership,
                formattedDirectExposure: this.formatCurrency(party.directExposure || 0),
                formattedDirectProposedExposure: this.formatCurrency(party.directProposedExposure || party.directExposure || 0),
                formattedIndirectExposure: this.formatCurrency(party.indirectExposure || 0),
                formattedIndirectProposedExposure: this.formatCurrency(party.indirectProposedExposure || party.indirectExposure || 0)
            };
        });
    }

    formatRepaymentSchedule(scheduleRows) {
        return scheduleRows.map(row => ({
            ...row,
            displayPaymentNumber: row.paymentNumber == null ? '-' : Number(row.paymentNumber).toFixed(0),
            formattedDueDate: this.formatDate(row.dueDate) || '-',
            formattedPrincipal: this.formatCurrency(row.principal || 0),
            formattedInterest: this.formatCurrency(row.interest || 0),
            formattedFee: this.formatCurrency(row.fee || 0),
            formattedTotalDue: this.formatCurrency(row.totalDue || 0),
            formattedOpeningBalance: this.formatCurrency(row.openingBalance || 0),
            formattedClosingBalance: this.formatCurrency(row.closingBalance || 0)
        }));
    }

    // Filter handlers for summary cards
    handleFilterClick(event) {
        const filterType = event.currentTarget.dataset.filter;
        this.currentFilter = filterType;
    }

    handleApplicationRelationshipFilterClick(event) {
        this.currentApplicationRelationshipFilter = event.currentTarget.dataset.relationship;
        this.expandedApplicationId = null;
        this.updateApplicationExpandIcons();
    }

    // Getters for card classes to show active state
    get totalLoansCardClass() {
        return this.currentFilter === 'all'
            ? 'slds-box summary-card summary-card-active'
            : 'slds-box summary-card summary-card-clickable';
    }

    get activeLoansCardClass() {
        return this.currentFilter === 'active'
            ? 'slds-box summary-card summary-card-active'
            : 'slds-box summary-card summary-card-clickable';
    }

    get closedLoansCardClass() {
        return this.currentFilter === 'closed'
            ? 'slds-box summary-card summary-card-active'
            : 'slds-box summary-card summary-card-clickable';
    }

    get goodStandingCardClass() {
        return this.currentFilter === 'goodStanding'
            ? 'slds-box summary-card summary-card-success summary-card-active'
            : 'slds-box summary-card summary-card-success summary-card-clickable';
    }

    get badStandingCardClass() {
        return this.currentFilter === 'badStanding'
            ? 'slds-box summary-card summary-card-warning summary-card-active'
            : 'slds-box summary-card summary-card-warning summary-card-clickable';
    }

    showError(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
        });
        this.dispatchEvent(evt);
    }

    // Getters for formatted values (LWC templates don't allow function calls)
    get formattedLTVRatio() {
        if (this.loanToValueRatio == null) return '0%';
        return this.loanToValueRatio.toFixed(2) + '%';
    }

    get formattedDebtRatio() {
        if (this.debtRatio == null) return '0%';
        return this.debtRatio.toFixed(2) + '%';
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

    // Navigate to account record page in new tab
    navigateToAccount(event) {
        event.preventDefault();
        if (this.accountInfo.accountId) {
            // Construct Salesforce record URL
            const baseUrl = window.location.origin;
            const recordUrl = `${baseUrl}/lightning/r/Account/${this.accountInfo.accountId}/view`;
            window.open(recordUrl, '_blank');
        }
    }

    // Getter for account record URL
    get accountRecordUrl() {
        if (this.accountInfo.accountId) {
            const baseUrl = window.location.origin;
            return `${baseUrl}/lightning/r/Account/${this.accountInfo.accountId}/view`;
        }
        return '#';
    }

    // Getter to check if account info is available
    get hasAccountInfo() {
        return this.accountInfo && this.accountInfo.accountId;
    }

    // Formatted getters for calculated fields
    get formattedTotalLoanAmount() {
        return this.formatCurrency(this.accountInfo?.totalLoanAmount || 0);
    }

    get formattedTotalPrincipalRemaining() {
        return this.formatCurrency(this.accountInfo?.totalPrincipalRemaining || 0);
    }

    get formattedTotalDelinquentAmount() {
        return this.formatCurrency(this.accountInfo?.totalDelinquentAmount || 0);
    }

    get formattedTotalPaidAmount() {
        return this.formatCurrency(this.accountInfo?.loanProgressPrincipalPaid || 0);
    }

    get formattedTotalBilledAmount() {
        return this.formatCurrency(this.accountInfo?.totalBilledAmount || 0);
    }

    get formattedDirectExposure() {
        return this.formatCurrency(this.exposureSummary?.directExposure || 0);
    }

    get formattedDirectExposureAsBorrower() {
        return this.formatCurrency(this.exposureSummary?.directExposureAsBorrower || 0);
    }

    get formattedDirectExposureAsCoBorrower() {
        return this.formatCurrency(this.exposureSummary?.directExposureAsCoBorrower || 0);
    }

    get formattedDirectExposureAsSigner() {
        return this.formatCurrency(this.exposureSummary?.directExposureAsSigner || 0);
    }

    get formattedDirectExposureAsCosigner() {
        return this.formatCurrency(this.exposureSummary?.directExposureAsCosigner || 0);
    }

    get formattedDirectProposedExposure() {
        return this.formatCurrency(this.exposureSummary?.directProposedExposure || 0);
    }

    get formattedDirectProposedExposureAsBorrower() {
        return this.formatCurrency(this.exposureSummary?.directProposedExposureAsBorrower || 0);
    }

    get formattedDirectProposedExposureAsCoBorrower() {
        return this.formatCurrency(this.exposureSummary?.directProposedExposureAsCoBorrower || 0);
    }

    get formattedDirectProposedExposureAsSigner() {
        return this.formatCurrency(this.exposureSummary?.directProposedExposureAsSigner || 0);
    }

    get formattedDirectProposedExposureAsCosigner() {
        return this.formatCurrency(this.exposureSummary?.directProposedExposureAsCosigner || 0);
    }

    get formattedIndirectExposure() {
        return this.formatCurrency(this.exposureSummary?.indirectExposure || 0);
    }

    get formattedIndirectExposureAsGuarantor() {
        return this.formatCurrency(this.exposureSummary?.indirectExposureAsGuarantor || 0);
    }

    get formattedIndirectProposedExposure() {
        return this.formatCurrency(this.exposureSummary?.indirectProposedExposure || 0);
    }

    get formattedIndirectProposedExposureAsGuarantor() {
        return this.formatCurrency(this.exposureSummary?.indirectProposedExposureAsGuarantor || 0);
    }

    get loanProgressRemainingPercentage() {
        const totalPrincipal = this.accountInfo?.loanProgressTotalPrincipal || 0;
        const principalRemaining = this.accountInfo?.loanProgressPrincipalRemaining || 0;
        if (totalPrincipal <= 0) {
            return 0;
        }
        return Math.max(0, Math.min((principalRemaining / totalPrincipal) * 100, 100));
    }

    get loanProgressPaidPercentage() {
        const totalPrincipal = this.accountInfo?.loanProgressTotalPrincipal || 0;
        if (totalPrincipal <= 0) {
            return 0;
        }
        const principalPaid = this.accountInfo?.loanProgressPrincipalPaid || 0;
        return this.clampPercent((principalPaid / totalPrincipal) * 100);
    }

    get formattedPrincipalPaydown() {
        return `${this.loanProgressPaidPercentage.toFixed(1)}%`;
    }

    get principalPaydownBarStyle() {
        return this.metricBarStyle(this.loanProgressPaidPercentage);
    }

    get fundingUtilizationBarStyle() {
        return this.metricBarStyle(this.utilization);
    }

    get paymentRiskScore() {
        if (this.riskSignals === 'High') return 100;
        if (this.riskSignals === 'Moderate') return 60;
        return 25;
    }

    get paymentRiskBarStyle() {
        return this.metricBarStyle(this.paymentRiskScore);
    }

    get paymentRiskBadgeClass() {
        const normalizedRisk = (this.riskSignals || 'Low').toLowerCase();
        return `risk-pill risk-pill-${normalizedRisk}`;
    }

    get paymentRiskBarClass() {
        const normalizedRisk = (this.riskSignals || 'Low').toLowerCase();
        return `insight-progress-bar risk-bar-${normalizedRisk}`;
    }

    get oldestUnpaidBillDate() {
        let oldestDate = null;
        let oldestTimestamp = null;
        (this.allLoanAccounts || []).forEach(loan => {
            const timestamp = this.toDateOnlyTimestamp(loan.oldestUnpaidBillDate);
            if (timestamp == null) return;
            if (oldestTimestamp == null || timestamp < oldestTimestamp) {
                oldestTimestamp = timestamp;
                oldestDate = loan.oldestUnpaidBillDate;
            }
        });
        return oldestDate;
    }

    get formattedOldestUnpaidBillDate() {
        return this.formatDate(this.oldestUnpaidBillDate) || '-';
    }

    metricBarStyle(value) {
        return `width: ${this.clampPercent(value)}%`;
    }

    clampPercent(value) {
        const numericValue = Number(value) || 0;
        return Math.max(0, Math.min(numericValue, 100));
    }

    toDateOnlyTimestamp(dateValue) {
        if (!dateValue) return null;

        const rawDate = String(dateValue);
        const dateOnlyMatch = rawDate.match(/^(\d{4})-(\d{2})-(\d{2})(?:$|T|\s)/);
        if (dateOnlyMatch) {
            return new Date(
                Number(dateOnlyMatch[1]),
                Number(dateOnlyMatch[2]) - 1,
                Number(dateOnlyMatch[3])
            ).getTime();
        }

        const timestamp = new Date(dateValue).getTime();
        return Number.isNaN(timestamp) ? null : timestamp;
    }

    // Calculate Financial Health Metrics
    calculateFinancialHealthMetrics() {
        // Monthly Payment comes from the API (sum of Payment_Amount__c from all loans)
        this.monthlyPayment = this.accountInfo?.totalMonthlyPayment || 0;

        // Also calculate Monthly Due (for backward compatibility)
        this.monthlyDue = this.monthlyPayment;

        this.utilization = this.accountInfo?.utilization || 0;

        // Calculate Payment Consistency (simplified - based on active loans with no past due)
        const activeLoans = this.allLoanAccounts.filter(loan => {
            const status = loan.status || '';
            return loan.productType !== 'Master Facility' && status && !status.startsWith('Closed');
        });
        const currentLoans = activeLoans.filter(loan => {
            return (loan.daysPastDue || 0) === 0;
        });
        this.paymentConsistency = activeLoans.length > 0 ?
            (currentLoans.length / activeLoans.length) * 100 : 100;

        // Determine Risk Signals
        if (this.activeBadStanding > 0 || this.accountInfo?.totalDelinquentAmount > 0) {
            this.riskSignals = 'High';
        } else if (this.paymentConsistency < 80 || this.utilization > 80) {
            this.riskSignals = 'Moderate';
        } else {
            this.riskSignals = 'Low';
        }
    }

    // Getter for formatted monthly due
    get formattedMonthlyDue() {
        return this.formatCurrency(this.monthlyDue);
    }

    // Getter for formatted monthly payment
    get formattedMonthlyPayment() {
        return this.formatCurrency(this.monthlyPayment);
    }

    // Getter for formatted loan progress remaining percentage
    get formattedLoanProgressRemaining() {
        return `${this.loanProgressRemainingPercentage.toFixed(1)}%`;
    }

    get formattedLoanProgressPrincipalRemaining() {
        return this.formatCurrency(this.accountInfo?.loanProgressPrincipalRemaining || 0);
    }

    // Getter for formatted loan progress paid amount
    get formattedLoanProgressPaid() {
        return this.formatCurrency(this.accountInfo?.loanProgressPrincipalPaid || 0);
    }

    // Getter for formatted payment status billed percentage
    get formattedPaymentStatusBilled() {
        const totalBilled = this.accountInfo?.totalBilledAmount || 0;
        const delinquent = this.accountInfo?.totalDelinquentAmount || 0;
        const total = totalBilled + delinquent;
        const billedPercentage = total > 0 ? (totalBilled / total) * 100 : 0;
        return `${billedPercentage.toFixed(1)}%`;
    }

    // Getter for formatted utilization
    get formattedUtilization() {
        return this.formatPercent(this.utilization);
    }

    get formattedParentLoanUtilization() {
        return this.formatPercent(this.accountInfo?.parentLoanUtilization || 0);
    }

    get formattedFundingInTranchesUtilization() {
        return this.formatPercent(this.accountInfo?.fundingInTranchesUtilization || 0);
    }

    // Getter for formatted payment consistency
    get formattedPaymentConsistency() {
        return this.formatPercent(this.paymentConsistency);
    }

    // Getter for risk signals class
    get riskSignalsClass() {
        if (this.riskSignals === 'High') return 'risk-high';
        if (this.riskSignals === 'Moderate') return 'risk-moderate';
        return 'risk-low';
    }

    // Handle loan row expansion
    handleLoanRowExpand(event) {
        const loanId = event.currentTarget.dataset.loanId;
        if (this.expandedLoanId === loanId) {
            this.expandedLoanId = null; // Collapse if already expanded
        } else {
            this.expandedLoanId = loanId; // Expand new row
        }
        // Update expand icons
        this.updateExpandIcons();
    }

    // Update expand icons for all loans
    updateExpandIcons() {
        if (this.allLoanAccounts && this.allLoanAccounts.length > 0) {
            this.allLoanAccounts = this.allLoanAccounts.map(loan => ({
                ...loan,
                expandIcon: this.isLoanExpanded(loan.loanId) ? 'utility:chevronup' : 'utility:chevrondown',
                isExpanded: this.isLoanExpanded(loan.loanId)
            }));
        }
    }

    // Check if loan row is expanded
    isLoanExpanded(loanId) {
        return this.expandedLoanId === loanId;
    }

    // Get status badge class helper
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

    // Get expand icon for a loan
    getLoanExpandIcon(loanId) {
        return this.isLoanExpanded(loanId) ? 'utility:chevronup' : 'utility:chevrondown';
    }

    handleApplicationRowExpand(event) {
        const applicationId = event.currentTarget.dataset.applicationId;
        this.expandedApplicationId = this.expandedApplicationId === applicationId ? null : applicationId;
        this.updateApplicationExpandIcons();
    }

    updateApplicationExpandIcons() {
        this.allApplications = (this.allApplications || []).map(application => ({
            ...application,
            expandIcon: this.isApplicationExpanded(application.applicationId)
                ? 'utility:chevronup' : 'utility:chevrondown',
            expandAlternativeText: this.isApplicationExpanded(application.applicationId)
                ? 'Hide application details' : 'Show application details',
            isExpanded: this.isApplicationExpanded(application.applicationId)
        }));
    }

    isApplicationExpanded(applicationId) {
        return this.expandedApplicationId === applicationId;
    }

    getApplicationStatusBadgeClass(status) {
        const normalizedStatus = (status || '').toUpperCase();
        if (normalizedStatus.includes('ACCEPTED') || normalizedStatus.includes('APPROVED')) {
            return 'slds-badge status-badge-good-standing';
        }
        if (normalizedStatus.includes('REJECTED') || normalizedStatus.includes('WITHDRAWN')) {
            return 'slds-badge status-badge-bad-standing';
        }
        if (normalizedStatus.includes('BOOKED') || normalizedStatus.includes('CLOSED')) {
            return 'slds-badge status-badge-closed';
        }
        return 'slds-badge status-badge-application';
    }

    // Handle loan click (navigate to loan record)
    handleLoanClick(event) {
        event.preventDefault();
        const loanId = event.currentTarget.dataset.loanId;
        // Find the loan account ID
        const loan = this.allLoanAccounts.find(l => l.loanId === loanId);
        if (loan && loan.loanAccountId) {
            const baseUrl = window.location.origin;
            const recordUrl = `${baseUrl}/lightning/r/Loan_Account__c/${loan.loanAccountId}/view`;
            window.open(recordUrl, '_blank');
        }
    }

    async handleApplicationClick(event) {
        event.preventDefault();
        const applicationId = event.currentTarget.dataset.applicationId;
        if (!applicationId) {
            return;
        }

        const pageReference = {
            type: 'standard__recordPage',
            attributes: {
                recordId: applicationId,
                actionName: 'view'
            }
        };
        const recordUrl = await this[NavigationMixin.GenerateUrl](pageReference);
        window.open(recordUrl, '_blank');
    }

    async openLoanPaymentSelector(action) {
        sessionStorage.setItem('loanPaymentAccountId', this.selectedAccountId);
        sessionStorage.setItem('loanAction', action);

        const selectorWindow = window.open('', '_blank');
        if (!selectorWindow) {
            this.showError('Navigation Error', 'Allow pop-ups for Salesforce, then try the selected loan action again.');
            return;
        }

        if (this.namespacePromise) {
            await this.namespacePromise;
        }

        const componentName = this.orgNamespacePrefix
            ? `${this.orgNamespacePrefix}__${LOAN_PAYMENT_SELECTOR_COMPONENT}`
            : `c__${LOAN_PAYMENT_SELECTOR_COMPONENT}`;

        const pageReference = {
            type: 'standard__component',
            attributes: {
                componentName
            },
            state: {
                c__accountId: this.selectedAccountId,
                c__action: action
            }
        };

        try {
            const componentUrl = await this[NavigationMixin.GenerateUrl](pageReference);
            selectorWindow.location.href = componentUrl;
        } catch {
            selectorWindow.close();
            this.showError('Navigation Error', 'Unable to open the selected loan action.');
        }
    }

    hasActiveLoans() {
        const activeLoans = this.allLoanAccounts.filter(loan => {
            const status = loan.status || '';
            return status && !status.startsWith('Closed');
        });

        return activeLoans.length > 0;
    }

    // Action Handlers
    async handleTakePayment(event) {
        event.stopPropagation();
        if (!this.selectedAccountId) {
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        if (!this.hasActiveLoans()) {
            this.showError('No Active Loans', 'There are no active loans available for payment.');
            return;
        }

        await this.openLoanPaymentSelector('takePayment');
    }

    async handleReversePayment(event) {
        event.stopPropagation();
        if (!this.selectedAccountId) {
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        if (!this.hasActiveLoans()) {
            this.showError('No Active Loans', 'There are no active loans available for reverse payment.');
            return;
        }

        await this.openLoanPaymentSelector('reversePayment');
    }

    async handleWaiveFee(event) {
        event.stopPropagation();
        if (!this.selectedAccountId) {
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        if (!this.hasActiveLoans()) {
            this.showError('No Active Loans', 'There are no active loans to waive fees for.');
            return;
        }

        await this.openLoanPaymentSelector('waiveFee');
    }

    async handleSetPromiseToPay(event) {
        event.stopPropagation();
        if (!this.selectedAccountId) {
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        if (!this.hasActiveLoans()) {
            this.showError('No Active Loans', 'There are no active loans to set a promise-to-pay for.');
            return;
        }

        await this.openLoanPaymentSelector('promiseToPay');
    }

    async handleGeneratePayoffQuote(event) {
        event.stopPropagation();
        if (!this.selectedAccountId) {
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        if (!this.hasActiveLoans()) {
            this.showError('No Active Loans', 'There are no active loans to generate a payoff quote for.');
            return;
        }

        await this.openLoanPaymentSelector('generatePayoffQuote');
    }

    async handleChangeDueDay(event) {
        event.stopPropagation();
        if (!this.selectedAccountId) {
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        if (!this.hasActiveLoans()) {
            this.showError('No Active Loans', 'There are no active loans to change due day for.');
            return;
        }

        await this.openLoanPaymentSelector('changeDueDay');
    }


    showInfo(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'info',
        });
        this.dispatchEvent(evt);
    }
}
