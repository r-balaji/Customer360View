import { createElement } from 'lwc';
import PartyRelationshipGraph from 'c/partyRelationshipGraph';
import getRelationshipGraphData from '@salesforce/apex/RelationshipGraphController.getRelationshipGraphData';
import getPartyAccountId from '@salesforce/apex/RelationshipGraphController.getPartyAccountId';

jest.mock('@salesforce/apex/RelationshipGraphController.getRelationshipGraphData', () => {
    const { createApexTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });

jest.mock('@salesforce/apex/RelationshipGraphController.getPartyAccountId', () => {
    const { createApexTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });

jest.mock('lightning/platformResourceLoader', () => ({
    loadScript: jest.fn(() => new Promise(() => {}))
}), { virtual: true });

const ACCOUNT_ID = '001000000000001';
const APPLICATION_ID = 'a97000000000001';
const GRAPH_DATA = {
    graphByAccountId: { [ACCOUNT_ID]: { Id: ACCOUNT_ID, Name: 'Graph Customer' } },
    applicationPartyAccountIds: [ACCOUNT_ID],
    selectedAccountId: ACCOUNT_ID
};
const flush = () => Promise.resolve();

function mount(properties = {}) {
    const element = createElement('c-party-relationship-graph', { is: PartyRelationshipGraph });
    Object.assign(element, { contextMode: 'ACCOUNT', recordId: ACCOUNT_ID }, properties);
    document.body.appendChild(element);
    return element;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

it('passes the native graph payload to the renderer', async () => {
    const element = mount();
    getRelationshipGraphData.emit(GRAPH_DATA);
    await flush();

    const graph = element.shadowRoot.querySelector('c-relationship-graph');
    expect(graph).not.toBeNull();
    expect(graph.allApplicationRelationshipList).toEqual(GRAPH_DATA.graphByAccountId);
    expect(graph.partyAccountsList).toEqual([ACCOUNT_ID]);
    expect(graph.selectedPartyAccId).toBe(ACCOUNT_ID);
    expect(graph.invokedFromAccountPage).toBe(true);
});

it('renders an empty state for an empty native graph payload', async () => {
    const element = mount();
    getRelationshipGraphData.emit({ graphByAccountId: {}, applicationPartyAccountIds: [] });
    await flush();

    expect(element.shadowRoot.textContent).toContain('No relationship graph data.');
    expect(element.shadowRoot.querySelector('c-relationship-graph')).toBeNull();
});

it('shows native Apex errors in an accessible Lightning alert', async () => {
    const element = mount();
    getRelationshipGraphData.error({ message: 'Unable to load relationship graph.' });
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain('Unable to load relationship graph.');
});

it('uses a fallback message when the wire error has no message', async () => {
    const element = mount();
    getRelationshipGraphData.error({});
    await flush();

    expect(element.shadowRoot.querySelector('[role="alert"]').textContent)
        .toContain('Unable to load relationship graph.');
});

it('recovers when a successful response follows an error', async () => {
    const element = mount();
    getRelationshipGraphData.error({ message: 'Temporary failure' });
    await flush();
    getRelationshipGraphData.emit(GRAPH_DATA);
    await flush();

    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    expect(element.shadowRoot.querySelector('c-relationship-graph')).not.toBeNull();
});

it('uses the native party account id while retaining application context', async () => {
    mount({ contextMode: 'APPLICATION', recordId: APPLICATION_ID, partyId: 'a2r000000000001' });
    getPartyAccountId.emit(ACCOUNT_ID);
    await flush();

    expect(getRelationshipGraphData.getLastConfig()).toEqual({
        applicationId: APPLICATION_ID,
        accountId: ACCOUNT_ID
    });
});

it('handles party lookup errors using the same native alert', async () => {
    const element = mount({ partyId: 'a2r000000000001' });
    getRelationshipGraphData.emit(GRAPH_DATA);
    await flush();
    getPartyAccountId.error({ message: 'Unable to load the party account.' });
    await flush();

    expect(element.shadowRoot.querySelector('[role="alert"]').textContent)
        .toContain('Unable to load the party account.');
});
