function dashboard_case33bw_single_bus_sweep_lab_v2_plotbus_totaldemand()
%DASHBOARD_CASE33BW_SINGLE_BUS_SWEEP_LAB_V2_PLOTBUS_TOTALDEMAND
% Deterministic single-bus Pd sweep dashboard for MATPOWER case33bw.
%
% Purpose:
%   Configured-base + selected PQ load sweep.
%   The user first defines the fixed network configuration with bus roles
%   (Slack/Grid, PQ Load, DER, Prosumer, Large Load). Then only one selected
%   PQ bus Pd is swept linearly between Pd_min and Pd_max. At each step, AC OPF
%   is solved and DLMP, C2L, voltage, loss, loading, and dispatch results are
%   exported.
%
% Requirements:
%   1) MATLAB with App UI components
%   2) MATPOWER on the MATLAB path
%   3) case33bw available on the MATLAB path
%
% Run:
%   dashboard_case33bw_single_bus_sweep_lab_v2_plotbus_totaldemand

    %% ============================================================
    % App state
    %% ============================================================
    app = struct();

    app.base_mpc      = loadCase33bwForSweepLab();
    app.nBus          = size(app.base_mpc.bus, 1);
    app.nBranch       = size(app.base_mpc.branch, 1);
    app.busRoleConfig = createDefaultBusRoleConfig(app.base_mpc);

    app.T             = table();  % step/scenario-level summary
    app.busResults    = table();  % long bus-level results
    app.branchResults = table();  % long branch-level results
    app.genResults    = table();  % long generator-level results

    app.selectedInspectBus = 1;
    app.topologyClickData = struct('busIds', [], 'x', [], 'y', []);

    %% ============================================================
    % UI construction - intentionally simpler than the original dashboard
    %% ============================================================
    app.fig = uifigure( ...
        'Name', 'case33bw DLMP Single-Bus Sweep Lab | v3 DLMP-based C2L', ...
        'Position', [50 45 1600 880]);
    app.fig.WindowButtonDownFcn = @(~, ~) handleFigureMouseDown();

    root = uigridlayout(app.fig, [2 1]);
    root.RowHeight = {48, '1x'};
    root.ColumnWidth = {'1x'};
    root.Padding = [10 10 10 10];
    root.RowSpacing = 8;

    %% ---------------- Top bar ----------------
    top = uigridlayout(root, [1 5]);
    top.Layout.Row = 1;
    top.ColumnWidth = {230, 180, 180, 180, '1x'};
    top.RowHeight = {'1x'};
    top.Padding = [0 0 0 0];
    top.ColumnSpacing = 10;

    app.runButton = uibutton(top, 'push', ...
        'Text', 'Run Single-Bus Sweep', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) runSweep());
    app.saveButton = uibutton(top, 'push', ...
        'Text', 'Save Results Excel', ...
        'ButtonPushedFcn', @(~, ~) saveCurrentResults());
    app.saveConfigButton = uibutton(top, 'push', ...
        'Text', 'Save Config', ...
        'ButtonPushedFcn', @(~, ~) saveCustomConfig());
    app.loadConfigButton = uibutton(top, 'push', ...
        'Text', 'Load Config', ...
        'ButtonPushedFcn', @(~, ~) loadCustomConfig());
    app.status = uilabel(top, ...
        'Text', 'v3 loaded. C2L = sum(max(Pd-Pg_by_bus,0).*DLMP). x-axis = Total Demand. Choose PQ sweep bus, then run.', ...
        'FontWeight', 'bold');

    %% ---------------- Main grid ----------------
    main = uigridlayout(root, [1 2]);
    main.Layout.Row = 2;
    main.ColumnWidth = {380, '1x'};
    main.RowHeight = {'1x'};
    main.Padding = [0 0 0 0];
    main.ColumnSpacing = 12;

    %% ============================================================
    % Left control panel
    %% ============================================================
    panel = uipanel(main, 'Title', 'Sweep Controls + Quick Role Editor');
    panel.Layout.Column = 1;
    try
        panel.Scrollable = 'on';
    catch
    end

    cg = uigridlayout(panel, [50 2]);
    cg.RowHeight = repmat({24}, 1, 50);
    cg.ColumnWidth = {150, '1x'};
    cg.Padding = [10 10 10 10];
    cg.RowSpacing = 6;

    addSection(cg, '1) Sweep settings');
    app.lblSweepBus = addLabel(cg, 'Selected Sweep Bus');
    app.sweepBusDrop = uidropdown(cg, ...
        'Items', busIdItems(app.base_mpc), ...
        'Value', '3', ...
        'ValueChangedFcn', @(~, ~) sweepBusChanged());

    % Plot Bus 1 / 2 define the buses whose DLMP traces are shown
    % in the Sweep Plots tab. They are separate from the Sweep Bus, which
    % defines the load-increase experiment on the x-axis.
    app.lblPlotBus1 = addLabel(cg, 'Plot Bus 1');
    app.plotBus1Drop = uidropdown(cg, ...
        'Items', busIdItems(app.base_mpc), ...
        'Value', '3', ...
        'ValueChangedFcn', @(~, ~) updateAllPlots());

    app.lblPlotBus2 = addLabel(cg, 'Plot Bus 2');
    app.plotBus2Drop = uidropdown(cg, ...
        'Items', busIdItems(app.base_mpc), ...
        'Value', '12', ...
        'ValueChangedFcn', @(~, ~) updateAllPlots());

    app.syncPlotBusButton = uibutton(cg, 'push', ...
        'Text', 'Use Sweep Bus for Plot Bus 1', ...
        'ButtonPushedFcn', @(~, ~) useSweepBusForPlots());
    app.syncPlotBusButton.Layout.Column = [1 2];

    app.lblPdMin = addLabel(cg, 'Pd min [MW]');
    app.pdMinField = uieditfield(cg, 'numeric', 'Value', defaultBusPd(app.base_mpc, 3));

    app.lblPdMax = addLabel(cg, 'Pd max [MW]');
    app.pdMaxField = uieditfield(cg, 'numeric', 'Value', max(defaultBusPd(app.base_mpc, 3) + 1.0, 1.0));

    app.lblSteps = addLabel(cg, 'Number of steps');
    app.stepsField = uispinner(cg, 'Value', 100, 'Limits', [2 10000], 'RoundFractionalValues', 'on');

    app.lblQMode = addLabel(cg, 'Q mode');
    app.qModeDrop = uidropdown(cg, ...
        'Items', {'Keep PF constant', 'Keep Qd constant'}, ...
        'Value', 'Keep PF constant');

    app.lblSweepPF = addLabel(cg, 'Sweep PF');
    app.sweepPfField = uieditfield(cg, 'numeric', 'Value', defaultBusPF(app.base_mpc, 3), 'Limits', [0.01 1.00]);

    app.lblOutput = addLabel(cg, 'Output Excel');
    app.outputField = uieditfield(cg, 'text', 'Value', 'case33bw_single_bus_sweep_results.xlsx');

    addSection(cg, '2) Quick bus role editor');
    app.lblBus = addLabel(cg, 'Bus');
    app.busSelectDrop = uidropdown(cg, ...
        'Items', busIdItems(app.base_mpc), ...
        'Value', '3', ...
        'ValueChangedFcn', @(~, ~) updateSelectedBusInfo(str2double(app.busSelectDrop.Value)));

    app.lblRole = addLabel(cg, 'Role');
    app.roleDrop = uidropdown(cg, 'Items', roleItems(), 'Value', 'PQ Load');

    app.lblAddedPd = addLabel(cg, 'Fixed added Pd [MW]');
    app.addPdField = uieditfield(cg, 'numeric', 'Value', 0, 'Limits', [0 Inf]);

    app.lblAddedPF = addLabel(cg, 'Fixed load PF');
    app.addPfField = uieditfield(cg, 'numeric', 'Value', 0.95, 'Limits', [0.01 1.00]);

    app.lblPminPmax = addLabel(cg, 'Pmin/Pmax [MW]');
    app.pminmaxField = uieditfield(cg, 'text', 'Value', '0, 1.0');

    app.lblQminQmax = addLabel(cg, 'Qmin/Qmax [MVAr]');
    app.qminmaxField = uieditfield(cg, 'text', 'Value', '-1.0, 1.0');

    app.lblVlim = addLabel(cg, 'Vmin/Vmax [p.u.]');
    app.vlimField = uieditfield(cg, 'text', 'Value', '0.90, 1.10');

    app.lblC2 = addLabel(cg, 'c2');
    app.c2Field = uieditfield(cg, 'numeric', 'Value', 0.010);

    app.lblC1 = addLabel(cg, 'c1');
    app.c1Field = uieditfield(cg, 'numeric', 'Value', 30);

    app.lblC0 = addLabel(cg, 'c0');
    app.c0Field = uieditfield(cg, 'numeric', 'Value', 0);

    app.applyRoleButton = uibutton(cg, 'push', ...
        'Text', 'Apply Selected Bus Role', ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) applySelectedBusRole());
    app.applyRoleButton.Layout.Column = [1 2];

    app.resetRolesButton = uibutton(cg, 'push', ...
        'Text', 'Reset Roles to case33bw Base', ...
        'ButtonPushedFcn', @(~, ~) resetAllRoles());
    app.resetRolesButton.Layout.Column = [1 2];

    app.helpArea = uitextarea(cg, ...
        'Editable', 'off', ...
        'FontName', 'Consolas', ...
        'FontSize', 11, ...
        'Value', { ...
            'RULES:', ...
            '• Sweep bus must be PQ Load.', ...
            '• Only selected sweep bus Pd is swept.', ...
            '• Plot Bus 1/2 only change displayed DLMP traces.', ...
            '• DER/Prosumer limits and costs stay fixed.', ...
            '• DER/Prosumer Pg/Qg are optimized by OPF.', ...
            '• Other PQ loads stay at case33bw base values.'});
    app.helpArea.Layout.Row = [34 39];
    app.helpArea.Layout.Column = [1 2];

    app.log = uitextarea(cg, ...
        'Editable', 'off', ...
        'FontName', 'Consolas', ...
        'FontSize', 11, ...
        'Value', {'Ready.'});
    app.log.Layout.Row = [40 50];
    app.log.Layout.Column = [1 2];

    %% ============================================================
    % Main tab area
    %% ============================================================
    tabs = uitabgroup(main);
    tabs.Layout.Column = 2;
    app.tabs = tabs;

    app.tabTopology = uitab(tabs, 'Title', 'Network Topology');
    app.tabPlots    = uitab(tabs, 'Title', 'Sweep Plots');
    app.tabData     = uitab(tabs, 'Title', 'Data Preview');
    app.tabRoles    = uitab(tabs, 'Title', 'Bus Role Editor');

    %% ---------------- Topology tab ----------------
    tg = uigridlayout(app.tabTopology, [1 2]);
    tg.Padding = [10 10 10 10];
    tg.ColumnWidth = {'1x', 340};

    app.axTopology = uiaxes(tg);
    app.axTopology.Layout.Column = 1;
    title(app.axTopology, 'case33bw Network Topology');

    infoPanel = uipanel(tg, 'Title', 'Legend + Selected Bus Details');
    infoPanel.Layout.Column = 2;
    ig = uigridlayout(infoPanel, [12 1]);
    ig.Padding = [10 10 10 10];
    ig.RowHeight = {24,24,24,24,24,24,24,24,'1x','1x','1x','1x'};

    uilabel(ig, 'Text', 'Blue: Slack/Grid',    'FontWeight', 'bold', 'FontColor', [0.00 0.25 0.90]);
    uilabel(ig, 'Text', 'Gray: PQ Load',       'FontWeight', 'bold', 'FontColor', [0.45 0.45 0.45]);
    uilabel(ig, 'Text', 'Green: DER',          'FontWeight', 'bold', 'FontColor', [0.00 0.55 0.20]);
    uilabel(ig, 'Text', 'Orange: Prosumer',    'FontWeight', 'bold', 'FontColor', [0.95 0.45 0.05]);
    uilabel(ig, 'Text', 'Red: Large Load',     'FontWeight', 'bold', 'FontColor', [0.85 0.10 0.10]);
    uilabel(ig, 'Text', 'Purple label: selected sweep bus', 'FontWeight', 'bold', 'FontColor', [0.60 0.00 0.80]);
    uilabel(ig, 'Text', 'Click a bus on topology to inspect/edit it.', 'FontAngle', 'italic');
    uilabel(ig, 'Text', 'Topology only draws BR_STATUS = 1 branches.', 'FontAngle', 'italic');

    app.busInfoArea = uitextarea(ig, ...
        'Editable', 'off', ...
        'FontName', 'Consolas', ...
        'FontSize', 12, ...
        'Value', {'Selected bus information appears here.'});
    app.busInfoArea.Layout.Row = [9 12];

    %% ---------------- Sweep plots tab ----------------
    % Plot Bus selectors are now placed in the left control panel, directly
    % under Selected Sweep Bus, so it is always visible. The Sweep Plots tab
    % only contains the plots.
    pg = uigridlayout(app.tabPlots, [2 2]);
    pg.Padding = [10 10 10 10];
    pg.RowHeight = {'1x', '1x'};
    pg.ColumnWidth = {'1x', '1x'};

    app.axC2L       = uiaxes(pg); app.axC2L.Layout.Row = 1; app.axC2L.Layout.Column = 1; title(app.axC2L, 'System C2L vs Total Demand');
    app.axDLMP      = uiaxes(pg); app.axDLMP.Layout.Row = 1; app.axDLMP.Layout.Column = 2; title(app.axDLMP, 'Bus 3 DLMP vs. Total Demand');
    app.axLoss      = uiaxes(pg); app.axLoss.Layout.Row = 2; app.axLoss.Layout.Column = 1; title(app.axLoss, 'Total Loss vs Total Demand');
    app.axDLMP2     = uiaxes(pg); app.axDLMP2.Layout.Row = 2; app.axDLMP2.Layout.Column = 2; title(app.axDLMP2, 'Bus 12 DLMP vs. Total Demand');

    %% ---------------- Data tab ----------------
    dg = uigridlayout(app.tabData, [2 2]);
    dg.Padding = [10 10 10 10];
    dg.RowHeight = {'1x','1x'};
    dg.ColumnWidth = {'1x','1x'};
    app.summaryUITable = uitable(dg, 'Data', table());
    app.busUITable = uitable(dg, 'Data', table());
    app.branchUITable = uitable(dg, 'Data', table());
    app.genUITable = uitable(dg, 'Data', table());

    %% ---------------- Role editor tab ----------------
    rg = uigridlayout(app.tabRoles, [1 1]);
    rg.Padding = [10 10 10 10];
    app.roleUITable = uitable(rg, ...
        'Data', app.busRoleConfig, ...
        'ColumnEditable', [false true true true true true true true true true true true true], ...
        'CellEditCallback', @(~, ~) roleTableEdited());
    try
        app.roleUITable.ColumnFormat = {'numeric', roleItems(), 'numeric', 'numeric', ...
            'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', ...
            'numeric', 'numeric', 'numeric'};
    catch
    end

    %% Initial refresh
    refreshRoleTableFromConfig();
    updateSelectedBusInfo(3);
    sweepBusChanged();
    refreshTopology();
    updateTables();

    %% ============================================================
    % Nested UI helper functions
    %% ============================================================
    function lab = addLabel(parent, txt)
        lab = uilabel(parent, 'Text', txt, 'HorizontalAlignment', 'right');
    end

    function lab = addSection(parent, txt)
        lab = uilabel(parent, 'Text', txt, 'FontWeight', 'bold');
        lab.Layout.Column = [1 2];
    end

    function items = roleItems()
        items = {'Slack/Grid', 'PQ Load', 'DER', 'Prosumer', 'Large Load'};
    end

    function sweepBusChanged()
        busId = str2double(app.sweepBusDrop.Value);
        app.sweepPfField.Value = defaultBusPF(app.base_mpc, busId);
        basePd = defaultBusPd(app.base_mpc, busId);
        if app.pdMinField.Value == 0 || ~isfinite(app.pdMinField.Value)
            app.pdMinField.Value = basePd;
        end
        if app.pdMaxField.Value <= app.pdMinField.Value
            app.pdMaxField.Value = app.pdMinField.Value + max(0.1, basePd);
        end

        % Before a sweep is generated, keep Plot Bus 1 aligned with the
        % Sweep Bus by default. After results exist, the user may choose any
        % Plot Bus 1 / 2 independently for comparison.
        try
            if isfield(app, 'plotBus1Drop') && (isempty(app.T) || height(app.T) == 0)
                app.plotBus1Drop.Value = char(string(busId));
            end
        catch
        end

        refreshTopology();
    end

    function useSweepBusForPlots()
        try
            app.plotBus1Drop.Value = app.sweepBusDrop.Value;
            updateAllPlots();
        catch
        end
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

            pRange = parseRangeText(app.pminmaxField.Value, 'Pmin/Pmax');
            qRange = parseRangeText(app.qminmaxField.Value, 'Qmin/Qmax');
            vRange = parseRangeText(app.vlimField.Value, 'Vmin/Vmax');

            roleCfg.role(rowIdx) = selectedRole;
            roleCfg.add_Pd_MW(rowIdx) = app.addPdField.Value;
            roleCfg.pf(rowIdx) = app.addPfField.Value;
            roleCfg.Pmin_MW(rowIdx) = pRange(1);
            roleCfg.Pmax_MW(rowIdx) = pRange(2);
            roleCfg.Qmin_MVAr(rowIdx) = qRange(1);
            roleCfg.Qmax_MVAr(rowIdx) = qRange(2);
            roleCfg.Vmin_pu(rowIdx) = vRange(1);
            roleCfg.Vmax_pu(rowIdx) = vRange(2);
            roleCfg.c2(rowIdx) = app.c2Field.Value;
            roleCfg.c1(rowIdx) = app.c1Field.Value;
            roleCfg.c0(rowIdx) = app.c0Field.Value;

            app.busRoleConfig = validateBusRoleConfig(roleCfg, app.base_mpc);
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
        try
            busRoleConfig = validateBusRoleConfig(app.busRoleConfig, app.base_mpc); %#ok<NASGU>
            createdAt = datetime('now'); %#ok<NASGU>
            baseCaseName = 'case33bw'; %#ok<NASGU>
            [file, path] = uiputfile('*.mat', 'Save Custom Bus Role Configuration');
            if isequal(file, 0)
                logMsg('Custom config save cancelled.');
                return;
            end
            save(fullfile(path, file), 'busRoleConfig', 'createdAt', 'baseCaseName');
            logMsg(sprintf('Saved custom config: %s', fullfile(path, file)));
        catch ME
            logMsg(sprintf('ERROR saving custom config: %s', ME.message));
            uialert(app.fig, ME.message, 'Save Config Error');
        end
    end

    function loadCustomConfig()
        try
            [file, path] = uigetfile('*.mat', 'Load Custom Bus Role Configuration');
            if isequal(file, 0)
                logMsg('Custom config load cancelled.');
                return;
            end
            S = load(fullfile(path, file));
            if ~isfield(S, 'busRoleConfig')
                error('Selected MAT-file does not contain busRoleConfig.');
            end
            app.busRoleConfig = validateBusRoleConfig(S.busRoleConfig, app.base_mpc);
            refreshBusRoleConfigUI(app.selectedInspectBus);
            logMsg(sprintf('Loaded custom config: %s', fullfile(path, file)));
        catch ME
            logMsg(sprintf('ERROR loading custom config: %s', ME.message));
            uialert(app.fig, ME.message, 'Load Config Error');
        end
    end

    function roleTableEdited()
        try
            roleCfg = getRoleConfigFromUITable();
            app.busRoleConfig = validateBusRoleConfig(roleCfg, app.base_mpc);
            refreshBusRoleConfigUI(app.selectedInspectBus);
            logMsg('Bus role table updated.');
        catch ME
            logMsg(sprintf('ERROR in role table: %s', ME.message));
            uialert(app.fig, ME.message, 'Role Table Error');
            refreshRoleTableFromConfig();
        end
    end

    function refreshBusRoleConfigUI(focusBusId)
        if nargin < 1 || isempty(focusBusId) || ~isfinite(focusBusId)
            focusBusId = app.selectedInspectBus;
        end
        refreshRoleTableFromConfig();
        syncQuickRoleEditorToBus(focusBusId);
        updateSelectedBusInfo(focusBusId);
        refreshTopology();
        updateTables();
    end

    function refreshRoleTableFromConfig()
        app.roleUITable.Data = app.busRoleConfig;
    end

    function roleCfg = getRoleConfigFromUITable()
        roleCfg = app.roleUITable.Data;
        if ~istable(roleCfg)
            roleCfg = struct2table(roleCfg);
        end
        roleCfg = normalizeRoleConfigColumns(roleCfg, app.base_mpc);
        roleCfg.role = string(roleCfg.role);
    end

    function syncQuickRoleEditorToBus(busId)
        try
            rowIdx = find(app.busRoleConfig.bus_id == busId, 1);
            if isempty(rowIdx)
                return;
            end
            r = app.busRoleConfig(rowIdx, :);
            app.busSelectDrop.Value = char(string(busId));
            app.roleDrop.Value = char(r.role);
            app.addPdField.Value = r.add_Pd_MW;
            app.addPfField.Value = r.pf;
            app.pminmaxField.Value = sprintf('%.6g, %.6g', r.Pmin_MW, r.Pmax_MW);
            app.qminmaxField.Value = sprintf('%.6g, %.6g', r.Qmin_MVAr, r.Qmax_MVAr);
            app.vlimField.Value = sprintf('%.6g, %.6g', r.Vmin_pu, r.Vmax_pu);
            app.c2Field.Value = r.c2;
            app.c1Field.Value = r.c1;
            app.c0Field.Value = r.c0;
        catch
        end
    end

    function updateSelectedBusInfo(busId)
        try
            if isempty(busId) || ~isfinite(busId)
                return;
            end
            app.selectedInspectBus = busId;
            syncQuickRoleEditorToBus(busId);
            app.busInfoArea.Value = selectedBusInfoText(busId, app.base_mpc, app.busRoleConfig, app.busResults);
            refreshTopology();
        catch ME
            app.busInfoArea.Value = {sprintf('Could not read bus %d details.', busId), ME.message};
        end
    end

    function refreshTopology()
        try
            sweepBus = str2double(app.sweepBusDrop.Value);
        catch
            sweepBus = NaN;
        end
        app.topologyClickData = drawCaseTopology(app.axTopology, app.base_mpc, app.busRoleConfig, sweepBus, app.selectedInspectBus);
    end

    function handleFigureMouseDown()
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
            xr = max(eps, diff(xl));
            yr = max(eps, diff(yl));
            d = sqrt(((x - xClick) ./ xr).^2 + ((y - yClick) ./ yr).^2);
            [minD, idx] = min(d);
            if minD <= 0.045
                updateSelectedBusInfo(app.topologyClickData.busIds(idx));
            end
        catch
        end
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
    % Run, save, update plots
    %% ============================================================
    function cfg = readSweepConfigFromUI()
        cfg = struct();
        cfg.sweepBus = str2double(app.sweepBusDrop.Value);
        cfg.pdMin = app.pdMinField.Value;
        cfg.pdMax = app.pdMaxField.Value;
        cfg.N = round(app.stepsField.Value);
        cfg.qMode = string(app.qModeDrop.Value);
        cfg.sweepPF = app.sweepPfField.Value;
        cfg.outputFile = strtrim(app.outputField.Value);
        cfg.roleConfig = validateBusRoleConfig(getRoleConfigFromUITable(), app.base_mpc);

        if isempty(cfg.outputFile)
            cfg.outputFile = 'case33bw_single_bus_sweep_results.xlsx';
        end
        if cfg.N < 2
            error('Number of steps must be at least 2.');
        end
        if ~isfinite(cfg.pdMin) || ~isfinite(cfg.pdMax) || cfg.pdMin < 0 || cfg.pdMax <= cfg.pdMin
            error('Pd min/max must be finite and Pd max must be greater than Pd min.');
        end
        if cfg.sweepPF <= 0 || cfg.sweepPF > 1
            error('Sweep PF must be in (0, 1].');
        end

        row = cfg.roleConfig(cfg.roleConfig.bus_id == cfg.sweepBus, :);
        if isempty(row)
            error('Selected sweep bus does not exist.');
        end
        if string(row.role) ~= "PQ Load"
            error('Selected sweep bus must be PQ Load. Current role of bus %d is %s.', cfg.sweepBus, string(row.role));
        end
        if cfg.sweepBus == getSlackBusId(app.base_mpc)
            error('Slack/Grid bus cannot be used as the sweep PQ bus.');
        end
    end

    function runSweep()
        try
            app.runButton.Enable = 'off';
            app.status.Text = 'Running deterministic single-bus sweep...';
            logMsg('Starting deterministic single-bus Pd sweep.');
            drawnow;

            cfg = readSweepConfigFromUI();
            pdValues = linspace(cfg.pdMin, cfg.pdMax, cfg.N);

            app.T = table();
            app.busResults = table();
            app.branchResults = table();
            app.genResults = table();

            mpopt = mpoption('verbose', 0, 'out.all', 0, 'opf.ac.solver', 'MIPS');

            summaryRows = cell(cfg.N, 1);
            busTables = cell(cfg.N, 1);
            branchTables = cell(cfg.N, 1);
            genTables = cell(cfg.N, 1);
            successCount = 0;

            for k = 1:cfg.N
                pd = pdValues(k);
                try
                    [mpc, sweepInfo] = buildSingleBusSweepMPC(app.base_mpc, cfg.roleConfig, cfg, pd, k);
                    results = runopf(mpc, mpopt);
                    if isfield(results, 'success') && results.success == 1
                        successCount = successCount + 1;
                        [summaryRows{k}, busTables{k}, branchTables{k}, genTables{k}] = extractSweepResults(k, mpc, results, cfg.roleConfig, sweepInfo);
                    else
                        summaryRows{k} = makeFailedSummaryRow(k, sweepInfo, 'runopf returned success = 0');
                        busTables{k} = table();
                        branchTables{k} = table();
                        genTables{k} = table();
                    end
                catch ME
                    sweepInfo = basicSweepInfo(k, cfg, pd);
                    summaryRows{k} = makeFailedSummaryRow(k, sweepInfo, ME.message);
                    busTables{k} = table();
                    branchTables{k} = table();
                    genTables{k} = table();
                    if k == 1 || mod(k, max(1, round(cfg.N/10))) == 0
                        logMsg(sprintf('Step %d failed: %s', k, ME.message));
                    end
                end

                if k == 1 || mod(k, max(1, round(cfg.N/10))) == 0 || k == cfg.N
                    app.status.Text = sprintf('Sweep progress: %d / %d steps, %d successful.', k, cfg.N, successCount);
                    logMsg(app.status.Text);
                    drawnow limitrate;
                end
            end

            app.T = struct2table([summaryRows{:}]);
            app.busResults = vertcatNonEmpty(busTables);
            app.branchResults = vertcatNonEmpty(branchTables);
            app.genResults = vertcatNonEmpty(genTables);

            updateAllPlots();
            updateTables();
            saveCurrentResults();

            app.status.Text = sprintf('Done. %d / %d OPF steps successful.', successCount, cfg.N);
            logMsg(app.status.Text);
        catch ME
            app.status.Text = 'Error.';
            logMsg(sprintf('ERROR: %s', ME.message));
            uialert(app.fig, ME.message, 'Sweep Error');
        end
        app.runButton.Enable = 'on';
    end

    function updateTables()
        app.summaryUITable.Data = firstNRows(app.T, 150);
        app.busUITable.Data = firstNRows(app.busResults, 200);
        app.branchUITable.Data = firstNRows(app.branchResults, 200);
        app.genUITable.Data = firstNRows(app.genResults, 200);
    end

    function updateAllPlots()
        refreshTopology();
        axesList = {app.axC2L, app.axDLMP, app.axLoss, app.axDLMP2};
        for ii = 1:numel(axesList)
            cla(axesList{ii});
        end

        if isempty(app.T) || height(app.T) == 0
            return;
        end
        T = app.T(app.T.success == true, :);
        if isempty(T) || height(T) == 0
            text(app.axC2L, 0.1, 0.5, 'No successful OPF steps.', 'Units', 'normalized');
            return;
        end

        plotBus1 = selectedPlotBusForPlots(T, 1);
        plotBus2 = selectedPlotBusForPlots(T, 2);

        % C2L is a system-level metric: objective_cost / total_Pd.
        % Therefore its x-axis is total system demand, not the plot bus or only
        % the swept bus demand.
        xC2L = T.total_Pd_MW;
        yyaxis(app.axC2L, 'left');
        plot(app.axC2L, xC2L, T.cost_to_load_total, '.-');
        ylabel(app.axC2L, 'Objective Cost / Total Pd');
        yyaxis(app.axC2L, 'right');
        plot(app.axC2L, xC2L, T.total_Pd_MW, 'r-', 'LineWidth', 1.2);
        ylabel(app.axC2L, 'Total Demand Pd [MW]');
        yyaxis(app.axC2L, 'left');
        xlabel(app.axC2L, 'Total Demand Pd [MW]');
        title(app.axC2L, 'System C2L with Total Demand Reference');
        legend(app.axC2L, {'C2L', 'Total Demand'}, 'Location', 'best');
        grid(app.axC2L, 'on');

        [xDlmp, yDlmp] = busSeriesForPlot(T, app.busResults, plotBus1, 'DLMP_LAM_P', 'total_Pd_MW');
        yyaxis(app.axDLMP, 'left');
        if isempty(xDlmp)
            text(app.axDLMP, 0.1, 0.5, sprintf('No bus result found for Bus %d.', plotBus1), 'Units', 'normalized');
        else
            plot(app.axDLMP, xDlmp, yDlmp, '.-');
        end
        ylabel(app.axDLMP, 'LAM_P');
        yyaxis(app.axDLMP, 'right');
        plot(app.axDLMP, T.total_Pd_MW, T.total_Pd_MW, 'r-', 'LineWidth', 1.2);
        ylabel(app.axDLMP, 'Total Demand Pd [MW]');
        yyaxis(app.axDLMP, 'left');
        if ~isempty(xDlmp)
            legend(app.axDLMP, {sprintf('Bus %d DLMP', plotBus1), 'Total Demand'}, 'Location', 'best');
        end
        xlabel(app.axDLMP, 'Total Demand Pd [MW]');
        title(app.axDLMP, sprintf('Bus %d DLMP vs. Total Demand', plotBus1)); grid(app.axDLMP, 'on');

        yyaxis(app.axLoss, 'left');
        plot(app.axLoss, T.total_Pd_MW, T.total_P_loss_MW, '.-');
        ylabel(app.axLoss, 'P loss [MW]');
        yyaxis(app.axLoss, 'right');
        plot(app.axLoss, T.total_Pd_MW, T.total_Pd_MW, 'r-', 'LineWidth', 1.2);
        ylabel(app.axLoss, 'Total Demand Pd [MW]');
        yyaxis(app.axLoss, 'left');
        xlabel(app.axLoss, 'Total Demand Pd [MW]');
        title(app.axLoss, 'Total Loss with Total Demand Reference');
        legend(app.axLoss, {'Total Loss', 'Total Demand'}, 'Location', 'best');
        grid(app.axLoss, 'on');

        [xDlmp2, yDlmp2] = busSeriesForPlot(T, app.busResults, plotBus2, 'DLMP_LAM_P', 'total_Pd_MW');
        yyaxis(app.axDLMP2, 'left');
        if isempty(xDlmp2)
            text(app.axDLMP2, 0.1, 0.5, sprintf('No bus result found for Bus %d.', plotBus2), 'Units', 'normalized');
        else
            plot(app.axDLMP2, xDlmp2, yDlmp2, '.-');
        end
        ylabel(app.axDLMP2, 'LAM_P');
        yyaxis(app.axDLMP2, 'right');
        plot(app.axDLMP2, T.total_Pd_MW, T.total_Pd_MW, 'r-', 'LineWidth', 1.2);
        ylabel(app.axDLMP2, 'Total Demand Pd [MW]');
        yyaxis(app.axDLMP2, 'left');
        if ~isempty(xDlmp2)
            legend(app.axDLMP2, {sprintf('Bus %d DLMP', plotBus2), 'Total Demand'}, 'Location', 'best');
        end
        xlabel(app.axDLMP2, 'Total Demand Pd [MW]');
        title(app.axDLMP2, sprintf('Bus %d DLMP vs. Total Demand', plotBus2)); grid(app.axDLMP2, 'on');

        function busId = selectedPlotBusForPlots(Tlocal, slotNo)
            try
                if slotNo == 1
                    busId = str2double(app.plotBus1Drop.Value);
                else
                    busId = str2double(app.plotBus2Drop.Value);
                end
            catch
                busId = NaN;
            end
            if isempty(busId) || ~isfinite(busId)
                busId = Tlocal.sweep_bus(1);
            end
        end

        function [xOut, yOut] = busSeriesForPlot(Tlocal, B, busId, varName, xVarName)
            xOut = [];
            yOut = [];
            if nargin < 5 || isempty(xVarName)
                xVarName = 'swept_Pd_MW';
            end
            if isempty(B) || height(B) == 0 || ~ismember(varName, B.Properties.VariableNames)
                return;
            end
            if ~ismember(xVarName, Tlocal.Properties.VariableNames)
                return;
            end
            Bb = B(B.bus_id == busId, :);
            if isempty(Bb) || height(Bb) == 0
                return;
            end
            [~, ia, ib] = intersect(Tlocal.scenario_id, Bb.scenario_id, 'stable');
            if isempty(ia)
                return;
            end
            xOut = Tlocal.(xVarName)(ia);
            yOut = Bb.(varName)(ib);
        end
    end

    function saveCurrentResults()
        if isempty(app.T) || height(app.T) == 0
            logMsg('No sweep results to save yet.');
            return;
        end
        try
            outputFile = strtrim(app.outputField.Value);
            if isempty(outputFile)
                outputFile = 'case33bw_single_bus_sweep_results.xlsx';
            end
            [p, n, e] = fileparts(outputFile);
            if isempty(e)
                e = '.xlsx';
            end
            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            newName = sprintf('%s_%s%s', n, stamp, e);
            if isempty(p)
                outputFile = newName;
            else
                outputFile = fullfile(p, newName);
            end
            if isfile(outputFile)
                delete(outputFile);
            end
            writetable(app.T, outputFile, 'Sheet', 'sweep_summary');
            writetable(app.busResults, outputFile, 'Sheet', 'bus_results_long');
            writetable(app.branchResults, outputFile, 'Sheet', 'branch_results_long');
            writetable(app.genResults, outputFile, 'Sheet', 'gen_results_long');
            writetable(app.busRoleConfig, outputFile, 'Sheet', 'bus_role_config');
            writetable(createBusStaticTable(app.base_mpc, app.busRoleConfig), outputFile, 'Sheet', 'bus_static');
            writetable(createBranchStaticTable(app.base_mpc), outputFile, 'Sheet', 'branch_static');
            logMsg(sprintf('Saved Excel file: %s', outputFile));
        catch ME
            logMsg(sprintf('ERROR saving Excel: %s', ME.message));
            uialert(app.fig, ME.message, 'Save Results Error');
        end
    end

