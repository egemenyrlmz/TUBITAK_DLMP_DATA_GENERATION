function dashboard_case33bw_dlmp_scenario_lab()
%DASHBOARD_CASE33BW_DLMP_SCENARIO_LAB
% Interactive MATPOWER case33bw DLMP scenario dashboard.
%
% Project direction:
%   - The old custom 4-bus network is removed.
%   - The dashboard uses MATPOWER's case33bw test case only.
%   - The network is configured through bus roles, not generator technology.
%   - Bus roles:
%       1) Slack/Grid
%       2) PQ Load
%       3) DER
%       4) Prosumer
%       5) Large Load
%
% Requirements:
%   1) MATLAB with App UI components
%   2) MATPOWER on the MATLAB path
%   3) case33bw available in MATPOWER path
%
% Run:
%   dashboard_case33bw_dlmp_scenario_lab

    %% ============================================================
    % App state
    %% ============================================================
    app = struct();

    app.base_mpc          = loadCase33bwForDashboard();
    app.nBus              = size(app.base_mpc.bus, 1);
    app.nBranch           = size(app.base_mpc.branch, 1);
    app.busRoleConfig     = createDefaultBusRoleConfig(app.base_mpc);

    app.T                 = table();     % scenario-level summary
    app.busResults        = table();     % long bus-level results
    app.branchResults     = table();     % long branch-level results
    app.genResults        = table();     % long generator-level results
    app.validationTable   = table();
    app.validationSummary = table();
    app.econTable         = table();

    app.scenarioMPCs      = {};
    app.scenarioResults   = {};
    app.selectedInspectBus = 1;      % Bus currently shown in Selected Bus Details
    app.topologyClickData  = struct('busIds', [], 'x', [], 'y', []);

    %% ============================================================
    % UI construction
    %% ============================================================
    app.fig = uifigure( ...
        'Name', 'case33bw DLMP Scenario Lab | MATPOWER Dashboard', ...
        'Position', [40 40 1650 900]);

    % Robust topology node selection:
    % MATLAB graphplot hover/data-tip can identify nodes, but graphplot
    % ButtonDownFcn hit testing is inconsistent across versions. Therefore
    % we use a figure-level click handler and compute the nearest topology node.
    app.fig.WindowButtonDownFcn = @(~, ~) handleFigureMouseDown();

    rootGrid = uigridlayout(app.fig, [2 1]);
    rootGrid.RowHeight = {52, '1x'};
    rootGrid.ColumnWidth = {'1x'};
    rootGrid.Padding = [10 10 10 10];
    rootGrid.RowSpacing = 8;

    %% ---------------- Top button bar ----------------
    topButtonGrid = uigridlayout(rootGrid, [1 4]);
    topButtonGrid.Layout.Row = 1;
    topButtonGrid.Layout.Column = 1;
    topButtonGrid.ColumnWidth = {280, 280, 280, '1x'};
    topButtonGrid.RowHeight = {'1x'};
    topButtonGrid.Padding = [0 0 0 0];
    topButtonGrid.ColumnSpacing = 10;

    app.runButton = uibutton(topButtonGrid, 'push', ...
        'Text', 'Generate Scenarios + Analyze', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) runGeneration());

    app.loadButton = uibutton(topButtonGrid, 'push', ...
        'Text', 'Load Existing Excel + Analyze', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) loadExistingExcel());

    app.saveButton = uibutton(topButtonGrid, 'push', ...
        'Text', 'Save Current Results to Excel', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) saveCurrentResults());

    app.status = uilabel(topButtonGrid, ...
        'Text', 'Ready. case33bw loaded.', ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left');

    app.runButton.Layout.Row = 1; app.runButton.Layout.Column = 1;
    app.loadButton.Layout.Row = 1; app.loadButton.Layout.Column = 2;
    app.saveButton.Layout.Row = 1; app.saveButton.Layout.Column = 3;
    app.status.Layout.Row = 1; app.status.Layout.Column = 4;

    %% ---------------- Main grid ----------------
    mainGrid = uigridlayout(rootGrid, [1 2]);
    mainGrid.Layout.Row = 2;
    mainGrid.Layout.Column = 1;
    mainGrid.ColumnWidth = {410, '1x'};
    mainGrid.RowHeight = {'1x'};
    mainGrid.Padding = [0 0 0 0];
    mainGrid.ColumnSpacing = 12;
    app.mainGrid = mainGrid;

    %% ============================================================
    % Left control panel
    %% ============================================================
    controlPanel = uipanel(mainGrid, 'Title', 'Context Controls');
    controlPanel.Layout.Row = 1;
    controlPanel.Layout.Column = 1;
    try
        controlPanel.Scrollable = 'on';
    catch
    end

    cg = uigridlayout(controlPanel, [52 2]);
    cg.RowHeight = repmat({24}, 1, 52);
    cg.ColumnWidth = {165, '1x'};
    cg.Padding = [10 10 10 10];
    cg.RowSpacing = 6;

    app.sectionScenario = addSection(cg, 'Scenario settings');

    app.lblScenarioCount = addLabel(cg, 'Scenario count');
    app.nField = uispinner(cg, 'Value', 400, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');

    app.lblRandomSeed = addLabel(cg, 'Random seed');
    app.seedField = uispinner(cg, 'Value', 42, 'RoundFractionalValues', 'on');

    app.lblLoadPDF = addLabel(cg, 'Load PDF');
    app.loadPdfDrop = uidropdown(cg, 'Items', pdfItems(), 'Value', 'Normal-Truncated');

    app.lblPFPDF = addLabel(cg, 'PF PDF');
    app.pfPdfDrop = uidropdown(cg, 'Items', pdfItems(), 'Value', 'Normal-Truncated');

    app.lblOfferPDF = addLabel(cg, 'Offer PDF');
    app.offerPdfDrop = uidropdown(cg, 'Items', pdfItems(), 'Value', 'Normal-Truncated');

    app.lblGlobalLoadScale = addLabel(cg, 'Global load scale');
    app.globalLoadScaleField = uieditfield(cg, 'text', 'Value', '0.85, 1.15');

    app.sectionQuickRole = addSection(cg, 'Quick bus role editor');

    app.lblBus = addLabel(cg, 'Bus');
    app.busSelectDrop = uidropdown(cg, ...
        'Items', busIdItems(app.base_mpc), ...
        'Value', '2', ...
        'ValueChangedFcn', @(~, ~) updateSelectedBusInfo(str2double(app.busSelectDrop.Value)));

    app.lblRole = addLabel(cg, 'Role');
    app.roleDrop = uidropdown(cg, 'Items', roleItems(), 'Value', 'PQ Load');

    app.lblAddedPd = addLabel(cg, 'Added Pd [MW]');
    app.addPdField = uieditfield(cg, 'text', 'Value', '0, 0');

    app.lblAddedPF = addLabel(cg, 'Added PF');
    app.addPfField = uieditfield(cg, 'text', 'Value', '0.90, 0.98');

    app.lblPminPmax = addLabel(cg, 'Pmin/Pmax [MW]');
    app.pminmaxField = uieditfield(cg, 'text', 'Value', '0, 1.0');

    app.lblQminQmax = addLabel(cg, 'Qmin/Qmax [MVAr]');
    app.qminmaxField = uieditfield(cg, 'text', 'Value', '-1.0, 1.0');

    app.lblVg = addLabel(cg, 'Vg [p.u.]');
    app.vgField = uieditfield(cg, 'numeric', 'Value', 1.00);

    app.lblC2 = addLabel(cg, 'c2 range');
    app.c2Field = uieditfield(cg, 'text', 'Value', '0.010, 0.010');

    app.lblC1 = addLabel(cg, 'c1 range');
    app.c1Field = uieditfield(cg, 'text', 'Value', '30, 30');

    app.lblC0 = addLabel(cg, 'c0');
    app.c0Field = uieditfield(cg, 'numeric', 'Value', 0);

    app.applyRoleButton = uibutton(cg, 'push', ...
        'Text', 'Apply Selected Bus Role', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) applySelectedBusRole());
    app.applyRoleButton.Layout.Column = [1 2];

    app.saveCustomConfigButton = uibutton(cg, 'push', ...
        'Text', 'Save Custom Config', ...
        'ButtonPushedFcn', @(~, ~) saveCustomConfig());
    app.saveCustomConfigButton.Layout.Column = [1 2];

    app.loadCustomConfigButton = uibutton(cg, 'push', ...
        'Text', 'Load Custom Config', ...
        'ButtonPushedFcn', @(~, ~) loadCustomConfig());
    app.loadCustomConfigButton.Layout.Column = [1 2];

    app.resetRolesButton = uibutton(cg, 'push', ...
        'Text', 'Reset All Roles to case33bw Base', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) resetAllRoles());
    app.resetRolesButton.Layout.Column = [1 2];

    app.sectionPlotSelectors = addSection(cg, 'Dynamic plot bus selectors');

    app.lblPlotBusA = addLabel(cg, 'Plot Bus A');
    app.plotBusADrop = uidropdown(cg, 'Items', busIdItems(app.base_mpc), 'Value', '2', ...
        'ValueChangedFcn', @(~, ~) updateAllPlots());

    app.lblPlotBusB = addLabel(cg, 'Plot Bus B');
    defaultB = char(string(min(17, app.nBus)));
    app.plotBusBDrop = uidropdown(cg, 'Items', busIdItems(app.base_mpc), 'Value', defaultB, ...
        'ValueChangedFcn', @(~, ~) updateAllPlots());

    app.lblPlotBusC = addLabel(cg, 'Plot Bus C');
    defaultC = char(string(app.nBus));
    app.plotBusCDrop = uidropdown(cg, 'Items', busIdItems(app.base_mpc), 'Value', defaultC, ...
        'ValueChangedFcn', @(~, ~) updateAllPlots());

    app.sectionValidationExport = addSection(cg, 'Validation and export');

    app.lblRunValidation = addLabel(cg, 'Run validation');
    app.validateCheck = uicheckbox(cg, 'Text', 'RUNPF consistency check', 'Value', true);

    app.lblOutputExcel = addLabel(cg, 'Output Excel');
    app.outputField = uieditfield(cg, 'text', 'Value', 'dataset_case33bw_dashboard.xlsx');

    app.contextInfoArea = uitextarea(cg, ...
        'Editable', 'off', ...
        'FontName', 'Consolas', ...
        'FontSize', 11, ...
        'BackgroundColor', [1 1 1], ...
        'Value', {'Context-specific guidance appears here.'});
    app.contextInfoArea.Layout.Row = [34 38];
    app.contextInfoArea.Layout.Column = [1 2];

    app.sideStatus = uilabel(cg, 'Text', 'Ready.', 'FontWeight', 'bold');
    app.sideStatus.Layout.Column = [1 2];

    app.log = uitextarea(cg, 'Editable', 'off', 'Value', {'Ready. Configure bus roles and run.'});
    app.log.Layout.Row = [40 52];
    app.log.Layout.Column = [1 2];

    %% ============================================================
    % Main tab area
    %% ============================================================
    tabs = uitabgroup(mainGrid);
    tabs.Layout.Row = 1;
    tabs.Layout.Column = 2;
    tabs.SelectionChangedFcn = @(~, event) updateContextControls(event.NewValue);
    app.tabs = tabs;

    app.tabTopology    = uitab(tabs, 'Title', 'Network Topology');
    app.tabOverview    = uitab(tabs, 'Title', 'Overview');
    app.tabEconometric = uitab(tabs, 'Title', 'Econometric Outputs');
    app.tabValidation  = uitab(tabs, 'Title', 'Validation Diagnostics');
    app.tabData        = uitab(tabs, 'Title', 'Data Preview');
    app.tabRoles       = uitab(tabs, 'Title', 'Bus Role Editor');

    %% ---------------- Topology tab ----------------
    tg = uigridlayout(app.tabTopology, [1 2]);
    tg.Padding = [10 10 10 10];
    tg.ColumnWidth = {'1x', 330};

    app.axTopology = uiaxes(tg);
    title(app.axTopology, 'case33bw Network Topology');
    app.axTopology.Layout.Row = 1;
    app.axTopology.Layout.Column = 1;

    infoPanel = uipanel(tg, 'Title', 'Topology Legend + Bus Details');
    infoPanel.Layout.Row = 1;
    infoPanel.Layout.Column = 2;

    % Two-column legend:
    %   left  = colored topology marker
    %   right = role explanation
    % This makes the graph colors immediately understandable for the user.
    ig = uigridlayout(infoPanel, [17 2]);
    ig.RowHeight = [{28}, {28}, {28}, {28}, {28}, {28}, {28}, {28}, {28}, {28}, {28}, {24}, {24}, {'1x'}, {'1x'}, {'1x'}, {'1x'}];
    ig.ColumnWidth = {30, '1x'};
    ig.Padding = [10 10 10 10];
    ig.RowSpacing = 4;
    ig.ColumnSpacing = 6;

    addLegendItem(ig, 1,  '●', [0.00 0.25 0.90], 'Slack/Grid (SLK)', true);
    addLegendItem(ig, 2,  '●', [0.55 0.55 0.55], 'PQ Load (PQ)', false);
    addLegendItem(ig, 3,  '●', [0.00 0.55 0.20], 'DER / PV Bus (DER)', false);
    addLegendItem(ig, 4,  '●', [0.95 0.45 0.05], 'Prosumer / PV Bus (PRO)', false);
    addLegendItem(ig, 5,  '●', [0.85 0.10 0.10], 'Large Load (LL)', false);
    addLegendItem(ig, 6,  'ABC', [0.60 0.00 0.80], 'Selected Plot Bus Label', true);

    addLegendNote(ig, 7,  'Click a bus on the topology to inspect it.');
    addLegendNote(ig, 8,  'Selected plot buses keep their role marker; only their labels become purple and bold.');
    addLegendNote(ig, 9,  'Branch data comes from mpc.branch.');
    addLegendNote(ig, 10, 'Bus roles are user-defined.');
    addLegendNote(ig, 11, 'OPF uses the generated mpc struct.');

    detailIcon = uilabel(ig, 'Text', 'ℹ', 'FontWeight', 'bold', 'FontSize', 16, ...
        'HorizontalAlignment', 'center', 'FontColor', [0.10 0.10 0.10]);
    detailIcon.Layout.Row = 12;
    detailIcon.Layout.Column = 1;

    detailTitle = uilabel(ig, 'Text', 'Selected Bus Details', 'FontWeight', 'bold');
    detailTitle.Layout.Row = 12;
    detailTitle.Layout.Column = 2;

    detailHint = uilabel(ig, 'Text', 'Shows base demand, role settings, generation limits, and latest OPF output.', ...
        'FontAngle', 'italic');
    detailHint.Layout.Row = 13;
    detailHint.Layout.Column = [1 2];

    app.busInfoArea = uitextarea(ig, ...
        'Editable', 'off', ...
        'FontName', 'Consolas', ...
        'FontSize', 12, ...
        'BackgroundColor', [1 1 1], ...
        'Value', { ...
            'SELECTED BUS SUMMARY', ...
            ' ', ...
            '• Click a bus on the topology graph.', ...
            '• Bus role, demand, limits, and cost data will appear here.', ...
            '• After running scenarios, latest OPF results will also appear here.' ...
        });
    app.busInfoArea.Layout.Row = [14 17];
    app.busInfoArea.Layout.Column = [1 2];

    %% ---------------- Overview tab ----------------
    og = uigridlayout(app.tabOverview, [2 2]);
    og.Padding = [10 10 10 10];
    app.axLoadHist = uiaxes(og); title(app.axLoadHist, 'Load Distribution'); grid(app.axLoadHist, 'off');
    app.axDlmpHist = uiaxes(og); title(app.axDlmpHist, 'Selected Bus DLMP Distribution'); grid(app.axDlmpHist, 'off');
    app.axVoltage  = uiaxes(og); title(app.axVoltage, 'Voltage Mean / Min / Max'); grid(app.axVoltage, 'off');
    app.axLoading  = uiaxes(og); title(app.axLoading, 'Branch Loading'); grid(app.axLoading, 'off');

    %% ---------------- Econometric tab ----------------
    eg = uigridlayout(app.tabEconometric, [2 3]);
    eg.Padding = [10 10 10 10];
    eg.ColumnWidth = {'1x', '1x', '1x'};

    app.axBusADlmpDemand = uiaxes(eg); title(app.axBusADlmpDemand, 'Bus A DLMP vs Total Demand'); grid(app.axBusADlmpDemand, 'off');
    app.axBusBDlmpDemand = uiaxes(eg); title(app.axBusBDlmpDemand, 'Bus B DLMP vs Total Demand'); grid(app.axBusBDlmpDemand, 'off');
    app.axBusCDlmpDemand = uiaxes(eg); title(app.axBusCDlmpDemand, 'Bus C DLMP vs Total Demand'); grid(app.axBusCDlmpDemand, 'off');
    app.axCostOLS        = uiaxes(eg); title(app.axCostOLS, 'Objective Cost vs Total Demand'); grid(app.axCostOLS, 'off');
    app.axLossDemand     = uiaxes(eg); title(app.axLossDemand, 'Losses vs Total Demand'); grid(app.axLossDemand, 'off');
    app.axC2LDemand      = uiaxes(eg); title(app.axC2LDemand, 'Cost-to-Load vs Total Demand'); grid(app.axC2LDemand, 'off');

    %% ---------------- Validation tab ----------------
    vg = uigridlayout(app.tabValidation, [2 2]);
    vg.Padding = [10 10 10 10];
    vg.ColumnWidth = {'1x', 470};

    app.axValErrors = uiaxes(vg);
    app.axValErrors.Layout.Row = 1;
    app.axValErrors.Layout.Column = 1;
    title(app.axValErrors, 'Validation Error Severity');

    app.axFailReasons = uiaxes(vg);
    app.axFailReasons.Layout.Row = 2;
    app.axFailReasons.Layout.Column = 1;
    title(app.axFailReasons, 'Dominant Fail Reasons');

    app.validationUITable = uitable(vg, 'Data', table());
    app.validationUITable.Layout.Row = [1 2];
    app.validationUITable.Layout.Column = 2;

    %% ---------------- Data tab ----------------
    dg = uigridlayout(app.tabData, [2 2]);
    dg.Padding = [10 10 10 10];
    dg.RowHeight = {'1x', '1x'};
    dg.ColumnWidth = {'1x', '1x'};

    app.summaryUITable = uitable(dg, 'Data', table());
    app.summaryUITable.Layout.Row = 1;
    app.summaryUITable.Layout.Column = 1;

    app.busUITable = uitable(dg, 'Data', table());
    app.busUITable.Layout.Row = 1;
    app.busUITable.Layout.Column = 2;

    app.branchUITable = uitable(dg, 'Data', table());
    app.branchUITable.Layout.Row = 2;
    app.branchUITable.Layout.Column = 1;

    app.genUITable = uitable(dg, 'Data', table());
    app.genUITable.Layout.Row = 2;
    app.genUITable.Layout.Column = 2;

    %% ---------------- Bus role table tab ----------------
    rg = uigridlayout(app.tabRoles, [1 1]);
    rg.Padding = [10 10 10 10];

    app.roleUITable = uitable(rg, ...
        'Data', app.busRoleConfig, ...
        'ColumnEditable', [false true true true true true true true true true true true true true true true], ...
        'CellEditCallback', @(~, ~) roleTableEdited());
    try
        app.roleUITable.ColumnFormat = {'numeric', roleItems(), 'numeric', 'numeric', 'numeric', 'numeric', ...
            'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric'};
    catch
    end

    %% Initial UI refresh
    refreshRoleTableFromConfig();
    refreshTopology();
    updateSelectedBusInfo(1);
    updateTables();
    updateContextControls(app.tabTopology);

    %% ============================================================
    % Nested helper functions - UI
    %% ============================================================
    function lab = addLabel(parent, txt)
        lab = uilabel(parent, 'Text', txt, 'HorizontalAlignment', 'right');
    end

    function lab = addSection(parent, txt)
        lab = uilabel(parent, 'Text', txt, 'FontWeight', 'bold');
        lab.Layout.Column = [1 2];
    end

    function addLegendItem(parent, rowNo, markerText, markerColor, labelText, isBold)
        icon = uilabel(parent, ...
            'Text', markerText, ...
            'FontSize', 18, ...
            'FontWeight', 'bold', ...
            'FontColor', markerColor, ...
            'HorizontalAlignment', 'center');
        icon.Layout.Row = rowNo;
        icon.Layout.Column = 1;

        if isBold
            fw = 'bold';
        else
            fw = 'normal';
        end

        lab = uilabel(parent, ...
            'Text', labelText, ...
            'FontWeight', fw, ...
            'HorizontalAlignment', 'left');
        lab.Layout.Row = rowNo;
        lab.Layout.Column = 2;
    end

    function addLegendNote(parent, rowNo, noteText)
        spacer = uilabel(parent, 'Text', '');
        spacer.Layout.Row = rowNo;
        spacer.Layout.Column = 1;

        lab = uilabel(parent, ...
            'Text', noteText, ...
            'FontAngle', 'italic', ...
            'HorizontalAlignment', 'left');
        lab.Layout.Row = rowNo;
        lab.Layout.Column = 2;
    end

    function items = pdfItems()
        items = {'Uniform', 'Normal-Truncated', 'Triangular', 'Beta(2,2)-Bounded', 'Lognormal-Truncated', 'Two-Peak Mixture'};
    end

    function items = roleItems()
        items = {'Slack/Grid', 'PQ Load', 'DER', 'Prosumer', 'Large Load'};
    end

    function applySelectedBusRole()
        try
            roleCfg = getRoleConfigFromUITable();
            busId = str2double(app.busSelectDrop.Value);
            rowIdx = find(roleCfg.bus_id == busId, 1);

            if isempty(rowIdx)
                error('Selected bus does not exist in case33bw.');
            end

            selectedRole = string(app.roleDrop.Value);
            if selectedRole == "Slack/Grid" && busId ~= getSlackBusId(app.base_mpc)
                error('Only the original case33bw slack/grid bus can be assigned Slack/Grid role.');
            end

            pdRange = parseRange(app.addPdField.Value, 'Added Pd');
            pfRange = parseRange(app.addPfField.Value, 'Added PF');
            pRange = parseRange(app.pminmaxField.Value, 'Pmin/Pmax');
            qRange = parseRange(app.qminmaxField.Value, 'Qmin/Qmax');
            c2Range = parseRange(app.c2Field.Value, 'c2 range');
            c1Range = parseRange(app.c1Field.Value, 'c1 range');

            roleCfg.role(rowIdx) = selectedRole;
            roleCfg.add_Pd_min_MW(rowIdx) = pdRange(1);
            roleCfg.add_Pd_max_MW(rowIdx) = pdRange(2);
            roleCfg.pf_min(rowIdx) = pfRange(1);
            roleCfg.pf_max(rowIdx) = pfRange(2);
            roleCfg.Pmin_MW(rowIdx) = pRange(1);
            roleCfg.Pmax_MW(rowIdx) = pRange(2);
            roleCfg.Qmin_MVAr(rowIdx) = qRange(1);
            roleCfg.Qmax_MVAr(rowIdx) = qRange(2);
            roleCfg.Vg_pu(rowIdx) = app.vgField.Value;
            roleCfg.c2_min(rowIdx) = c2Range(1);
            roleCfg.c2_max(rowIdx) = c2Range(2);
            roleCfg.c1_min(rowIdx) = c1Range(1);
            roleCfg.c1_max(rowIdx) = c1Range(2);
            roleCfg.c0(rowIdx) = app.c0Field.Value;

            roleCfg = validateBusRoleConfig(roleCfg, app.busRoleConfig, app.base_mpc);
            app.busRoleConfig = roleCfg;
            refreshBusRoleConfigUI(busId);
            logMsg(sprintf('Applied role "%s" to bus %d.', selectedRole, busId));
        catch ME
            app.status.Text = 'Role update error.';
            logMsg(sprintf('ERROR applying bus role: %s', ME.message));
            uialert(app.fig, ME.message, 'Bus Role Error');
        end
    end

    function resetAllRoles()
        app.busRoleConfig = createDefaultBusRoleConfig(app.base_mpc);
        refreshBusRoleConfigUI(app.selectedInspectBus);
        logMsg('Bus roles reset to case33bw base roles.');
    end

    function saveCustomConfig()
        % Save only the bus-role/economic configuration, not scenario results.
        try
            busRoleConfig = validateBusRoleConfig(app.busRoleConfig, app.busRoleConfig, app.base_mpc); %#ok<NASGU>
            createdAt = datetime('now'); %#ok<NASGU>
            baseCaseName = 'case33bw'; %#ok<NASGU>

            [file, path] = uiputfile('*.mat', 'Save Custom Bus Role Configuration');
            if isequal(file, 0)
                logMsg('Custom config save cancelled by user.');
                return;
            end

            save(fullfile(path, file), 'busRoleConfig', 'createdAt', 'baseCaseName');
            logMsg(sprintf('Saved custom bus role config: %s', fullfile(path, file)));
            uialert(app.fig, ...
                'Custom bus role configuration saved. Scenario results were not included.', ...
                'Custom Config Saved');
        catch ME
            logMsg(sprintf('ERROR saving custom config: %s', ME.message));
            uialert(app.fig, ME.message, 'Save Custom Config Error');
        end
    end

    function loadCustomConfig()
        % Load only the bus-role/economic configuration from an external MAT-file.
        try
            [file, path] = uigetfile('*.mat', 'Load Custom Bus Role Configuration');
            if isequal(file, 0)
                logMsg('Custom config load cancelled by user.');
                return;
            end

            fullName = fullfile(path, file);
            S = load(fullName);
            if ~isfield(S, 'busRoleConfig')
                error('Selected MAT-file does not contain a "busRoleConfig" variable.');
            end

            app.busRoleConfig = validateBusRoleConfig(S.busRoleConfig, app.busRoleConfig, app.base_mpc);
            refreshBusRoleConfigUI(app.selectedInspectBus);

            logMsg(sprintf('Loaded custom bus role config: %s', fullName));
            uialert(app.fig, ...
                'Custom bus role configuration loaded successfully.', ...
                'Custom Config Loaded');
        catch ME
            logMsg(sprintf('ERROR loading custom config: %s', ME.message));
            uialert(app.fig, ME.message, 'Load Custom Config Error');
        end
    end

    function roleTableEdited()
        try
            roleCfg = getRoleConfigFromUITable();
            roleCfg = validateBusRoleConfig(roleCfg, app.busRoleConfig, app.base_mpc);
            app.busRoleConfig = roleCfg;
            refreshBusRoleConfigUI(app.selectedInspectBus);
            logMsg('Bus role table updated.');
        catch ME
            logMsg(sprintf('ERROR in role table: %s', ME.message));
            uialert(app.fig, ME.message, 'Role Table Error');
            refreshRoleTableFromConfig();
        end
    end

    function refreshRoleTableFromConfig()
        app.roleUITable.Data = app.busRoleConfig;
    end

    function refreshBusRoleConfigUI(focusBusId)
        if nargin < 1 || isempty(focusBusId) || ~isfinite(focusBusId)
            focusBusId = app.selectedInspectBus;
        end

        if isempty(focusBusId) || ~any(app.busRoleConfig.bus_id == focusBusId)
            focusBusId = app.busRoleConfig.bus_id(1);
        end

        refreshRoleTableFromConfig();
        syncQuickRoleEditorToBus(focusBusId);
        updateSelectedBusInfo(focusBusId);
        updateTables();
        updateContextControls(app.tabs.SelectedTab);
    end

    function roleCfg = getRoleConfigFromUITable()
        roleCfg = app.roleUITable.Data;
        if ~istable(roleCfg)
            roleCfg = struct2table(roleCfg);
        end
        roleCfg.role = string(roleCfg.role);
    end

    function refreshTopology()
        try
            selected = [str2double(app.plotBusADrop.Value), str2double(app.plotBusBDrop.Value), str2double(app.plotBusCDrop.Value)];
        catch
            selected = [];
        end
        app.topologyClickData = drawCaseTopology(app.axTopology, app.base_mpc, app.busRoleConfig, selected, app.selectedInspectBus);
    end

    function updateSelectedBusInfo(busId)
        try
            if isempty(busId) || ~isfinite(busId)
                return;
            end

            app.selectedInspectBus = busId;
            syncQuickRoleEditorToBus(busId);
            app.busInfoArea.Value = selectedBusInfoText(busId, app.base_mpc, app.busRoleConfig, app.busResults);

            % Redraw topology so the inspected bus label becomes highlighted.
            refreshTopology();
        catch ME
            app.busInfoArea.Value = {sprintf('Could not read bus %d details.', busId), ME.message};
        end
    end

    function syncQuickRoleEditorToBus(busId)
        try
            if isempty(busId) || ~isfinite(busId)
                return;
            end

            rowIdx = find(app.busRoleConfig.bus_id == busId, 1);
            if isempty(rowIdx)
                return;
            end

            roleRow = app.busRoleConfig(rowIdx, :);

            busValue = char(string(busId));
            if ~strcmp(app.busSelectDrop.Value, busValue)
                app.busSelectDrop.Value = busValue;
            end

            app.roleDrop.Value = char(roleRow.role);
            app.addPdField.Value = formatRangeText(roleRow.add_Pd_min_MW, roleRow.add_Pd_max_MW);
            app.addPfField.Value = formatRangeText(roleRow.pf_min, roleRow.pf_max);
            app.pminmaxField.Value = formatRangeText(roleRow.Pmin_MW, roleRow.Pmax_MW);
            app.qminmaxField.Value = formatRangeText(roleRow.Qmin_MVAr, roleRow.Qmax_MVAr);
            app.vgField.Value = roleRow.Vg_pu;
            app.c2Field.Value = formatRangeText(roleRow.c2_min, roleRow.c2_max);
            app.c1Field.Value = formatRangeText(roleRow.c1_min, roleRow.c1_max);
            app.c0Field.Value = roleRow.c0;
        catch
            % Editor sync is convenience behavior; it should not interrupt UI use.
        end
    end

    function handleFigureMouseDown()
        % Select nearest topology node when user clicks near a node.
        % This avoids relying on graphplot ButtonDownFcn, which is not stable
        % in all MATLAB releases and UIAxes configurations.

        try
            if app.tabs.SelectedTab ~= app.tabTopology
                return;
            end

            if isempty(app.topologyClickData) || isempty(app.topologyClickData.busIds)
                return;
            end

            cp = app.axTopology.CurrentPoint;
            xClick = cp(1, 1);
            yClick = cp(1, 2);

            xl = app.axTopology.XLim;
            yl = app.axTopology.YLim;

            if xClick < xl(1) || xClick > xl(2) || yClick < yl(1) || yClick > yl(2)
                return;
            end

            x = app.topologyClickData.x(:);
            y = app.topologyClickData.y(:);

            % Normalize distance so the click tolerance is scale-independent.
            xr = max(eps, diff(xl));
            yr = max(eps, diff(yl));
            d = sqrt(((x - xClick) ./ xr).^2 + ((y - yClick) ./ yr).^2);

            [minD, idx] = min(d);

            % 0.045 means about 4.5% of the axes range. This gives a generous
            % clickable area around each bus without selecting a bus when the
            % user clicks empty space.
            if minD <= 0.045
                busId = app.topologyClickData.busIds(idx);
                updateSelectedBusInfo(busId);
            end
        catch
            % Keep UI robust; click handling should never interrupt workflow.
        end
    end

    function updateContextControls(selectedTab)
        % Dynamic left-side panel. Shows only the controls that are relevant
        % for the currently selected tab.

        showLeftPanel(true);
        hideAllContextControls();

        if selectedTab == app.tabTopology
            controlPanel.Title = 'Context Controls | Network Topology';
            showScenarioSettings(true);
            showQuickRoleEditor(true);
            layoutForTopology();
            hideContextInfoForTopology();

        elseif selectedTab == app.tabEconometric
            controlPanel.Title = 'Context Controls | Econometric Outputs';
            showPlotSelectors(true);
            layoutForEconometric();
            showContextInfo({
                'ECONOMETRIC PLOT CONTROLS'
                ' '
                '• Select Plot Bus A/B/C.'
                '• The three selected buses define DLMP-vs-demand plots.'
                '• Purple squares on topology show selected plot buses.'
                '• Scatter points show scenario-level DLMP behavior.'
                '• Red curve shows total demand distribution.'
                });

        elseif selectedTab == app.tabOverview
            controlPanel.Title = 'Context Controls | Overview';
            layoutForOverview();
            showContextInfo(datasetSummaryText());
            showValidationExport(false);

        elseif selectedTab == app.tabValidation
            controlPanel.Title = 'Context Controls | Validation Diagnostics';
            showValidationExport(true);
            layoutForValidation();
            showContextInfo({
                'VALIDATION GUIDE'
                ' '
                '• RUNPF success: reconstructed power flow converged.'
                '• Validation pass: RUNPF output matches OPF output.'
                '• Vm tolerance      : 1e-5 p.u.'
                '• Va tolerance      : 1e-3 deg'
                '• P/Q tolerance     : 1e-4 MW/MVAr'
                '• Loading tolerance : 1e-3 % if RATE_A is defined.'
                '• If RATE_A is zero/undefined, loading check is N/A.'
                ' '
                'Tip: Enable Run validation before scenario generation.'
                });

        elseif selectedTab == app.tabData
            controlPanel.Title = 'Context Controls | Data Preview / Export';
            showValidationExport(true);
            setVisible(false, {app.lblRunValidation, app.validateCheck});
            layoutForDataPreview();
            showContextInfo({
                'DATA PREVIEW / EXPORT'
                ' '
                '• scenario_dataset: scenario-level summary.'
                '• bus_results_long: one row per scenario-bus.'
                '• branch_results_long: one row per scenario-branch.'
                '• gen_results_long: one row per scenario-generator.'
                '• Save Current Results exports the current dataset.'
                });

        elseif selectedTab == app.tabRoles
            % Bus Role Editor needs maximum width for the 33-bus table.
            % Hide the left panel by collapsing its column.
            controlPanel.Title = 'Context Controls';
            showLeftPanel(false);

        else
            controlPanel.Title = 'Context Controls';
            showContextInfo({'No controls for this tab.'});
        end
    end

    function showLeftPanel(tf)
        try
            if tf
                app.mainGrid.ColumnWidth = {410, '1x'};
                controlPanel.Visible = 'on';
            else
                app.mainGrid.ColumnWidth = {0, '1x'};
                controlPanel.Visible = 'off';
            end
        catch
            % Safe fallback for older MATLAB versions
            if tf
                controlPanel.Visible = 'on';
            else
                controlPanel.Visible = 'off';
            end
        end
    end

    function hideAllContextControls()
        % Use cell arrays instead of heterogeneous handle arrays.
        % This avoids MATLAB UI handle concatenation issues across different component classes.

        allControls = {
            app.sectionScenario
            app.lblScenarioCount
            app.nField
            app.lblRandomSeed
            app.seedField
            app.lblLoadPDF
            app.loadPdfDrop
            app.lblPFPDF
            app.pfPdfDrop
            app.lblOfferPDF
            app.offerPdfDrop
            app.lblGlobalLoadScale
            app.globalLoadScaleField

            app.sectionQuickRole
            app.lblBus
            app.busSelectDrop
            app.lblRole
            app.roleDrop
            app.lblAddedPd
            app.addPdField
            app.lblAddedPF
            app.addPfField
            app.lblPminPmax
            app.pminmaxField
            app.lblQminQmax
            app.qminmaxField
            app.lblVg
            app.vgField
            app.lblC2
            app.c2Field
            app.lblC1
            app.c1Field
            app.lblC0
            app.c0Field
            app.applyRoleButton
            app.saveCustomConfigButton
            app.loadCustomConfigButton
            app.resetRolesButton

            app.sectionPlotSelectors
            app.lblPlotBusA
            app.plotBusADrop
            app.lblPlotBusB
            app.plotBusBDrop
            app.lblPlotBusC
            app.plotBusCDrop

            app.sectionValidationExport
            app.lblRunValidation
            app.validateCheck
            app.lblOutputExcel
            app.outputField

            app.contextInfoArea
            app.sideStatus
            app.log
            };

        setVisible(false, allControls);
    end


    function layoutForTopology()
        % Compact layout for Network Topology tab.
        % Shows only the controls needed to configure the network.
        % Long guidance/log areas are hidden on this tab to prevent vertical overflow.

        r = 1;
        r = placeSection(app.sectionScenario, r);
        r = placeRow(app.lblScenarioCount, app.nField, r);
        r = placeRow(app.lblRandomSeed, app.seedField, r);
        r = placeRow(app.lblLoadPDF, app.loadPdfDrop, r);
        r = placeRow(app.lblPFPDF, app.pfPdfDrop, r);
        r = placeRow(app.lblOfferPDF, app.offerPdfDrop, r);
        r = placeRow(app.lblGlobalLoadScale, app.globalLoadScaleField, r);

        r = r + 1;
        r = placeSection(app.sectionQuickRole, r);
        r = placeRow(app.lblBus, app.busSelectDrop, r);
        r = placeRow(app.lblRole, app.roleDrop, r);
        r = placeRow(app.lblAddedPd, app.addPdField, r);
        r = placeRow(app.lblAddedPF, app.addPfField, r);
        r = placeRow(app.lblPminPmax, app.pminmaxField, r);
        r = placeRow(app.lblQminQmax, app.qminmaxField, r);
        r = placeRow(app.lblVg, app.vgField, r);
        r = placeRow(app.lblC2, app.c2Field, r);
        r = placeRow(app.lblC1, app.c1Field, r);
        r = placeRow(app.lblC0, app.c0Field, r);

        app.applyRoleButton.Layout.Row = r;
        app.applyRoleButton.Layout.Column = [1 2];
        r = r + 1;

        app.saveCustomConfigButton.Layout.Row = r;
        app.saveCustomConfigButton.Layout.Column = [1 2];
        r = r + 1;

        app.loadCustomConfigButton.Layout.Row = r;
        app.loadCustomConfigButton.Layout.Column = [1 2];
        r = r + 1;

        app.resetRolesButton.Layout.Row = r;
        app.resetRolesButton.Layout.Column = [1 2];

        % Keep status/log/context hidden on this dense configuration tab.
        app.contextInfoArea.Visible = 'off';
        app.sideStatus.Visible = 'off';
        app.log.Visible = 'off';
    end


    function layoutForEconometric()
        % Compact layout for Econometric Outputs tab.
        r = 1;
        r = placeSection(app.sectionPlotSelectors, r);
        r = placeRow(app.lblPlotBusA, app.plotBusADrop, r);
        r = placeRow(app.lblPlotBusB, app.plotBusBDrop, r);
        r = placeRow(app.lblPlotBusC, app.plotBusCDrop, r);

        r = r + 1;
        app.contextInfoArea.Layout.Row = [r, r+7];
        app.contextInfoArea.Layout.Column = [1 2];
        r = r + 8;

        app.sideStatus.Layout.Row = r;
        app.sideStatus.Layout.Column = [1 2];
        r = r + 1;

        app.log.Layout.Row = [r, min(r+8, 52)];
        app.log.Layout.Column = [1 2];
    end

    function layoutForOverview()
        % Summary-only layout for Overview tab.
        r = 1;
        app.contextInfoArea.Layout.Row = [r, r+12];
        app.contextInfoArea.Layout.Column = [1 2];
        r = r + 13;

        app.sideStatus.Layout.Row = r;
        app.sideStatus.Layout.Column = [1 2];
        r = r + 1;

        app.log.Layout.Row = [r, min(r+10, 52)];
        app.log.Layout.Column = [1 2];
    end

    function layoutForValidation()
        % Validation-focused layout.
        r = 1;
        r = placeSection(app.sectionValidationExport, r);
        r = placeRow(app.lblRunValidation, app.validateCheck, r);
        r = placeRow(app.lblOutputExcel, app.outputField, r);

        r = r + 1;
        app.contextInfoArea.Layout.Row = [r, r+10];
        app.contextInfoArea.Layout.Column = [1 2];
        r = r + 11;

        app.sideStatus.Layout.Row = r;
        app.sideStatus.Layout.Column = [1 2];
        r = r + 1;

        app.log.Layout.Row = [r, min(r+10, 52)];
        app.log.Layout.Column = [1 2];
    end

    function layoutForDataPreview()
        % Export-focused layout for Data Preview.
        r = 1;
        r = placeSection(app.sectionValidationExport, r);
        r = placeRow(app.lblOutputExcel, app.outputField, r);

        r = r + 1;
        app.contextInfoArea.Layout.Row = [r, r+11];
        app.contextInfoArea.Layout.Column = [1 2];
        r = r + 12;

        app.sideStatus.Layout.Row = r;
        app.sideStatus.Layout.Column = [1 2];
        r = r + 1;

        app.log.Layout.Row = [r, min(r+10, 52)];
        app.log.Layout.Column = [1 2];
    end

    function r = placeSection(h, r)
        h.Layout.Row = r;
        h.Layout.Column = [1 2];
        r = r + 1;
    end

    function r = placeRow(labelHandle, controlHandle, r)
        labelHandle.Layout.Row = r;
        labelHandle.Layout.Column = 1;
        controlHandle.Layout.Row = r;
        controlHandle.Layout.Column = 2;
        r = r + 1;
    end

    function showScenarioSettings(tf)
        setVisible(tf, {
            app.sectionScenario
            app.lblScenarioCount
            app.nField
            app.lblRandomSeed
            app.seedField
            app.lblLoadPDF
            app.loadPdfDrop
            app.lblPFPDF
            app.pfPdfDrop
            app.lblOfferPDF
            app.offerPdfDrop
            app.lblGlobalLoadScale
            app.globalLoadScaleField
            });
    end

    function showQuickRoleEditor(tf)
        setVisible(tf, {
            app.sectionQuickRole
            app.lblBus
            app.busSelectDrop
            app.lblRole
            app.roleDrop
            app.lblAddedPd
            app.addPdField
            app.lblAddedPF
            app.addPfField
            app.lblPminPmax
            app.pminmaxField
            app.lblQminQmax
            app.qminmaxField
            app.lblVg
            app.vgField
            app.lblC2
            app.c2Field
            app.lblC1
            app.c1Field
            app.lblC0
            app.c0Field
            app.applyRoleButton
            app.saveCustomConfigButton
            app.loadCustomConfigButton
            app.resetRolesButton
            });
    end

    function showPlotSelectors(tf)
        setVisible(tf, {
            app.sectionPlotSelectors
            app.lblPlotBusA
            app.plotBusADrop
            app.lblPlotBusB
            app.plotBusBDrop
            app.lblPlotBusC
            app.plotBusCDrop
            });
    end

    function showValidationExport(tf)
        setVisible(tf, {
            app.sectionValidationExport
            app.lblRunValidation
            app.validateCheck
            app.lblOutputExcel
            app.outputField
            });
    end

    function hideContextInfoForTopology()
        % Network Topology already has extensive information on the right-side
        % legend + selected bus details. Keeping this left panel compact makes
        % scenario and bus-role controls fully visible without scrolling.
        try
            app.contextInfoArea.Visible = 'off';
            app.sideStatus.Visible = 'off';
            app.log.Visible = 'off';
        catch
        end
    end

    function showContextInfo(lines)
        app.contextInfoArea.Visible = 'on';
        app.sideStatus.Visible = 'on';
        app.log.Visible = 'on';
        app.contextInfoArea.Value = lines;
    end

    function setVisible(tf, handles)
        if tf
            v = 'on';
        else
            v = 'off';
        end

        if isempty(handles)
            return;
        end

        if ~iscell(handles)
            handles = num2cell(handles);
        end

        for jj = 1:numel(handles)
            try
                handles{jj}.Visible = v;
            catch
                try
                    handles(jj).Visible = v;
                catch
                end
            end
        end
    end


    function txt = datasetSummaryText()
        if isempty(app.T) || height(app.T) == 0
            txt = {
                'OVERVIEW'
                ' '
                '• No scenario dataset generated yet.'
                '• Configure the network in Network Topology.'
                '• Click Generate Scenarios + Analyze.'
                '• Overview plots will summarize demand, DLMP, voltage and loading.'
                };
            return;
        end

        txt = {
            'DATASET SUMMARY'
            ' '
            sprintf('• Scenarios              : %d', height(app.T))
            sprintf('• Total Pd range [MW]    : %.3f – %.3f', min(app.T.total_Pd_MW), max(app.T.total_Pd_MW))
            sprintf('• Mean total Pd [MW]     : %.3f', mean(app.T.total_Pd_MW, 'omitnan'))
            sprintf('• Max loading [%%]        : %.3f', max(app.T.max_branch_loading_percent, [], 'omitnan'))
            sprintf('• Mean DLMP LAM_P        : %.3f', mean(app.T.mean_DLMP_LAM_P, 'omitnan'))
            sprintf('• DLMP spread max        : %.3f', max(app.T.DLMP_spread_LAM_P, [], 'omitnan'))
            sprintf('• Local gen share mean   : %.3f', mean(app.T.local_generation_share, 'omitnan'))
            ''
            'Use Overview plots to inspect system-level behavior.'
            };
    end

    function logMsg(msg)
        stamp = datestr(now, 'HH:MM:SS');
        current = app.log.Value;
        if ischar(current)
            current = {current};
        end
        app.log.Value = [current; {sprintf('[%s] %s', stamp, msg)}];
        drawnow limitrate;
    end

    %% ============================================================
    % Nested helper functions - callbacks
    %% ============================================================
    function runGeneration()
        try
            app.runButton.Enable = 'off';
            app.status.Text = 'Running case33bw OPF scenarios...';
            app.sideStatus.Text = 'Running...';
            logMsg('Starting case33bw scenario generation.');
            drawnow;

            cfg = readConfigFromUI();
            rng(cfg.seed);

            app.T = table();
            app.busResults = table();
            app.branchResults = table();
            app.genResults = table();
            app.validationTable = table();
            app.validationSummary = table();
            app.econTable = table();
            app.scenarioMPCs = {};
            app.scenarioResults = {};

            mpopt = mpoption('verbose', 0, 'out.all', 0, 'opf.ac.solver', 'MIPS');

            summaryRows = struct([]);
            busTables = cell(cfg.N, 1);
            branchTables = cell(cfg.N, 1);
            genTables = cell(cfg.N, 1);

            validCount = 0;
            totalAttempts = 0;
            opfFailCount = 0;

            while validCount < cfg.N
                candidateNo = validCount + 1;
                solved = false;

                for attempt = 1:cfg.maxAttemptsPerScenario
                    totalAttempts = totalAttempts + 1;

                    try
                        [mpc, scenarioInfo] = buildScenarioMPC(app.base_mpc, cfg.roleConfig, cfg);
                    catch ME
                        error('Scenario construction failed: %s', ME.message);
                    end

                    try
                        results = runopf(mpc, mpopt);
                    catch ME
                        opfFailCount = opfFailCount + 1;
                        if attempt == 1 || mod(opfFailCount, 25) == 0
                            logMsg(sprintf('Candidate %d OPF error: %s', candidateNo, ME.message));
                        end
                        continue;
                    end

                    if ~isfield(results, 'success') || results.success ~= 1
                        opfFailCount = opfFailCount + 1;
                        continue;
                    end

                    validCount = validCount + 1;

                    [summaryRow, busTable, branchTable, genTable] = extractScenarioResults( ...
                        validCount, mpc, results, cfg.roleConfig, scenarioInfo, attempt, cfg);

                    if validCount == 1
                        summaryRows = summaryRow;
                    else
                        summaryRows(validCount) = summaryRow;
                    end
                    busTables{validCount} = busTable;
                    branchTables{validCount} = branchTable;
                    genTables{validCount} = genTable;

                    app.scenarioMPCs{validCount, 1} = mpc;
                    app.scenarioResults{validCount, 1} = results;

                    solved = true;

                    if validCount == 1 || mod(validCount, max(1, round(cfg.N/10))) == 0 || validCount == cfg.N
                        app.status.Text = sprintf('Generated %d / %d scenarios', validCount, cfg.N);
                        app.sideStatus.Text = app.status.Text;
                        logMsg(sprintf('Generated %d / %d valid scenarios. Attempts: %d', validCount, cfg.N, totalAttempts));
                        drawnow limitrate;
                    end

                    break;
                end

                if ~solved
                    error('Could not generate candidate %d after %d attempts. Try wider ranges or less restrictive roles.', ...
                        candidateNo, cfg.maxAttemptsPerScenario);
                end
            end

            app.T = struct2table(summaryRows);
            app.busResults = vertcat(busTables{:});
            app.branchResults = vertcat(branchTables{:});
            app.genResults = vertcat(genTables{:});

            app.T = addScenarioDerivedMetrics(app.T);
            app.econTable = runEconometricModels(app.T);

            if cfg.runValidation
                logMsg('RUNPF validation started.');
                tol = defaultValidationTolerances();
                [app.validationTable, app.validationSummary] = validateGeneratedScenarios(app.scenarioMPCs, app.scenarioResults, tol);
                logMsg('RUNPF validation completed.');
            end

            updateAllPlots();
            updateTables();
            updateContextControls(app.tabs.SelectedTab);
            saveCurrentResults();

            app.status.Text = sprintf('Done. %d case33bw scenarios generated.', height(app.T));
            app.sideStatus.Text = 'Done.';
            logMsg(sprintf('Done. Requested output base: %s', cfg.outputFile));
        catch ME
            app.status.Text = 'Error.';
            app.sideStatus.Text = 'Error.';
            logMsg(sprintf('ERROR: %s', ME.message));
            uialert(app.fig, ME.message, 'Dashboard Error');
        end
        app.runButton.Enable = 'on';
    end

    function loadExistingExcel()
        try
            [file, path] = uigetfile('*.xlsx', 'Select scenario dataset Excel file');
            if isequal(file, 0)
                logMsg('Excel loading cancelled by user.');
                return;
            end

            fullName = fullfile(path, file);
            logMsg(sprintf('Loading Excel file: %s', fullName));

            availableSheets = sheetnames(fullName);

            if ~any(strcmpi(availableSheets, 'scenario_dataset'))
                error(['The selected Excel file does not contain a "scenario_dataset" sheet. ', ...
                       'Please select an Excel file exported by this dashboard.']);
            end

            T = readtable(fullName, 'Sheet', 'scenario_dataset');
            app.T = addScenarioDerivedMetrics(T);

            % New case33bw long-format export.
            if any(strcmpi(availableSheets, 'bus_results_long'))
                app.busResults = readtable(fullName, 'Sheet', 'bus_results_long');
            else
                % Fallback for earlier wide-format exports.
                app.busResults = convertWideScenarioDatasetToBusLong(app.T);
                logMsg('bus_results_long sheet not found. Converted available wide bus columns to long format.');
            end

            if any(strcmpi(availableSheets, 'branch_results_long'))
                app.branchResults = readtable(fullName, 'Sheet', 'branch_results_long');
            else
                % Fallback for earlier wide-format exports.
                app.branchResults = convertWideScenarioDatasetToBranchLong(app.T);
                logMsg('branch_results_long sheet not found. Converted available wide branch columns to long format.');
            end

            if any(strcmpi(availableSheets, 'gen_results_long'))
                app.genResults = readtable(fullName, 'Sheet', 'gen_results_long');
            else
                app.genResults = table();
                logMsg('gen_results_long sheet not found. Generator long table left empty.');
            end

            if any(strcmpi(availableSheets, 'bus_role_config'))
                roleCfg = readtable(fullName, 'Sheet', 'bus_role_config');
                roleCfg.role = string(roleCfg.role);
                app.busRoleConfig = validateBusRoleConfig(roleCfg, app.busRoleConfig, app.base_mpc);
                refreshBusRoleConfigUI(1);
                logMsg('Loaded bus_role_config sheet.');
            else
                logMsg('bus_role_config sheet not found. Keeping current/default bus role configuration.');
            end

            if any(strcmpi(availableSheets, 'runpf_validation'))
                app.validationTable = readtable(fullName, 'Sheet', 'runpf_validation');
            else
                app.validationTable = table();
            end

            if any(strcmpi(availableSheets, 'validation_summary'))
                app.validationSummary = readtable(fullName, 'Sheet', 'validation_summary');
            else
                app.validationSummary = table();
            end

            app.econTable = runEconometricModels(app.T);

            % Loaded Excel does not reconstruct the original mpc/results snapshots.
            % Therefore validation can be displayed if included, but cannot be rerun
            % exactly from loaded long-format results.
            app.scenarioMPCs = {};
            app.scenarioResults = {};

            refreshBusRoleConfigUI(1);
            updateAllPlots();
            updateTables();
            updateContextControls(app.tabs.SelectedTab);

            app.outputField.Value = file;
            app.status.Text = sprintf('Loaded %d scenario rows from Excel.', height(app.T));
            app.sideStatus.Text = 'Loaded.';
            logMsg(sprintf('Excel analysis completed. Scenario rows: %d', height(app.T)));
        catch ME
            app.status.Text = 'Load error.';
            app.sideStatus.Text = 'Load error.';
            logMsg(sprintf('ERROR loading Excel: %s', ME.message));
            uialert(app.fig, ME.message, 'Load Existing Excel Error');
        end
    end

    function saveCurrentResults()
        if isempty(app.T) || height(app.T) == 0
            logMsg('No scenario table to save yet.');
            return;
        end

        try
            outputFile = strtrim(app.outputField.Value);
            if isempty(outputFile)
                outputFile = 'dataset_case33bw_dashboard.xlsx';
            end

            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            [p, n, e] = fileparts(outputFile);
            if isempty(e)
                e = '.xlsx';
            end
            newName = sprintf('%s_%s%s', n, stamp, e);
            if isempty(p)
                outputFile = newName;
            else
                outputFile = fullfile(p, newName);
            end

            if isfile(outputFile)
                delete(outputFile);
            end

            writetable(app.T, outputFile, 'Sheet', 'scenario_dataset');
            writetable(app.busResults, outputFile, 'Sheet', 'bus_results_long');
            writetable(app.branchResults, outputFile, 'Sheet', 'branch_results_long');

            if ~isempty(app.genResults)
                writetable(app.genResults, outputFile, 'Sheet', 'gen_results_long');
            end

            writetable(app.busRoleConfig, outputFile, 'Sheet', 'bus_role_config');
            writetable(createBusStaticTable(app.base_mpc, app.busRoleConfig), outputFile, 'Sheet', 'bus_static');
            writetable(createBranchStaticTable(app.base_mpc), outputFile, 'Sheet', 'branch_static');
            writetable(selectDerivedMetrics(app.T), outputFile, 'Sheet', 'derived_metrics');

            if ~isempty(app.validationTable)
                writetable(app.validationTable, outputFile, 'Sheet', 'runpf_validation');
            end
            if ~isempty(app.validationSummary)
                writetable(app.validationSummary, outputFile, 'Sheet', 'validation_summary');
            end

            logMsg(sprintf('Saved Excel file: %s', outputFile));
        catch ME
            logMsg(sprintf('ERROR saving Excel: %s', ME.message));
            uialert(app.fig, ME.message, 'Save Error');
        end
    end

    function cfg = readConfigFromUI()
        cfg = struct();
        cfg.N = max(1, round(app.nField.Value));
        cfg.seed = round(app.seedField.Value);
        cfg.loadPDF = app.loadPdfDrop.Value;
        cfg.pfPDF = app.pfPdfDrop.Value;
        cfg.offerPDF = app.offerPdfDrop.Value;
        cfg.globalLoadScaleRange = parseRange(app.globalLoadScaleField.Value, 'Global load scale');
        cfg.outputFile = strtrim(app.outputField.Value);
        cfg.runValidation = app.validateCheck.Value;
        cfg.maxAttemptsPerScenario = 100;
        cfg.roleConfig = validateBusRoleConfig(getRoleConfigFromUITable(), app.busRoleConfig, app.base_mpc);

        if isempty(cfg.outputFile)
            cfg.outputFile = 'dataset_case33bw_dashboard.xlsx';
        end
    end

    %% ============================================================
    % Nested helper functions - UI update and plots
    %% ============================================================
    function updateTables()
        app.summaryUITable.Data = firstNRows(app.T, 100);
        app.busUITable.Data = firstNRows(app.busResults, 150);
        app.branchUITable.Data = firstNRows(app.branchResults, 150);
        app.genUITable.Data = firstNRows(app.genResults, 150);

        if ~isempty(app.validationTable)
            app.validationUITable.Data = firstNRows(app.validationTable, 100);
        else
            app.validationUITable.Data = table();
        end
    end

    function updateAllPlots()
        refreshTopology();

        if isempty(app.T) || height(app.T) == 0 || isempty(app.busResults)
            return;
        end

        T = app.T;
        B = app.busResults;
        R = app.branchResults;

        cla(app.axLoadHist); cla(app.axDlmpHist); cla(app.axVoltage); cla(app.axLoading);
        cla(app.axBusADlmpDemand); cla(app.axBusBDlmpDemand); cla(app.axBusCDlmpDemand);
        cla(app.axCostOLS); cla(app.axLossDemand); cla(app.axC2LDemand);
        cla(app.axValErrors); cla(app.axFailReasons);

        %% Overview: total demand
        histogram(app.axLoadHist, T.total_Pd_MW, max(10, round(sqrt(height(T)))));
        xlabel(app.axLoadHist, 'Total Pd [MW]');
        ylabel(app.axLoadHist, 'Count');
        title(app.axLoadHist, 'Total Demand Distribution');
        grid(app.axLoadHist, 'off');

        %% Overview: DLMP distribution for selected buses
        selectedBuses = selectedPlotBuses();
        hold(app.axDlmpHist, 'on');
        leg = cell(1, numel(selectedBuses));
        for i = 1:numel(selectedBuses)
            sb = selectedBuses(i);
            Bb = B(B.bus_id == sb, :);
            if ~isempty(Bb)
                histogram(app.axDlmpHist, Bb.DLMP_LAM_P, 'DisplayStyle', 'stairs');
                leg{i} = sprintf('Bus %d', sb);
            end
        end
        hold(app.axDlmpHist, 'off');
        xlabel(app.axDlmpHist, 'LAM_P');
        ylabel(app.axDlmpHist, 'Count');
        title(app.axDlmpHist, 'Selected Bus Active DLMP Distribution');
        if ~isempty(leg)
            legend(app.axDlmpHist, leg, 'Location', 'best');
        end
        grid(app.axDlmpHist, 'off');

        %% Overview: voltage profile across all buses
        busIds = unique(B.bus_id);
        meanVm = NaN(numel(busIds), 1);
        minVm = NaN(numel(busIds), 1);
        maxVm = NaN(numel(busIds), 1);
        for i = 1:numel(busIds)
            rows = B.bus_id == busIds(i);
            meanVm(i) = mean(B.Vm_pu(rows), 'omitnan');
            minVm(i) = min(B.Vm_pu(rows), [], 'omitnan');
            maxVm(i) = max(B.Vm_pu(rows), [], 'omitnan');
        end
        plot(app.axVoltage, busIds, meanVm, '-o');
        hold(app.axVoltage, 'on');
        plot(app.axVoltage, busIds, minVm, '--');
        plot(app.axVoltage, busIds, maxVm, '--');
        hold(app.axVoltage, 'off');
        xlabel(app.axVoltage, 'Bus');
        ylabel(app.axVoltage, 'Vm [p.u.]');
        title(app.axVoltage, 'Voltage Mean / Min / Max by Bus');
        legend(app.axVoltage, {'Mean','Min','Max'}, 'Location', 'best');
        grid(app.axVoltage, 'off');

        %% Overview: branch loading
        plot(app.axLoading, T.scenario_id, T.max_branch_loading_percent, '.-');
        xlabel(app.axLoading, 'Scenario');
        ylabel(app.axLoading, 'Max Branch Loading [%]');
        title(app.axLoading, 'Maximum Branch Loading by Scenario');
        grid(app.axLoading, 'off');

        %% Dynamic bus DLMP plots
        plotBusDLMPPanel(app.axBusADlmpDemand, selectedBuses(1));
        plotBusDLMPPanel(app.axBusBDlmpDemand, selectedBuses(2));
        plotBusDLMPPanel(app.axBusCDlmpDemand, selectedBuses(3));

        %% Existing economic relation plots
        plotInputOutputScatter(app.axCostOLS, T.total_Pd_MW, T.objective_cost, ...
            'Total Pd [MW]', 'Objective Cost', 'Objective Cost vs Total Demand');

        plotInputOutputScatter(app.axLossDemand, T.total_Pd_MW, T.total_P_loss_MW, ...
            'Total Pd [MW]', 'Total P Loss [MW]', 'Losses vs Total Demand');

        plotInputOutputScatter(app.axC2LDemand, T.total_Pd_MW, T.cost_to_load_total, ...
            'Total Pd [MW]', 'Cost-to-Load', 'C2L vs Total Demand');

        %% Validation plots
        if ~isempty(app.validationTable) && height(app.validationTable) > 0
            Vt = app.validationTable;
            loadingSeverity = Vt.max_abs_loading_error ./ 1e-3;
            loadingSeverity(~isfinite(loadingSeverity)) = NaN;

            severity = [ ...
                Vt.max_abs_Vm_error ./ 1e-5, ...
                Vt.max_abs_Va_error ./ 1e-3, ...
                Vt.max_abs_Pf_error ./ 1e-4, ...
                Vt.max_abs_Qf_error ./ 1e-4, ...
                loadingSeverity];
            plot(app.axValErrors, Vt.scenario_id, severity, '.');
            yline(app.axValErrors, 1, '--');
            xlabel(app.axValErrors, 'Scenario');
            ylabel(app.axValErrors, 'Error / Tolerance');
            title(app.axValErrors, 'Validation Error Severity');
            legend(app.axValErrors, {'Vm','Va','Pf','Qf','Loading','Pass threshold'}, 'Location', 'best');
            grid(app.axValErrors, 'off');

            failRows = Vt(Vt.runpf_success == 1 & Vt.validation_pass == 0, :);
            if height(failRows) > 0
                cats = categorical(failRows.dominant_fail_reason);
                histogram(app.axFailReasons, cats);
                title(app.axFailReasons, 'Dominant Reasons for Validation Fail');
                ylabel(app.axFailReasons, 'Count');
                grid(app.axFailReasons, 'off');
            else
                text(app.axFailReasons, 0.1, 0.5, 'No PF-success / validation-fail cases.', 'Units', 'normalized');
                axis(app.axFailReasons, 'off');
            end
        end

        function plotBusDLMPPanel(ax, busId)
            [x, y] = selectedBusXY(busId);
            plotDLMPScatterWithDemandDistribution(ax, x, y, ...
                'Total Pd [MW]', sprintf('Bus %d DLMP LAM_P', busId), ...
                sprintf('Bus %d DLMP vs Total Demand', busId));
        end

        function [x, y] = selectedBusXY(busId)
            Bb = B(B.bus_id == busId, :);
            x = [];
            y = [];
            if isempty(Bb)
                return;
            end
            [commonIds, ia, ib] = intersect(T.scenario_id, Bb.scenario_id);
            if isempty(commonIds)
                return;
            end
            x = T.total_Pd_MW(ia);
            y = Bb.DLMP_LAM_P(ib);
        end
    end

    function buses = selectedPlotBuses()
        buses = [str2double(app.plotBusADrop.Value), str2double(app.plotBusBDrop.Value), str2double(app.plotBusCDrop.Value)];
        buses = reshape(buses, 1, []);
    end

