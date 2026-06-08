function dashboard_4bus_dlmp_scenario_lab_4_1()
%DASHBOARD_4BUS_DLMP_SCENARIO_LAB
% Interactive 4-bus MATPOWER scenario generator, validation dashboard, and
% econometric output explorer.
%
% Requirements:
%   1) MATLAB
%   2) MATPOWER on the MATLAB path
%
% Run:
%   dashboard_4bus_dlmp_scenario_lab
%
% Notes:
%   - The network topology and generator limits are kept consistent with the
%     provided 4-bus radial 33 kV prosumer case.
%   - Scenario count, random seed, load PDF, power-factor PDF, offer PDF,
%     ranges, validation, and output file name are controlled from the UI.
%   - The output Excel file contains scenario data, static bus/branch data,
%     derived metrics, RUNPF validation diagnostics, validation summary, and
%     econometric model summaries.

    %% -----------------------------
    % App state
    %% -----------------------------
    app = struct();
    app.T = table();
    app.validationTable = table();
    app.validationSummary = table();
    app.econTable = table();
    app.base_mpc = case4bus_radial_33kv_prosumer_dashboard();

    %% -----------------------------
    % UI construction
    %% -----------------------------
    app.fig = uifigure( ...
        'Name', '4-Bus DLMP Scenario Lab | MATPOWER Dashboard', ...
        'Position', [60 60 1500 850]);

% =========================================================
% ROOT LAYOUT: TOP BUTTON BAR + MAIN DASHBOARD
% =========================================================

rootGrid = uigridlayout(app.fig, [2 1]);
rootGrid.RowHeight = {52, '1x'};        % first row is the top button bar
rootGrid.ColumnWidth = {'1x'};
rootGrid.Padding = [10 10 10 10];
rootGrid.RowSpacing = 8;

% =========================================================
% TOP BUTTON BAR
% =========================================================

topButtonGrid               = uigridlayout(rootGrid, [1 4]);
topButtonGrid.Layout.Row    = 1;
topButtonGrid.Layout.Column = 1;

topButtonGrid.ColumnWidth   = {260, 260, 260, '1x'};
topButtonGrid.RowHeight     = {'1x'};
topButtonGrid.Padding       = [0 0 0 0];
topButtonGrid.ColumnSpacing = 10;

app.runButton = uibutton(topButtonGrid, 'push', ...
    'Text', 'Generate Scenarios + Analyze', ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @(~, ~) runGeneration());

app.runButton.Layout.Row        = 1;
app.runButton.Layout.Column     = 1;

app.loadButton = uibutton(topButtonGrid, 'push', ...
    'Text', 'Load Existing Excel + Analyze', ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @(~, ~) loadExistingExcel());

app.loadButton.Layout.Row       = 1;
app.loadButton.Layout.Column    = 2;

app.saveButton = uibutton(topButtonGrid, 'push', ...
    'Text', 'Save Current Results to Excel', ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @(~, ~) saveCurrentResults());

app.saveButton.Layout.Row       = 1;
app.saveButton.Layout.Column    = 3;