end

%% ========================================================================
% Local computational functions - MATPOWER setup
%% ========================================================================
function C = mpConst()
    % MATPOWER case-format column constants.
    C.PQ = 1; C.PV = 2; C.REF = 3; C.NONE = 4;

    C.BUS_I = 1; C.BUS_TYPE = 2; C.PD = 3; C.QD = 4; C.GS = 5; C.BS = 6;
    C.BUS_AREA = 7; C.VM = 8; C.VA = 9; C.BASE_KV = 10; C.ZONE = 11;
    C.VMAX = 12; C.VMIN = 13; C.LAM_P = 14; C.LAM_Q = 15;

    C.GEN_BUS = 1; C.PG = 2; C.QG = 3; C.QMAX = 4; C.QMIN = 5;
    C.VG = 6; C.MBASE = 7; C.GEN_STATUS = 8; C.PMAX = 9; C.PMIN = 10;

    C.F_BUS = 1; C.T_BUS = 2; C.BR_R = 3; C.BR_X = 4; C.BR_B = 5;
    C.RATE_A = 6; C.RATE_B = 7; C.RATE_C = 8; C.TAP = 9; C.SHIFT = 10;
    C.BR_STATUS = 11; C.ANGMIN = 12; C.ANGMAX = 13;
    C.PF = 14; C.QF = 15; C.PT = 16; C.QT = 17;
