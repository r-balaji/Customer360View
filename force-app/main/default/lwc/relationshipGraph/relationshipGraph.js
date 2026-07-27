/* global d3 */
import { LightningElement, api} from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript} from 'lightning/platformResourceLoader';
import D3 from '@salesforce/resourceUrl/q2lwcc__d3js';
import LIGHTNING_ICONS from '@salesforce/resourceUrl/q2lwcc__Lightning_Icons';
import getAccountCollateralDetails from '@salesforce/apex/AccountCollateralController.getAccountCollateralDetails';

export default class RelationshipGraph extends LightningElement {
    @api invokedFromAccountPage = false;

    nodes_data = [];

    links_data = [];

    levelLines = [];

    graph = {
        nodes: {},
        links: {},
    };

    boxWidth = 280;

    boxHeight = 116;

    accordionSectionDefPadding = 24;

    gap = {
        width: 96,
        height: 116,
        sublevel: 72
    };

    label = {
        width: 116,
        height: 22,
    };

    margin = {
        top: 40,
        right: 32,
        bottom: 72,
        left: 32
    };

    colorScheme = {
        'Individual': '#16A34A',
        'Business' : '#1473E6',
        'Trust': '#7C3AED'
    }

    softColorScheme = {
        'Individual': '#DCFCE7',
        'Business': '#DBEAFE',
        'Trust': '#EDE9FE'
    }

    fontFamily = 'Salesforce Sans, Arial, sans-serif';

    nodeUserIcons = {
        'Individual':'people',
        'Business':'employee_contact',
        'Trust':'shield'
    }

    errorFlag = false;
    detailErrorMsg;
    isMaxNodesPerRowEven;
    maxNodesPerRow;
    _selectedPartyAccId;
    defaultNodesPerRow = 5;
    minimumNodesPerRow = 2;
    maximumNodesPerRow = 8;
    sectionHeight = 680;
    link;
    relationshipLoaded = false;
    _sectionWidth;
    _providedSectionWidth;
    _partyAccountsList = [];
    _allApplicationRelationshipList;
    _accountCollateralByAccount = {};
    selectedCollateralAccount;
    graphSubtitle = 'Select an entity to explore its relationship network.';
    zoomLevel = 1;
    _baseCanvasWidth;
    _baseCanvasHeight;
    _svgRoot;
    _svgStage;
    _stageOffsetX = 0;
    _selectedNodeSid;
    _columnOverride;
    _collateralLoadKey;
    _resizeObserver;
    _centerTimer;
    isD3Loaded = false;
    graphRenderVersion = 0;
    rootResolutionMode = 'none';

    @api  get sectionWidth(){
        return this._sectionWidth;
    }

    set sectionWidth(value){
        this._providedSectionWidth = Number(value) || 0;
        this._sectionWidth = value;
    }

    @api get partyAccountsList(){
        return this._partyAccountsList;
    }

    set partyAccountsList(value){
        this._partyAccountsList = value || [];
        if(this.relationshipLoaded && !this.invokedFromAccountPage){
            this.initializeProps();
            this.invokeGraph();
        }
    }

    @api get allApplicationRelationshipList(){
        return this._allApplicationRelationshipList;
    }

    set allApplicationRelationshipList(value){
        this._allApplicationRelationshipList = value;
        if(this.relationshipLoaded){
            this.initializeProps();
            this.invokeGraph();
        }
    }

    @api get accountCollateralByAccount(){
        return this._accountCollateralByAccount;
    }

    set accountCollateralByAccount(value){
        this._accountCollateralByAccount = value || {};
        if(this.relationshipLoaded && this.invokedFromAccountPage){
            this.initializeProps();
            this.invokeGraph();
        }
    }

    @api
    set selectedPartyAccId(value) {
        this._selectedPartyAccId = value;
        if(this.relationshipLoaded){
            this.initializeProps();
            this.invokeGraph();
        }
    }

    get selectedPartyAccId() {
        return this._selectedPartyAccId;
    }

    connectedCallback(){
        this.initializeProps();
        this.invokeGraph();
        this.relationshipLoaded = true;
    }

    renderedCallback() {
        if (import.meta.env.SSR || this._resizeObserver || !window.ResizeObserver) {
            return;
        }
        const viewport = this.template.querySelector('.graph');
        if (viewport) {
            this._resizeObserver = new window.ResizeObserver(() => this.centerRootInViewport());
            this._resizeObserver.observe(viewport);
        }
    }

    disconnectedCallback() {
        this._resizeObserver?.disconnect();
        this._resizeObserver = undefined;
        if (this._centerTimer) {
            clearTimeout(this._centerTimer);
            this._centerTimer = undefined;
        }
    }

    initializeProps(){
        this.nodes_data = [];
        this.links_data = [];
        this.levelLines = [];
        this.graph = {
            nodes: {},
            links: {},
        };
    }