app.status = uilabel(topButtonGrid, ...
    'Text', 'Ready.', ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

    app.status.Layout.Row       = 1;
    app.status.Layout.Column    = 4;
    
    % =========================================================
    % MAIN DASHBOARD AREA
    % =========================================================
    
    mainGrid                = uigridlayout(rootGrid, [1 2]);
    mainGrid.Layout.Row     = 2;
    mainGrid.Layout.Column  = 1;
    
    mainGrid.ColumnWidth    = {360, '1x'};
    mainGrid.RowHeight      = {'1x'};
    mainGrid.Padding        = [0 0 0 0];
    mainGrid.ColumnSpacing  = 12;
    controlPanel            = uipanel(mainGrid, 'Title', 'Scenario Controls');
    try
        controlPanel.Scrollable = 'on';
    catch
        % Older MATLAB releases may not support scrollable panels.
    end
    controlPanel.Layout.Row = 1;
    controlPanel.Layout.Column = 1;

    cg = uigridlayout(controlPanel, [30 2]);
    cg.RowHeight = repmat({26}, 1, 30);
    cg.ColumnWidth = {160, '1x'};
    cg.Padding = [10 10 10 10];
    cg.RowSpacing = 6;

    addLabel(cg, 'Scenario count');
    app.nField = uispinner(cg, 'Value', 400, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');

    addLabel(cg, 'Random seed');
    app.seedField = uispinner(cg, 'Value', 42, 'RoundFractionalValues', 'on');

    addLabel(cg, 'Load PDF');
    app.loadPdfDrop = uidropdown(cg, 'Items', pdfItems(), 'Value', 'Uniform');

    addLabel(cg, 'Power factor PDF');
    app.pfPdfDrop = uidropdown(cg, 'Items', pdfItems(), 'Value', 'Uniform');

    addLabel(cg, 'Offer PDF');
    app.offerPdfDrop = uidropdown(cg, 'Items', pdfItems(), 'Value', 'Uniform');

    addSection(cg, 'Demand and PF ranges');

    addLabel(cg, 'Bus 2 Pd [MW]');
    app.pd2Field = uieditfield(cg, 'text', 'Value', '1.60, 2.40');

    addLabel(cg, 'Bus 4 Pd [MW]');
    app.pd4Field = uieditfield(cg, 'text', 'Value', '0.50, 1.10');

    addLabel(cg, 'Bus 2 PF');
    app.pf2Field = uieditfield(cg, 'text', 'Value', '0.88, 0.98');

    addLabel(cg, 'Bus 4 PF');
    app.pf4Field = uieditfield(cg, 'text', 'Value', '0.88, 0.98');

    addSection(cg, 'Offer coefficient ranges');

    addLabel(cg, 'Grid c1');
    app.gridC1Field = uieditfield(cg, 'text', 'Value', '80, 80');

    addLabel(cg, 'DER c1');
    app.derC1Field = uieditfield(cg, 'text', 'Value', '30, 30');

    addLabel(cg, 'Prosumer c1');
    app.proC1Field = uieditfield(cg, 'text', 'Value', '20, 20');

    addLabel(cg, 'Grid c2');
    app.gridC2Field = uieditfield(cg, 'text', 'Value', '0.015, 0.015');

    addLabel(cg, 'DER c2');
    app.derC2Field = uieditfield(cg, 'text', 'Value', '0.010, 0.010');

    addLabel(cg, 'Prosumer c2');
    app.proC2Field = uieditfield(cg, 'text', 'Value', '0.005, 0.005');

    addSection(cg, 'Validation and export');

    addLabel(cg, 'Run validation');
    app.validateCheck = uicheckbox(cg, 'Text', 'RUNPF consistency check', 'Value', true);

    addLabel(cg, 'Output Excel');
    app.outputField = uieditfield(cg, 'text', 'Value', 'dataset_4bus_dashboard.xlsx');

    app.sideStatus = uilabel(cg, 'Text', 'Ready.', 'FontWeight', 'bold');
    app.sideStatus.Layout.Row = 27;
    app.sideStatus.Layout.Column = [1 2];

    app.log = uitextarea(cg, 'Editable', 'off', 'Value', {'Ready. Configure inputs and run.'});
    app.log.Layout.Row = [28 30];
    app.log.Layout.Column = [1 2];

    tabs = uitabgroup(mainGrid);
    tabs.Layout.Row = 1;
    tabs.Layout.Column = 2;

    app.tabOverview = uitab(tabs, 'Title', 'Overview');
    app.tabEconometrics = uitab(tabs, 'Title', 'Econometric Outputs');
    app.tabValidation = uitab(tabs, 'Title', 'Validation Diagnostics');
    app.tabData = uitab(tabs, 'Title', 'Data Preview');

    og = uigridlayout(app.tabOverview, [2 2]);
    og.Padding = [10 10 10 10];
    app.axLoadHist = uiaxes(og); title(app.axLoadHist, 'Load Distribution'); grid(app.axLoadHist, 'off');
    app.axDlmpHist = uiaxes(og); title(app.axDlmpHist, 'DLMP Distribution'); grid(app.axDlmpHist, 'off');
    app.axVoltage = uiaxes(og); title(app.axVoltage, 'Voltage Box Plot Proxy'); grid(app.axVoltage, 'off');
    app.axLoading = uiaxes(og); title(app.axLoading, 'Branch Loading'); grid(app.axLoading, 'off');

    eg = uigridlayout(app.tabEconometrics, [2 3]);
    eg.Padding = [10 10 10 10];
    eg.ColumnWidth = {'1x', '1x', '1x'};

    app.axBus2DlmpDemand = uiaxes(eg);
    title(app.axBus2DlmpDemand, 'Bus 2 DLMP vs Total Demand');
    grid(app.axBus2DlmpDemand, 'off');

    app.axBus3DlmpDemand = uiaxes(eg);
    title(app.axBus3DlmpDemand, 'Bus 3 DLMP vs Total Demand');
    grid(app.axBus3DlmpDemand, 'off');

    app.axBus4DlmpDemand = uiaxes(eg);
    title(app.axBus4DlmpDemand, 'Bus 4 DLMP vs Total Demand');
    grid(app.axBus4DlmpDemand, 'off');

    app.axCostOLS = uiaxes(eg);
    title(app.axCostOLS, 'Objective Cost vs Total Demand');
    grid(app.axCostOLS, 'off');

    app.axLossDemand = uiaxes(eg);
    title(app.axLossDemand, 'Losses vs Total Demand');
    grid(app.axLossDemand, 'off');

    app.axC2LDemand = uiaxes(eg);
    title(app.axC2LDemand, 'Cost-to-Load vs Total Demand');
    grid(app.axC2LDemand, 'off');

    vg = uigridlayout(app.tabValidation, [2 2]);
    vg.Padding = [10 10 10 10];
    vg.ColumnWidth = {'1x', 420};
    app.axValErrors = uiaxes(vg); title(app.axValErrors, 'Validation Error Severity'); grid(app.axValErrors, 'off');
    app.axFailReasons = uiaxes(vg); title(app.axFailReasons, 'Dominant Fail Reasons'); grid(app.axFailReasons, 'off');
    app.validationUITable = uitable(vg, 'Data', table());
    app.validationUITable.Layout.Row = [1 2];
    app.validationUITable.Layout.Column = 2;
    app.validationSummaryArea = uitextarea(vg, 'Editable', 'off', 'Value', {'No validation result yet.'});
    app.validationSummaryArea.Layout.Row = 2;
    app.validationSummaryArea.Layout.Column = 1;

    dg = uigridlayout(app.tabData, [1 1]);
    dg.Padding = [10 10 10 10];
    app.dataUITable = uitable(dg, 'Data', table());

    %% -----------------------------
    % Nested UI helper functions
    %% -----------------------------
    function addLabel(parent, txt)
        uilabel(parent, 'Text', txt, 'HorizontalAlignment', 'right');
    end

    function addSection(parent, txt)
        lab = uilabel(parent, 'Text', txt, 'FontWeight', 'bold');
        lab.Layout.Column = [1 2];
    end

    function items = pdfItems()
        items = {'Uniform', 'Normal-Truncated', 'Triangular', 'Beta(2,2)-Bounded', 'Lognormal-Truncated', 'Two-Peak Mixture'};
    end

    %% -----------------------------
    % Main callbacks
    %% -----------------------------
    function runGeneration()
        try
            app.runButton.Enable = 'off';
            app.status.Text = 'Running OPF scenarios...';
            logMsg('Starting scenario generation.');
            drawnow;

            cfg = readConfigFromUI();
            rng(cfg.seed);

            base_mpc = app.base_mpc;
            mpopt = mpoption('verbose', 0, 'out.all', 0, 'opf.ac.solver', 'MIPS');

            rows = struct([]);
            validCount = 0;
            totalAttempts = 0;
            rejectedCount = 0;
            opfFailCount = 0;

            while validCount < cfg.N
                scenarioSolved = false;
                candidateNo = validCount + 1;

                for attempt = 1:cfg.maxAttemptsPerScenario
                    totalAttempts = totalAttempts + 1;

                    scenario = generateScenarioFromConfig(cfg);
                    [scenario, isValid, validationMessage] = repairAndValidateScenarioDashboard(scenario, cfg.range);
                    if ~isValid
                        rejectedCount = rejectedCount + 1;
                        if attempt == 1 || mod(rejectedCount, 25) == 0
                            logMsg(sprintf('Candidate %d rejected: %s', candidateNo, validationMessage));
                        end
                        continue;
                    end

                    mpc = applyScenarioToMPCDashboard(base_mpc, scenario);

                    try
                        results = runopf(mpc, mpopt);
                    catch ME
                        opfFailCount = opfFailCount + 1;
                        if attempt == 1 || mod(opfFailCount, 25) == 0
                            logMsg(sprintf('Candidate %d OPF error: %s', candidateNo, ME.message));
                        end
                        continue;
                    end

                    if ~results.success
                        opfFailCount = opfFailCount + 1;
                        continue;
                    end

                    validCount = validCount + 1;
                    row = createOneRowRecordDashboard(validCount, scenario, results, attempt, cfg);

                    if validCount == 1
                        rows = row;
                    else
                        rows(validCount) = row;
                    end

                    scenarioSolved = true;
                    if validCount == 1 || mod(validCount, max(1, round(cfg.N/10))) == 0 || validCount == cfg.N
                        app.status.Text = sprintf('Generated %d / %d scenarios', validCount, cfg.N);
                        logMsg(sprintf('Generated %d / %d valid scenarios. Attempts: %d', validCount, cfg.N, totalAttempts));
                        drawnow limitrate;
                    end
                    break;
                end

                if ~scenarioSolved
                    error('Could not generate candidate %d after %d attempts. Try wider ranges or a different PDF.', candidateNo, cfg.maxAttemptsPerScenario);
                end
            end

            app.T = struct2table(rows);
            app.T = addDerivedMetrics(app.T);

            app.econTable = runEconometricModels(app.T);

            if cfg.runValidation
                logMsg('RUNPF validation started.');
                tol = defaultValidationTolerances();
                [app.validationTable, app.validationSummary] = validateScenarioTableWithRunpf(app.T, base_mpc, tol);
                logMsg('RUNPF validation completed.');
            else
                app.validationTable = table();
                app.validationSummary = table();
            end

            updateAllPlots();
            updateTables();
            saveCurrentResults();

            app.status.Text = sprintf('Done. %d scenarios generated.', height(app.T));
            logMsg(sprintf('Done. Excel output: %s', cfg.outputFile));
        catch ME
            app.status.Text = 'Error.';
            logMsg(sprintf('ERROR: %s', ME.message));
            uialert(app.fig, ME.message, 'Dashboard Error');
        end
        app.runButton.Enable = 'on';
    end

    function loadExistingExcel()
        try
            [file, path] = uigetfile('*.xlsx', 'Select scenario dataset Excel file');
            if isequal(file, 0)
                return;
            end
            fullName = fullfile(path, file);
            logMsg(sprintf('Loading %s', fullName));

            T = readtable(fullName, 'Sheet', 'scenario_dataset');
            app.T = addDerivedMetrics(T);
            app.econTable = runEconometricModels(app.T);

            if app.validateCheck.Value
                tol = defaultValidationTolerances();
                [app.validationTable, app.validationSummary] = validateScenarioTableWithRunpf(app.T, app.base_mpc, tol);
            else
                app.validationTable = table();
                app.validationSummary = table();
            end

            updateAllPlots();
            updateTables();
            app.outputField.Value = file;
            app.status.Text = sprintf('Loaded %d rows.', height(app.T));
            logMsg('Existing Excel analysis completed.');
        catch ME
            app.status.Text = 'Error.';
            logMsg(sprintf('ERROR loading Excel: %s', ME.message));
            uialert(app.fig, ME.message, 'Load Error');
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
                outputFile = 'dataset_4bus_dashboard.xlsx';
            end
            % Append current date-time stamp to the filename (before extension)
            % Format: YYYYMMDD_HHMMSS
            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            [p, n, e] = fileparts(outputFile);
            newName = sprintf('%s_%s%s', n, stamp, e);
            if isempty(p)
                outputFile = newName;
            else
                outputFile = fullfile(p, newName);
            end

            if isfile(outputFile)
                delete(outputFile);
            end

            exportTable = selectScenarioExportColumns(app.T);

            writetable(exportTable, outputFile, 'Sheet', 'scenario_dataset');
            writetable(createBusStaticTableDashboard(app.base_mpc), outputFile, 'Sheet', 'bus_static');
            writetable(createBranchStaticTableDashboard(app.base_mpc), outputFile, 'Sheet', 'branch_static');
            writetable(selectDerivedMetrics(app.T), outputFile, 'Sheet', 'derived_metrics');

            if ~isempty(app.validationTable)
                writetable(app.validationTable, outputFile, 'Sheet', 'runpf_validation');
            end
            if ~isempty(app.validationSummary)
                writetable(app.validationSummary, outputFile, 'Sheet', 'validation_summary');
            end
            % Econometric model table is intentionally not exported.
            % The dashboard now focuses on visual input-output relationships.

            logMsg(sprintf('Saved Excel file: %s', outputFile));
        catch ME
            logMsg(sprintf('ERROR saving Excel: %s', ME.message));
            uialert(app.fig, ME.message, 'Save Error');
        end
    end

    %% -----------------------------
    % UI update functions
    %% -----------------------------
    function updateTables()
        if ~isempty(app.T)
            app.dataUITable.Data = firstNRows(app.T, 100);
        end
        % Econometric output table removed intentionally.
        % This tab now focuses on direct input-output scatter relations.
        if ~isempty(app.validationTable)
            app.validationUITable.Data = firstNRows(app.validationTable, 100);
            app.validationSummaryArea.Value = validationSummaryText(app.validationSummary);
        else
            app.validationUITable.Data = table();
            app.validationSummaryArea.Value = {'Validation was not run.'};
        end
    end

    function updateAllPlots()
        T = app.T;
        if isempty(T) || height(T) == 0
            return;
        end

        cla(app.axLoadHist); cla(app.axDlmpHist); cla(app.axVoltage); cla(app.axLoading);
        cla(app.axBus2DlmpDemand); cla(app.axBus3DlmpDemand); cla(app.axBus4DlmpDemand);
        cla(app.axCostOLS); cla(app.axLossDemand); cla(app.axC2LDemand);
        cla(app.axValErrors); cla(app.axFailReasons);

        %% Overview plots
        histogram(app.axLoadHist, T.total_Pd_MW, max(10, round(sqrt(height(T)))));
        xlabel(app.axLoadHist, 'Total Pd [MW]');
        ylabel(app.axLoadHist, 'Count');
        title(app.axLoadHist, 'Total Demand Distribution');
        grid(app.axLoadHist, 'off');

        dlmpVars = {'out_bus1_DLMP_LAM_P', 'out_bus2_DLMP_LAM_P', 'out_bus3_DLMP_LAM_P', 'out_bus4_DLMP_LAM_P'};
        hold(app.axDlmpHist, 'on');
        for i = 1:numel(dlmpVars)
            histogram(app.axDlmpHist, T.(dlmpVars{i}), 'DisplayStyle', 'stairs');
        end
        hold(app.axDlmpHist, 'off');
        xlabel(app.axDlmpHist, 'LAM_P');
        ylabel(app.axDlmpHist, 'Count');
        title(app.axDlmpHist, 'Bus-Level Active DLMP Distribution');
        legend(app.axDlmpHist, {'Bus 1','Bus 2','Bus 3','Bus 4'}, 'Location', 'best');
        grid(app.axDlmpHist, 'off');

        V = [T.out_bus1_Vm_pu, T.out_bus2_Vm_pu, T.out_bus3_Vm_pu, T.out_bus4_Vm_pu];
        plot(app.axVoltage, 1:4, mean(V, 1), '-o');
        hold(app.axVoltage, 'on');
        plot(app.axVoltage, 1:4, min(V, [], 1), '--');
        plot(app.axVoltage, 1:4, max(V, [], 1), '--');
        hold(app.axVoltage, 'off');
        xticks(app.axVoltage, 1:4);
        xlabel(app.axVoltage, 'Bus'); ylabel(app.axVoltage, 'Vm [p.u.]');
        title(app.axVoltage, 'Voltage Mean / Min / Max');
        legend(app.axVoltage, {'Mean','Min','Max'}, 'Location', 'best');
        grid(app.axVoltage, 'off');

        L = [T.out_branch1_loading_percent, T.out_branch2_loading_percent, T.out_branch3_loading_percent];
        plot(app.axLoading, L, '.');
        xlabel(app.axLoading, 'Scenario'); ylabel(app.axLoading, 'Loading [%]');
        title(app.axLoading, 'Branch Loading by Scenario');
        legend(app.axLoading, {'Branch 1','Branch 2','Branch 3'}, 'Location', 'best');
        grid(app.axLoading, 'off');

        %% Econometric / input-output relation plots
        % Bus 1 is the slack/reference bus, so the demand-DLMP relation plots
        % focus on Bus 2, Bus 3, and Bus 4.
        % The red line on the right y-axis is the Total Pd distribution.
        plotDLMPScatterWithDemandDistribution(app.axBus2DlmpDemand, ...
            T.total_Pd_MW, T.out_bus2_DLMP_LAM_P, ...
            'Total Pd [MW]', 'Bus 2 DLMP LAM_P', ...
            'Bus 2 DLMP vs Total Demand');

        plotDLMPScatterWithDemandDistribution(app.axBus3DlmpDemand, ...
            T.total_Pd_MW, T.out_bus3_DLMP_LAM_P, ...
            'Total Pd [MW]', 'Bus 3 DLMP LAM_P', ...
            'Bus 3 DLMP vs Total Demand');

        plotDLMPScatterWithDemandDistribution(app.axBus4DlmpDemand, ...
            T.total_Pd_MW, T.out_bus4_DLMP_LAM_P, ...
            'Total Pd [MW]', 'Bus 4 DLMP LAM_P', ...
            'Bus 4 DLMP vs Total Demand');

        plotInputOutputScatter(app.axCostOLS, T.total_Pd_MW, T.objective_cost, ...
            'Total Pd [MW]', 'Objective Cost', ...
            'Objective Cost vs Total Demand');

        plotInputOutputScatter(app.axLossDemand, T.total_Pd_MW, T.total_P_loss_MW, ...
            'Total Pd [MW]', 'Total P Loss [MW]', ...
            'Losses vs Total Demand');

        plotInputOutputScatter(app.axC2LDemand, T.total_Pd_MW, T.cost_to_load_total, ...
            'Total Pd [MW]', 'Cost-to-Load', ...
            'C2L vs Total Demand');

        %% Validation plots
        if ~isempty(app.validationTable) && height(app.validationTable) > 0
            Vt = app.validationTable;
            severity = [Vt.max_abs_Vm_error ./ 1e-5, Vt.max_abs_Va_error ./ 1e-3, ...
                        Vt.max_abs_Pf_error ./ 1e-4, Vt.max_abs_Qf_error ./ 1e-4, ...
                        Vt.max_abs_loading_error ./ 1e-3];
            plot(app.axValErrors, severity, '.');
            yline(app.axValErrors, 1, '--');
            xlabel(app.axValErrors, 'Scenario'); ylabel(app.axValErrors, 'Error / Tolerance');
            title(app.axValErrors, 'Validation Error Severity');
            legend(app.axValErrors, {'Vm','Va','Pf','Qf','Loading','Pass threshold'}, 'Location', 'best');
            grid(app.axValErrors, 'off');

            failRows = Vt(Vt.runpf_success == 1 & Vt.validation_pass == 0, :);
            if height(failRows) > 0
                cats = categorical(failRows.dominant_fail_reason);
                histogram(app.axFailReasons, cats);
                title(app.axFailReasons, 'Dominant Reasons for PF Success + Validation Fail');
                ylabel(app.axFailReasons, 'Count');
                grid(app.axFailReasons, 'off');
            else
                text(app.axFailReasons, 0.1, 0.5, 'No PF-success / validation-fail cases.', 'Units', 'normalized');
                axis(app.axFailReasons, 'off');
            end
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

    function cfg = readConfigFromUI()
        cfg                 = struct();
        cfg.N               = max(1, round(app.nField.Value));
        cfg.seed            = round(app.seedField.Value);
        cfg.loadPDF         = app.loadPdfDrop.Value;
        cfg.pfPDF           = app.pfPdfDrop.Value;
        cfg.offerPDF        = app.offerPdfDrop.Value;
        cfg.runValidation   = app.validateCheck.Value;
        cfg.outputFile      = strtrim(app.outputField.Value);
        cfg.maxAttemptsPerScenario = 100;

        r = struct();
        r.Pd2 = parseRange(app.pd2Field.Value, 'Bus 2 Pd');
        r.Pd4 = parseRange(app.pd4Field.Value, 'Bus 4 Pd');
        r.pf2 = parseRange(app.pf2Field.Value, 'Bus 2 PF');
        r.pf4 = parseRange(app.pf4Field.Value, 'Bus 4 PF');

        r.grid_c1 = parseRange(app.gridC1Field.Value, 'Grid c1');
        r.der_c1 = parseRange(app.derC1Field.Value, 'DER c1');
        r.pro_c1 = parseRange(app.proC1Field.Value, 'Prosumer c1');

        r.grid_c2 = parseRange(app.gridC2Field.Value, 'Grid c2');
        r.der_c2 = parseRange(app.derC2Field.Value, 'DER c2');
        r.pro_c2 = parseRange(app.proC2Field.Value, 'Prosumer c2');

        r.grid_c0 = [0 0];
        r.der_c0 = [0 0];
        r.pro_c0 = [0 0];
        cfg.range = r;

        if isempty(cfg.outputFile)
            cfg.outputFile = 'dataset_4bus_dashboard.xlsx';
        end
    end
end

%% ========================================================================
% Local computational functions
%% ========================================================================
function rangePair = parseRange(txt, label)
    if isnumeric(txt)
        vals = txt;
    else
        vals = sscanf(char(txt), '%f%*[,; ]%f');
    end
    if numel(vals) ~= 2
        error('%s must be entered as two numbers, for example: 1.60, 2.40', label);
    end
    rangePair = vals(:)';
    if rangePair(1) > rangePair(2)
        error('%s has min greater than max.', label);
    end
end

function scenario = generateScenarioFromConfig(cfg)
    r = cfg.range;

    scenario.Pd2 = sampleByPDF(r.Pd2, cfg.loadPDF);
    scenario.Pd4 = sampleByPDF(r.Pd4, cfg.loadPDF);
    scenario.pf2 = sampleByPDF(r.pf2, cfg.pfPDF);
    scenario.pf4 = sampleByPDF(r.pf4, cfg.pfPDF);

    scenario.Qd2 = calcQfromPandPFDashboard(scenario.Pd2, scenario.pf2);
    scenario.Qd4 = calcQfromPandPFDashboard(scenario.Pd4, scenario.pf4);
    scenario.Pd3 = 0;
    scenario.Qd3 = 0;

    scenario.grid_c2 = sampleByPDF(r.grid_c2, cfg.offerPDF);
    scenario.grid_c1 = sampleByPDF(r.grid_c1, cfg.offerPDF);
    scenario.grid_c0 = sampleByPDF(r.grid_c0, cfg.offerPDF);

    scenario.der_c2 = sampleByPDF(r.der_c2, cfg.offerPDF);
    scenario.der_c1 = sampleByPDF(r.der_c1, cfg.offerPDF);
    scenario.der_c0 = sampleByPDF(r.der_c0, cfg.offerPDF);

    scenario.pro_c2 = sampleByPDF(r.pro_c2, cfg.offerPDF);
    scenario.pro_c1 = sampleByPDF(r.pro_c1, cfg.offerPDF);
    scenario.pro_c0 = sampleByPDF(r.pro_c0, cfg.offerPDF);

    scenario.load_pdf = string(cfg.loadPDF);
    scenario.pf_pdf = string(cfg.pfPDF);
    scenario.offer_pdf = string(cfg.offerPDF);
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
            mu = 0.5;
            sigma = 1/6;
            x = truncatedNormal01(mu, sigma);

        case 'Triangular'
            % Symmetric triangular distribution on [0, 1].
            if u < 0.5
                x = sqrt(0.5 * u);
            else
                x = 1 - sqrt(0.5 * (1 - u));
            end

        case 'Beta(2,2)-Bounded'
            % Exact Beta(2,2) using Gamma(2,1) from exponential sums.
            g1 = -log(max(realmin, rand() * rand()));
            g2 = -log(max(realmin, rand() * rand()));
            x = g1 / (g1 + g2);

        case 'Lognormal-Truncated'
            % Right-skewed distribution, truncated to [0, 1].
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

function [scenario, isValid, message] = repairAndValidateScenarioDashboard(scenario, range)
    isValid = true;
    message = 'OK';

    scenario.Pd2 = clampToRangeDashboard(scenario.Pd2, range.Pd2);
    scenario.Pd4 = clampToRangeDashboard(scenario.Pd4, range.Pd4);
    scenario.pf2 = clampToRangeDashboard(scenario.pf2, range.pf2);
    scenario.pf4 = clampToRangeDashboard(scenario.pf4, range.pf4);

    scenario.Qd2 = calcQfromPandPFDashboard(scenario.Pd2, scenario.pf2);
    scenario.Qd4 = calcQfromPandPFDashboard(scenario.Pd4, scenario.pf4);
    scenario.Pd3 = 0;
    scenario.Qd3 = 0;

    scenario.grid_c2 = clampToRangeDashboard(scenario.grid_c2, range.grid_c2);
    scenario.grid_c1 = clampToRangeDashboard(scenario.grid_c1, range.grid_c1);
    scenario.grid_c0 = clampToRangeDashboard(scenario.grid_c0, range.grid_c0);
    scenario.der_c2 = clampToRangeDashboard(scenario.der_c2, range.der_c2);
    scenario.der_c1 = clampToRangeDashboard(scenario.der_c1, range.der_c1);
    scenario.der_c0 = clampToRangeDashboard(scenario.der_c0, range.der_c0);
    scenario.pro_c2 = clampToRangeDashboard(scenario.pro_c2, range.pro_c2);
    scenario.pro_c1 = clampToRangeDashboard(scenario.pro_c1, range.pro_c1);
    scenario.pro_c0 = clampToRangeDashboard(scenario.pro_c0, range.pro_c0);

    if scenario.Pd2 <= 0 || scenario.Pd4 <= 0
        isValid = false; message = 'Negative or zero active load detected.'; return;
    end
    if scenario.pf2 <= 0 || scenario.pf2 > 1 || scenario.pf4 <= 0 || scenario.pf4 > 1
        isValid = false; message = 'Invalid power factor detected.'; return;
    end
    if scenario.Qd2 < 0 || scenario.Qd4 < 0
        isValid = false; message = 'Negative reactive load detected.'; return;
    end
    if scenario.grid_c2 < 0 || scenario.der_c2 < 0 || scenario.pro_c2 < 0
        isValid = false; message = 'Negative quadratic offer coefficient detected.'; return;
    end
 
    % [mcOK, mcMessage] = checkMarginalCostOrderingDashboard(scenario);
    % if ~mcOK
    %     isValid = false; message = mcMessage; return;
    % end
end

function mpc = applyScenarioToMPCDashboard(base_mpc, scenario)
    define_constants;
    mpc = base_mpc;

    mpc.bus(2, PD) = scenario.Pd2;
    mpc.bus(2, QD) = scenario.Qd2;
    mpc.bus(3, PD) = 0;
    mpc.bus(3, QD) = 0;
    mpc.bus(4, PD) = scenario.Pd4;
    mpc.bus(4, QD) = scenario.Qd4;

    mpc.gencost(1, 5) = scenario.grid_c2;
    mpc.gencost(1, 6) = scenario.grid_c1;
    mpc.gencost(1, 7) = scenario.grid_c0;
    mpc.gencost(2, 5) = scenario.der_c2;
    mpc.gencost(2, 6) = scenario.der_c1;
    mpc.gencost(2, 7) = scenario.der_c0;
    mpc.gencost(3, 5) = scenario.pro_c2;
    mpc.gencost(3, 6) = scenario.pro_c1;
    mpc.gencost(3, 7) = scenario.pro_c0;
end

function row = createOneRowRecordDashboard(scenario_id, scenario, results, attempt, cfg)
    define_constants;
    row = struct();

    row.scenario_id = scenario_id;
    row.opf_success = results.success;
    row.objective_cost = results.f;
    row.attempt_no = attempt;
    row.load_pdf = scenario.load_pdf;
    row.pf_pdf = scenario.pf_pdf;
    row.offer_pdf = scenario.offer_pdf;
    row.N_requested = cfg.N;

    row.in_bus2_Pd_MW = scenario.Pd2;
    row.in_bus2_Qd_MVAr = scenario.Qd2;
    row.in_bus2_pf = scenario.pf2;
    row.in_bus3_Pd_MW = scenario.Pd3;
    row.in_bus3_Qd_MVAr = scenario.Qd3;
    row.in_bus4_Pd_MW = scenario.Pd4;
    row.in_bus4_Qd_MVAr = scenario.Qd4;
    row.in_bus4_pf = scenario.pf4;

    row.in_grid_c2 = scenario.grid_c2;
    row.in_grid_c1 = scenario.grid_c1;
    row.in_grid_c0 = scenario.grid_c0;
    row.in_der_c2 = scenario.der_c2;
    row.in_der_c1 = scenario.der_c1;
    row.in_der_c0 = scenario.der_c0;
    row.in_prosumer_c2 = scenario.pro_c2;
    row.in_prosumer_c1 = scenario.pro_c1;
    row.in_prosumer_c0 = scenario.pro_c0;

    for b = 1:4
        prefix = sprintf('out_bus%d_', b);
        row.([prefix 'Vm_pu']) = results.bus(b, VM);
        row.([prefix 'Va_deg']) = results.bus(b, VA);
        row.([prefix 'DLMP_LAM_P']) = results.bus(b, LAM_P);
        row.([prefix 'DLMP_LAM_Q']) = results.bus(b, LAM_Q);
    end

    row.out_grid_Pg_MW = results.gen(1, PG);
    row.out_grid_Qg_MVAr = results.gen(1, QG);
    row.out_der_Pg_MW = results.gen(2, PG);
    row.out_der_Qg_MVAr = results.gen(2, QG);
    row.out_prosumer_Pg_MW = results.gen(3, PG);
    row.out_prosumer_Qg_MVAr = results.gen(3, QG);

    for br = 1:3
        prefix = sprintf('out_branch%d_', br);
        Pf = results.branch(br, PF);
        Pt = results.branch(br, PT);
        Qf = results.branch(br, QF);
        Qt = results.branch(br, QT);
        Sf = sqrt(Pf^2 + Qf^2);
        St = sqrt(Pt^2 + Qt^2);
        rateA = results.branch(br, RATE_A);
        row.([prefix 'Pf_MW']) = Pf;
        row.([prefix 'Pt_MW']) = Pt;
        row.([prefix 'Qf_MVAr']) = Qf;
        row.([prefix 'Qt_MVAr']) = Qt;
        row.([prefix 'P_loss_MW']) = Pf + Pt;
        row.([prefix 'Q_loss_MVAr']) = Qf + Qt;
        row.([prefix 'loading_percent']) = 100 * max(Sf, St) / rateA;
    end
end

function T = addDerivedMetrics(T)
    if isempty(T)
        return;
    end

    % Backward compatibility with earlier datasets that did not export LAM_Q.
    for b = 1:4
        qName = sprintf('out_bus%d_DLMP_LAM_Q', b);
        if ~ismember(qName, T.Properties.VariableNames)
            T.(qName) = NaN(height(T), 1);
        end
    end

    T.total_Pd_MW = T.in_bus2_Pd_MW + T.in_bus3_Pd_MW + T.in_bus4_Pd_MW;
    T.total_Qd_MVAr = T.in_bus2_Qd_MVAr + T.in_bus3_Qd_MVAr + T.in_bus4_Qd_MVAr;
    T.total_P_loss_MW = T.out_branch1_P_loss_MW + T.out_branch2_P_loss_MW + T.out_branch3_P_loss_MW;
    T.total_Q_loss_MVAr = T.out_branch1_Q_loss_MVAr + T.out_branch2_Q_loss_MVAr + T.out_branch3_Q_loss_MVAr;
    T.max_branch_loading_percent = max([T.out_branch1_loading_percent, T.out_branch2_loading_percent, T.out_branch3_loading_percent], [], 2);

    dlmpP = [T.out_bus1_DLMP_LAM_P, T.out_bus2_DLMP_LAM_P, T.out_bus3_DLMP_LAM_P, T.out_bus4_DLMP_LAM_P];
    dlmpQ = [T.out_bus1_DLMP_LAM_Q, T.out_bus2_DLMP_LAM_Q, T.out_bus3_DLMP_LAM_Q, T.out_bus4_DLMP_LAM_Q];
    T.mean_DLMP_LAM_P = mean(dlmpP, 2);
    T.DLMP_spread_LAM_P = max(dlmpP, [], 2) - min(dlmpP, [], 2);
    T.mean_DLMP_LAM_Q = mean(dlmpQ, 2);
    T.DLMP_spread_LAM_Q = max(dlmpQ, [], 2) - min(dlmpQ, [], 2);
    T.local_generation_MW = T.out_der_Pg_MW + T.out_prosumer_Pg_MW;
    T.local_generation_share = T.local_generation_MW ./ max(eps, (T.out_grid_Pg_MW + T.local_generation_MW));

    % Cost-to-Load (C2L): customer net load at each non-slack bus multiplied
    % by that bus' active DLMP. Positive net load is billed; negative net load
    % is not counted as customer payment in this metric.
    T.net_load_bus2_MW = max(T.in_bus2_Pd_MW, 0);
    T.net_load_bus3_MW = max(T.in_bus3_Pd_MW - T.out_der_Pg_MW, 0);
    T.net_load_bus4_MW = max(T.in_bus4_Pd_MW - T.out_prosumer_Pg_MW, 0);

    T.cost_to_load_bus2 = T.net_load_bus2_MW .* T.out_bus2_DLMP_LAM_P;
    T.cost_to_load_bus3 = T.net_load_bus3_MW .* T.out_bus3_DLMP_LAM_P;
    T.cost_to_load_bus4 = T.net_load_bus4_MW .* T.out_bus4_DLMP_LAM_P;
    T.cost_to_load_total = T.cost_to_load_bus2 + T.cost_to_load_bus3 + T.cost_to_load_bus4;
end

function derived = selectDerivedMetrics(T)
    cols = {'scenario_id','total_Pd_MW','total_Qd_MVAr','objective_cost', ...
            'total_P_loss_MW','total_Q_loss_MVAr','max_branch_loading_percent', ...
            'mean_DLMP_LAM_P','DLMP_spread_LAM_P','mean_DLMP_LAM_Q','DLMP_spread_LAM_Q', ...
            'local_generation_MW','local_generation_share', ...
            'net_load_bus2_MW','net_load_bus3_MW','net_load_bus4_MW', ...
            'cost_to_load_bus2','cost_to_load_bus3','cost_to_load_bus4','cost_to_load_total'};
    cols = cols(ismember(cols, T.Properties.VariableNames));
    derived = T(:, cols);
end

function exportTable = selectScenarioExportColumns(T)
    cols = {'scenario_id', ...
            'in_bus2_Pd_MW', 'in_bus2_Qd_MVAr', ...
            'in_bus4_Pd_MW', 'in_bus4_Qd_MVAr', ...
            'in_grid_c2', 'in_grid_c1', ...
            'in_der_c2', 'in_der_c1', ...
            'in_prosumer_c2', 'in_prosumer_c1', ...
            'out_bus1_Vm_pu', 'out_bus1_Va_deg', 'out_bus1_DLMP_LAM_P', ...
            'out_bus2_Vm_pu', 'out_bus2_Va_deg', 'out_bus2_DLMP_LAM_P', ...
            'out_bus3_Vm_pu', 'out_bus3_Va_deg', 'out_bus3_DLMP_LAM_P', ...
            'out_bus4_Vm_pu', 'out_bus4_Va_deg', 'out_bus4_DLMP_LAM_P', ...
            'out_grid_Pg_MW', 'out_grid_Qg_MVAr', ...
            'out_der_Pg_MW', 'out_der_Qg_MVAr', ...
            'out_prosumer_Pg_MW', 'out_prosumer_Qg_MVAr'};
    cols = cols(ismember(cols, T.Properties.VariableNames));
    exportTable = T(:, cols);
end

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

    [coef, r2, rmse] = olsSummary(T.out_grid_Pg_MW, [T.total_Pd_MW, T.out_der_Pg_MW, T.out_prosumer_Pg_MW], ...
        {'total_Pd_MW','out_der_Pg_MW','out_prosumer_Pg_MW'});
    modelRows(end+1, :) = {'M4', 'out_grid_Pg_MW', 'grid_dispatch ~ total_Pd + DER_Pg + prosumer_Pg', coef, r2, rmse, height(T)};

    econTable = cell2table(modelRows, 'VariableNames', {'model_id','dependent_variable','formula','coefficients','R_squared','RMSE','N'});
end

function [coefString, r2, rmse] = olsSummary(y, Xraw, names)
    X = [ones(size(Xraw,1),1), Xraw];
    [yhat, residuals, beta] = simpleOLS(y, X);
    sst = sum((y - mean(y)).^2);
    sse = sum(residuals.^2);
    if sst > 0
        r2 = 1 - sse / sst;
    else
        r2 = NaN;
    end
    rmse = sqrt(mean(residuals.^2));

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
        ylabel(ax, 'Total Pd distribution [count]');
    else
        ylabel(ax, 'Total Pd distribution [count]');
    end

    yyaxis(ax, 'left');
end

function X = tableToNumericMatrix(T, vars)
    X = zeros(height(T), numel(vars));
    for i = 1:numel(vars)
        X(:, i) = T.(vars{i});
    end
end

function out = firstNRows(T, N)
    if isempty(T)
        out = table();
    else
        out = T(1:min(N, height(T)), :);
    end
end

function txt = validationSummaryText(summaryTable)
    if isempty(summaryTable)
        txt = {'No validation summary.'};
        return;
    end

    s = summaryTable(1, :);
    txt = {
        sprintf('Rows checked: %d', s.number_of_excel_rows)
        sprintf('RUNPF success: %d / %d', s.number_of_runpf_success, s.number_of_excel_rows)
        sprintf('Validation pass: %d / %d', s.number_of_validation_pass, s.number_of_excel_rows)
        sprintf('Validation mismatch: %d', s.number_of_validation_mismatch)
        sprintf('Max Vm error: %.3g p.u.', s.max_abs_Vm_error)
        sprintf('Max Va error: %.3g deg', s.max_abs_Va_error)
        sprintf('Max checked Pg error: %.3g MW', s.max_abs_checked_Pg_error)
        sprintf('Max checked Qg error: %.3g MVAr', s.max_abs_checked_Qg_error)
        sprintf('Max branch loading error: %.3g %%', s.max_abs_loading_error)
        ''
        'Interpretation:'
        'RUNPF success = the reconstructed physical power-flow problem converged.'
        'Validation pass = the reconstructed RUNPF values match the OPF Excel outputs within strict tolerances.'
        'PF success + validation fail usually means the PF solved, but not to the exact same OPF-consistent numerical point.'
        'Typical causes: slack Pg/Qg dependency, PV-bus Qg dependency, OPF voltage/branch constraints, and very tight tolerances.'
        };
end

function tol = defaultValidationTolerances()
    tol = struct();
    tol.Vm = 1e-5;
    tol.Va = 1e-3;
    tol.P = 1e-4;
    tol.Q = 1e-4;
    tol.loading = 1e-3;
end

function [validationTable, summaryTable] = validateScenarioTableWithRunpf(T, base_mpc, tol)
    define_constants;
    N = height(T);
    validationRows = struct([]);
    nRunpfSuccess = 0;
    nRunpfFail = 0;
    nValidationPass = 0;
    nValidationMismatch = 0;

    mpopt = mpoption('verbose', 0, 'out.all', 0);

    for k = 1:N
        mpc = base_mpc;

        mpc.bus(2, PD) = T.in_bus2_Pd_MW(k);
        mpc.bus(2, QD) = T.in_bus2_Qd_MVAr(k);
        mpc.bus(3, PD) = 0;
        mpc.bus(3, QD) = 0;
        mpc.bus(4, PD) = T.in_bus4_Pd_MW(k);
        mpc.bus(4, QD) = T.in_bus4_Qd_MVAr(k);

        mpc.gen(1, PG) = T.out_grid_Pg_MW(k);
        mpc.gen(1, QG) = T.out_grid_Qg_MVAr(k);
        mpc.gen(2, PG) = T.out_der_Pg_MW(k);
        mpc.gen(2, QG) = T.out_der_Qg_MVAr(k);
        mpc.gen(3, PG) = T.out_prosumer_Pg_MW(k);
        mpc.gen(3, QG) = T.out_prosumer_Qg_MVAr(k);

        mpc.gen(1, VG) = T.out_bus1_Vm_pu(k);
        mpc.gen(2, VG) = T.out_bus3_Vm_pu(k);
        mpc.gen(3, VG) = T.out_bus4_Vm_pu(k);

        for b = 1:4
            mpc.bus(b, VM) = T.(sprintf('out_bus%d_Vm_pu', b))(k);
            mpc.bus(b, VA) = T.(sprintf('out_bus%d_Va_deg', b))(k);
        end

        row = struct();
        row.scenario_id = T.scenario_id(k);
        row.runpf_success = 0;
        row.error_message = "";
        row.validation_pass = 0;
        row.dominant_fail_reason = "not_run";
        row.diagnosis = "";

        row.max_abs_Vm_error = NaN;
        row.max_abs_Va_error = NaN;
        row.max_abs_checked_Pg_error = NaN;
        row.max_abs_checked_Qg_error = NaN;
        row.max_abs_Pf_error = NaN;
        row.max_abs_Qf_error = NaN;
        row.max_abs_Ploss_error = NaN;
        row.max_abs_Qloss_error = NaN;
        row.max_abs_loading_error = NaN;

        row.grid_Pg_abs_error = NaN;
        row.grid_Qg_abs_error = NaN;
        row.der_Qg_abs_error = NaN;

        try
            pf_results = runpf(mpc, mpopt);
            row.runpf_success = pf_results.success;
        catch ME
            pf_results = [];
            row.runpf_success = 0;
            row.error_message = string(ME.message);
        end

        if row.runpf_success == 1
            nRunpfSuccess = nRunpfSuccess + 1;

            Vm_errors = zeros(4, 1);
            Va_errors = zeros(4, 1);
            for b = 1:4
                Vm_excel = T.(sprintf('out_bus%d_Vm_pu', b))(k);
                Va_excel = T.(sprintf('out_bus%d_Va_deg', b))(k);
                Vm_runpf = pf_results.bus(b, VM);
                Va_runpf = pf_results.bus(b, VA);
                Vm_errors(b) = abs(Vm_runpf - Vm_excel);
                Va_errors(b) = abs(Va_runpf - Va_excel);
                row.(sprintf('bus%d_Vm_abs_error', b)) = Vm_errors(b);
                row.(sprintf('bus%d_Va_abs_error', b)) = Va_errors(b);
            end
            row.max_abs_Vm_error = max(Vm_errors);
            row.max_abs_Va_error = max(Va_errors);

            Pg_excel = [T.out_grid_Pg_MW(k); T.out_der_Pg_MW(k); T.out_prosumer_Pg_MW(k)];
            Qg_excel = [T.out_grid_Qg_MVAr(k); T.out_der_Qg_MVAr(k); T.out_prosumer_Qg_MVAr(k)];
            Pg_runpf = pf_results.gen(:, PG);
            Qg_runpf = pf_results.gen(:, QG);
            Pg_errors = abs(Pg_runpf - Pg_excel);
            Qg_errors = abs(Qg_runpf - Qg_excel);

            row.grid_Pg_abs_error = Pg_errors(1);
            row.grid_Qg_abs_error = Qg_errors(1);
            row.der_Pg_abs_error = Pg_errors(2);
            row.der_Qg_abs_error = Qg_errors(2);
            row.prosumer_Pg_abs_error = Pg_errors(3);
            row.prosumer_Qg_abs_error = Qg_errors(3);
            row.max_abs_checked_Pg_error = max([Pg_errors(2); Pg_errors(3)]);
            row.max_abs_checked_Qg_error = Qg_errors(3);

            Pf_errors = zeros(3, 1);
            Qf_errors = zeros(3, 1);
            Ploss_errors = zeros(3, 1);
            Qloss_errors = zeros(3, 1);
            loading_errors = zeros(3, 1);

            for br = 1:3
                Pf_excel = T.(sprintf('out_branch%d_Pf_MW', br))(k);
                Qf_excel = T.(sprintf('out_branch%d_Qf_MVAr', br))(k);
                Ploss_excel = T.(sprintf('out_branch%d_P_loss_MW', br))(k);
                Qloss_excel = T.(sprintf('out_branch%d_Q_loss_MVAr', br))(k);
                loading_excel = T.(sprintf('out_branch%d_loading_percent', br))(k);

                Pf_runpf = pf_results.branch(br, PF);
                Pt_runpf = pf_results.branch(br, PT);
                Qf_runpf = pf_results.branch(br, QF);
                Qt_runpf = pf_results.branch(br, QT);
                Ploss_runpf = Pf_runpf + Pt_runpf;
                Qloss_runpf = Qf_runpf + Qt_runpf;
                Sf_runpf = sqrt(Pf_runpf^2 + Qf_runpf^2);
                St_runpf = sqrt(Pt_runpf^2 + Qt_runpf^2);
                rateA = pf_results.branch(br, RATE_A);
                loading_runpf = 100 * max(Sf_runpf, St_runpf) / rateA;

                Pf_errors(br) = abs(Pf_runpf - Pf_excel);
                Qf_errors(br) = abs(Qf_runpf - Qf_excel);
                Ploss_errors(br) = abs(Ploss_runpf - Ploss_excel);
                Qloss_errors(br) = abs(Qloss_runpf - Qloss_excel);
                loading_errors(br) = abs(loading_runpf - loading_excel);
            end

            row.max_abs_Pf_error = max(Pf_errors);
            row.max_abs_Qf_error = max(Qf_errors);
            row.max_abs_Ploss_error = max(Ploss_errors);
            row.max_abs_Qloss_error = max(Qloss_errors);
            row.max_abs_loading_error = max(loading_errors);

            row.validation_pass = double( ...
                row.max_abs_Vm_error <= tol.Vm && ...
                row.max_abs_Va_error <= tol.Va && ...
                row.max_abs_checked_Pg_error <= tol.P && ...
                row.max_abs_checked_Qg_error <= tol.Q && ...
                row.max_abs_Pf_error <= tol.P && ...
                row.max_abs_Qf_error <= tol.Q && ...
                row.max_abs_Ploss_error <= tol.P && ...
                row.max_abs_Qloss_error <= tol.Q && ...
                row.max_abs_loading_error <= tol.loading);

            [row.dominant_fail_reason, row.diagnosis] = diagnoseValidationRow(row, tol);

            if row.validation_pass == 1
                nValidationPass = nValidationPass + 1;
            else
                nValidationMismatch = nValidationMismatch + 1;
            end
        else
            nRunpfFail = nRunpfFail + 1;
            row.dominant_fail_reason = "runpf_fail";
            row.diagnosis = "RUNPF itself failed to converge or threw an error.";
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
        min(validationTable.runpf_success), min(validationTable.validation_pass), ...
        max(validationTable.max_abs_Vm_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Va_error, [], 'omitnan'), ...
        max(validationTable.max_abs_checked_Pg_error, [], 'omitnan'), ...
        max(validationTable.max_abs_checked_Qg_error, [], 'omitnan'), ...
        max(validationTable.grid_Pg_abs_error, [], 'omitnan'), ...
        max(validationTable.grid_Qg_abs_error, [], 'omitnan'), ...
        max(validationTable.der_Qg_abs_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Pf_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Qf_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Ploss_error, [], 'omitnan'), ...
        max(validationTable.max_abs_Qloss_error, [], 'omitnan'), ...
        max(validationTable.max_abs_loading_error, [], 'omitnan'), ...
        'VariableNames', { ...
        'number_of_excel_rows', 'number_of_runpf_success', 'number_of_runpf_fail', ...
        'number_of_validation_pass', 'number_of_validation_mismatch', ...
        'minimum_runpf_success_flag', 'minimum_validation_pass_flag', ...
        'max_abs_Vm_error', 'max_abs_Va_error', 'max_abs_checked_Pg_error', ...
        'max_abs_checked_Qg_error', 'diagnostic_max_grid_Pg_error', ...
        'diagnostic_max_grid_Qg_error', 'diagnostic_max_der_Qg_error', ...
        'max_abs_Pf_error', 'max_abs_Qf_error', 'max_abs_Ploss_error', ...
        'max_abs_Qloss_error', 'max_abs_loading_error'});
end

function [reason, diagnosis] = diagnoseValidationRow(row, tol)
    if row.validation_pass == 1
        reason = "pass";
        diagnosis = "RUNPF solution matches exported OPF outputs within all strict tolerances.";
        return;
    end

    names = ["Vm mismatch", "Va mismatch", "Checked Pg mismatch", "Checked Qg mismatch", ...
             "Branch Pf mismatch", "Branch Qf mismatch", "Branch P-loss mismatch", ...
             "Branch Q-loss mismatch", "Branch loading mismatch"];
    values = [row.max_abs_Vm_error / tol.Vm, row.max_abs_Va_error / tol.Va, ...
              row.max_abs_checked_Pg_error / tol.P, row.max_abs_checked_Qg_error / tol.Q, ...
              row.max_abs_Pf_error / tol.P, row.max_abs_Qf_error / tol.Q, ...
              row.max_abs_Ploss_error / tol.P, row.max_abs_Qloss_error / tol.Q, ...
              row.max_abs_loading_error / tol.loading];
    values(~isfinite(values)) = -Inf;
    [~, idx] = max(values);
    reason = names(idx);

    dependentNote = "";
    if isfinite(row.grid_Pg_abs_error) && (row.grid_Pg_abs_error > tol.P || row.grid_Qg_abs_error > tol.Q || row.der_Qg_abs_error > tol.Q)
        dependentNote = " Slack Pg/Qg and PV-bus Qg are PF-dependent variables; their diagnostic mismatch is expected and is not part of the strict pass decision.";
    end

    diagnosis = "RUNPF converged, but the reconstructed PF point is not numerically identical to the exported OPF point. Dominant mismatch: " + reason + "." + dependentNote;
end

function value = clampToRangeDashboard(value, rangePair)
    value = max(rangePair(1), min(rangePair(2), value));
end

function Q = calcQfromPandPFDashboard(P, pf)
    if pf <= 0 || pf > 1
        error('Power factor must be in the interval (0, 1].');
    end
    Q = P * tan(acos(pf));
end

% function [isOK, message] = checkMarginalCostOrderingDashboard(scenario)
%     isOK = true;
%     message = 'OK';
%     Ptest = [0 0.5 1.0 1.5 2.0];
%     MC_grid = 2 * scenario.grid_c2 .* Ptest + scenario.grid_c1;
%     MC_der  = 2 * scenario.der_c2  .* Ptest + scenario.der_c1;
%     MC_pro  = 2 * scenario.pro_c2  .* Ptest + scenario.pro_c1;
%     if any(MC_der >= MC_grid)
%         isOK = false;
%         message = 'DER marginal cost is not cheaper than grid over test range.';
%         return;
%     end
%     if any(MC_pro >= MC_grid)
%         isOK = false;
%         message = 'Prosumer marginal cost is not cheaper than grid over test range.';
%         return;
%     end
% end

function busTable = createBusStaticTableDashboard(mpc)
    define_constants;
    bus_id = mpc.bus(:, BUS_I);
    bus_type = mpc.bus(:, BUS_TYPE);
    base_kV = mpc.bus(:, BASE_KV);
    Vmax = mpc.bus(:, VMAX);
    Vmin = mpc.bus(:, VMIN);
    is_slack = double(bus_type == 3);
    is_PQ = double(bus_type == 1);
    is_PV = double(bus_type == 2);
    is_prosumer = zeros(size(bus_id));
    is_prosumer(bus_id == 4) = 1;
    bus_role = strings(length(bus_id), 1);
    for i = 1:length(bus_id)
        if bus_id(i) == 1
            bus_role(i) = "Slack/Grid";
        elseif bus_id(i) == 2
            bus_role(i) = "PQ Load";
        elseif bus_id(i) == 3
            bus_role(i) = "PV + DER";
        elseif bus_id(i) == 4
            bus_role(i) = "Prosumer";
        else
            bus_role(i) = "Unknown";
        end
    end
    busTable = table(bus_id, bus_role, bus_type, is_slack, is_PQ, is_PV, is_prosumer, base_kV, Vmin, Vmax, ...
        'VariableNames', {'bus_id','bus_role','matpower_bus_type','is_slack','is_PQ','is_PV','is_prosumer','base_kV','Vmin_pu','Vmax_pu'});
end

function branchTable = createBranchStaticTableDashboard(mpc)
    define_constants;
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

function mpc = case4bus_radial_33kv_prosumer_dashboard()
    mpc.version = '2';
    mpc.baseMVA = 10;

    %% Bus data
    % bus_i type Pd Qd Gs Bs area Vm Va baseKV zone Vmax Vmin
    mpc.bus = [
        1   3   0.0  0.0  0  0  1    1.000  0  33     1    1.05 0.95;
        2   1   2.0  0.8  0  0  1    1.000  0  33     1    1.05 0.95;
        3   2   0.0  0.0  0  0  1    1.000  0  33     1    1.05 0.95;
        4   1   0.8  0.3  0  0  1    1.000  0  33     1    1.05 0.95;
    ];

    %% Generator data
    % bus Pg Qg Qmax Qmin Vg mBase status Pmax Pmin Pc1 Pc2 Qc1min Qc1max Qc2min Qc2max ramp_agc ramp_10 ramp_30 ramp_q apf
    mpc.gen = [
        1   1.0  0  20.0 -20.0  1.00 10    1      20.0 0.0  0   0   0      0      0      0      0        0       0       0      0;
        3   1.0  0   2.0  -2.0  1.00 10    1       1.3 0.0  0   0   0      0      0      0      0        0       0       0      0;
        4   0.5  0   1.0  -1.0  1.00 10    1       1.2 0.0  0   0   0      0      0      0      0        0       0       0      0;
    ];

    %% Branch data
    mpc.branch = [
        1    2    0.00588  0.00698  0  5.0   5.0   5.0   0     0     1      -360   360;
        2    3    0.00441  0.00523  0  4.0   4.0   4.0   0     0     1      -360   360;
        3    4    0.00294  0.00349  0  3.0   3.0   3.0   0     0     1      -360   360;
    ];

    %% Generator cost data
    % C(P) = c2*P^2 + c1*P + c0
    mpc.gencost = [
        2     0       0        3     0.020   90   0;
        2     0       0        3     0.015   35   0;
        2     0       0        3     0.010   25   0;
    ];

    mpc.bus_name = {'Grid Slack Bus'; 'PQ Load Bus'; 'DER Bus'; 'Prosumer Bus'};
    mpc.gentype = {'GRID'; 'LOCAL_DER'; 'PROSUMER'};
end
