import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CONSTANTS, reduceErrors } from 'q2lwcc/utils';
import getRelationshipGraphData from '@salesforce/apex/RelationshipGraphController.getRelationshipGraphData';
import getPartyAccountId from '@salesforce/apex/RelationshipGraphController.getPartyAccountId';


export default class PartyRelationshipGraph extends LightningElement {
    @api recordId;
    @api contextMode = 'AUTO'; // AUTO | ACCOUNT | APPLICATION
    @api selectedAccountId;
    @api sectionWidth = 1200;
    @api componentTitle = 'Relationship Graph';
    @api partyId; //when invoked from application, partyId will be used

    pageRef;
    isLoading = true;
    errorFlag = false;
    detailErrorMsg;
    resolvedApplicationId;
    resolvedAccountId;

    graphByAccountId = {};
    partyAccountIds = [];
    graphSelectedAccountId;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        this.pageRef = pageRef;
        this.resolveContextIds();
    }

    connectedCallback() {
        this.resolveContextIds();
    }

    get normalizedContextMode() {
        return (this.contextMode || 'AUTO').toUpperCase();
    }

    get isApplicationContext() {
        if (this.normalizedContextMode === 'APPLICATION') {
            return true;
        }
        if (this.normalizedContextMode === 'ACCOUNT') {
            return false;
        }
        // AUTO mode: prefer explicit c__applicationId or application recordId pattern.
        return !!this.resolvedApplicationId;
    }

    get isAccountContext() {
        return !this.isApplicationContext;
    }

    get effectiveSectionWidth() {
        // Keep a stable layout width for the graph renderer.
        // Using live offsetWidth can create a feedback loop where graph width grows each render.
        return this.sectionWidth || 1200;
    }

    get hasGraphData() {
        return this.graphByAccountId && Object.keys(this.graphByAccountId).length > 0;
    }

    get graphErrorMessage() {
        return this.detailErrorMsg || 'Unable to load relationship graph.';
    }

    resolveContextIds() {
        const state = this.pageRef?.state || {};
        const attributes = this.pageRef?.attributes || {};
        const pageAccountId = state.c__accountId;
        const pageApplicationId = state.c__applicationId;
        const explicitSelectedAccountId = this.selectedAccountId || state.c__selectedAccountId;
        const stateRecordId = state.recordId || state.c__recordId || null;
        const attributeRecordId = attributes.recordId || null;
        const urlRecordId = this.extractRecordIdFromUrl();
        const resolvedRecordId = this.recordId || stateRecordId || attributeRecordId || urlRecordId || null;

        this.resolvedApplicationId = pageApplicationId || null;
        this.resolvedAccountId = explicitSelectedAccountId || pageAccountId || null;

        // Preserve the application context even when partyId supplies the selected Account.
        if (resolvedRecordId) {
            if (resolvedRecordId.startsWith('001')) {
                this.resolvedAccountId = this.resolvedAccountId || resolvedRecordId;
            } else if (!this.resolvedApplicationId) {
                this.resolvedApplicationId = resolvedRecordId;
            }
        }

        // Explicit mode override to avoid AUTO ambiguity.
        if (this.normalizedContextMode === 'ACCOUNT') {
            this.resolvedApplicationId = null;
            this.resolvedAccountId = this.resolvedAccountId || resolvedRecordId;
        } else if (this.normalizedContextMode === 'APPLICATION') {
            this.resolvedApplicationId = this.resolvedApplicationId || resolvedRecordId;
        }
    }

    extractRecordIdFromUrl() {
        if (import.meta.env.SSR || !window?.location?.pathname) {
            return null;
        }
        const match = window.location.pathname.match(/\/([a-zA-Z0-9]{15,18})\/(?:view|edit|related|clone)(?:\/|$)/);
        return match ? match[1] : null;
    }

    @wire(getRelationshipGraphData, {
        applicationId: '$resolvedApplicationId',
        accountId: '$resolvedAccountId'
    })
    wiredGraphData(result) {
        this.isLoading = false;
        const { data, error } = result;
        if (data) {
            if (data.status === CONSTANTS.STATUS_SUCCESS) {
                this.errorFlag = false;
                this.detailErrorMsg = null;
                this.graphByAccountId = data.response?.graphByAccountId || {};
                this.partyAccountIds = data.response?.applicationPartyAccountIds || [];
                this.graphSelectedAccountId = data.response?.selectedAccountId;
            } else {
                this.errorFlag = true;
                this.detailErrorMsg = reduceErrors(data.messages).join('\n');
            }
        } else if (error) {
            this.errorFlag = true;
            this.detailErrorMsg = reduceErrors(error).join('\n');
        }
    }

    @wire(getPartyAccountId, { partyId: '$partyId' })
    wiredPartyAccountId(result) {
        const { data, error } = result;
        if (data) {
            if (data.status === CONSTANTS.STATUS_SUCCESS) {
                this.selectedAccountId = data.response;
                // Feed the resolved account id into the graph context so the wire refetches.
                this.resolveContextIds();
            } else {
                this.errorFlag = true;
                this.detailErrorMsg = reduceErrors(data.messages).join('\n');
            }
        } else if (error) {
            this.errorFlag = true;
            this.detailErrorMsg = reduceErrors(error).join('\n');
        }
    }
}