    invokeGraph() {
        const renderVersion = ++this.graphRenderVersion;
        const loadD3Promise = this.isD3Loaded ? Promise.resolve() : loadScript(this, D3);
        Promise.all([
            loadD3Promise
        ])
        .then(()=>{
            if (renderVersion !== this.graphRenderVersion) {
                return;
            }
            this.isD3Loaded = true;
            this.initializeD3();
            if(!import.meta.env.SSR){
                this.dispatchEvent(new CustomEvent('load'));
            }
        })
        .catch(error =>{
            if(!import.meta.env.SSR){
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.message,
                        variant: 'error'
                    })
                );
            }
        });
    }

    getSelectedRootAccount() {
        if (!this.selectedPartyAccId) {
            this.rootResolutionMode = 'no-selected-id';
            return null;
        }
        const account = this.getAccountById(this.selectedPartyAccId);
        this.rootResolutionMode = account ? 'selected-id' : 'selected-id-not-found';
        return account;
    }


    getAccountById(accountId) {
        if (!this.allApplicationRelationshipList || !accountId) {
            return null;
        }

        const directMatch = this.allApplicationRelationshipList[accountId];
        if (directMatch) {
            return directMatch;
        }

        const account15 = String(accountId).substring(0, 15);
        const matchedKey = Object.keys(this.allApplicationRelationshipList).find(
            (key) => String(key).substring(0, 15) === account15
        );
        if (matchedKey) {
            return this.allApplicationRelationshipList[matchedKey];
        }

        const matchedValue = Object.values(this.allApplicationRelationshipList).find(
            (account) => account?.Id && String(account.Id).substring(0, 15) === account15
        );
        if (matchedValue) {
            return matchedValue;
        }

        // Application payloads can carry selected account only in relationship rows.
        // Search relationship records for a matching Account shape and use it as root.
        for (const account of Object.values(this.allApplicationRelationshipList)) {
            const entityRels = account?.clcommon__EntityRelationships__r || [];
            for (const rel of entityRels) {
                const candidate = rel?.clcommon__Related_Entity__r;
                if (candidate?.Id && String(candidate.Id).substring(0, 15) === account15) {
                    return candidate;
                }
            }

            const relatedEntityRels = account?.clcommon__RelatedEntityRelationships__r || [];
            for (const rel of relatedEntityRels) {
                const candidate = rel?.clcommon__Entity__r;
                if (candidate?.Id && String(candidate.Id).substring(0, 15) === account15) {
                    return candidate;
                }
            }
        }
        return null;
    }

    getNodePresentationType(node) {
        const legalEntityType = String(node?.class || '').toLowerCase();
        return legalEntityType.includes('trust') ? 'Trust' : node.type;
    }

    getNodeColor(node) {
        return this.colorScheme[this.getNodePresentationType(node)];
    }

    getNodeSoftColor(node) {
        return this.softColorScheme[this.getNodePresentationType(node)];
    }

    getNodeIcon(node) {
        return this.nodeUserIcons[this.getNodePresentationType(node)];
    }

    getAccountCollateral(accountId) {
        if (!accountId || !this._accountCollateralByAccount) {
            return null;
        }
        const directMatch = this._accountCollateralByAccount[accountId];
        if (directMatch) {
            return directMatch;
        }
        const account15 = String(accountId).substring(0, 15);
        const matchedKey = Object.keys(this._accountCollateralByAccount).find(
            (key) => String(key).substring(0, 15) === account15
        );
        return matchedKey ? this._accountCollateralByAccount[matchedKey] : null;
    }

    openCollateralPanel(accountId) {
        const accountDetails = this.getAccountCollateral(accountId);
        if (!accountDetails?.collaterals?.length) {
            this.selectedCollateralAccount = undefined;
            return;
        }
        this.selectedCollateralAccount = {
            ...accountDetails,
            collaterals: accountDetails.collaterals.map((collateral) => ({
                ...collateral,
                displayValue: collateral.appraisedValue ?? collateral.recordedValue,
                valueLabel: collateral.appraisedValue != null ? 'Appraised value' : 'Recorded value',
                hasDisplayValue: collateral.appraisedValue != null || collateral.recordedValue != null,
                hasOwnership: collateral.ownershipPercentage != null,
                hasLiens: collateral.liens?.length > 0,
                hasApplications: collateral.applications?.length > 0,
                liens: (collateral.liens || []).map((lien) => ({
                    ...lien,
                    hasAmount: lien.amount != null,
                    context: lien.applicationName || lien.loanAccountName,
                    summary: `${this.getLienKindLabel(lien.kind)}${lien.position == null ? '' : ` · Position ${lien.position}`}`
                })),
                applications: (collateral.applications || []).map((application) => ({
                    ...application,
                    hasAdvanceRate: application.advanceRate != null,
                    hasAdvanceValue: application.advanceValue != null
                }))
            }))
        };
    }

    getLienKindLabel(kind) {
        if (kind === 'APPLICATION') {
            return 'Application lien';
        }
        if (kind === 'CONTRACT') {
            return 'Contract lien';
        }
        return 'External lien';
    }

    closeCollateralPanel() {
        this.selectedCollateralAccount = undefined;
    }

    loadRenderedCollateral(accountIds) {
        const ids = [...new Set(accountIds.filter(Boolean))].sort();
        const loadKey = ids.join(',');
        if (!this.invokedFromAccountPage || !ids.length || loadKey === this._collateralLoadKey) {
            return;
        }
        this._collateralLoadKey = loadKey;
        getAccountCollateralDetails({accountIds: ids})
            .then(data => {
                this._accountCollateralByAccount = JSON.parse(JSON.stringify(data));
                this.initializeProps();
                this.invokeGraph();
            })
            .catch(error => this.dispatchEvent(new ShowToastEvent({
                title: 'Collateral unavailable',
                message: error.body?.message || error.message,
                variant: 'warning'
            })));
    }

    getNodeNameLines(name) {
        const words = String(name || '').trim().split(/\s+/).filter(Boolean);
        const lines = [];
        let currentLine = '';
        const maxCharacters = 22;

        words.forEach((word) => {
            const candidate = currentLine ? `${currentLine} ${word}` : word;
            if (candidate.length <= maxCharacters || !currentLine) {
                currentLine = candidate;
            } else if (lines.length === 0) {
                lines.push(currentLine);
                currentLine = word;
            } else {
                currentLine = `${currentLine} ${word}`;
            }
        });

        if (currentLine) {
            lines.push(currentLine);
        }

        if (lines.length > 2) {
            lines[1] = `${lines.slice(1).join(' ').slice(0, maxCharacters - 1).trim()}…`;
        }
        return lines.slice(0, 2);
    }

    getNodesPerRowForZoom() {
        if (this._columnOverride) {
            return this._columnOverride;
        }
        const responsiveCount = Math.round(this.defaultNodesPerRow / this.zoomLevel);
        return Math.max(this.minimumNodesPerRow, Math.min(this.maximumNodesPerRow, responsiveCount));
    }

    getRequiredCanvasWidth(nodesPerRow) {
        return this.margin.left + this.margin.right +
            (nodesPerRow * this.boxWidth) +
            ((nodesPerRow - 1) * this.gap.width);
    }

    initializeD3(preserveView = false){
        const self = this;
        const parent = d3.select(this.template.querySelector('.graph'));
        if (!preserveView) {
            this.zoomLevel = 1;
            this._selectedNodeSid = undefined;
            this.selectedCollateralAccount = undefined;
        }
        let rootAccount = this.getSelectedRootAccount();
        if (!rootAccount && !this.selectedPartyAccId && this.allApplicationRelationshipList) {
            const firstKey = Object.keys(this.allApplicationRelationshipList)[0];
            rootAccount = firstKey ? this.allApplicationRelationshipList[firstKey] : null;
            if (rootAccount) {
                this.rootResolutionMode = 'first-account-fallback';
            }
        }
        if (!rootAccount) {
            // Keep the current canvas visible if root resolution is temporarily unavailable.
            this.graphSubtitle = 'Waiting for relationship graph data.';
            return;
        }
        parent.selectAll('*').remove();
        this.getAccountSpecificData(rootAccount, 0);
        this.formatData();
        this.loadRenderedCollateral(this.nodes_data.map(node => node.sid));
        const relatedEntityCount = Math.max(0, this.nodes_data.length - 1);
        this.graphSubtitle = `${rootAccount.Name} · ${relatedEntityCount} related ${relatedEntityCount === 1 ? 'entity' : 'entities'}`;
        const nodesPerRow = this.getNodesPerRowForZoom();
        const minWidth = this.getRequiredCanvasWidth(nodesPerRow);
        this._sectionWidth = Math.max(this._providedSectionWidth || 1200, minWidth);
        const svgRoot = parent.append('svg')
                            .attr('class', 'relationship-canvas')
                            .attr('width', this._sectionWidth)
                            .attr('height', self.sectionHeight)
                            .attr('role', 'group')
                            .attr('aria-label', 'Interactive account relationship network');
        let svg = svgRoot.append('g');

        this.maxNodesPerRow = nodesPerRow;
        this.isMaxNodesPerRowEven = (this.maxNodesPerRow % 2 === 0) ? true : false;
        this.renderRelationshipGraph(this.maxNodesPerRow);
        this._baseCanvasWidth = this._sectionWidth;
        this._baseCanvasHeight = Number(svgRoot.attr('height')) || this.sectionHeight;
        this._svgRoot = svgRoot;
        this._svgStage = svg;
        this.applyZoom();

        //set up the simulation
        d3.forceSimulation().nodes(this.nodes_data);
        d3.forceLink(this.links_data).id((d) => d.id);
        d3.forceManyBody().strength(-100);

        this.link = svg.append('g').attr('class', 'links');
        this.links_data.forEach((relationship) => {
            this.drawLine(relationship.id, relationship.source, relationship.target);
        });
        svg.append('g').attr('class', 'nodes');
        let node = svg.select('.nodes')
                        .selectAll('g')
                        .data(this.nodes_data)
                        .enter()
                        .append('g')
                        .attr('class', (d) => (!this.invokedFromAccountPage && !d.inApplication) ? 'unit is-related-account' : 'unit')
                        .style('--entity-color', (d) => this.getNodeColor(d))
                        .attr('role', 'button')
                        .attr('tabindex', 0)
                        .attr('aria-pressed', 'false')
                        .attr('aria-label', (d) => `${d.name}, ${d.relationshipRole ? `${d.relationshipRole}, ` : ''}${d.class || d.type}${d.inApplication ? ', application party' : ', related account'}${d.collateralCount ? `, ${d.collateralCount} owned collateral` : ''}`);

        let clickNode;
        const activateNode = (targetNode) => {
            const selectedNode = d3.select(targetNode).datum();
            if(!self.invokedFromAccountPage && selectedNode.inApplication && selectedNode.sid !== self.selectedPartyAccId){
                self.selectedPartyAccId = selectedNode.sid;
                return;
            }
            if(clickNode){
                clickNode.selected = false;
                d3.select(clickNode.parentNode)
                    .attr('aria-pressed', 'false')
                    .classed('is-active', false);
                self.addOrRemoveLinks(d3.select(clickNode).datum(), false);
            }
            clickNode = targetNode;
            clickNode.selected = true;
            self._selectedNodeSid = d3.select(clickNode).datum().sid;
            d3.select(clickNode.parentNode)
                .attr('aria-pressed', 'true')
                .classed('is-active', true);
            self.addOrRemoveLinks(d3.select(clickNode).datum(), true);
            if (self.invokedFromAccountPage) {
                self.openCollateralPanel(selectedNode.sid);
            }
        };

        node.append('title')
            .text((d) => `${d.name}${d.relationshipRole ? ` - ${d.relationshipRole}` : ''} - ${d.class || d.type}${d.inApplication ? ' - Application party' : ' - Related account'}`);

        node.on('keydown', function(event) {
            if(event.key === 'Enter' || event.key === ' '){
                event.preventDefault();
                const targetNode = d3.select(this).select('rect.node').node();
                if(targetNode){
                    activateNode(targetNode);
                }
            }
        });

        node.append('rect')
            .attr('x', (d) => d.x)
            .attr('y',  (d) => d.y)
            .attr('id',  (d) => d.id)
            .attr('width', self.boxWidth)
            .attr('height', self.boxHeight)
            .attr('class', 'node')
            .attr('stroke', (d) => (!this.invokedFromAccountPage && !d.inApplication) ? this.getNodeColor(d) : '#E5E5E5')
            .attr('fill', '#FFFFFF')
            .attr('stroke-width', '1.25px')
            .attr('stroke-dasharray', (d) => (!this.invokedFromAccountPage && !d.inApplication) ? '6 4' : null)
            .attr('cursor', 'pointer')
            .attr('selected', false)
            .attr('rx', 11)
            .attr('ry', 11)
            .on('click', function() {
                activateNode(this);
            });

        //adding rect shape for left border
        node.append('rect')
            .attr('class', 'node-accent')
            .attr('x', (d) => { return d.x + 1; })
            .attr('y',  (d) => { return d.y + 1; })
            .attr('width', 7)
            .attr('height', self.boxHeight - 2)
            .attr('fill', (d) => this.getNodeColor(d))
            .attr('rx', 5)
            .attr('ry', 5)
            .attr('pointer-events', 'none');

        //for top right selected icon
        const selectdIcon = node.append('svg')
                                .attr('id', (d) =>'icon-' + d.id )
                                .attr('x', (d) =>  d.x + this.boxWidth - 30)
                                .attr('y', (d) => d.y + 11)
                                .attr('width',18)
                                .attr('height',18)
                                .attr('fill','#fff')
                                .attr('viewBox','1000 1000')
                                .attr('pointer-events', 'none')
                                .attr('style', 'visibility: hidden');

        selectdIcon.append('rect')
            .attr('width',18)
            .attr('height',18)
            .attr('rx',10)
            .attr('ry',10)
            .attr('pointer-events', 'none')
            .style('fill','#1473E6');

        selectdIcon.append('use')
            .attr('xlink:href',LIGHTNING_ICONS + '#task2');

        node.append('g')
            .attr('class', 'text-box')
            .attr('id', (d) => 'badge-' + d.id)
            .attr('active', false)
            .append('rect')
                .attr('class', 'type')
                .attr('pointer-events', 'none')
                .attr('fill', '#F2F2F2')
                .attr('stroke', '#F2F2F2')
                .attr('stroke-width', '1px')
                .attr('rx', 12)
                .attr('ry', 12)
                .attr('x', (d) => d.x + 22)
                .attr('y', (d) => d.y + 82)
                .attr('selected',false)
                .attr('width', (d)=>Math.min(190, Math.max(64, ((d.class || d.type || 'Entity').length * 6.5) + 22)))
                .attr('height', self.label.height);

        node.selectAll("g.text-box").append('text')
            .attr('x', (d) => d.x + 22 + Math.min(190, Math.max(64, ((d.class || d.type || 'Entity').length * 6.5) + 22))/2)
            .attr('y', (d) => d.y + 97)
            .attr('font-family', self.fontFamily)
            .attr('font-size', '11.25')
            .attr('font-weight', '600')
            .attr('fill', '#5C5C5C')
            .attr('text-anchor', 'middle')
            .attr('class','type-text')
            .attr('pointer-events', 'none')
            .text((d) => d.class || d.type);

        const nameText = node.append('text')
                .attr('x', (d) => d.x + 72)
                .attr('y', (d) => d.y + 22)
                .attr('font-family', self.fontFamily)
                .attr('font-size', '16')
                .attr('font-weight', (d) => d.inApplication ? '700' : '600')
                .attr('fill', '#181818')
                .attr('class', 'name-text')
                .attr('text-anchor', 'start')
                .attr('alignment-baseline', 'text-before-edge');

        nameText.each(function(d) {
            const lines = self.getNodeNameLines(d.name);
            d3.select(this)
                .selectAll('tspan')
                .data(lines)
                .enter()
                .append('tspan')
                .attr('x', d.x + 72)
                .attr('dy', (line, index) => index === 0 ? 0 : 19)
                .text((line) => line);
        });

        node.append('text')
            .attr('x', (d) => d.x + 72)
            .attr('y', (d) => d.y + 69)
            .attr('font-family', self.fontFamily)
            .attr('font-size', '11.5')
            .attr('font-weight', '600')
            .attr('fill', '#5C5C5C')
            .attr('class', 'relationship-text')
            .attr('pointer-events', 'none')
            .text((d) => d.relationshipRole || '');

        node.append('text')
            .attr('x', (d) => d.x + self.boxWidth - 18)
            .attr('y', (d) => d.y + 97)
            .attr('text-anchor', 'end')
            .attr('font-size', '11')
            .attr('font-weight', '700')
            .attr('fill', (d) => self.getNodeColor(d))
            .attr('class', 'ownership-text')
            .attr('pointer-events', 'none')
            .text((d) => d.ownershipPercentage == null ? '' : `${d.ownershipPercentage}% Ownership`);

        //for user icons in each nodes
        const nodeIcon = node.append('svg')
                        .attr('x' ,(d)=> d.x + 22 )
                        .attr('y' ,(d)=> d.y + 18)
                        .attr('width',38)
                        .attr('height',38)
                        .style('fill',(d) => this.getNodeColor(d))
                        .attr('viewBox','1000 1000');

        nodeIcon.append('rect')
                    .attr('width',38)
                    .attr('height',38)
                    .attr('rx',9)
                    .attr('ry',9)
                    .style('pointer-events','none')
                    .style('fill',(d) => this.getNodeSoftColor(d));

        nodeIcon.append('use')
                        .attr('xlink:href',(d) => LIGHTNING_ICONS + `#${self.getNodeIcon(d)}`);

        const collateralIndicator = node.filter((d) => d.collateralCount > 0)
            .append('g')
            .attr('class', 'collateral-node-indicator')
            .attr('aria-hidden', 'true');

        collateralIndicator.append('circle')
            .attr('cx', (d) => d.x + 57)
            .attr('cy', (d) => d.y + 52)
            .attr('r', 11)
            .attr('fill', '#EA580C')
            .attr('stroke', '#FFFFFF')
            .attr('stroke-width', 2);

        collateralIndicator.append('text')
            .attr('x', (d) => d.x + 57)
            .attr('y', (d) => d.y + 56)
            .attr('text-anchor', 'middle')
            .attr('font-family', self.fontFamily)
            .attr('font-size', '10')
            .attr('font-weight', '700')
            .attr('fill', '#FFFFFF')
            .text((d) => {
                return d.collateralCount > 9 ? '9+' : d.collateralCount;
            });

        if (this._selectedNodeSid) {
            const selectedNode = node
                .filter((d) => d.sid === this._selectedNodeSid)
                .select('rect.node')
                .node();
            if (selectedNode) {
                activateNode(selectedNode);
            } else {
                this._selectedNodeSid = undefined;
            }
        }
        this.centerRootInViewport();
    }

    getAccountSpecificData(account, level){
        let node = this.addAccountNode(account, level);
        if(!node.processed){
            node.processed = true;
            let accResult = this.getAccountById(account.Id);
            if(accResult){
                let queriedAccount = accResult;

                let accountsToProcess = [];

                // add entities
                let entityRelations = queriedAccount.clcommon__EntityRelationships__r;
                if(entityRelations && entityRelations.length){
                    let records = [];
                    if(entityRelations.length > 1){
                        records = [...entityRelations];
                    } else {
                        records.push(...entityRelations);
                    }

                    for(let i = 0; i < records.length; i++) {
                        let relation = records[i];
                        if(!relation.clcommon__Related_Entity__c){
                            continue;
                        }
                        this.addRelation(queriedAccount.Id,
                                    relation.clcommon__Related_Entity__c,
                                    relation.clcommon__Entity_Role__c,
                                    relation.clcommon__Related_Entity_Role__c,
                                    relation.clcommon__Ownership_Percentage__c);
                        this.addAccountNode(relation.clcommon__Related_Entity__r, level + 1);
                        accountsToProcess.push(relation.clcommon__Related_Entity__r);
                    }
                }

                // add related entities
                let relatedEntityRelations = queriedAccount.clcommon__RelatedEntityRelationships__r;
                if(relatedEntityRelations && relatedEntityRelations.length){
                    let records = [];
                    if(relatedEntityRelations.length > 1){
                        records = [...relatedEntityRelations];
                    } else {
                        records.push(...relatedEntityRelations);
                    }
                    for (let i = 0; i < records.length; i++) {
                        let relation = records[i];
                        if(!relation.clcommon__Entity__c)
                          continue;
                        this.addRelation(queriedAccount.Id,
                                    relation.clcommon__Entity__c,
                                    relation.clcommon__Related_Entity_Role__c,
                                    relation.clcommon__Entity_Role__c,
                                    relation.clcommon__Ownership_Percentage__c);
                        this.addAccountNode(relation.clcommon__Entity__r, level + 1);
                        accountsToProcess.push(relation.clcommon__Entity__r);
                    }
                }

                // process added accounts
                if(accountsToProcess && accountsToProcess.length){
                    for (let i = 0; i < accountsToProcess.length; i++) {
                        this.getAccountSpecificData(accountsToProcess[i],  node.level + 1);
                    }
                }
            }
        }
    }

    addRelation(n1, n2, n1Ton2Relation, n2Ton1Relation, ownershipPercentage){
        // check if the relation exists
        let areNodesLinked = false;
        if((this.graph.links[n1] && this.graph.links[n1][n2] && this.graph.links[n1][n2][0] === n1Ton2Relation) ||
                (this.graph.links[n2] && this.graph.links[n2][n1] && this.graph.links[n2][n1][0] === n2Ton1Relation)){
            areNodesLinked = true;
        }
        if(!areNodesLinked){
            let n1Relations = this.graph.links[n1];
            if(!n1Relations){
                n1Relations = {};
                this.graph.links[n1] = n1Relations;
            }
            if(!n2Ton1Relation){
                n2Ton1Relation = n1Ton2Relation;
            }
            n1Relations[n2] = [n1Ton2Relation, n2Ton1Relation, ownershipPercentage];
        }
    }

    addAccountNode(acc, level){
        if(!this.graph.nodes[acc.Id]){
            const inApplication = this.invokedFromAccountPage || this.isApplicationParty(acc.Id);
            const collateralDetails = this.invokedFromAccountPage ? this.getAccountCollateral(acc.Id) : null;
            this.graph.nodes[acc.Id] = {
                'sid': acc.Id,
                'name': acc.Name,
                'type': 'Business',
                'level': level,
                'processed' : false,
                'inApplication' : inApplication,
                'collateralCount': collateralDetails?.collaterals?.length || 0
            };
            if(acc.clcommon__Legal_Entity_Type__c){
                this.graph.nodes[acc.Id].class = acc.clcommon__Legal_Entity_Type__r.Name;
                if(acc.clcommon__Legal_Entity_Type__r.Name === 'Individual'
                    || acc.clcommon__Legal_Entity_Type__r.Name === 'Sole Proprietorship'){
                    this.graph.nodes[acc.Id].type = 'Individual';
                }
            }
        } else {
            if(level < this.graph.nodes[acc.Id].level){
                this.graph.nodes[acc.Id].level = level;
            }
        }
        return this.graph.nodes[acc.Id];
    }

    isApplicationParty(accountId){
        const comparableId = String(accountId || '').substring(0, 15);
        return this._partyAccountsList.some(id => String(id || '').substring(0, 15) === comparableId);
    }

    formatData(){
        // add all nodes and links to graph
        for(let key in this.graph.nodes){
            if (Object.hasOwn(this.graph.nodes, key)) {
                let obj = this.graph.nodes[key];
                obj.selected = false;
                this.nodes_data.push(obj);
                // get all links and map it
                let relationMapping = this.graph.links[key];
                if(relationMapping){
                    let parent = this.graph.nodes[key];
                    for(let linkKey in relationMapping){
                        if (Object.hasOwn(relationMapping, linkKey)) {
                            let child = this.graph.nodes[linkKey];
                            this.links_data.push({
                                'source': parent.sid,
                                'target': child.sid,
                                'relationship': relationMapping[linkKey],
                            });
                        }
                    }
                }
            }
        }
    }

    renderRelationshipGraph(maxNodesPerRow) {
        let count = [];
        let subLevel = [];
        let maxHeight = this.sectionHeight - this.margin.bottom;

        this.nodes_data.forEach( (d) => {
            if(count[d.level]){
                count[d.level] += 1;
            } else {
                count[d.level] = 1;
            }

            d.colIndex = (count[d.level] - 1) % maxNodesPerRow;
            d.sublevel = Math.floor((count[d.level] - 1)/maxNodesPerRow);
            subLevel[d.level] = d.sublevel;
        });

        count.forEach((node, index) => {
            let lNode = {
                level : index,
            };
            let totalNoOfSubLevels = 0;
            for(let t = 0; t <= index; t++){
                totalNoOfSubLevels += subLevel[t];
            }
            lNode.y = (this.margin.top) + ((this.boxHeight + this.gap.height) * index) + ((this.boxHeight + this.gap.sublevel) * totalNoOfSubLevels) + this.boxHeight + this.gap.height / 2;
            this.levelLines.push(lNode);
        });

        this.nodes_data.forEach((d, i)=>{
            const nodesInRow = Math.min(
                maxNodesPerRow,
                count[d.level] - (d.sublevel * maxNodesPerRow)
            );
            const availableWidth = this._sectionWidth - this.margin.left - this.margin.right;
            const rowWidth = (nodesInRow * this.boxWidth) + ((nodesInRow - 1) * this.gap.width);
            const rowStart = this.margin.left + Math.max(0, (availableWidth - rowWidth) / 2);
            d.x = rowStart + ((this.boxWidth + this.gap.width) * d.colIndex);

            // get no of levels
            let totalNoOfSubLevels = 0;
            for(let t = 0; t < d.level ; t++){
                totalNoOfSubLevels = totalNoOfSubLevels + subLevel[t];
            }
            d.y = this.margin.top + ((this.boxHeight + this.gap.height) * d.level) + ((this.boxHeight + this.gap.sublevel) * (totalNoOfSubLevels + d.sublevel));
            if(d.y + this.boxHeight > maxHeight){
                maxHeight = d.y + this.boxHeight;
            }
            d.id = 'n' + i;
        });

        const rootNode = this.nodes_data.find((node) => node.level === 0);
        this.links_data.forEach((d) => {
            d.source = this.findNodeBySID(d.source);
            d.target = this.findNodeBySID(d.target);
            d.id = 'l' + d.source.id + d.target.id;
            d.sourcerole = d.relationship[0];
            d.targetrole = d.relationship[1] ? d.relationship[1] : d.relationship[0];
            const linkedNode = d.source === rootNode ? d.target : d.target === rootNode ? d.source : null;
            if(linkedNode && d.relationship[2] != null){
                linkedNode.ownershipPercentage = d.relationship[2];
            }
            const relatedNode = d.source.level > d.target.level ? d.source : d.target.level > d.source.level ? d.target : null;
            if(relatedNode && !relatedNode.relationshipRole){
                relatedNode.relationshipRole = relatedNode === d.source ? d.sourcerole : d.targetrole;
            }
        });

        if(maxHeight + this.margin.bottom > this.sectionHeight){
            d3.select(this.template.querySelector('.graph > svg')).attr('height', maxHeight + this.margin.bottom + this.margin.top); // set svg height to see scroll bar
        }
    }

    findNodeBySID(text) {
        'use strict';
        let i;
        for (i = 0; i < this.nodes_data.length; i += 1) {
            if (this.nodes_data[i].sid === text) {
                return this.nodes_data[i];
            }
        }
        return null;
    }

    getPath(pathNodes){
        let dcurve = d3.curveStepAfter;
        let lineGenerator = d3.line()
        .curve(dcurve);
        let pathCoordinates = [];
        if(pathNodes){
            pathNodes.forEach((d) => {
                pathCoordinates.push([d.y, d.x]);
            });
        }
        return lineGenerator(pathCoordinates);
    }

    getCoordinates(source, target){
        let p1 = {}, p2 = {},
            p3 = {}, p4 = {};
        let connectionsList;
        // check if the nodes are aligned horizontally
        if(source.y === target.y){
            p1.x = source.y;
            p1.y = source.x + (this.boxWidth/2);

            p2.x = source.y - this.boxHeight/2;
            p2.y = source.x + (this.boxWidth/2);

            p3.x = target.y - this.boxHeight/2;
            p3.y = target.x + (this.boxWidth/2);

            // p4.x = target.y - this.label.height/2;
            p4.x = target.y;
            p4.y = target.x + (this.boxWidth/2);
            connectionsList = [p1, p2, p3, p4];
        } else if(source.x === target.x){
            // if right most nodes are connected
            if(source.colIndex === (this.maxNodesPerRow - 1)){ // to be tested
                // join from left side
                p1.x = source.y + this.boxHeight/2;
                p1.y = source.x;

                p2.x = source.y + this.boxHeight/2;
                p2.y = source.x - this.gap.width/2;

                p3.x = target.y + this.boxHeight/2;
                p3.y = target.x - this.gap.width/2;

                p4.x = target.y + this.boxHeight/2;
                p4.y = target.x;
            } else {
                // join from right side
                p1.x = source.y + this.boxHeight/2;
                p1.y = source.x + this.boxWidth;

                p2.x = source.y + this.boxHeight/2;
                p2.y = source.x + this.boxWidth + this.gap.width/2;

                p3.x = target.y + this.boxHeight/2;
                p3.y = target.x + this.boxWidth + this.gap.width/2;

                p4.x = target.y + this.boxHeight/2;
                p4.y = target.x + this.boxWidth;
            }
            connectionsList = [p1, p2, p3, p4];
        } else {
            // which side are the nodes located
            let midpoint = ((this.margin.left + this.margin.right) + this.maxNodesPerRow*(this.gap.width + this.boxWidth) - this.gap.width)/2;
            let mid = this.maxNodesPerRow/2;
            let isAdjustmentNeeded = this.isMaxNodesPerRowEven &&
                                        ((source.level === 0 && (target.colIndex === mid || target.colIndex === mid - 1)) ||
                                        (target.level === 0 && (source.colIndex === mid || source.colIndex === mid - 1)));
            if((source.x < midpoint && target.x < midpoint) || (source.x > midpoint && target.x > midpoint)){
                // both on left side or right side
                if(source.x < target.x){
                    // left node = source
                    p1.x = source.y + this.boxHeight/2;
                    p1.y = source.x + this.boxWidth;

                    p2.x = source.y + this.boxHeight/2;
                    p2.y = source.x + this.boxWidth + this.gap.width/2;

                    p3.x = target.y + this.boxHeight/2;
                    p3.y = source.x + this.boxWidth + this.gap.width/2;

                    p4.x = target.y + this.boxHeight/2;
                    p4.y = target.x;

                    if(isAdjustmentNeeded){
                        if(source.level === 0){
                            p1.x = p2.x = source.y + this.boxHeight;
                            p1.y = p2.y = source.x + this.boxWidth/2;
                        } else {
                            p3.x = p4.x = target.y + this.boxHeight;
                            p3.y = p4.y = target.x + this.boxWidth/2;
                        }
                    }
                    connectionsList = [p1, p2, p3, p4];
                } else {
                    // left node = target
                    p1.x = target.y + this.boxHeight/2;
                    p1.y = target.x + this.boxWidth;

                    p2.x = target.y + this.boxHeight/2;
                    p2.y = target.x + this.boxWidth + this.gap.width/2;

                    p3.x = source.y + this.boxHeight/2;
                    p3.y = target.x + this.boxWidth + this.gap.width/2;

                    p4.x = source.y + this.boxHeight/2;
                    p4.y = source.x;

                    if(isAdjustmentNeeded){
                        if(source.level === 0){
                            p3.x = p4.x = source.y + this.boxHeight;
                            p3.y = p4.y = source.x + this.boxWidth/2;
                        } else {
                            p1.x = p2.x = target.y + this.boxHeight;
                            p1.y = p2.y = target.x + this.boxWidth/2;
                        }
                    }
                    if(p1.y < p4.y){
                        connectionsList = [p4, p3, p2, p1];
                    }
                    else{
                        connectionsList = [p1, p2, p3, p4];
                    }

                }
            } else {
                // one on left and other on right
                if(source.x < target.x){
                    p1.x = source.y + this.boxHeight/2;
                    p1.y = source.x + this.boxWidth;

                    p2.x = source.y + this.boxHeight/2;
                    p2.y = target.x - this.gap.width/2;

                    p3.x = target.y + this.boxHeight/2;
                    p3.y = target.x - this.gap.width/2;

                    p4.x = target.y + this.boxHeight/2;
                    p4.y = target.x;

                    if(isAdjustmentNeeded){
                        if(source.level === 0){
                            p1.x = p2.x = source.y + this.boxHeight;
                            p1.y = p2.y = source.x + this.boxWidth/2;
                            p3.y = source.x + this.boxWidth/2;
                        } else {
                            p3.x = p4.x = target.y + this.boxHeight;
                            p3.y = p4.y = target.x + this.boxWidth/2;
                            p2.y = target.x + this.boxWidth/2;
                        }
                    }
                    connectionsList = [p1, p2, p3, p4];
                } else {
                    p1.x = target.y + this.boxHeight/2;
                    p1.y = target.x + this.boxWidth;

                    p2.x = target.y + this.boxHeight/2;
                    p2.y = source.x - this.gap.width/2;

                    p3.x = source.y + this.boxHeight/2;
                    p3.y = source.x - this.gap.width/2;

                    p4.x = source.y + this.boxHeight/2;
                    p4.y = source.x;

                    if(isAdjustmentNeeded){
                        if(source.level === 0){
                            p3.x = p4.x = source.y + this.boxHeight;
                            p3.y = p4.y = source.x + this.boxWidth/2;
                            p2.y = source.x + this.boxWidth/2;
                        } else {
                            p1.x = p2.x = target.y + this.boxHeight;
                            p1.y = p2.y = target.x + this.boxWidth/2;
                            p3.y = target.x + this.boxWidth/2;
                        }
                    }
                    connectionsList = [ p4,p3,p2,p1];
                }
            }
        }
        return connectionsList;
    }

    getModernCoordinates(source, target) {
        if (source.y === target.y) {
            const sourceIsLeft = source.x < target.x;
            const leftNode = sourceIsLeft ? source : target;
            const rightNode = sourceIsLeft ? target : source;
            const routeY = leftNode.y + this.boxHeight + Math.max(30, this.gap.height / 2);
            return [
                { x: leftNode.x + this.boxWidth / 2, y: leftNode.y + this.boxHeight },
                { x: leftNode.x + this.boxWidth / 2, y: routeY },
                { x: rightNode.x + this.boxWidth / 2, y: routeY },
                { x: rightNode.x + this.boxWidth / 2, y: rightNode.y + this.boxHeight }
            ];
        }

        const upperNode = source.y < target.y ? source : target;
        const lowerNode = source.y < target.y ? target : source;
        const start = {
            x: upperNode.x + this.boxWidth / 2,
            y: upperNode.y + this.boxHeight
        };
        const end = {
            x: lowerNode.x + this.boxWidth / 2,
            y: lowerNode.y
        };
        const midpointY = start.y + ((end.y - start.y) / 2);

        return [
            start,
            { x: start.x, y: midpointY },
            { x: end.x, y: midpointY },
            end
        ];
    }

    getModernPath(points, radius = 14) {
        if (!points?.length) {
            return '';
        }

        let path = `M ${points[0].x} ${points[0].y}`;
        for (let index = 1; index < points.length - 1; index += 1) {
            const previous = points[index - 1];
            const corner = points[index];
            const next = points[index + 1];
            const incoming = { x: corner.x - previous.x, y: corner.y - previous.y };
            const outgoing = { x: next.x - corner.x, y: next.y - corner.y };
            const incomingLength = Math.hypot(incoming.x, incoming.y) || 1;
            const outgoingLength = Math.hypot(outgoing.x, outgoing.y) || 1;
            const cornerRadius = Math.min(radius, incomingLength / 2, outgoingLength / 2);
            const entry = {
                x: corner.x - (incoming.x / incomingLength) * cornerRadius,
                y: corner.y - (incoming.y / incomingLength) * cornerRadius
            };
            const exit = {
                x: corner.x + (outgoing.x / outgoingLength) * cornerRadius,
                y: corner.y + (outgoing.y / outgoingLength) * cornerRadius
            };
            path += ` L ${entry.x} ${entry.y} Q ${corner.x} ${corner.y} ${exit.x} ${exit.y}`;
        }

        const lastPoint = points[points.length - 1];
        return `${path} L ${lastPoint.x} ${lastPoint.y}`;
    }

    addOrRemoveLinks(val, stat) {
        const graphElement = this.template.querySelector('.graph');
        const activeNodeIds = new Set(stat ? [val.id] : []);

        this.links_data.forEach((d) => {
            const isActiveLink = stat && (d.source.id === val.id || d.target.id === val.id);
            if (isActiveLink) {
                activeNodeIds.add(d.source.id);
                activeNodeIds.add(d.target.id);
            }

            d3.select(this.template.querySelector('#' + d.id))
                .classed('is-active', isActiveLink)
                .classed('is-dim', stat && !isActiveLink);
            d3.select(this.template.querySelector('#' + d.id + '-source'))
                .classed('is-active', isActiveLink)
                .classed('is-dim', stat && !isActiveLink);
            d3.select(this.template.querySelector('#' + d.id + '-target'))
                .classed('is-active', isActiveLink)
                .classed('is-dim', stat && !isActiveLink);
        });

        d3.select(graphElement)
            .selectAll('.unit')
            .classed('is-active', (d) => stat && d.id === val.id)
            .classed('is-neighbor', (d) => stat && d.id !== val.id && activeNodeIds.has(d.id))
            .classed('is-dim', (d) => stat && !activeNodeIds.has(d.id))
            .attr('aria-pressed', (d) => String(stat && d.id === val.id));

        d3.select(graphElement)
            .selectAll('.node')
            .attr('selected', (d) => String(stat && d.id === val.id));

        d3.select(graphElement)
            .selectAll('[id^="icon-"]')
            .attr('style', (d) => d.id === val.id && stat ? 'visibility: visible' : 'visibility: hidden');
    }

    drawLine(lineId, source, target){
        const isApplicationLink = this.invokedFromAccountPage || (source.inApplication && target.inApplication);
        const relatedNode = !source.inApplication ? source : target;
        const relationshipColor = this.getNodeColor(relatedNode);
        const coordinates = this.getModernCoordinates(source, target);
        const baseClass = isApplicationLink ? 'link' : 'link link-secondary';
        const endpointClass = isApplicationLink ? 'endpoint' : 'endpoint endpoint-secondary';

        this.link.append('path')
            .attr('class', baseClass)
            .attr('id', lineId)
            .attr('vector-effect', 'non-scaling-stroke')
            .attr('d', this.getModernPath(coordinates))
            .style('--relationship-color', relationshipColor);

        this.link.append('circle')
            .attr('id', lineId + '-source')
            .attr('class', endpointClass)
            .attr('cx', coordinates[0].x)
            .attr('cy', coordinates[0].y)
            .attr('r', 4)
            .attr('vector-effect', 'non-scaling-stroke')
            .style('--relationship-color', relationshipColor);

        const lastCoordinate = coordinates[coordinates.length - 1];
        this.link.append('circle')
            .attr('id', lineId + '-target')
            .attr('class', endpointClass)
            .attr('cx', lastCoordinate.x)
            .attr('cy', lastCoordinate.y)
            .attr('r', 4)
            .attr('vector-effect', 'non-scaling-stroke')
            .style('--relationship-color', relationshipColor);
    }

    applyZoom() {
        if (!this._svgRoot || !this._svgStage || !this._baseCanvasWidth || !this._baseCanvasHeight) {
            return;
        }
        const scaledWidth = this._baseCanvasWidth * this.zoomLevel;
        const canvasWidth = this.zoomLevel < 1 ? this._baseCanvasWidth : scaledWidth;
        const horizontalOffset = this.zoomLevel < 1 ? (this._baseCanvasWidth - scaledWidth) / 2 : 0;
        this._stageOffsetX = horizontalOffset;
        this._svgStage.attr('transform', `translate(${horizontalOffset}, 0) scale(${this.zoomLevel})`);
        this._svgRoot
            .attr('width', Math.round(canvasWidth))
            .attr('height', Math.round(this._baseCanvasHeight * this.zoomLevel));
    }

    relayoutGraph(columnOverride) {
        this._columnOverride = columnOverride;
        try {
            this.initializeProps();
            this.initializeD3(true);
        } finally {
            this._columnOverride = undefined;
        }
    }

    centerRootInViewport() {
        if (import.meta.env.SSR) {
            return;
        }
        const applyCentering = () => {
            const viewport = this.template.querySelector('.graph');
            const rootNode = this.nodes_data.find((node) => node.level === 0);
            if (!viewport || !rootNode) {
                return;
            }
            const rootCenter = this._stageOffsetX +
                ((rootNode.x + (this.boxWidth / 2)) * this.zoomLevel);
            const centeredScrollPosition = rootCenter - (viewport.clientWidth / 2);
            const maximumScrollPosition = Math.max(0, viewport.scrollWidth - viewport.clientWidth);
            viewport.scrollLeft = Math.max(0, Math.min(maximumScrollPosition, centeredScrollPosition));
        };

        requestAnimationFrame(() => requestAnimationFrame(applyCentering));
        if (this._centerTimer) {
            clearTimeout(this._centerTimer);
        }
        this._centerTimer = setTimeout(applyCentering, 200);
    }

    zoomIn() {
        const nextZoom = Math.min(1.5, Number((this.zoomLevel + 0.15).toFixed(2)));
        if (nextZoom !== this.zoomLevel) {
            this.zoomLevel = nextZoom;
            this.relayoutGraph();
        }
    }

    zoomOut() {
        const nextZoom = Math.max(0.65, Number((this.zoomLevel - 0.15).toFixed(2)));
        if (nextZoom !== this.zoomLevel) {
            this.zoomLevel = nextZoom;
            this.relayoutGraph();
        }
    }

    fitGraphToView() {
        const viewport = this.template.querySelector('.graph');
        if (!viewport) {
            return;
        }
        const availableWidth = Math.max(1, viewport.clientWidth - 24);
        const fiveColumnWidth = this.getRequiredCanvasWidth(this.defaultNodesPerRow);
        this.zoomLevel = Math.max(0.65, Math.min(1, availableWidth / fiveColumnWidth));
        this.relayoutGraph(this.defaultNodesPerRow);
        viewport.scrollTop = 0;
    }

    addLegend(parent){
        let container = parent.append('div').attr('class', 'legend-box slds-is-absolute slds-var-p-top_xx-small slds-var-p-horizontal_xx-small');
        for (let key in this.colorScheme) {
            if(Object.hasOwn(this.colorScheme, key)){
                let divWrapper = container.append('div');
                divWrapper.append('div')
                        .attr('class', 'legend')
                        .attr('style', () => { return 'background-color:' + this.colorScheme[key]});
                divWrapper.append('div')
                        .attr('class', 'legend-text slds-is-relative slds-var-p-around_xxx-small')
                        .text(() => key);
            }
        }
    }
}