end

%% ========================================================================
% Local computational functions - MATPOWER case setup
%% ========================================================================
function mpc = loadCase33bwForDashboard()
    try
        mpc = loadcase('case33bw');
    catch ME
        error(['Could not load MATPOWER case33bw. Make sure MATPOWER is installed, ' ...
               'case33bw is on the MATLAB path, and run install_matpower if needed. Original error: %s'], ME.message);
    end

    mpc = ensureOPFReady(mpc);
end

function mpc = ensureOPFReady(mpc)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    if ~isfield(mpc, 'version')
        mpc.version = '2';
    end
    if ~isfield(mpc, 'baseMVA') || isempty(mpc.baseMVA)
        mpc.baseMVA = 100;
    end

    if ~isfield(mpc, 'bus') || isempty(mpc.bus)
        error('The loaded case does not contain mpc.bus.');
    end
    if ~isfield(mpc, 'branch') || isempty(mpc.branch)
        error('The loaded case does not contain mpc.branch.');
    end

    if ~any(mpc.bus(:, BUS_TYPE) == 3)
        mpc.bus(1, BUS_TYPE) = 3;
    end
    slackBus = mpc.bus(find(mpc.bus(:, BUS_TYPE) == 3, 1), BUS_I);

    if ~isfield(mpc, 'gen') || isempty(mpc.gen)
        mpc.gen = zeros(1, 21);
        mpc.gen(1, GEN_BUS) = slackBus;
        mpc.gen(1, PG) = sum(mpc.bus(:, PD));
        mpc.gen(1, QG) = sum(mpc.bus(:, QD));
        mpc.gen(1, QMAX) = 100;
        mpc.gen(1, QMIN) = -100;
        mpc.gen(1, VG) = 1.00;
        mpc.gen(1, MBASE) = mpc.baseMVA;
        mpc.gen(1, GEN_STATUS) = 1;
        mpc.gen(1, PMAX) = max(100, 2 * sum(mpc.bus(:, PD)));
        mpc.gen(1, PMIN) = 0;
    else
        if size(mpc.gen, 2) < 21
            mpc.gen(:, end+1:21) = 0;
        end
        if ~any(mpc.gen(:, GEN_BUS) == slackBus & mpc.gen(:, GEN_STATUS) > 0)
            newGen = zeros(1, size(mpc.gen, 2));
            newGen(GEN_BUS) = slackBus;
            newGen(PG) = sum(mpc.bus(:, PD));
            newGen(QG) = sum(mpc.bus(:, QD));
            newGen(QMAX) = 100;
            newGen(QMIN) = -100;
            newGen(VG) = 1.00;
            newGen(MBASE) = mpc.baseMVA;
            newGen(GEN_STATUS) = 1;
            newGen(PMAX) = max(100, 2 * sum(mpc.bus(:, PD)));
            newGen(PMIN) = 0;
            mpc.gen = [newGen; mpc.gen];
        end
    end

    nGen = size(mpc.gen, 1);
    if ~isfield(mpc, 'gencost') || isempty(mpc.gencost) || size(mpc.gencost, 1) ~= nGen
        mpc.gencost = repmat([2 0 0 3 0.020 80 0], nGen, 1);
    else
        if size(mpc.gencost, 2) < 7
            mpc.gencost(:, end+1:7) = 0;
            mpc.gencost(:, 1) = 2;
            mpc.gencost(:, 4) = 3;
        end
    end

    if size(mpc.branch, 2) < 13
        mpc.branch(:, end+1:13) = 0;
        mpc.branch(:, BR_STATUS) = 1;
        mpc.branch(:, ANGMIN) = -360;
        mpc.branch(:, ANGMAX) = 360;
    end
