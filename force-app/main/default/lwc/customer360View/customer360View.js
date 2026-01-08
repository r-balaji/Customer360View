import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getCustomerSummary from '@salesforce/apex/Customer360Controller.getCustomerSummary';

export default class Customer360View extends NavigationMixin(LightningElement) {
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

    get isSearchDisabled() {
        return !this.selectedAccountId;
    }

    // Getter for filtered loan accounts based on current filter
    get filteredLoanAccounts() {
        if (!this.allLoanAccounts || this.allLoanAccounts.length === 0) {
            return [];
        }

        if (this.currentFilter === 'all') {
            return this.allLoanAccounts;
        }

        return this.allLoanAccounts.filter(loan => {
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

    handleAccountChange(event) {
        console.log('=== ACCOUNT CHANGE EVENT ===');
        console.log('Full event object:', event);
        console.log('Event detail:', event.detail);
        console.log('Event target:', event.target);
        
        // Try different ways to get the account ID
        const accountId = event.detail?.recordId || 
                         event.detail?.value || 
                         event.target?.value || 
                         (event.detail && typeof event.detail === 'string' ? event.detail : null);
        
        console.log('Extracted Account ID:', accountId);
        
        this.selectedAccountId = accountId;
        
        if (!accountId) {
            console.log('Account was cleared');
            // Account was cleared
            this.customerSummary = null;
            this.allLoanAccounts = [];
            this.currentFilter = 'all';
            // Reset account info
            this.accountInfo = {
                accountId: null,
                customerName: null,
                email: null,
                phone: null,
                address: null,
                accountNumber: null,
                totalLoanAmount: 0,
                totalPrincipalRemaining: 0,
                totalDelinquentAmount: 0
            };
            // Reset summary cards
            this.totalLoans = 0;
            this.activeLoans = 0;
            this.closedLoans = 0;
            this.activeGoodStanding = 0;
            this.activeBadStanding = 0;
            this.loanToValueRatio = 0;
            this.debtRatio = 0;
        } else {
            console.log('Account ID set to:', this.selectedAccountId);
        }
    }

    handleSearch(event) {
        console.log('=== SEARCH BUTTON CLICKED ===');
        console.log('Selected Account ID:', this.selectedAccountId);
        console.log('Event:', event);
        
        if (!this.selectedAccountId) {
            console.error('No account selected!');
            this.showError('Validation Error', 'Please select an account first');
            return;
        }
        
        console.log('Calling loadCustomerSummary...');
        this.loadCustomerSummary();
    }

    loadCustomerSummary() {
        if (!this.selectedAccountId) {
            console.error('No account ID selected');
            this.showError('Validation Error', 'Please select an account first');
            return;
        }

        console.log('Loading customer summary for account:', this.selectedAccountId);
        this.isLoading = true;
        
        getCustomerSummary({ accountId: this.selectedAccountId })
            .then(result => {
                console.log('Customer summary loaded:', result);
                this.customerSummary = result;
                this.allLoanAccounts = result.loans || []; // Store all loans
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
                    totalBilledAmount: result.totalBilledAmount || 0
                };
                
                // Update summary cards
                this.totalLoans = result.summary.totalLoans || 0;
                this.activeLoans = result.summary.activeLoans || 0;
                this.closedLoans = result.summary.closedLoans || 0;
                this.activeGoodStanding = result.summary.activeGoodStandingLoans || 0;
                this.activeBadStanding = result.summary.activeBadStandingLoans || 0;
                this.loanToValueRatio = result.summary.loanToValueRatio || 0;
                this.debtRatio = result.summary.debtRatio || 0;
                
                this.isLoading = false;
                console.log('Summary cards updated:', {
                    totalLoans: this.totalLoans,
                    activeLoans: this.activeLoans,
                    allLoanAccounts: this.allLoanAccounts.length,
                    filteredLoanAccounts: this.filteredLoanAccounts.length
                });
            })
            .catch(error => {
                console.error('Error loading customer summary:', error);
                console.error('Error details:', JSON.stringify(error, null, 2));
                const errorMessage = error.body?.message || error.message || 'Unknown error occurred';
                this.showError('Error', 'Failed to load customer summary: ' + errorMessage);
                this.isLoading = false;
            });
    }

    handleLoanExpand(event) {
        const loanId = event.detail.loanId;
        // Handle loan expansion - details will be loaded by loanAccountCard component
    }

    // Filter handlers for summary cards
    handleFilterClick(event) {
        const filterType = event.currentTarget.dataset.filter;
        console.log('Filter clicked:', filterType);
        this.currentFilter = filterType;
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
        const totalPaid = (this.accountInfo?.totalLoanAmount || 0) - (this.accountInfo?.totalPrincipalRemaining || 0);
        return this.formatCurrency(totalPaid);
    }

    get formattedTotalBilledAmount() {
        return this.formatCurrency(this.accountInfo?.totalBilledAmount || 0);
    }

    // Pie chart path calculations
    // Helper function to create SVG arc path
    createArcPath(cx, cy, radius, startAngle, endAngle) {
        const start = this.polarToCartesian(cx, cy, radius, endAngle);
        const end = this.polarToCartesian(cx, cy, radius, startAngle);
        const largeArcFlag = endAngle - startAngle <= 180 ? "0" : "1";
        return [
            "M", cx, cy,
            "L", start.x, start.y,
            "A", radius, radius, 0, largeArcFlag, 0, end.x, end.y,
            "Z"
        ].join(" ");
    }

    polarToCartesian(centerX, centerY, radius, angleInDegrees) {
        const angleInRadians = (angleInDegrees - 90) * Math.PI / 180.0;
        return {
            x: centerX + (radius * Math.cos(angleInRadians)),
            y: centerY + (radius * Math.sin(angleInRadians))
        };
    }

    // Loan Progress Pie Chart - Total Principal Remaining vs Total Loan Amount
    get loanProgressRemainingPath() {
        const totalLoan = this.accountInfo?.totalLoanAmount || 0;
        const principalRemaining = this.accountInfo?.totalPrincipalRemaining || 0;
        const remainingPercentage = totalLoan > 0 ? (principalRemaining / totalLoan) * 100 : 0;
        const startAngle = 0;
        const endAngle = (remainingPercentage / 100) * 360;
        return this.createArcPath(100, 100, 90, startAngle, endAngle);
    }

    get loanProgressPaidPath() {
        const totalLoan = this.accountInfo?.totalLoanAmount || 0;
        const principalRemaining = this.accountInfo?.totalPrincipalRemaining || 0;
        const remainingPercentage = totalLoan > 0 ? (principalRemaining / totalLoan) * 100 : 0;
        const paidPercentage = 100 - remainingPercentage;
        const startAngle = (remainingPercentage / 100) * 360;
        const endAngle = 360;
        return this.createArcPath(100, 100, 90, startAngle, endAngle);
    }

    // Payment Status Pie Chart
    get paymentStatusBilledPath() {
        const totalBilled = this.accountInfo?.totalBilledAmount || 0;
        const delinquent = this.accountInfo?.totalDelinquentAmount || 0;
        const total = totalBilled + delinquent;
        const billedPercentage = total > 0 ? (totalBilled / total) * 100 : 0;
        const startAngle = 0;
        const endAngle = (billedPercentage / 100) * 360;
        return this.createArcPath(100, 100, 90, startAngle, endAngle);
    }

    get paymentStatusDelinquentPath() {
        const totalBilled = this.accountInfo?.totalBilledAmount || 0;
        const delinquent = this.accountInfo?.totalDelinquentAmount || 0;
        const total = totalBilled + delinquent;
        const billedPercentage = total > 0 ? (totalBilled / total) * 100 : 0;
        const delinquentPercentage = 100 - billedPercentage;
        const startAngle = (billedPercentage / 100) * 360;
        const endAngle = 360;
        return this.createArcPath(100, 100, 90, startAngle, endAngle);
    }
}