end

function mpc = loadCase33bwForSweepLab()
    try
        mpc = loadcase('case33bw');
    catch ME
        error(['Could not load MATPOWER case33bw. Make sure MATPOWER is installed, ', ...
               'case33bw is on the MATLAB path, and install_matpower has been run. Original error: %s'], ME.message);
    end
    mpc = ensureOPFReady(mpc);
end

function mpc = ensureOPFReady(mpc)
    C = mpConst();

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
    if size(mpc.bus, 2) < C.VMIN
        mpc.bus(:, end+1:C.VMIN) = 0;
    end
    if size(mpc.branch, 2) < C.ANGMAX
        mpc.branch(:, end+1:C.ANGMAX) = 0;
    end

    % Make sure exactly one slack bus exists.
    if ~any(mpc.bus(:, C.BUS_TYPE) == C.REF)
        mpc.bus(1, C.BUS_TYPE) = C.REF;
    end
    slackBus = getSlackBusId(mpc);

    % Fill voltage limits if missing.
    badVmax = ~isfinite(mpc.bus(:, C.VMAX)) | mpc.bus(:, C.VMAX) <= 0;
    badVmin = ~isfinite(mpc.bus(:, C.VMIN)) | mpc.bus(:, C.VMIN) <= 0;
    mpc.bus(badVmax, C.VMAX) = 1.10;
    mpc.bus(badVmin, C.VMIN) = 0.90;

    % Fill branch defaults.
    if size(mpc.branch, 2) >= C.BR_STATUS
        badStatus = ~isfinite(mpc.branch(:, C.BR_STATUS));
        mpc.branch(badStatus, C.BR_STATUS) = 1;
    end
    if size(mpc.branch, 2) >= C.ANGMAX
        noAngMax = ~isfinite(mpc.branch(:, C.ANGMAX)) | mpc.branch(:, C.ANGMAX) == 0;
        noAngMin = ~isfinite(mpc.branch(:, C.ANGMIN)) | mpc.branch(:, C.ANGMIN) == 0;
        mpc.branch(noAngMax, C.ANGMAX) = 360;
        mpc.branch(noAngMin, C.ANGMIN) = -360;
    end

    % Ensure generator matrix exists and contains an active slack generator.
    if ~isfield(mpc, 'gen') || isempty(mpc.gen)
        mpc.gen = makeGenRow(slackBus, sum(mpc.bus(:, C.PD)), sum(mpc.bus(:, C.QD)), ...
            100, -100, 1.0, mpc.baseMVA, 1, max(100, 2*sum(mpc.bus(:, C.PD))), 0);
    else
        if size(mpc.gen, 2) < 21
            mpc.gen(:, end+1:21) = 0;
        end
        if ~any(mpc.gen(:, C.GEN_BUS) == slackBus & mpc.gen(:, C.GEN_STATUS) > 0)
            newGen = makeGenRow(slackBus, sum(mpc.bus(:, C.PD)), sum(mpc.bus(:, C.QD)), ...
                100, -100, 1.0, mpc.baseMVA, 1, max(100, 2*sum(mpc.bus(:, C.PD))), 0);
            mpc.gen = [newGen; mpc.gen];
        end
    end

    % Ensure generator cost exists.
    nGen = size(mpc.gen, 1);
    if ~isfield(mpc, 'gencost') || isempty(mpc.gencost) || size(mpc.gencost, 1) ~= nGen
        mpc.gencost = repmat([2 0 0 3 0.010 35 0], nGen, 1);
    elseif size(mpc.gencost, 2) < 7
        mpc.gencost(:, end+1:7) = 0;
        mpc.gencost(:, 1) = 2;
        mpc.gencost(:, 4) = 3;
    end