end

function roleCfg = createDefaultBusRoleConfig(mpc)
    C = mpConst();
    BUS_I = C.BUS_I; PD = C.PD;

    busId = mpc.bus(:, BUS_I);
    nBus = numel(busId);
    slackBus = getSlackBusId(mpc);

    % ============================================================
    % True base case33bw configuration
    % ============================================================
    % Bus 1      -> Slack/Grid
    % Bus 2-33   -> PQ Load
    % No DER
    % No Prosumer
    % No Large Load
    %
    % This represents the original case33bw base system before adding
    % local generation, prosumers, or extra large loads.
    % ============================================================

    role = strings(nBus, 1);
    role(:) = "PQ Load";
    role(busId == slackBus) = "Slack/Grid";

    % No additional load in the true base model.
    addMin = zeros(nBus, 1);
    addMax = zeros(nBus, 1);

    % PF values are kept as default placeholders.
    % They do not affect ordinary PQ buses because case33bw already has Pd/Qd.
    pfMin = 0.90 * ones(nBus, 1);
    pfMax = 0.98 * ones(nBus, 1);

    % Generator-related placeholders.
    % For PQ buses these are not used.
    Pmin = zeros(nBus, 1);
    Pmax = zeros(nBus, 1);
    Qmin = zeros(nBus, 1);
    Qmax = zeros(nBus, 1);
    Vg   = ones(nBus, 1);

    % Cost placeholders.
    % For PQ buses these are not used.
    c2Min = zeros(nBus, 1);
    c2Max = zeros(nBus, 1);
    c1Min = zeros(nBus, 1);
    c1Max = zeros(nBus, 1);
    c0    = zeros(nBus, 1);

    % Slack/Grid source.
    for i = 1:nBus
        if busId(i) == slackBus
            Pmin(i) = 0;
            Pmax(i) = max(100, 2 * sum(mpc.bus(:, PD)));
            Qmin(i) = -100;
            Qmax(i) = 100;
            Vg(i)   = 1.00;

            % Grid/slack cost.
            c2Min(i) = 0.020;
            c2Max(i) = 0.020;
            c1Min(i) = 80;
            c1Max(i) = 80;
            c0(i)    = 0;
        end
    end

    roleCfg = table(busId, role, addMin, addMax, pfMin, pfMax, ...
        Pmin, Pmax, Qmin, Qmax, Vg, c2Min, c2Max, c1Min, c1Max, c0, ...
        'VariableNames', {'bus_id','role','add_Pd_min_MW','add_Pd_max_MW', ...
        'pf_min','pf_max','Pmin_MW','Pmax_MW','Qmin_MVAr','Qmax_MVAr', ...
        'Vg_pu','c2_min','c2_max','c1_min','c1_max','c0'});