end

function row = makeGenRow(busId, Pg, Qg, Qmax, Qmin, Vg, mBase, status, Pmax, Pmin)
    row = zeros(1, 21);
    C = mpConst();
    row(C.GEN_BUS) = busId;
    row(C.PG) = Pg;
    row(C.QG) = Qg;
    row(C.QMAX) = Qmax;
    row(C.QMIN) = Qmin;
    row(C.VG) = Vg;
    row(C.MBASE) = mBase;
    row(C.GEN_STATUS) = status;
    row(C.PMAX) = Pmax;
    row(C.PMIN) = Pmin;
end

function slackBus = getSlackBusId(mpc)
    C = mpConst();
    idx = find(mpc.bus(:, C.BUS_TYPE) == C.REF, 1);
    if isempty(idx)
        idx = 1;
    end
    slackBus = mpc.bus(idx, C.BUS_I);
end

%% ========================================================================
% Role configuration
%% ========================================================================
function roleCfg = createDefaultBusRoleConfig(base_mpc)
    C = mpConst();
    busIds = base_mpc.bus(:, C.BUS_I);
    n = numel(busIds);
    slackBus = getSlackBusId(base_mpc);
    totalPd = sum(base_mpc.bus(:, C.PD));

    role = repmat("PQ Load", n, 1);
    role(busIds == slackBus) = "Slack/Grid";

    addPd = zeros(n, 1);
    pf = arrayfun(@(b) defaultBusPF(base_mpc, b), busIds);
    pf(~isfinite(pf) | pf <= 0 | pf > 1) = 0.95;

    Pmin = zeros(n, 1);
    Pmax = zeros(n, 1);
    Qmin = -ones(n, 1);
    Qmax = ones(n, 1);
    Vmin = base_mpc.bus(:, C.VMIN);
    Vmax = base_mpc.bus(:, C.VMAX);

    % Robust voltage-limit defaults. Some MATPOWER distribution cases or
    % edited configs can contain 0, NaN, or swapped limits. The role table
    % must always start from valid OPF voltage limits.
    badVmin = ~isfinite(Vmin) | Vmin <= 0;
    Vmin(badVmin) = 0.90;

    badVmax = ~isfinite(Vmax) | Vmax <= 0 | Vmax <= Vmin;
    Vmax(badVmax) = 1.10;

    stillBad = Vmax <= Vmin;
    Vmin(stillBad) = 0.90;
    Vmax(stillBad) = 1.10;

    c2 = 0.010 * ones(n, 1);
    c1 = 30 * ones(n, 1);
    c0 = zeros(n, 1);

    % More robust default limits/cost for the grid/slack resource.
    sidx = find(busIds == slackBus, 1);
    Pmax(sidx) = max(100, 2 * totalPd + 10);
    Qmin(sidx) = -100;
    Qmax(sidx) = 100;
    c2(sidx) = 0.010;
    c1(sidx) = 35;

    roleCfg = table(busIds, role, addPd, pf, Pmin, Pmax, Qmin, Qmax, Vmin, Vmax, c2, c1, c0, ...
        'VariableNames', {'bus_id','role','add_Pd_MW','pf','Pmin_MW','Pmax_MW', ...
        'Qmin_MVAr','Qmax_MVAr','Vmin_pu','Vmax_pu','c2','c1','c0'});
end

function roleCfg = normalizeRoleConfigColumns(roleCfg, base_mpc)
    % Accepts both the new deterministic role table and older range-based
    % configs from the scenario dashboard. In older configs, min values are
    % used deterministically for cost/PF/fixed added load.
    def = createDefaultBusRoleConfig(base_mpc);
    if ~istable(roleCfg)
        roleCfg = struct2table(roleCfg);
    end
    if ~ismember('bus_id', roleCfg.Properties.VariableNames)
        error('Role config must contain bus_id.');
    end
    n = height(roleCfg);

    if ~ismember('role', roleCfg.Properties.VariableNames)
        roleCfg.role = def.role(1:n);
    end
    roleCfg.role = string(roleCfg.role);

    roleCfg = ensureVar(roleCfg, 'add_Pd_MW', oldOrDefault(roleCfg, def, 'add_Pd_min_MW', 'add_Pd_MW'));
    roleCfg = ensureVar(roleCfg, 'pf', oldOrDefault(roleCfg, def, 'pf_min', 'pf'));
    roleCfg = ensureVar(roleCfg, 'Pmin_MW', oldOrDefault(roleCfg, def, 'Pmin_MW', 'Pmin_MW'));
    roleCfg = ensureVar(roleCfg, 'Pmax_MW', oldOrDefault(roleCfg, def, 'Pmax_MW', 'Pmax_MW'));
    roleCfg = ensureVar(roleCfg, 'Qmin_MVAr', oldOrDefault(roleCfg, def, 'Qmin_MVAr', 'Qmin_MVAr'));
    roleCfg = ensureVar(roleCfg, 'Qmax_MVAr', oldOrDefault(roleCfg, def, 'Qmax_MVAr', 'Qmax_MVAr'));
    roleCfg = ensureVar(roleCfg, 'Vmin_pu', oldOrDefault(roleCfg, def, 'Vmin_pu', 'Vmin_pu'));
    roleCfg = ensureVar(roleCfg, 'Vmax_pu', oldOrDefault(roleCfg, def, 'Vmax_pu', 'Vmax_pu'));
    roleCfg = ensureVar(roleCfg, 'c2', oldOrDefault(roleCfg, def, 'c2_min', 'c2'));
    roleCfg = ensureVar(roleCfg, 'c1', oldOrDefault(roleCfg, def, 'c1_min', 'c1'));
    roleCfg = ensureVar(roleCfg, 'c0', oldOrDefault(roleCfg, def, 'c0', 'c0'));

    roleCfg = roleCfg(:, {'bus_id','role','add_Pd_MW','pf','Pmin_MW','Pmax_MW', ...
        'Qmin_MVAr','Qmax_MVAr','Vmin_pu','Vmax_pu','c2','c1','c0'});
end

function T = ensureVar(T, name, values)
    if ~ismember(name, T.Properties.VariableNames)
        T.(name) = values;
    end
end

function values = oldOrDefault(T, def, oldName, defName)
    if ismember(oldName, T.Properties.VariableNames)
        values = T.(oldName);
    elseif ismember(defName, T.Properties.VariableNames)
        values = T.(defName);
    else
        [~, loc] = ismember(T.bus_id, def.bus_id);
        loc(loc == 0) = 1;
        values = def.(defName)(loc);
    end
end