end


function roleCfg = validateBusRoleConfig(candidateCfg, referenceCfg, mpc)
    allowed = ["Slack/Grid", "PQ Load", "DER", "Prosumer", "Large Load"];
    required = {'bus_id','role','add_Pd_min_MW','add_Pd_max_MW','pf_min','pf_max', ...
        'Pmin_MW','Pmax_MW','Qmin_MVAr','Qmax_MVAr','Vg_pu','c2_min','c2_max','c1_min','c1_max','c0'};
    numericCols = {'bus_id','add_Pd_min_MW','add_Pd_max_MW','pf_min','pf_max', ...
        'Pmin_MW','Pmax_MW','Qmin_MVAr','Qmax_MVAr','Vg_pu','c2_min','c2_max','c1_min','c1_max','c0'};

    if nargin < 3
        error('validateBusRoleConfig requires candidate config, reference config, and mpc.');
    end

    if ~istable(candidateCfg)
        error('Bus role config must be a table.');
    end

    if ~istable(referenceCfg)
        error('Reference bus role config must be a table.');
    end

    roleCfg = candidateCfg;

    for i = 1:numel(required)
        if ~ismember(required{i}, roleCfg.Properties.VariableNames)
            error('Bus role config is missing column: %s', required{i});
        end
    end

    for i = 1:numel(numericCols)
        colName = numericCols{i};
        if ~isnumeric(roleCfg.(colName))
            error('Bus role config column "%s" must be numeric.', colName);
        end
    end

    refNames = referenceCfg.Properties.VariableNames;
    if all(ismember(refNames, roleCfg.Properties.VariableNames))
        roleCfg = roleCfg(:, refNames);
    else
        roleCfg = roleCfg(:, required);
    end

    roleCfg.role = string(roleCfg.role);
    busIds = mpc.bus(:, 1);

    if height(roleCfg) ~= numel(busIds) || any(sort(roleCfg.bus_id) ~= sort(busIds))
        error('Bus role config must contain exactly one row for every case33bw bus.');
    end

    [tf, loc] = ismember(busIds, roleCfg.bus_id);
    if ~all(tf)
        error('Bus role config bus IDs do not match the current case33bw bus IDs.');
    end
    roleCfg = roleCfg(loc, :);

    slackBus = getSlackBusId(mpc);
    slackRows = roleCfg.role == "Slack/Grid";
    if sum(slackRows) ~= 1 || roleCfg.bus_id(slackRows) ~= slackBus
        error('Exactly one Slack/Grid role is allowed, and it must be the original case33bw slack bus.');
    end

    for k = 1:height(roleCfg)
        if ~any(roleCfg.role(k) == allowed)
            error('Invalid role "%s" at bus %d.', roleCfg.role(k), roleCfg.bus_id(k));
        end

        if roleCfg.add_Pd_min_MW(k) > roleCfg.add_Pd_max_MW(k)
            error('Added Pd min > max at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.pf_min(k) < 0 || roleCfg.pf_max(k) > 1 || roleCfg.pf_min(k) > roleCfg.pf_max(k)
            error('Invalid PF range at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.Pmin_MW(k) > roleCfg.Pmax_MW(k)
            error('Pmin > Pmax at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.Qmin_MVAr(k) > roleCfg.Qmax_MVAr(k)
            error('Qmin > Qmax at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.c2_min(k) > roleCfg.c2_max(k) || roleCfg.c1_min(k) > roleCfg.c1_max(k)
            error('Invalid cost range at bus %d.', roleCfg.bus_id(k));
        end
    end
end

%% ========================================================================
% Local computational functions - scenario generation
%% ========================================================================
function [mpc, scenarioInfo] = buildScenarioMPC(base_mpc, roleCfg, cfg)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    mpc = base_mpc;
    roleCfg = validateBusRoleConfig(roleCfg, createDefaultBusRoleConfig(base_mpc), base_mpc);

    if size(mpc.gen, 2) < 21
        mpc.gen(:, end+1:21) = 0;
    end

    % Start with the original case33bw base load and apply a global load scale.
    loadScale = sampleByPDF(cfg.globalLoadScaleRange, cfg.loadPDF);

    basePd = base_mpc.bus(:, PD);
    baseQd = base_mpc.bus(:, QD);

    mpc.bus(:, PD) = basePd .* loadScale;
    mpc.bus(:, QD) = baseQd .* loadScale;

    % Keep only original generators initially, then add DER/Prosumer generators.
    mpc = ensureOPFReady(mpc);

    slackBus = getSlackBusId(mpc);

    % Update base grid/slack cost using Slack/Grid role row.
    slackRole = roleCfg(roleCfg.bus_id == slackBus, :);
    if ~isempty(slackRole)
        gridC2 = sampleByPDF([slackRole.c2_min, slackRole.c2_max], cfg.offerPDF);
        gridC1 = sampleByPDF([slackRole.c1_min, slackRole.c1_max], cfg.offerPDF);
        gridC0 = slackRole.c0;
        slackGenRows = find(mpc.gen(:, GEN_BUS) == slackBus);
        if ~isempty(slackGenRows)
            mpc.gencost(slackGenRows(1), :) = [2 0 0 3 gridC2 gridC1 gridC0];
            mpc.gen(slackGenRows(1), PMAX) = max(mpc.gen(slackGenRows(1), PMAX), slackRole.Pmax_MW);
            mpc.gen(slackGenRows(1), PMIN) = slackRole.Pmin_MW;
            mpc.gen(slackGenRows(1), QMIN) = slackRole.Qmin_MVAr;
            mpc.gen(slackGenRows(1), QMAX) = slackRole.Qmax_MVAr;
            mpc.gen(slackGenRows(1), VG) = slackRole.Vg_pu;
        end
    end

    busRoleStrings = strings(size(mpc.bus, 1), 1);
    addedLoadP = zeros(size(mpc.bus, 1), 1);
    addedLoadQ = zeros(size(mpc.bus, 1), 1);

    for k = 1:height(roleCfg)
        busId = roleCfg.bus_id(k);
        busRow = find(mpc.bus(:, BUS_I) == busId, 1);
        if isempty(busRow)
            error('Bus %d not found in mpc.bus.', busId);
        end

        role = string(roleCfg.role(k));
        busRoleStrings(busRow) = role;

        switch role
            case "Slack/Grid"
                mpc.bus(busRow, BUS_TYPE) = 3;

            case "PQ Load"
                if busId ~= slackBus
                    mpc.bus(busRow, BUS_TYPE) = 1;
                end

            case "Large Load"
                mpc.bus(busRow, BUS_TYPE) = 1;
                addP = sampleByPDF([roleCfg.add_Pd_min_MW(k), roleCfg.add_Pd_max_MW(k)], cfg.loadPDF);
                addPF = sampleByPDF([roleCfg.pf_min(k), roleCfg.pf_max(k)], cfg.pfPDF);
                addQ = calcQfromPandPF(addP, addPF);
                mpc.bus(busRow, PD) = mpc.bus(busRow, PD) + addP;
                mpc.bus(busRow, QD) = mpc.bus(busRow, QD) + addQ;
                addedLoadP(busRow) = addP;
                addedLoadQ(busRow) = addQ;

            case "DER"
                mpc.bus(busRow, BUS_TYPE) = 2;
                [mpc, ~] = appendRoleGenerator(mpc, roleCfg(k, :), cfg);

            case "Prosumer"
                mpc.bus(busRow, BUS_TYPE) = 2;
                addP = sampleByPDF([roleCfg.add_Pd_min_MW(k), roleCfg.add_Pd_max_MW(k)], cfg.loadPDF);
                addPF = sampleByPDF([roleCfg.pf_min(k), roleCfg.pf_max(k)], cfg.pfPDF);
                addQ = calcQfromPandPF(addP, addPF);
                mpc.bus(busRow, PD) = mpc.bus(busRow, PD) + addP;
                mpc.bus(busRow, QD) = mpc.bus(busRow, QD) + addQ;
                addedLoadP(busRow) = addP;
                addedLoadQ(busRow) = addQ;
                [mpc, ~] = appendRoleGenerator(mpc, roleCfg(k, :), cfg);

            otherwise
                error('Unsupported role "%s".', role);
        end
    end

    % OPF safety checks.
    if any(mpc.bus(:, PD) < 0) || any(mpc.bus(:, QD) < 0)
        error('Negative load detected after scenario generation.');
    end

    scenarioInfo = struct();
    scenarioInfo.loadScale = loadScale;
    scenarioInfo.addedLoadP = addedLoadP;
    scenarioInfo.addedLoadQ = addedLoadQ;
    scenarioInfo.busRoleStrings = busRoleStrings;
end

function [mpc, genRow] = appendRoleGenerator(mpc, roleRow, cfg)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    if size(mpc.gen, 2) < 21
        mpc.gen(:, end+1:21) = 0;
    end

    genRow = zeros(1, size(mpc.gen, 2));
    genRow(GEN_BUS) = roleRow.bus_id;
    genRow(PG) = max(0, min(roleRow.Pmax_MW, 0.5 * roleRow.Pmax_MW));
    genRow(QG) = 0;
    genRow(QMAX) = roleRow.Qmax_MVAr;
    genRow(QMIN) = roleRow.Qmin_MVAr;
    genRow(VG) = roleRow.Vg_pu;
    genRow(MBASE) = mpc.baseMVA;
    genRow(GEN_STATUS) = 1;
    genRow(PMAX) = roleRow.Pmax_MW;
    genRow(PMIN) = roleRow.Pmin_MW;

    c2 = sampleByPDF([roleRow.c2_min, roleRow.c2_max], cfg.offerPDF);
    c1 = sampleByPDF([roleRow.c1_min, roleRow.c1_max], cfg.offerPDF);
    c0 = roleRow.c0;
    costRow = [2 0 0 3 c2 c1 c0];

    mpc.gen = [mpc.gen; genRow];
    mpc.gencost = [mpc.gencost; costRow];
end

%% ========================================================================
% Local computational functions - result extraction
%% ========================================================================
function [summaryRow, busTable, branchTable, genTable] = extractScenarioResults(scenarioId, mpc, results, roleCfg, scenarioInfo, attempt, cfg)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    nBus = size(results.bus, 1);
    nBranch = size(results.branch, 1);
    nGen = size(results.gen, 1);

    busId = results.bus(:, BUS_I);
    role = strings(nBus, 1);
    for i = 1:nBus
        idx = find(roleCfg.bus_id == busId(i), 1);
        if isempty(idx)
            role(i) = "Unknown";
        else
            role(i) = string(roleCfg.role(idx));
        end
    end

    genPgByBus = zeros(nBus, 1);
    genQgByBus = zeros(nBus, 1);
    for g = 1:nGen
        b = results.gen(g, GEN_BUS);
        br = find(busId == b, 1);
        if ~isempty(br)
            genPgByBus(br) = genPgByBus(br) + results.gen(g, PG);
            genQgByBus(br) = genQgByBus(br) + results.gen(g, QG);
        end
    end

    Pd = mpc.bus(:, PD);
    Qd = mpc.bus(:, QD);
    Vm = results.bus(:, VM);
    Va = results.bus(:, VA);
    lamP = results.bus(:, LAM_P);
    lamQ = results.bus(:, LAM_Q);
    addedP = scenarioInfo.addedLoadP;
    addedQ = scenarioInfo.addedLoadQ;

    netLoad = max(Pd - genPgByBus, 0);
    costToLoad = netLoad .* lamP;

    scenario_id = repmat(scenarioId, nBus, 1);
    busTable = table(scenario_id, busId, role, Pd, Qd, addedP, addedQ, ...
        genPgByBus, genQgByBus, netLoad, Vm, Va, lamP, lamQ, costToLoad, ...
        'VariableNames', {'scenario_id','bus_id','role','Pd_MW','Qd_MVAr', ...
        'added_Pd_MW','added_Qd_MVAr','Pg_MW','Qg_MVAr','net_load_MW', ...
        'Vm_pu','Va_deg','DLMP_LAM_P','DLMP_LAM_Q','cost_to_load'});

    branch_id = (1:nBranch)';
    from_bus = results.branch(:, F_BUS);
    to_bus = results.branch(:, T_BUS);
    Pf = results.branch(:, PF);
    Pt = results.branch(:, PT);
    Qf = results.branch(:, QF);
    Qt = results.branch(:, QT);
    P_loss = Pf + Pt;
    Q_loss = Qf + Qt;
    rateA = results.branch(:, RATE_A);
    loading = calculateBranchLoadingPercent(results.branch);
    scenario_id_b = repmat(scenarioId, nBranch, 1);

    branchTable = table(scenario_id_b, branch_id, from_bus, to_bus, Pf, Pt, Qf, Qt, P_loss, Q_loss, rateA, loading, ...
        'VariableNames', {'scenario_id','branch_id','from_bus','to_bus','Pf_MW','Pt_MW', ...
        'Qf_MVAr','Qt_MVAr','P_loss_MW','Q_loss_MVAr','rateA_MVA','loading_percent'});

    gen_id = (1:nGen)';
    gen_bus = results.gen(:, GEN_BUS);
    Pg = results.gen(:, PG);
    Qg = results.gen(:, QG);
    Pmin = results.gen(:, PMIN);
    Pmax = results.gen(:, PMAX);
    Qmin = results.gen(:, QMIN);
    Qmax = results.gen(:, QMAX);
    Vg = results.gen(:, VG);
    status = results.gen(:, GEN_STATUS);
    c2 = results.gencost(:, 5);
    c1 = results.gencost(:, 6);
    c0 = results.gencost(:, 7);
    scenario_id_g = repmat(scenarioId, nGen, 1);

    genTable = table(scenario_id_g, gen_id, gen_bus, Pg, Qg, Pmin, Pmax, Qmin, Qmax, Vg, status, c2, c1, c0, ...
        'VariableNames', {'scenario_id','gen_id','bus_id','Pg_MW','Qg_MVAr','Pmin_MW','Pmax_MW', ...
        'Qmin_MVAr','Qmax_MVAr','Vg_pu','status','c2','c1','c0'});

    dlmpP = lamP;
    dlmpQ = lamQ;

    slackBus = getSlackBusId(mpc);
    slackGenRows = find(results.gen(:, GEN_BUS) == slackBus);
    if isempty(slackGenRows)
        gridPg = NaN;
        gridQg = NaN;
    else
        gridPg = sum(results.gen(slackGenRows, PG));
        gridQg = sum(results.gen(slackGenRows, QG));
    end

    localGenRows = results.gen(:, GEN_BUS) ~= slackBus;
    localGenMW = sum(results.gen(localGenRows, PG));

    summaryRow = struct();
    summaryRow.scenario_id = scenarioId;
    summaryRow.opf_success = results.success;
    summaryRow.objective_cost = results.f;
    summaryRow.attempt_no = attempt;
    summaryRow.N_requested = cfg.N;
    summaryRow.load_pdf = string(cfg.loadPDF);
    summaryRow.pf_pdf = string(cfg.pfPDF);
    summaryRow.offer_pdf = string(cfg.offerPDF);
    summaryRow.global_load_scale = scenarioInfo.loadScale;

    summaryRow.total_Pd_MW = sum(Pd);
    summaryRow.total_Qd_MVAr = sum(Qd);
    summaryRow.total_added_Pd_MW = sum(addedP);
    summaryRow.total_added_Qd_MVAr = sum(addedQ);
    summaryRow.total_P_loss_MW = sum(P_loss);
    summaryRow.total_Q_loss_MVAr = sum(Q_loss);
    summaryRow.max_branch_loading_percent = max(loading, [], 'omitnan');
    summaryRow.mean_DLMP_LAM_P = mean(dlmpP, 'omitnan');
    summaryRow.DLMP_spread_LAM_P = max(dlmpP, [], 'omitnan') - min(dlmpP, [], 'omitnan');
    summaryRow.mean_DLMP_LAM_Q = mean(dlmpQ, 'omitnan');
    summaryRow.DLMP_spread_LAM_Q = max(dlmpQ, [], 'omitnan') - min(dlmpQ, [], 'omitnan');
    summaryRow.out_grid_Pg_MW = gridPg;
    summaryRow.out_grid_Qg_MVAr = gridQg;
    summaryRow.local_generation_MW = localGenMW;
    summaryRow.local_generation_share = localGenMW ./ max(eps, gridPg + localGenMW);
    summaryRow.cost_to_load_total = sum(costToLoad);
    summaryRow.number_of_DER_buses = sum(role == "DER");
    summaryRow.number_of_prosumer_buses = sum(role == "Prosumer");
    summaryRow.number_of_large_load_buses = sum(role == "Large Load");
end

function busLong = convertWideScenarioDatasetToBusLong(T)
%CONVERTWIDESCENARIODATASETTOBUSLONG Converts old wide bus output columns to long format when possible.

    if isempty(T) || ~ismember('scenario_id', T.Properties.VariableNames)
        busLong = table();
        return;
    end

    vars = string(T.Properties.VariableNames);
    pattern = "^out_bus(\d+)_Vm_pu$";
    busIds = [];

    for i = 1:numel(vars)
        tok = regexp(vars(i), pattern, 'tokens', 'once');
        if ~isempty(tok)
            busIds(end+1, 1) = str2double(tok{1}); %#ok<AGROW>
        end
    end

    busIds = unique(busIds);
    chunks = cell(numel(busIds), 1);

    for j = 1:numel(busIds)
        b = busIds(j);
        n = height(T);

        scenario_id = T.scenario_id;
        bus_id = repmat(b, n, 1);
        role = repmat("Unknown", n, 1);

        Pd_MW = readOptionalWide(T, sprintf('in_bus%d_Pd_MW', b), n);
        Qd_MVAr = readOptionalWide(T, sprintf('in_bus%d_Qd_MVAr', b), n);
        added_Pd_MW = NaN(n, 1);
        added_Qd_MVAr = NaN(n, 1);
        Pg_MW = NaN(n, 1);
        Qg_MVAr = NaN(n, 1);
        net_load_MW = NaN(n, 1);

        Vm_pu = readOptionalWide(T, sprintf('out_bus%d_Vm_pu', b), n);
        Va_deg = readOptionalWide(T, sprintf('out_bus%d_Va_deg', b), n);
        DLMP_LAM_P = readOptionalWide(T, sprintf('out_bus%d_DLMP_LAM_P', b), n);
        DLMP_LAM_Q = readOptionalWide(T, sprintf('out_bus%d_DLMP_LAM_Q', b), n);
        cost_to_load = NaN(n, 1);

        chunks{j} = table(scenario_id, bus_id, role, Pd_MW, Qd_MVAr, added_Pd_MW, added_Qd_MVAr, ...
            Pg_MW, Qg_MVAr, net_load_MW, Vm_pu, Va_deg, DLMP_LAM_P, DLMP_LAM_Q, cost_to_load, ...
            'VariableNames', {'scenario_id','bus_id','role','Pd_MW','Qd_MVAr','added_Pd_MW','added_Qd_MVAr', ...
            'Pg_MW','Qg_MVAr','net_load_MW','Vm_pu','Va_deg','DLMP_LAM_P','DLMP_LAM_Q','cost_to_load'});
    end

    if isempty(chunks)
        busLong = table();
    else
        busLong = vertcat(chunks{:});
    end
end

function branchLong = convertWideScenarioDatasetToBranchLong(T)
%CONVERTWIDESCENARIODATASETTOBRANCHLONG Converts old wide branch output columns to long format when possible.

    if isempty(T) || ~ismember('scenario_id', T.Properties.VariableNames)
        branchLong = table();
        return;
    end

    vars = string(T.Properties.VariableNames);
    pattern = "^out_branch(\d+)_Pf_MW$";
    branchIds = [];

    for i = 1:numel(vars)
        tok = regexp(vars(i), pattern, 'tokens', 'once');
        if ~isempty(tok)
            branchIds(end+1, 1) = str2double(tok{1}); %#ok<AGROW>
        end
    end

    branchIds = unique(branchIds);
    chunks = cell(numel(branchIds), 1);

    for j = 1:numel(branchIds)
        br = branchIds(j);
        n = height(T);

        scenario_id = T.scenario_id;
        branch_id = repmat(br, n, 1);
        from_bus = NaN(n, 1);
        to_bus = NaN(n, 1);

        Pf_MW = readOptionalWide(T, sprintf('out_branch%d_Pf_MW', br), n);
        Pt_MW = readOptionalWide(T, sprintf('out_branch%d_Pt_MW', br), n);
        Qf_MVAr = readOptionalWide(T, sprintf('out_branch%d_Qf_MVAr', br), n);
        Qt_MVAr = readOptionalWide(T, sprintf('out_branch%d_Qt_MVAr', br), n);
        P_loss_MW = readOptionalWide(T, sprintf('out_branch%d_P_loss_MW', br), n);
        Q_loss_MVAr = readOptionalWide(T, sprintf('out_branch%d_Q_loss_MVAr', br), n);
        rateA_MVA = NaN(n, 1);
        loading_percent = readOptionalWide(T, sprintf('out_branch%d_loading_percent', br), n);

        chunks{j} = table(scenario_id, branch_id, from_bus, to_bus, Pf_MW, Pt_MW, Qf_MVAr, Qt_MVAr, ...
            P_loss_MW, Q_loss_MVAr, rateA_MVA, loading_percent, ...
            'VariableNames', {'scenario_id','branch_id','from_bus','to_bus','Pf_MW','Pt_MW','Qf_MVAr','Qt_MVAr', ...
            'P_loss_MW','Q_loss_MVAr','rateA_MVA','loading_percent'});
    end

    if isempty(chunks)
        branchLong = table();
    else
        branchLong = vertcat(chunks{:});
    end
end

function x = readOptionalWide(T, varName, n)
%READOPTIONALWIDE Reads a variable if it exists, otherwise returns NaN vector.
    if ismember(varName, T.Properties.VariableNames)
        x = T.(varName);
    else
        x = NaN(n, 1);
    end
end


function T = addScenarioDerivedMetrics(T)
    if isempty(T)
        return;
    end

    needed = {'total_Pd_MW','total_Qd_MVAr','max_branch_loading_percent','total_P_loss_MW', ...
        'local_generation_share','out_grid_Pg_MW','local_generation_MW','cost_to_load_total'};
    for i = 1:numel(needed)
        if ~ismember(needed{i}, T.Properties.VariableNames)
            T.(needed{i}) = NaN(height(T), 1);
        end
    end
end

function derived = selectDerivedMetrics(T)
    cols = {'scenario_id','total_Pd_MW','total_Qd_MVAr','objective_cost', ...
            'total_added_Pd_MW','total_P_loss_MW','total_Q_loss_MVAr','max_branch_loading_percent', ...
            'mean_DLMP_LAM_P','DLMP_spread_LAM_P','mean_DLMP_LAM_Q','DLMP_spread_LAM_Q', ...
            'out_grid_Pg_MW','local_generation_MW','local_generation_share','cost_to_load_total', ...
            'number_of_DER_buses','number_of_prosumer_buses','number_of_large_load_buses'};
    cols = cols(ismember(cols, T.Properties.VariableNames));
    derived = T(:, cols);
end

%% ========================================================================
% Local computational functions - validation
%% ========================================================================
function tol = defaultValidationTolerances()
    tol = struct();
    tol.Vm = 1e-5;
    tol.Va = 1e-3;
    tol.P = 1e-4;
    tol.Q = 1e-4;
    tol.loading = 1e-3;
end

function [validationTable, summaryTable] = validateGeneratedScenarios(mpcList, resultsList, tol)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    N = numel(mpcList);
    validationRows = struct([]);
    nRunpfSuccess = 0;
    nRunpfFail = 0;
    nValidationPass = 0;
    nValidationMismatch = 0;

    mpopt = mpoption('verbose', 0, 'out.all', 0);

    for k = 1:N
        mpc = mpcList{k};
        opf = resultsList{k};

        row = struct();
        row.scenario_id = k;
        row.runpf_success = 0;
        row.validation_pass = 0;
        row.dominant_fail_reason = "not_run";
        row.diagnosis = "";
        row.error_message = "";

        row.max_abs_Vm_error = NaN;
        row.max_abs_Va_error = NaN;
        row.max_abs_Pg_error = NaN;
        row.max_abs_Qg_error = NaN;
        row.max_abs_Pf_error = NaN;
        row.max_abs_Qf_error = NaN;
        row.max_abs_Ploss_error = NaN;
        row.max_abs_Qloss_error = NaN;
        row.max_abs_loading_error = NaN;

        try
            mpc.bus(:, VM) = opf.bus(:, VM);
            mpc.bus(:, VA) = opf.bus(:, VA);
            mpc.gen(:, PG) = opf.gen(:, PG);
            mpc.gen(:, QG) = opf.gen(:, QG);
            mpc.gen(:, VG) = opf.gen(:, VG);

            pf = runpf(mpc, mpopt);
            row.runpf_success = pf.success;
        catch ME
            pf = [];
            row.runpf_success = 0;
            row.error_message = string(ME.message);
        end

        if row.runpf_success == 1
            nRunpfSuccess = nRunpfSuccess + 1;

            VmErr = abs(pf.bus(:, VM) - opf.bus(:, VM));
            VaErr = abs(pf.bus(:, VA) - opf.bus(:, VA));
            PgErr = abs(pf.gen(:, PG) - opf.gen(:, PG));
            QgErr = abs(pf.gen(:, QG) - opf.gen(:, QG));

            row.max_abs_Vm_error = max(VmErr, [], 'omitnan');
            row.max_abs_Va_error = max(VaErr, [], 'omitnan');
            row.max_abs_Pg_error = max(PgErr, [], 'omitnan');
            row.max_abs_Qg_error = max(QgErr, [], 'omitnan');

            PfErr = abs(pf.branch(:, PF) - opf.branch(:, PF));
            QfErr = abs(pf.branch(:, QF) - opf.branch(:, QF));
            PlossErr = abs((pf.branch(:, PF) + pf.branch(:, PT)) - (opf.branch(:, PF) + opf.branch(:, PT)));
            QlossErr = abs((pf.branch(:, QF) + pf.branch(:, QT)) - (opf.branch(:, QF) + opf.branch(:, QT)));
            loadingErr = abs(calculateBranchLoadingPercent(pf.branch) - calculateBranchLoadingPercent(opf.branch));

            row.max_abs_Pf_error = max(PfErr, [], 'omitnan');
            row.max_abs_Qf_error = max(QfErr, [], 'omitnan');
            row.max_abs_Ploss_error = max(PlossErr, [], 'omitnan');
            row.max_abs_Qloss_error = max(QlossErr, [], 'omitnan');

            % In many distribution test cases, including case33bw, RATE_A can be
            % zero/undefined for all branches. In that case branch loading percent
            % is not applicable and calculateBranchLoadingPercent returns NaN.
            % NaN loading must not make an otherwise valid PF/OPF comparison fail.
            finiteLoadingErr = loadingErr(isfinite(loadingErr));
            if isempty(finiteLoadingErr)
                row.max_abs_loading_error = NaN;
                loadingOK = true;
            else
                row.max_abs_loading_error = max(finiteLoadingErr);
                loadingOK = row.max_abs_loading_error <= tol.loading;
            end

            row.validation_pass = double( ...
                row.max_abs_Vm_error <= tol.Vm && ...
                row.max_abs_Va_error <= tol.Va && ...
                row.max_abs_Pf_error <= tol.P && ...
                row.max_abs_Qf_error <= tol.Q && ...
                row.max_abs_Ploss_error <= tol.P && ...
                row.max_abs_Qloss_error <= tol.Q && ...
                loadingOK);

            [row.dominant_fail_reason, row.diagnosis] = diagnoseValidationRow(row, tol);

            if row.validation_pass == 1
                nValidationPass = nValidationPass + 1;
            else
                nValidationMismatch = nValidationMismatch + 1;
            end
        else
            nRunpfFail = nRunpfFail + 1;
            row.dominant_fail_reason = "runpf_fail";
            row.diagnosis = "RUNPF failed to converge or threw an error.";
        end

        if k == 1
            validationRows = row;
        else
            validationRows(k) = row;
        end
    end

    validationTable = struct2table(validationRows);
    summaryTable = table( ...
        N, nRunpfSuccess, nRunpfFail, nValidationPass, nValidationMismatch, ...
        max(validationTable.max_abs_Vm_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Va_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Pf_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Qf_error, [], 'omitnan'), ...
        max(validationTable.max_abs_loading_error, [], 'omitnan'), ...
        'VariableNames', {'number_of_rows','number_of_runpf_success','number_of_runpf_fail', ...
        'number_of_validation_pass','number_of_validation_mismatch','max_abs_Vm_error', ...
        'max_abs_Va_error','max_abs_Pf_error','max_abs_Qf_error','max_abs_loading_error'});
end

function [reason, diagnosis] = diagnoseValidationRow(row, tol)
    if row.validation_pass == 1
        reason = "pass";
        if isfield(row, 'max_abs_loading_error') && ~isfinite(row.max_abs_loading_error)
            diagnosis = "RUNPF solution matches OPF outputs within strict voltage and branch-flow tolerances. Branch loading check is N/A because branch RATE_A values are zero/undefined.";
        else
            diagnosis = "RUNPF solution matches OPF outputs within strict voltage and branch-flow tolerances.";
        end
        return;
    end

    names = ["Vm mismatch", "Va mismatch", "Branch Pf mismatch", "Branch Qf mismatch", ...
             "Branch P-loss mismatch", "Branch Q-loss mismatch", "Branch loading mismatch"];
    values = [row.max_abs_Vm_error / tol.Vm, row.max_abs_Va_error / tol.Va, ...
              row.max_abs_Pf_error / tol.P, row.max_abs_Qf_error / tol.Q, ...
              row.max_abs_Ploss_error / tol.P, row.max_abs_Qloss_error / tol.Q, ...
              row.max_abs_loading_error / tol.loading];
    values(~isfinite(values)) = -Inf;
    [~, idx] = max(values);
    reason = names(idx);
    diagnosis = "RUNPF converged, but reconstructed PF point is not numerically identical to the OPF point. Dominant mismatch: " + reason + ".";
end

%% ========================================================================
% Local computational functions - plotting and topology
%% ========================================================================
function clickData = drawCaseTopology(ax, mpc, roleCfg, selectedBuses, inspectedBusId)
    if nargin < 4
        selectedBuses = [];
    end
    if nargin < 5
        inspectedBusId = [];
    end

    clickData = struct('busIds', [], 'x', [], 'y', []);

    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;
    cla(ax);

    allBusNames = string(mpc.bus(:, BUS_I));
    activeBranchMask = (mpc.branch(:, BR_STATUS) ~= 0);
    fromBus = string(mpc.branch(activeBranchMask, F_BUS));
    toBus = string(mpc.branch(activeBranchMask, T_BUS));
    G = graph(fromBus, toBus, [], allBusNames);

    nodeLabels = makeTopologyNodeLabels(G.Nodes.Name, roleCfg, selectedBuses);
    emptyLabels = repmat({''}, numnodes(G), 1);

    try
        p = plot(ax, G, 'Layout', 'layered', 'NodeLabel', emptyLabels, 'LineWidth', 1.0);
    catch
        p = plot(ax, G, 'NodeLabel', emptyLabels, 'LineWidth', 1.0);
    end

    title(ax, 'case33bw Radial Network Topology with User-Defined Bus Roles');
    axis(ax, 'off');

    % Default PQ load style.
    try
        p.MarkerSize = 7;
        p.NodeColor = [0.55 0.55 0.55];
        p.EdgeColor = [0.70 0.70 0.70];

        highlightRole("Slack/Grid", [0.00 0.25 0.90], 10);
        highlightRole("DER",        [0.00 0.55 0.20], 9);
        highlightRole("Prosumer",   [0.95 0.45 0.05], 9);
        highlightRole("Large Load", [0.85 0.10 0.10], 9);

        drawTopologyLabels(ax, p, G, nodeLabels, selectedBuses, inspectedBusId);

        % Save node coordinates for robust figure-level click selection.
        clickData.busIds = str2double(string(G.Nodes.Name));
        clickData.x = p.XData(:);
        clickData.y = p.YData(:);
    catch
        % Some older MATLAB versions have limited graphplot styling support.
    end

    function highlightRole(roleName, color, markerSize)
        nodes = string(roleCfg.bus_id(roleCfg.role == roleName));
        nodes = nodes(ismember(nodes, G.Nodes.Name));
        if ~isempty(nodes)
            highlight(p, nodes, 'NodeColor', color, 'MarkerSize', markerSize);
        end
    end
end

function nodeLabels = makeTopologyNodeLabels(nodeNames, roleCfg, selectedBuses)
%MAKETOPOLOGYNODELABELS Creates readable bus labels for topology graph.
%
% Selected plot buses keep their real role marker/color. Only the text label
% gets A/B/C suffix and will be drawn as purple + bold by drawTopologyLabels.

    if nargin < 3
        selectedBuses = [];
    end

    nodeNames = string(nodeNames);
    nodeLabels = strings(numel(nodeNames), 1);

    for i = 1:numel(nodeNames)
        busId = str2double(nodeNames(i));
        idx = find(roleCfg.bus_id == busId, 1);

        if isempty(idx)
            roleAbbrev = "UNK";
        else
            roleAbbrev = roleToAbbrev(string(roleCfg.role(idx)));
        end

        suffix = selectedBusSuffix(busId, selectedBuses);

        if strlength(suffix) > 0
            nodeLabels(i) = sprintf('%d | %s | %s', busId, roleAbbrev, suffix);
        else
            nodeLabels(i) = sprintf('%d | %s', busId, roleAbbrev);
        end
    end

    nodeLabels = cellstr(nodeLabels);
end

function suffix = selectedBusSuffix(busId, selectedBuses)
%SELECTEDBUSSUFFIX Returns A/B/C if the bus is selected for plot panels.

    suffix = "";
    if isempty(selectedBuses)
        return;
    end

    labels = ["A", "B", "C"];
    for k = 1:min(numel(selectedBuses), numel(labels))
        if busId == selectedBuses(k)
            suffix = labels(k);
            return;
        end
    end
end

function drawTopologyLabels(ax, p, G, nodeLabels, selectedBuses, inspectedBusId)
%DRAWTOPOLOGYLABELS Draws topology labels manually.
%
% MATLAB graphplot labels cannot be styled individually in a reliable way.
% Therefore, graph built-in labels are disabled and labels are drawn using
% text().
%
% - Selected plot bus labels are purple and bold.
% - Inspected bus label has a light background and bold font.

    if nargin < 5
        selectedBuses = [];
    end
    if nargin < 6
        inspectedBusId = [];
    end

    holdState = ishold(ax);
    hold(ax, 'on');

    selectedNames = string(selectedBuses);
    inspectedName = string(inspectedBusId);

    for i = 1:numnodes(G)
        busName = string(G.Nodes.Name(i));
        isPlotSelected = any(selectedNames == busName);
        isInspected = (~isempty(inspectedBusId) && inspectedName == busName);

        if isPlotSelected
            labelColor = [0.60 0.00 0.80];
            fontWeight = 'bold';
        else
            labelColor = [0.15 0.15 0.15];
            fontWeight = 'normal';
        end

        if isInspected
            bg = [1.00 0.95 0.65];
            edge = [0.20 0.20 0.20];
            fontWeight = 'bold';
        else
            bg = 'none';
            edge = 'none';
        end

        text(ax, p.XData(i), p.YData(i), ['  ' nodeLabels{i}], ...
            'Color', labelColor, ...
            'FontWeight', fontWeight, ...
            'FontSize', 10, ...
            'Interpreter', 'none', ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'middle', ...
            'BackgroundColor', bg, ...
            'EdgeColor', edge, ...
            'Margin', 1, ...
            'HitTest', 'off');
    end

    if ~holdState
        hold(ax, 'off');
    end
end


function abbr = roleToAbbrev(roleName)
%ROLETOABBREV Short role labels for topology visualization.

    switch string(roleName)
        case "Slack/Grid"
            abbr = "SLK";
        case "PQ Load"
            abbr = "PQ";
        case "DER"
            abbr = "DER";
        case "Prosumer"
            abbr = "PRO";
        case "Large Load"
            abbr = "LL";
        otherwise
            abbr = "UNK";
    end
end

function handleTopologyNodeClick(ax, p, G, nodeClickFcn)
%HANDLETPOLOGYNODECLICK Finds the nearest plotted node and sends its bus id
% to the UI callback.

    if isempty(nodeClickFcn)
        return;
    end

    try
        cp = ax.CurrentPoint;
        xClick = cp(1, 1);
        yClick = cp(1, 2);

        xData = p.XData(:);
        yData = p.YData(:);

        dist2 = (xData - xClick).^2 + (yData - yClick).^2;
        [~, idx] = min(dist2);

        if isempty(idx) || idx < 1 || idx > numnodes(G)
            return;
        end

        busId = str2double(string(G.Nodes.Name(idx)));
        if isfinite(busId)
            nodeClickFcn(busId);
        end
    catch
    end
end

function txt = selectedBusInfoText(busId, mpc, roleCfg, busResults)
%SELECTEDBUSINFOTEXT Builds readable selected-bus information for UI panel.

    C = mpConst();
    BUS_I = C.BUS_I; PD = C.PD; QD = C.QD;

    row = find(mpc.bus(:, BUS_I) == busId, 1);
    if isempty(row)
        txt = {sprintf('Bus %d not found.', busId)};
        return;
    end

    roleRow = roleCfg(roleCfg.bus_id == busId, :);
    if isempty(roleRow)
        roleName = "Unknown";
        addPd = [NaN NaN];
        pfRange = [NaN NaN];
        pRange = [NaN NaN];
        qRange = [NaN NaN];
        vg = NaN;
        c2 = [NaN NaN];
        c1 = [NaN NaN];
        c0 = NaN;
    else
        roleName = string(roleRow.role);
        addPd = [roleRow.add_Pd_min_MW, roleRow.add_Pd_max_MW];
        pfRange = [roleRow.pf_min, roleRow.pf_max];
        pRange = [roleRow.Pmin_MW, roleRow.Pmax_MW];
        qRange = [roleRow.Qmin_MVAr, roleRow.Qmax_MVAr];
        vg = roleRow.Vg_pu;
        c2 = [roleRow.c2_min, roleRow.c2_max];
        c1 = [roleRow.c1_min, roleRow.c1_max];
        c0 = roleRow.c0;
    end

    roleType = roleToMatpowerBusType(roleName);
    roleTypeText = matpowerTypeText(roleType);

    txt = { ...
        sprintf('BUS %d SUMMARY', busId)
        ' '
        'GENERAL'
        sprintf('• Role                 : %s', roleName)
        sprintf('• MATPOWER BUS_TYPE    : %d (%s)', roleType, roleTypeText)
        ' '
        'BASE DEMAND / CONFIGURATION'
        sprintf('• case33bw base Pd/Qd  : %.4f MW / %.4f MVAr', mpc.bus(row, PD), mpc.bus(row, QD))
        sprintf('• Added Pd range       : %.4f – %.4f MW', addPd(1), addPd(2))
        sprintf('• Added PF range       : %.3f – %.3f', pfRange(1), pfRange(2))
        sprintf('• Pmin / Pmax          : %.4f – %.4f MW', pRange(1), pRange(2))
        sprintf('• Qmin / Qmax          : %.4f – %.4f MVAr', qRange(1), qRange(2))
        sprintf('• Vg                   : %.3f p.u.', vg)
        ' '
        'COST MODEL'
        sprintf('• C(P) = %.4f P^2 + %.4f P + %.4f', c2(1), c1(1), c0)
        ' '
        'INTERPRETATION'
        sprintf('• %s', roleInterpretation(roleName))
        };

    if ~isempty(busResults) && istable(busResults) && ismember('bus_id', busResults.Properties.VariableNames)
        latestScenario = max(busResults.scenario_id);
        br = busResults(busResults.scenario_id == latestScenario & busResults.bus_id == busId, :);

        if height(br) == 1
            txt = [txt; { ...
                ' '
                sprintf('LATEST OPF RESULT (SCENARIO %d)', latestScenario)
                sprintf('• Final Pd / Qd        : %.4f MW / %.4f MVAr', br.Pd_MW, br.Qd_MVAr)
                sprintf('• Pg / Qg at bus       : %.4f MW / %.4f MVAr', br.Pg_MW, br.Qg_MVAr)
                sprintf('• Vm / Va              : %.4f p.u. / %.4f deg', br.Vm_pu, br.Va_deg)
                sprintf('• DLMP LAM_P / LAM_Q   : %.4f / %.4f', br.DLMP_LAM_P, br.DLMP_LAM_Q)
                sprintf('• Cost-to-load         : %.4f', br.cost_to_load)
                }];
        end
    end
end

function txt = matpowerTypeText(busType)
%MATPOWERTYPETEXT Human-readable MATPOWER bus type label.
    switch busType
        case 3
            txt = 'Slack / Reference';
        case 2
            txt = 'PV / Generator Bus';
        case 1
            txt = 'PQ / Load Bus';
        otherwise
            txt = 'Unknown';
    end
end


function busType = roleToMatpowerBusType(roleName)
%ROLETOMATPOWERBUSTYPE Returns the bus type used during scenario construction.
    switch string(roleName)
        case "Slack/Grid"
            busType = 3;
        case {"DER", "Prosumer"}
            busType = 2;
        otherwise
            busType = 1;
    end
end

function txt = roleInterpretation(roleName)
%ROLEINTERPRETATION Short explanation for the selected role.
    switch string(roleName)
        case "Slack/Grid"
            txt = 'Reference/grid source. OPF uses it to supply remaining demand and losses.';
        case "PQ Load"
            txt = 'Load-only bus. Uses case33bw base demand scaled by global_load_scale.';
        case "DER"
            txt = 'Generator-only PV bus. Adds local generation, no extra load.';
        case "Prosumer"
            txt = 'PV bus with both local demand and local generation.';
        case "Large Load"
            txt = 'PQ bus with additional demand. Not used in the approved default base model.';
        otherwise
            txt = 'Unknown role.';
    end
end


function plotInputOutputScatter(ax, x, y, xlab, ylab, ttl)
    cla(ax);
    yyaxis(ax, 'left');
    scatter(ax, x, y, 24, 'filled');
    xlabel(ax, xlab);
    ylabel(ax, ylab);
    title(ax, ttl);
    grid(ax, 'off');
end

function plotDLMPScatterWithDemandDistribution(ax, x, y, xlab, ylab, ttl)
    cla(ax);
    ok = isfinite(x) & isfinite(y);

    yyaxis(ax, 'left');
    scatter(ax, x(ok), y(ok), 24, 'filled');
    xlabel(ax, xlab);
    ylabel(ax, ylab);
    title(ax, ttl);
    grid(ax, 'off');

    yyaxis(ax, 'right');
    xOk = x(isfinite(x));
    if numel(xOk) >= 2
        nBins = max(10, round(sqrt(numel(xOk))));
        [counts, edges] = histcounts(xOk, nBins);
        centers = edges(1:end-1) + diff(edges) / 2;
        plot(ax, centers, counts, 'r-', 'LineWidth', 1.5);
    end
    ylabel(ax, 'Total Pd distribution [count]');

    yyaxis(ax, 'left');
end

%% ========================================================================
% Local computational functions - econometrics
%% ========================================================================
function econTable = runEconometricModels(T)
    if isempty(T) || height(T) < 4
        econTable = table();
        return;
    end

    modelRows = {};

    [coef, r2, rmse] = olsSummary(T.objective_cost, [T.total_Pd_MW, T.total_Qd_MVAr, T.max_branch_loading_percent], ...
        {'total_Pd_MW','total_Qd_MVAr','max_branch_loading_percent'});
    modelRows(end+1, :) = {'M1', 'objective_cost', 'objective_cost ~ total_Pd + total_Qd + max_loading', coef, r2, rmse, height(T)};

    [coef, r2, rmse] = olsSummary(T.DLMP_spread_LAM_P, [T.total_Pd_MW, T.total_P_loss_MW, T.max_branch_loading_percent], ...
        {'total_Pd_MW','total_P_loss_MW','max_branch_loading_percent'});
    modelRows(end+1, :) = {'M2', 'DLMP_spread_LAM_P', 'DLMP_spread ~ total_Pd + losses + max_loading', coef, r2, rmse, height(T)};

    [coef, r2, rmse] = olsSummary(T.total_P_loss_MW, [T.total_Pd_MW, T.total_Qd_MVAr, T.local_generation_share], ...
        {'total_Pd_MW','total_Qd_MVAr','local_generation_share'});
    modelRows(end+1, :) = {'M3', 'total_P_loss_MW', 'losses ~ total_Pd + total_Qd + local_generation_share', coef, r2, rmse, height(T)};

    [coef, r2, rmse] = olsSummary(T.out_grid_Pg_MW, [T.total_Pd_MW, T.local_generation_MW, T.cost_to_load_total], ...
        {'total_Pd_MW','local_generation_MW','cost_to_load_total'});
    modelRows(end+1, :) = {'M4', 'out_grid_Pg_MW', 'grid_dispatch ~ total_Pd + local_generation + C2L', coef, r2, rmse, height(T)};

    econTable = cell2table(modelRows, 'VariableNames', {'model_id','dependent_variable','formula','coefficients','R_squared','RMSE','N'});
end

function [coefString, r2, rmse] = olsSummary(y, Xraw, names)
    X = [ones(size(Xraw,1),1), Xraw];
    [yhat, residuals, beta] = simpleOLS(y, X);
    sst = sum((y - mean(y, 'omitnan')).^2, 'omitnan');
    sse = sum(residuals.^2, 'omitnan');

    if sst > 0
        r2 = 1 - sse / sst;
    else
        r2 = NaN;
    end
    rmse = sqrt(mean(residuals.^2, 'omitnan'));

    parts = strings(numel(beta),1);
    parts(1) = sprintf('Intercept=%.6g', beta(1));
    for i = 2:numel(beta)
        parts(i) = sprintf('%s=%.6g', names{i-1}, beta(i));
    end
    coefString = strjoin(parts, '; ');
end

function [yhat, residuals, beta] = simpleOLS(y, X)
    ok = all(isfinite(X), 2) & isfinite(y);
    beta = NaN(size(X, 2), 1);
    yhat = NaN(size(y));
    residuals = NaN(size(y));
    if sum(ok) >= size(X, 2)
        beta = X(ok, :) \ y(ok);
        yhat(ok) = X(ok, :) * beta;
        residuals(ok) = y(ok) - yhat(ok);
    end
end

%% ========================================================================
% Local computational functions - static/export tables
%% ========================================================================
function busTable = createBusStaticTable(mpc, roleCfg)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    bus_id = mpc.bus(:, BUS_I);
    bus_type = mpc.bus(:, BUS_TYPE);
    base_kV = mpc.bus(:, BASE_KV);
    base_Pd_MW = mpc.bus(:, PD);
    base_Qd_MVAr = mpc.bus(:, QD);
    Vmax = mpc.bus(:, VMAX);
    Vmin = mpc.bus(:, VMIN);

    bus_role = strings(numel(bus_id), 1);
    for i = 1:numel(bus_id)
        idx = find(roleCfg.bus_id == bus_id(i), 1);
        if isempty(idx)
            bus_role(i) = "Unknown";
        else
            bus_role(i) = string(roleCfg.role(idx));
        end
    end

    is_slack = double(bus_type == 3);
    is_PQ = double(bus_type == 1);
    is_PV = double(bus_type == 2);

    busTable = table(bus_id, bus_role, bus_type, is_slack, is_PQ, is_PV, ...
        base_Pd_MW, base_Qd_MVAr, base_kV, Vmin, Vmax, ...
        'VariableNames', {'bus_id','bus_role','matpower_bus_type','is_slack','is_PQ','is_PV', ...
        'base_Pd_MW','base_Qd_MVAr','base_kV','Vmin_pu','Vmax_pu'});
end

function branchTable = createBranchStaticTable(mpc)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    branch_id = (1:size(mpc.branch, 1))';
    from_bus = mpc.branch(:, F_BUS);
    to_bus = mpc.branch(:, T_BUS);
    r_pu = mpc.branch(:, BR_R);
    x_pu = mpc.branch(:, BR_X);
    b_pu = mpc.branch(:, BR_B);
    rateA_MVA = mpc.branch(:, RATE_A);
    status = mpc.branch(:, BR_STATUS);

    branchTable = table(branch_id, from_bus, to_bus, r_pu, x_pu, b_pu, rateA_MVA, status, ...
        'VariableNames', {'branch_id','from_bus','to_bus','r_pu','x_pu','b_pu','rateA_MVA','status'});
end

%% ========================================================================
% Local computational functions - general utilities
%% ========================================================================
function items = busIdItems(mpc)
    ids = mpc.bus(:, 1);
    items = cellstr(string(ids));
end

function slackBus = getSlackBusId(mpc)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;
    idx = find(mpc.bus(:, BUS_TYPE) == 3, 1);
    if isempty(idx)
        slackBus = mpc.bus(1, BUS_I);
    else
        slackBus = mpc.bus(idx, BUS_I);
    end
end

function rangePair = parseRange(txt, label)
    if isnumeric(txt)
        vals = txt;
    else
        vals = sscanf(char(txt), '%f%*[,; ]%f');
    end

    if numel(vals) ~= 2
        error('%s must be entered as two numbers, for example: 0.85, 1.15', label);
    end

    rangePair = vals(:)';
    if rangePair(1) > rangePair(2)
        error('%s has min greater than max.', label);
    end
end

function txt = formatRangeText(minVal, maxVal)
    txt = sprintf('%.6g, %.6g', minVal, maxVal);
end

function value = sampleByPDF(rangePair, pdfName)
    minVal = rangePair(1);
    maxVal = rangePair(2);

    if minVal == maxVal
        value = minVal;
        return;
    end

    width = maxVal - minVal;
    u = rand();

    switch char(pdfName)
        case 'Uniform'
            x = u;

        case 'Normal-Truncated'
            x = truncatedNormal01(0.5, 1/6);

        case 'Triangular'
            if u < 0.5
                x = sqrt(0.5 * u);
            else
                x = 1 - sqrt(0.5 * (1 - u));
            end

        case 'Beta(2,2)-Bounded'
            g1 = -log(max(realmin, rand() * rand()));
            g2 = -log(max(realmin, rand() * rand()));
            x = g1 / (g1 + g2);

        case 'Lognormal-Truncated'
            sigma = 0.35;
            mu = log(0.45);
            x = NaN;
            for i = 1:200
                cand = exp(mu + sigma * randn());
                if cand >= 0 && cand <= 1
                    x = cand;
                    break;
                end
            end
            if isnan(x)
                x = min(1, max(0, exp(mu + sigma * randn())));
            end

        case 'Two-Peak Mixture'
            if rand() < 0.5
                x = truncatedNormal01(0.28, 0.10);
            else
                x = truncatedNormal01(0.72, 0.10);
            end

        otherwise
            error('Unknown PDF option: %s', pdfName);
    end

    value = minVal + width * min(1, max(0, x));
end

function x = truncatedNormal01(mu, sigma)
    x = NaN;
    for i = 1:200
        cand = mu + sigma * randn();
        if cand >= 0 && cand <= 1
            x = cand;
            return;
        end
    end
    x = min(1, max(0, mu + sigma * randn()));
end

function Q = calcQfromPandPF(P, pf)
    if pf <= 0 || pf > 1
        error('Power factor must be in the interval (0, 1].');
    end
    Q = P * tan(acos(pf));
end

function loading = calculateBranchLoadingPercent(branch)
    C = mpConst();
    PQ = C.PQ; PV = C.PV; REF = C.REF; NONE = C.NONE;
    BUS_I = C.BUS_I; BUS_TYPE = C.BUS_TYPE; PD = C.PD; QD = C.QD; GS = C.GS; BS = C.BS; BUS_AREA = C.BUS_AREA; VM = C.VM; VA = C.VA; BASE_KV = C.BASE_KV; ZONE = C.ZONE; VMAX = C.VMAX; VMIN = C.VMIN; LAM_P = C.LAM_P; LAM_Q = C.LAM_Q;
    GEN_BUS = C.GEN_BUS; PG = C.PG; QG = C.QG; QMAX = C.QMAX; QMIN = C.QMIN; VG = C.VG; MBASE = C.MBASE; GEN_STATUS = C.GEN_STATUS; PMAX = C.PMAX; PMIN = C.PMIN;
    F_BUS = C.F_BUS; T_BUS = C.T_BUS; BR_R = C.BR_R; BR_X = C.BR_X; BR_B = C.BR_B; RATE_A = C.RATE_A; RATE_B = C.RATE_B; RATE_C = C.RATE_C; TAP = C.TAP; SHIFT = C.SHIFT; BR_STATUS = C.BR_STATUS; ANGMIN = C.ANGMIN; ANGMAX = C.ANGMAX; PF = C.PF; QF = C.QF; PT = C.PT; QT = C.QT;

    Pf = branch(:, PF);
    Pt = branch(:, PT);
    Qf = branch(:, QF);
    Qt = branch(:, QT);
    rateA = branch(:, RATE_A);

    Sf = sqrt(Pf.^2 + Qf.^2);
    St = sqrt(Pt.^2 + Qt.^2);

    loading = NaN(size(rateA));
    valid = rateA > 0;
    loading(valid) = 100 * max(Sf(valid), St(valid)) ./ rateA(valid);

    % If case has zero ratings, leave loading as NaN instead of dividing by zero.
end

function out = firstNRows(T, N)
    if isempty(T)
        out = table();
    else
        out = T(1:min(N, height(T)), :);
    end
end


function C = mpConst()
%MPCONST Local MATPOWER column indices.
% Avoids calling define_constants inside nested/static workspaces.

    C.PQ = 1;
    C.PV = 2;
    C.REF = 3;
    C.NONE = 4;

    % bus matrix columns
    C.BUS_I = 1;
    C.BUS_TYPE = 2;
    C.PD = 3;
    C.QD = 4;
    C.GS = 5;
    C.BS = 6;
    C.BUS_AREA = 7;
    C.VM = 8;
    C.VA = 9;
    C.BASE_KV = 10;
    C.ZONE = 11;
    C.VMAX = 12;
    C.VMIN = 13;
    C.LAM_P = 14;
    C.LAM_Q = 15;

    % generator matrix columns
    C.GEN_BUS = 1;
    C.PG = 2;
    C.QG = 3;
    C.QMAX = 4;
    C.QMIN = 5;
    C.VG = 6;
    C.MBASE = 7;
    C.GEN_STATUS = 8;
    C.PMAX = 9;
    C.PMIN = 10;

    % branch matrix columns
    C.F_BUS = 1;
    C.T_BUS = 2;
    C.BR_R = 3;
    C.BR_X = 4;
    C.BR_B = 5;
    C.RATE_A = 6;
    C.RATE_B = 7;
    C.RATE_C = 8;
    C.TAP = 9;
    C.SHIFT = 10;
    C.BR_STATUS = 11;
    C.ANGMIN = 12;
    C.ANGMAX = 13;
    C.PF = 14;
    C.QF = 15;
    C.PT = 16;
    C.QT = 17;
end