function roleCfg = validateBusRoleConfig(roleCfg, base_mpc)
    C = mpConst();
    roleCfg = normalizeRoleConfigColumns(roleCfg, base_mpc);
    validRoles = ["Slack/Grid", "PQ Load", "DER", "Prosumer", "Large Load"];
    baseBusIds = base_mpc.bus(:, C.BUS_I);
    slackBus = getSlackBusId(base_mpc);

    if numel(unique(roleCfg.bus_id)) ~= height(roleCfg)
        error('Role config contains duplicate bus_id values.');
    end
    if any(~ismember(roleCfg.bus_id, baseBusIds))
        error('Role config contains bus IDs not present in case33bw.');
    end

    for k = 1:height(roleCfg)
        if ~any(roleCfg.role(k) == validRoles)
            error('Invalid role at bus %d: %s', roleCfg.bus_id(k), roleCfg.role(k));
        end
        if roleCfg.role(k) == "Slack/Grid" && roleCfg.bus_id(k) ~= slackBus
            error('Only original slack bus %d can be Slack/Grid.', slackBus);
        end
        numericVals = [roleCfg.add_Pd_MW(k), roleCfg.pf(k), roleCfg.Pmin_MW(k), roleCfg.Pmax_MW(k), ...
            roleCfg.Qmin_MVAr(k), roleCfg.Qmax_MVAr(k), roleCfg.Vmin_pu(k), roleCfg.Vmax_pu(k), ...
            roleCfg.c2(k), roleCfg.c1(k), roleCfg.c0(k)];
        if any(~isfinite(numericVals))
            error('Non-finite numeric value in role config at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.add_Pd_MW(k) < 0
            error('Fixed added Pd must be non-negative at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.pf(k) <= 0 || roleCfg.pf(k) > 1
            error('PF must be in (0, 1] at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.Pmin_MW(k) > roleCfg.Pmax_MW(k)
            error('Pmin cannot be greater than Pmax at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.Qmin_MVAr(k) > roleCfg.Qmax_MVAr(k)
            error('Qmin cannot be greater than Qmax at bus %d.', roleCfg.bus_id(k));
        end
        if roleCfg.Vmin_pu(k) <= 0 || roleCfg.Vmax_pu(k) <= roleCfg.Vmin_pu(k)
            error('Invalid Vmin/Vmax at bus %d. Use Vmin < Vmax, e.g. 0.90, 1.10. Current values: Vmin=%.6g, Vmax=%.6g.', ...
                roleCfg.bus_id(k), roleCfg.Vmin_pu(k), roleCfg.Vmax_pu(k));
        end
    end

    % Ensure the original slack bus row remains Slack/Grid.
    srow = find(roleCfg.bus_id == slackBus, 1);
    if isempty(srow)
        error('Role config does not contain the slack bus.');
    end
    roleCfg.role(srow) = "Slack/Grid";
end

%% ========================================================================
% Sweep mpc construction
%% ========================================================================
function [mpc, sweepInfo] = buildSingleBusSweepMPC(base_mpc, roleCfg, cfg, sweptPd, stepId)
    C = mpConst();
    mpc = ensureOPFReady(base_mpc);
    roleCfg = validateBusRoleConfig(roleCfg, base_mpc);
    slackBus = getSlackBusId(base_mpc);

    % Reset buses to deterministic configured-base loads. No random PDF,
    % no global scaling: all base case33bw Pd/Qd values stay fixed unless
    % modified by fixed role additions or selected PQ sweep.
    mpc.bus(:, C.PD) = base_mpc.bus(:, C.PD);
    mpc.bus(:, C.QD) = base_mpc.bus(:, C.QD);
    mpc.bus(:, C.BUS_TYPE) = C.PQ;
    mpc.bus(mpc.bus(:, C.BUS_I) == slackBus, C.BUS_TYPE) = C.REF;

    % Apply bus voltage limits from role table.
    for k = 1:height(roleCfg)
        b = roleCfg.bus_id(k);
        idx = find(mpc.bus(:, C.BUS_I) == b, 1);
        if isempty(idx)
            continue;
        end
        mpc.bus(idx, C.VMIN) = roleCfg.Vmin_pu(k);
        mpc.bus(idx, C.VMAX) = roleCfg.Vmax_pu(k);
    end

    % Build generators from configured roles: one slack/grid generator plus
    % DER/Prosumer generators. Fixed input values remain fixed; Pg/Qg are
    % OPF decision variables within P/Q limits.
    genRows = [];
    costRows = [];

    slackRole = roleCfg(roleCfg.bus_id == slackBus, :);
    if isempty(slackRole)
        error('Slack/Grid role is missing.');
    end
    slackPmax = slackRole.Pmax_MW;
    if slackPmax <= slackRole.Pmin_MW
        slackPmax = max(100, 2 * sum(base_mpc.bus(:, C.PD)) + sweptPd + 10);
    end
    genRows = [genRows; makeGenRow(slackBus, 0, 0, slackRole.Qmax_MVAr, slackRole.Qmin_MVAr, ...
        1.0, mpc.baseMVA, 1, slackPmax, slackRole.Pmin_MW)]; %#ok<AGROW>
    costRows = [costRows; makeCostRow(slackRole.c2, slackRole.c1, slackRole.c0)]; %#ok<AGROW>

    for k = 1:height(roleCfg)
        b = roleCfg.bus_id(k);
        r = roleCfg(k, :);
        idx = find(mpc.bus(:, C.BUS_I) == b, 1);
        if isempty(idx)
            continue;
        end
        role = string(r.role);

        if role == "Large Load"
            [addP, addQ] = fixedLoadPQ(r.add_Pd_MW, r.pf);
            mpc.bus(idx, C.PD) = mpc.bus(idx, C.PD) + addP;
            mpc.bus(idx, C.QD) = mpc.bus(idx, C.QD) + addQ;
        elseif role == "Prosumer"
            [addP, addQ] = fixedLoadPQ(r.add_Pd_MW, r.pf);
            mpc.bus(idx, C.PD) = mpc.bus(idx, C.PD) + addP;
            mpc.bus(idx, C.QD) = mpc.bus(idx, C.QD) + addQ;
            mpc.bus(idx, C.BUS_TYPE) = C.PV;
            genRows = [genRows; makeGenRow(b, 0, 0, r.Qmax_MVAr, r.Qmin_MVAr, 1.0, ...
                mpc.baseMVA, 1, r.Pmax_MW, r.Pmin_MW)]; %#ok<AGROW>
            costRows = [costRows; makeCostRow(r.c2, r.c1, r.c0)]; %#ok<AGROW>
        elseif role == "DER"
            % DER does not remove original case33bw load. It adds a local
            % controllable generator at that bus.
            mpc.bus(idx, C.BUS_TYPE) = C.PV;
            genRows = [genRows; makeGenRow(b, 0, 0, r.Qmax_MVAr, r.Qmin_MVAr, 1.0, ...
                mpc.baseMVA, 1, r.Pmax_MW, r.Pmin_MW)]; %#ok<AGROW>
            costRows = [costRows; makeCostRow(r.c2, r.c1, r.c0)]; %#ok<AGROW>
        end
    end

    % Apply selected PQ bus sweep after fixed role configuration. The swept
    % value is the final Pd of that bus, not base + added.
    sweepIdx = find(mpc.bus(:, C.BUS_I) == cfg.sweepBus, 1);
    if isempty(sweepIdx)
        error('Selected sweep bus %d was not found.', cfg.sweepBus);
    end
    sweepRole = roleCfg(roleCfg.bus_id == cfg.sweepBus, :);
    if string(sweepRole.role) ~= "PQ Load"
        error('Selected sweep bus must be PQ Load.');
    end

    baseQ = base_mpc.bus(sweepIdx, C.QD);
    if cfg.qMode == "Keep PF constant"
        qSign = sign(baseQ);
        if qSign == 0
            qSign = 1;
        end
        sweptQd = qSign * sweptPd * tan(acos(cfg.sweepPF));
    else
        sweptQd = baseQ;
    end
    mpc.bus(sweepIdx, C.PD) = sweptPd;
    mpc.bus(sweepIdx, C.QD) = sweptQd;
    mpc.bus(sweepIdx, C.BUS_TYPE) = C.PQ;

    mpc.gen = genRows;
    mpc.gencost = costRows;

    sweepInfo = basicSweepInfo(stepId, cfg, sweptPd);
    sweepInfo.swept_Qd_MVAr = sweptQd;
    sweepInfo.total_Pd_MW = sum(mpc.bus(:, C.PD));
    sweepInfo.total_Qd_MVAr = sum(mpc.bus(:, C.QD));
end

function row = makeCostRow(c2, c1, c0)
    row = [2 0 0 3 c2 c1 c0];
end

function [P, Q] = fixedLoadPQ(P, pf)
    P = max(0, P);
    pf = min(max(pf, 0.01), 1.0);
    Q = P * tan(acos(pf));
end

function info = basicSweepInfo(stepId, cfg, sweptPd)
    info = struct();
    info.scenario_id = stepId;
    info.sweep_step = stepId;
    info.sweep_bus = cfg.sweepBus;
    info.swept_Pd_MW = sweptPd;
    info.swept_Qd_MVAr = NaN;
    info.q_mode = string(cfg.qMode);
    info.sweep_pf = cfg.sweepPF;
    info.total_Pd_MW = NaN;
    info.total_Qd_MVAr = NaN;
end

%% ========================================================================
% Result extraction
%% ========================================================================
function [summaryRow, busTable, branchTable, genTable] = extractSweepResults(stepId, mpc, results, roleCfg, sweepInfo)
    C = mpConst();
    bus = results.bus;
    branch = results.branch;
    gen = results.gen;
    gencost = mpc.gencost;

    if size(bus, 2) < C.LAM_Q
        bus(:, end+1:C.LAM_Q) = NaN;
    end
    if size(branch, 2) < C.QT
        branch(:, end+1:C.QT) = NaN;
    end

    inService = branch(:, C.BR_STATUS) > 0;
    Pf = branch(:, C.PF);
    Qf = branch(:, C.QF);
    Pt = branch(:, C.PT);
    Qt = branch(:, C.QT);
    Sfrom = sqrt(Pf.^2 + Qf.^2);
    Sto = sqrt(Pt.^2 + Qt.^2);
    rateA = branch(:, C.RATE_A);
    loading = NaN(size(branch, 1), 1);
    hasRate = isfinite(rateA) & rateA > 0;
    loading(hasRate) = max(Sfrom(hasRate), Sto(hasRate)) ./ rateA(hasRate) * 100;
    pLoss = Pf + Pt;
    qLoss = Qf + Qt;

    selectedBusRow = find(bus(:, C.BUS_I) == sweepInfo.sweep_bus, 1);
    if isempty(selectedBusRow)
        selectedLamP = NaN;
        selectedLamQ = NaN;
        selectedVm = NaN;
    else
        selectedLamP = bus(selectedBusRow, C.LAM_P);
        selectedLamQ = bus(selectedBusRow, C.LAM_Q);
        selectedVm = bus(selectedBusRow, C.VM);
    end

    slackBus = getSlackBusId(mpc);
    slackGenRows = gen(:, C.GEN_BUS) == slackBus;
    slackPg = sum(gen(slackGenRows, C.PG), 'omitnan');
    localGenRows = ~slackGenRows;
    localPg = sum(gen(localGenRows, C.PG), 'omitnan');
    totalPg = sum(gen(:, C.PG), 'omitnan');
    totalQg = sum(gen(:, C.QG), 'omitnan');
    totalPd = sum(bus(:, C.PD), 'omitnan');
    totalQd = sum(bus(:, C.QD), 'omitnan');
    totalPLoss = sum(pLoss(inService), 'omitnan');
    totalQLoss = sum(qLoss(inService), 'omitnan');

    objective = NaN;
    if isfield(results, 'f')
        objective = results.f;
    end

    % DLMP-based Cost-to-Load (C2L):
    %   netLoad_i = max(Pd_i - Pg_i_at_same_bus, 0)
    %   C2L_i     = netLoad_i * LAM_P_i
    %   C2L_total = sum_i C2L_i
    % This replaces the older objective_cost / total_Pd ratio while keeping
    % the same summary column name for downstream plots/export compatibility.
    genPgByBus = zeros(size(bus, 1), 1);
    for gg = 1:size(gen, 1)
        if size(gen, 2) >= C.GEN_STATUS && gen(gg, C.GEN_STATUS) <= 0
            continue;
        end
        genBus = gen(gg, C.GEN_BUS);
        busRow = find(bus(:, C.BUS_I) == genBus, 1);
        if ~isempty(busRow)
            genPgByBus(busRow) = genPgByBus(busRow) + gen(gg, C.PG);
        end
    end
    netLoad = max(bus(:, C.PD) - genPgByBus, 0);
    costToLoad = sum(netLoad .* bus(:, C.LAM_P), 'omitnan');

    localShare = localPg ./ max(eps, totalPg);

    summaryRow = struct();
    summaryRow.scenario_id = stepId;
    summaryRow.sweep_step = stepId;
    summaryRow.success = true;
    summaryRow.fail_reason = "";
    summaryRow.sweep_bus = sweepInfo.sweep_bus;
    summaryRow.swept_Pd_MW = sweepInfo.swept_Pd_MW;
    summaryRow.swept_Qd_MVAr = sweepInfo.swept_Qd_MVAr;
    summaryRow.q_mode = sweepInfo.q_mode;
    summaryRow.sweep_pf = sweepInfo.sweep_pf;
    summaryRow.objective_cost = objective;
    summaryRow.cost_to_load_total = costToLoad;
    summaryRow.total_Pd_MW = totalPd;
    summaryRow.total_Qd_MVAr = totalQd;
    summaryRow.total_Pg_MW = totalPg;
    summaryRow.total_Qg_MVAr = totalQg;
    summaryRow.slack_Pg_MW = slackPg;
    summaryRow.local_gen_Pg_MW = localPg;
    summaryRow.local_generation_share = localShare;
    summaryRow.total_P_loss_MW = totalPLoss;
    summaryRow.total_Q_loss_MVAr = totalQLoss;
    summaryRow.min_Vm_pu = min(bus(:, C.VM), [], 'omitnan');
    summaryRow.max_Vm_pu = max(bus(:, C.VM), [], 'omitnan');
    summaryRow.selected_bus_Vm_pu = selectedVm;
    summaryRow.selected_bus_DLMP_LAM_P = selectedLamP;
    summaryRow.selected_bus_DLMP_LAM_Q = selectedLamQ;
    summaryRow.mean_DLMP_LAM_P = mean(bus(:, C.LAM_P), 'omitnan');
    summaryRow.max_DLMP_LAM_P = max(bus(:, C.LAM_P), [], 'omitnan');
    summaryRow.min_DLMP_LAM_P = min(bus(:, C.LAM_P), [], 'omitnan');
    summaryRow.DLMP_spread_LAM_P = summaryRow.max_DLMP_LAM_P - summaryRow.min_DLMP_LAM_P;
    summaryRow.max_branch_loading_percent = max(loading, [], 'omitnan');
    summaryRow.max_branch_flow_MVA = max(max(Sfrom, Sto), [], 'omitnan');

    % Bus long table.
    nBus = size(bus, 1);
    busRole = strings(nBus, 1);
    for i = 1:nBus
        r = roleCfg(roleCfg.bus_id == bus(i, C.BUS_I), :);
        if isempty(r)
            busRole(i) = "Unknown";
        else
            busRole(i) = string(r.role);
        end
    end
    busTable = table( ...
        repmat(stepId, nBus, 1), repmat(stepId, nBus, 1), repmat(sweepInfo.sweep_bus, nBus, 1), repmat(sweepInfo.swept_Pd_MW, nBus, 1), ...
        bus(:, C.BUS_I), busRole, bus(:, C.PD), bus(:, C.QD), bus(:, C.VM), bus(:, C.VA), bus(:, C.LAM_P), bus(:, C.LAM_Q), ...
        bus(:, C.BUS_I) == sweepInfo.sweep_bus, ...
        'VariableNames', {'scenario_id','sweep_step','sweep_bus','swept_Pd_MW','bus_id','role','Pd_MW','Qd_MVAr','Vm_pu','Va_deg','DLMP_LAM_P','DLMP_LAM_Q','is_sweep_bus'});

    % Branch long table.
    nBranch = size(branch, 1);
    branchTable = table( ...
        repmat(stepId, nBranch, 1), (1:nBranch)', repmat(sweepInfo.sweep_bus, nBranch, 1), repmat(sweepInfo.swept_Pd_MW, nBranch, 1), ...
        branch(:, C.F_BUS), branch(:, C.T_BUS), branch(:, C.BR_STATUS), branch(:, C.RATE_A), ...
        branch(:, C.PF), branch(:, C.QF), branch(:, C.PT), branch(:, C.QT), pLoss, qLoss, loading, ...
        'VariableNames', {'scenario_id','branch_id','sweep_bus','swept_Pd_MW','f_bus','t_bus','branch_status','RATE_A','Pf_MW','Qf_MVAr','Pt_MW','Qt_MVAr','P_loss_MW','Q_loss_MVAr','loading_percent'});

    % Generator long table.
    nGen = size(gen, 1);
    genRole = strings(nGen, 1);
    c2 = NaN(nGen, 1); c1 = NaN(nGen, 1); c0 = NaN(nGen, 1);
    for g = 1:nGen
        r = roleCfg(roleCfg.bus_id == gen(g, C.GEN_BUS), :);
        if isempty(r)
            genRole(g) = "Unknown";
        else
            genRole(g) = string(r.role);
        end
        if size(gencost, 1) >= g && size(gencost, 2) >= 7
            c2(g) = gencost(g, 5);
            c1(g) = gencost(g, 6);
            c0(g) = gencost(g, 7);
        end
    end
    genTable = table( ...
        repmat(stepId, nGen, 1), (1:nGen)', repmat(sweepInfo.sweep_bus, nGen, 1), repmat(sweepInfo.swept_Pd_MW, nGen, 1), ...
        gen(:, C.GEN_BUS), genRole, gen(:, C.PG), gen(:, C.QG), gen(:, C.PMIN), gen(:, C.PMAX), gen(:, C.QMIN), gen(:, C.QMAX), c2, c1, c0, ...
        'VariableNames', {'scenario_id','gen_id','sweep_bus','swept_Pd_MW','gen_bus','role','Pg_MW','Qg_MVAr','Pmin_MW','Pmax_MW','Qmin_MVAr','Qmax_MVAr','c2','c1','c0'});
end

function summaryRow = makeFailedSummaryRow(stepId, sweepInfo, reason)
    fields = {'scenario_id','sweep_step','success','fail_reason','sweep_bus','swept_Pd_MW','swept_Qd_MVAr','q_mode','sweep_pf', ...
        'objective_cost','cost_to_load_total','total_Pd_MW','total_Qd_MVAr','total_Pg_MW','total_Qg_MVAr','slack_Pg_MW','local_gen_Pg_MW', ...
        'local_generation_share','total_P_loss_MW','total_Q_loss_MVAr','min_Vm_pu','max_Vm_pu','selected_bus_Vm_pu', ...
        'selected_bus_DLMP_LAM_P','selected_bus_DLMP_LAM_Q','mean_DLMP_LAM_P','max_DLMP_LAM_P','min_DLMP_LAM_P','DLMP_spread_LAM_P','max_branch_loading_percent','max_branch_flow_MVA'};
    summaryRow = cell2struct(cell(size(fields)), fields, 2);
    summaryRow.scenario_id = stepId;
    summaryRow.sweep_step = stepId;
    summaryRow.success = false;
    summaryRow.fail_reason = string(reason);
    summaryRow.sweep_bus = sweepInfo.sweep_bus;
    summaryRow.swept_Pd_MW = sweepInfo.swept_Pd_MW;
    summaryRow.swept_Qd_MVAr = sweepInfo.swept_Qd_MVAr;
    summaryRow.q_mode = sweepInfo.q_mode;
    summaryRow.sweep_pf = sweepInfo.sweep_pf;
    for k = 10:numel(fields)
        if isempty(summaryRow.(fields{k}))
            summaryRow.(fields{k}) = NaN;
        end
    end
end

%% ========================================================================
% Static tables and display helpers
%% ========================================================================
function T = createBusStaticTable(base_mpc, roleCfg)
    C = mpConst();
    bus = base_mpc.bus;
    n = size(bus, 1);
    role = strings(n, 1);
    for i = 1:n
        r = roleCfg(roleCfg.bus_id == bus(i, C.BUS_I), :);
        if isempty(r)
            role(i) = "Unknown";
        else
            role(i) = string(r.role);
        end
    end
    T = table(bus(:, C.BUS_I), role, bus(:, C.PD), bus(:, C.QD), bus(:, C.VMIN), bus(:, C.VMAX), ...
        'VariableNames', {'bus_id','role','base_Pd_MW','base_Qd_MVAr','base_Vmin_pu','base_Vmax_pu'});
end

function T = createBranchStaticTable(base_mpc)
    C = mpConst();
    br = base_mpc.branch;
    if size(br, 2) < C.ANGMAX
        br(:, end+1:C.ANGMAX) = NaN;
    end
    T = table((1:size(br, 1))', br(:, C.F_BUS), br(:, C.T_BUS), br(:, C.BR_R), br(:, C.BR_X), br(:, C.BR_B), br(:, C.RATE_A), br(:, C.BR_STATUS), ...
        'VariableNames', {'branch_id','f_bus','t_bus','r','x','b','RATE_A','BR_STATUS'});
end

function txt = selectedBusInfoText(busId, base_mpc, roleCfg, busResults)
    C = mpConst();
    idx = find(base_mpc.bus(:, C.BUS_I) == busId, 1);
    if isempty(idx)
        txt = {sprintf('Bus %d not found.', busId)};
        return;
    end
    r = roleCfg(roleCfg.bus_id == busId, :);
    if isempty(r)
        r = createDefaultBusRoleConfig(base_mpc);
        r = r(r.bus_id == busId, :);
    end
    lines = {
        sprintf('BUS %d SUMMARY', busId)
        '----------------------------------------'
        sprintf('Role              : %s', string(r.role))
        sprintf('Base Pd / Qd      : %.6g MW / %.6g MVAr', base_mpc.bus(idx, C.PD), base_mpc.bus(idx, C.QD))
        sprintf('Fixed added Pd    : %.6g MW', r.add_Pd_MW)
        sprintf('Fixed load PF     : %.6g', r.pf)
        sprintf('Pmin / Pmax       : %.6g / %.6g MW', r.Pmin_MW, r.Pmax_MW)
        sprintf('Qmin / Qmax       : %.6g / %.6g MVAr', r.Qmin_MVAr, r.Qmax_MVAr)
        sprintf('Vmin / Vmax       : %.6g / %.6g p.u.', r.Vmin_pu, r.Vmax_pu)
        sprintf('Cost c2/c1/c0     : %.6g / %.6g / %.6g', r.c2, r.c1, r.c0)
        };
    if ~isempty(busResults) && height(busResults) > 0 && any(busResults.bus_id == busId)
        rows = busResults(busResults.bus_id == busId, :);
        last = rows(end, :);
        lines = [lines; {
            ' '
            'LATEST SUCCESSFUL OPF OUTPUT'
            '----------------------------------------'
            sprintf('Swept Pd          : %.6g MW', last.swept_Pd_MW)
            sprintf('Pd / Qd in OPF    : %.6g MW / %.6g MVAr', last.Pd_MW, last.Qd_MVAr)
            sprintf('Vm / Va           : %.6g p.u. / %.6g deg', last.Vm_pu, last.Va_deg)
            sprintf('LAM_P / LAM_Q     : %.6g / %.6g', last.DLMP_LAM_P, last.DLMP_LAM_Q)
            }];
    end
    txt = lines;
end

function clickData = drawCaseTopology(ax, base_mpc, roleCfg, sweepBus, inspectBus)
    C = mpConst();
    cla(ax);
    br = base_mpc.branch;
    if size(br, 2) < C.BR_STATUS
        br(:, end+1:C.BR_STATUS) = 1;
    end
    active = br(:, C.BR_STATUS) > 0;
    s = br(active, C.F_BUS);
    t = br(active, C.T_BUS);
    nBus = size(base_mpc.bus, 1);
    G = graph(s, t, [], nBus);
    p = plot(ax, G, 'Layout', 'layered', 'NodeLabel', compose('%d', 1:nBus));
    p.MarkerSize = 6;
    p.LineWidth = 1.2;
    p.EdgeColor = [0.55 0.55 0.55];
    p.NodeColor = [0.55 0.55 0.55];
    title(ax, 'case33bw Active Topology (BR\_STATUS = 1)');
    axis(ax, 'equal');
    grid(ax, 'off');

    colors = roleColors();
    for k = 1:height(roleCfg)
        b = roleCfg.bus_id(k);
        if b < 1 || b > nBus
            continue;
        end
        c = colors.pq;
        switch string(roleCfg.role(k))
            case "Slack/Grid"
                c = colors.slack;
            case "DER"
                c = colors.der;
            case "Prosumer"
                c = colors.prosumer;
            case "Large Load"
                c = colors.large;
            otherwise
                c = colors.pq;
        end
        highlight(p, b, 'NodeColor', c, 'MarkerSize', 7);
    end
    if isfinite(sweepBus) && sweepBus >= 1 && sweepBus <= nBus
        highlight(p, sweepBus, 'NodeColor', colors.sweep, 'MarkerSize', 10);
    end
    if isfinite(inspectBus) && inspectBus >= 1 && inspectBus <= nBus
        highlight(p, inspectBus, 'MarkerSize', 11);
    end
    clickData = struct('busIds', (1:nBus)', 'x', p.XData(:), 'y', p.YData(:));
end

function colors = roleColors()
    colors = struct();
    colors.slack = [0.00 0.25 0.90];
    colors.pq = [0.55 0.55 0.55];
    colors.der = [0.00 0.55 0.20];
    colors.prosumer = [0.95 0.45 0.05];
    colors.large = [0.85 0.10 0.10];
    colors.sweep = [0.60 0.00 0.80];
end

function items = busIdItems(mpc)
    C = mpConst();
    items = cellstr(string(mpc.bus(:, C.BUS_I)));
end

function pd = defaultBusPd(mpc, busId)
    C = mpConst();
    idx = find(mpc.bus(:, C.BUS_I) == busId, 1);
    if isempty(idx)
        pd = 0;
    else
        pd = mpc.bus(idx, C.PD);
    end
end

function pf = defaultBusPF(mpc, busId)
    C = mpConst();
    idx = find(mpc.bus(:, C.BUS_I) == busId, 1);
    if isempty(idx)
        pf = 0.95;
        return;
    end
    P = abs(mpc.bus(idx, C.PD));
    Q = abs(mpc.bus(idx, C.QD));
    if P <= 0 && Q <= 0
        pf = 0.95;
    else
        pf = P / sqrt(P^2 + Q^2);
        if ~isfinite(pf) || pf <= 0 || pf > 1
            pf = 0.95;
        end
    end
end

function range = parseRangeText(txt, name)
    if isnumeric(txt)
        if numel(txt) ~= 2
            error('%s must contain two values.', name);
        end
        range = reshape(double(txt), 1, 2);
        return;
    end
    s = char(string(txt));
    s = strrep(s, ';', ',');
    nums = sscanf(s, '%f,%f');
    if numel(nums) ~= 2
        nums = sscanf(s, '%f %f');
    end
    if numel(nums) ~= 2 || any(~isfinite(nums))
        error('%s must be written as two numeric values, e.g. "0, 1.0".', name);
    end
    range = reshape(nums, 1, 2);
end

function T = firstNRows(T, N)
    if isempty(T) || height(T) == 0
        return;
    end
    T = T(1:min(N, height(T)), :);
end

function T = vertcatNonEmpty(cells)
    nonEmpty = cells(~cellfun(@(x) isempty(x) || height(x) == 0, cells));
    if isempty(nonEmpty)
        T = table();
    else
        T = vertcat(nonEmpty{:});
    end
end
