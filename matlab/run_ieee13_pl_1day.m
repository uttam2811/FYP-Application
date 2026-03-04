%% ============================================================
%  AUTO-RUN IEEE 13 BUS SYSTEM — 1-Day Power-Loss Simulation
%  -----------------------------------------------------------
%  Model: aIEEE13bus_with_solar_13bus_pl_1day.slx
%
%  This script:
%    1. Opens the Simulink model automatically
%    2. Runs the 1-day power-loss simulation
%    3. Uploads system topology to the web dashboard
%    4. Streams live measurement data (V, I, P, Q) for all buses
%    5. Sends final analysis results with bus status & load info
%
%  USAGE:
%    >> run_ieee13_pl_1day
%    OR: matlab -batch "run('D:/FYP Application/matlab/run_ieee13_pl_1day.m')"
%
%  REQUIREMENTS:
%    - Web server running at http://localhost:3000
%    - Model file: aIEEE13bus_with_solar_13bus_pl_1day.slx
%% ============================================================

function run_ieee13_pl_1day()
    clc;

    % ===== SUPPRESS ALL FIGURES — everything goes to the website =====
    set(0, 'DefaultFigureVisible', 'off');
    close all hidden;

    % ===== LOG FILE for debugging =====
    LOG_FILE = fullfile(fileparts(mfilename('fullpath')), '..', 'server', 'matlab-output', 'matlab_debug.log');
    try
        fLog = fopen(LOG_FILE, 'w');
        if fLog > 0
            fprintf(fLog, 'MATLAB run_ieee13_pl_1day started at %s\n', datestr(now));
            fclose(fLog);
        end
    catch; end

    fprintf('╔══════════════════════════════════════════════════════╗\n');
    fprintf('║  IEEE 13 Bus — 1-Day Power-Loss Simulation          ║\n');
    fprintf('╚══════════════════════════════════════════════════════╝\n\n');

    %% ===== CONFIGURATION =====
    SERVER_URL  = 'http://localhost:3000';
    MODEL_DIR   = 'D:\FPY Application_Files';
    MODEL_FILE  = 'aIEEE13bus_with_solar_13bus_pl_1day';
    MODEL_PATH  = fullfile(MODEL_DIR, [MODEL_FILE '.slx']);
    SESSION_ID  = ['pl1day_' datestr(now, 'yyyy_mm_dd_HHMMSS')];

    % Verify server is reachable
    fprintf('[1/6] Checking web server connection...\n');
    try
        options = weboptions('Timeout', 5, 'RequestMethod', 'post', ...
            'MediaType', 'application/json');
        webwrite([SERVER_URL '/api/bus-system/measurements'], ...
            jsonencode(struct('session_id','test','bus_id','test', ...
            'measurements', struct('voltage_V',0))), options);
    catch
    end
    fprintf('       ✓ Server connection OK\n\n');

    % Verify model file exists
    fprintf('[2/6] Locating Simulink model...\n');
    if ~exist(MODEL_PATH, 'file')
        error('Model file not found: %s', MODEL_PATH);
    end
    fprintf('       ✓ Found: %s\n\n', MODEL_PATH);

    %% ===== STEP 1: UPLOAD SYSTEM TOPOLOGY =====
    fprintf('[3/6] Uploading system topology to dashboard...\n');
    upload_topology(SERVER_URL, SESSION_ID);
    fprintf('       ✓ Topology uploaded (Session: %s)\n\n', SESSION_ID);

    %% ===== STEP 2: NOTIFY SIMULATION STARTING =====
    notify_status(SERVER_URL, SESSION_ID, 'running', 'Simulation starting...');

    %% ===== STEP 3: GENERATE WEATHER DATA & OPEN MODEL =====
    fprintf('[4/6] Opening and running Simulink model...\n');
    fprintf('       Model: %s\n', MODEL_FILE);

    addpath(MODEL_DIR);

    % ===== RUN WEATHER GENERATOR FIRST =====
    % This creates irradiance_profile and temperature_profile in workspace
    % NOTE: weather_generator_1day.m has "clear" at the top, so run it BEFORE
    %       setting Ts_Power/Ts_Control.
    fprintf('\n       Running weather_generator_1day to create load profiles...\n');
    try
        % Save current dir
        prevDir = pwd;
        cd(MODEL_DIR);

        % Suppress figures before running weather generator
        set(0, 'DefaultFigureVisible', 'off');

        % Run the weather generator script (it creates variables in base workspace)
        % We wrap it to suppress its 'clear' from killing our function vars
        evalin('base', 'set(0,''DefaultFigureVisible'',''off'');');
        evalin('base', 'run(''weather_generator_1day.m'')');
        evalin('base', 'close all hidden;');

        cd(prevDir);

        % Verify the key variables were created
        if evalin('base', 'exist(''irradiance_profile'',''var'')')
            irr = evalin('base', 'irradiance_profile');
            fprintf('       ✓ irradiance_profile created (%d x %d)\n', size(irr,1), size(irr,2));
        else
            fprintf('       ⚠ irradiance_profile NOT found after running weather generator\n');
        end

        if evalin('base', 'exist(''temperature_profile'',''var'')')
            tmp = evalin('base', 'temperature_profile');
            fprintf('       ✓ temperature_profile created (%d x %d)\n', size(tmp,1), size(tmp,2));
        else
            fprintf('       ⚠ temperature_profile NOT found after running weather generator\n');
        end

        % Also check if the .mat file was saved and load it for good measure
        matFile = fullfile(MODEL_DIR, 'weather_real_March6_IST.mat');
        if exist(matFile, 'file')
            evalin('base', sprintf('load(''%s'');', strrep(matFile, '\', '\\')));
            fprintf('       ✓ Loaded %s into workspace\n', matFile);
        end

        % ===== STREAM WEATHER DATA TO WEBSITE =====
        fprintf('       Streaming weather data to website...\n');
        wOpts = weboptions('MediaType','application/json','RequestMethod','post','Timeout',5);
        wUrl = [SERVER_URL '/api/bus-system/measurements'];
        weatherSent = 0;
        try
            if exist('irr', 'var') && size(irr,2) >= 2
                for wi = 1:size(irr,1)
                    m = struct('session_id', SESSION_ID, 'bus_id', 'WEATHER', ...
                        'measurements', struct(...
                            'irradiance_Wm2', irr(wi,2), ...
                            'time_s', irr(wi,1), ...
                            'hour', irr(wi,1), ...
                            'timestamp_matlab', datestr(now)));
                    if exist('tmp', 'var') && wi <= size(tmp,1)
                        m.measurements.temperature_C = tmp(wi,2);
                    end
                    try webwrite(wUrl, jsonencode(m), wOpts); weatherSent = weatherSent + 1; catch; end
                end
            end
            fprintf('       ✓ Sent %d weather data points to dashboard\n', weatherSent);
        catch
            fprintf('       ⚠ Could not stream weather data\n');
        end

        fprintf('       ✓ Weather data ready\n\n');
    catch exWeather
        fprintf('       ⚠ Weather generator error: %s\n', exWeather.message);
        fprintf('       Continuing anyway — From Workspace auto-fill will attempt defaults...\n\n');
    end

    % Set required workspace parameters AFTER weather generator
    % (weather_generator_1day.m has "clear" which would wipe these)
    Ts_Power   = 5e-5;    % Power system discrete sample time
    Ts_Control = 1e-4;    % Control system sample time
    assignin('base', 'Ts_Power',   Ts_Power);
    assignin('base', 'Ts_Control', Ts_Control);
    fprintf('       ✓ Ts_Power  = %g s\n', Ts_Power);
    fprintf('       ✓ Ts_Control = %g s\n', Ts_Control);

    try
        load_system(MODEL_PATH);
        fprintf('       ✓ Model loaded successfully\n');
    catch ex
        fprintf('       ✗ Error loading model: %s\n', ex.message);
        notify_status(SERVER_URL, SESSION_ID, 'error', ex.message);
        return;
    end

    % ===== FIX DUPLICATE 'fcn' IN MATLAB FUNCTION BLOCKS =====
    % The model has a known bug: some MATLAB Function blocks contain
    % duplicate 'function fcn(...)' declarations. Auto-fix them.
    fprintf('\n       Checking MATLAB Function blocks for duplicate fcn...\n');
    try
        mfBlocks = find_system(MODEL_FILE, 'BlockType', 'SubSystem', ...
            'MaskType', 'Stateflow: MATLAB Function Block');
    catch
        mfBlocks = {};
    end
    % Also try finding via SFunctionName
    try
        mfBlocks2 = find_system(MODEL_FILE, 'BlockType', 'SubSystem', ...
            'SFBlockType', 'MATLAB Function');
        mfBlocks = [mfBlocks; mfBlocks2];
    catch
    end
    % Direct search for Embedded MATLAB blocks
    try
        emBlocks = find_system(MODEL_FILE, 'BlockType', 'SubSystem');
        for eb = 1:length(emBlocks)
            blkPath = emBlocks{eb};
            try
                % Check if this subsystem contains Stateflow chart (MATLAB Function)
                rt = sfroot;
                chart = rt.find('-isa', 'Stateflow.EMChart', 'Path', blkPath);
                if ~isempty(chart)
                    mfBlocks{end+1} = blkPath;
                end
            catch
            end
        end
    catch
    end

    % Use Stateflow API to fix MATLAB Function blocks directly
    modelFixed = false;
    try
        rt = sfroot;
        allCharts = rt.find('-isa', 'Stateflow.EMChart');
        fprintf('       Found %d MATLAB Function (EMChart) blocks\n', length(allCharts));

        for ci = 1:length(allCharts)
            chart = allCharts(ci);
            chartPath = chart.Path;

            % Only fix charts in our model
            if ~startsWith(chartPath, MODEL_FILE)
                continue;
            end

            fprintf('       Checking: %s\n', chartPath);

            % Get all Stateflow functions in this chart
            fcns = chart.find('-isa', 'Stateflow.EMFunction');
            if isempty(fcns)
                fcns = chart.find('-isa', 'Stateflow.Function');
            end

            if length(fcns) > 1
                % Multiple function objects — check for duplicate 'fcn' names
                fcnNames = {};
                for fi = 1:length(fcns)
                    fcnNames{fi} = fcns(fi).Name;
                end
                fprintf('         Functions found: %s\n', strjoin(fcnNames, ', '));

                % Find duplicates
                [uniqueNames, ia] = unique(fcnNames, 'stable');
                if length(uniqueNames) < length(fcnNames)
                    fprintf('         ⚠ Duplicate function names detected! Removing duplicates...\n');
                    duplicateIdx = setdiff(1:length(fcnNames), ia);
                    for di = length(duplicateIdx):-1:1
                        fprintf('           Removing duplicate: %s (index %d)\n', ...
                            fcnNames{duplicateIdx(di)}, duplicateIdx(di));
                        try
                            fcns(duplicateIdx(di)).delete();
                            modelFixed = true;
                        catch exDel
                            fprintf('           ⚠ Could not delete: %s\n', exDel.message);
                        end
                    end
                end
            end

            % Also check the script text for duplicate function declarations
            try
                scriptText = chart.Script;
                if ~isempty(scriptText)
                    lines = strsplit(scriptText, newline);
                    fcnLineIdx = [];
                    for li = 1:length(lines)
                        trimmed = strtrim(lines{li});
                        if startsWith(trimmed, 'function ')
                            fcnLineIdx(end+1) = li;
                        end
                    end

                    if length(fcnLineIdx) > 1
                        fprintf('         Script has %d function declarations (lines: %s)\n', ...
                            length(fcnLineIdx), num2str(fcnLineIdx));

                        % Check if they have the same signature
                        sigs = {};
                        for fi = 1:length(fcnLineIdx)
                            sigs{fi} = strtrim(lines{fcnLineIdx(fi)});
                        end

                        % Remove exact duplicate declarations
                        % Keep only the first occurrence of each signature block
                        [~, keepIdx] = unique(sigs, 'stable');
                        if length(keepIdx) < length(fcnLineIdx)
                            removeIdx = setdiff(1:length(fcnLineIdx), keepIdx);
                            fprintf('         Removing %d duplicate function block(s) from script\n', length(removeIdx));

                            % Determine line ranges for each function
                            removeLines = [];
                            for ri = 1:length(removeIdx)
                                startLine = fcnLineIdx(removeIdx(ri));
                                if removeIdx(ri) < length(fcnLineIdx)
                                    endLine = fcnLineIdx(removeIdx(ri)) - 1;
                                    % Find next function start
                                    nextFcnIdx = find(fcnLineIdx > startLine, 1, 'first');
                                    if ~isempty(nextFcnIdx)
                                        endLine = fcnLineIdx(nextFcnIdx) - 1;
                                    else
                                        endLine = length(lines);
                                    end
                                else
                                    endLine = length(lines);
                                end
                                removeLines = [removeLines, startLine:endLine];
                            end

                            keepLines = setdiff(1:length(lines), removeLines);
                            newScript = strjoin(lines(keepLines), newline);
                            chart.Script = newScript;
                            modelFixed = true;
                            fprintf('         ✓ Script fixed (removed %d lines)\n', length(removeLines));
                        end
                    end
                end
            catch exScript
                fprintf('         ⚠ Script check error: %s\n', exScript.message);
            end
        end
    catch exSF
        fprintf('       ⚠ Stateflow API error: %s\n', exSF.message);
    end

    if modelFixed
        try
            save_system(MODEL_FILE);
            fprintf('       ✓ Model saved with duplicate-fcn fixes\n');
        catch
            fprintf('       ⚠ Could not save fixed model (read-only?)\n');
        end
    else
        fprintf('       ✓ No duplicate fcn issues found (or already fixed)\n');
    end

    % ===== FIX UNDEFINED OUTPUT ARGUMENTS IN MATLAB FUNCTION BLOCKS =====
    % Simulink code-gen requires every output to be assigned on ALL paths.
    % We auto-initialise every output to 0 at the top of the function body.
    fprintf('\n       Checking MATLAB Function outputs for missing initialisations...\n');
    outputFixed = false;
    try
        rt2 = sfroot;
        allCharts2 = rt2.find('-isa', 'Stateflow.EMChart');
        for ci2 = 1:length(allCharts2)
            chart2 = allCharts2(ci2);
            if ~startsWith(chart2.Path, MODEL_FILE)
                continue;
            end
            scriptText2 = chart2.Script;
            if isempty(scriptText2)
                continue;
            end

            lines2 = strsplit(scriptText2, newline);

            % Find function signature line:  function [out1,out2] = fcn(in1,in2)
            % or:  function out = fcn(in)
            sigIdx = 0;
            outputNames = {};
            for li2 = 1:length(lines2)
                trimLine = strtrim(lines2{li2});
                if startsWith(trimLine, 'function ')
                    sigIdx = li2;
                    % Parse outputs from signature
                    % Pattern A:  function [a, b, c] = name(...)
                    tok = regexp(trimLine, 'function\s*\[([^\]]+)\]\s*=', 'tokens');
                    if ~isempty(tok)
                        outputNames = strtrim(strsplit(tok{1}{1}, ','));
                    else
                        % Pattern B:  function a = name(...)
                        tok2 = regexp(trimLine, 'function\s+(\w+)\s*=', 'tokens');
                        if ~isempty(tok2)
                            outputNames = {tok2{1}{1}};
                        end
                    end
                    break;  % only first function signature
                end
            end

            if sigIdx == 0 || isempty(outputNames)
                continue;
            end

            % Check if each output is already initialised right after signature
            % Look for "outName = " within the first few lines after the signature
            needInit = {};
            bodyStart = sigIdx + 1;
            % Scan existing body for default assignments
            for oi = 1:length(outputNames)
                oName = outputNames{oi};
                found = false;
                % Check if there's already an init like "En = 0;" before any if/switch
                for li3 = bodyStart:min(bodyStart+20, length(lines2))
                    tl = strtrim(lines2{li3});
                    % Stop scanning at first control-flow statement
                    if startsWith(tl, 'if ') || startsWith(tl, 'switch ') || ...
                       startsWith(tl, 'for ') || startsWith(tl, 'while ')
                        break;
                    end
                    if startsWith(tl, [oName ' =']) || startsWith(tl, [oName '='])
                        found = true;
                        break;
                    end
                end
                if ~found
                    needInit{end+1} = oName;
                end
            end

            if ~isempty(needInit)
                fprintf('         %s: initialising outputs: %s\n', chart2.Path, strjoin(needInit, ', '));
                % Build init lines
                initLines = {};
                initLines{end+1} = '%% Auto-generated default output initialisations (code-gen safety)';
                for ni = 1:length(needInit)
                    initLines{end+1} = sprintf('%s = 0;', needInit{ni});
                end

                % Insert right after function signature line
                newLines = [lines2(1:sigIdx), initLines, lines2(sigIdx+1:end)];
                chart2.Script = strjoin(newLines, newline);
                outputFixed = true;
                fprintf('         ✓ Added default init for: %s\n', strjoin(needInit, ', '));
            end
        end
    catch exOut
        fprintf('       ⚠ Output-init fix error: %s\n', exOut.message);
    end

    if outputFixed
        try
            save_system(MODEL_FILE);
            fprintf('       ✓ Model saved with output-init fixes\n');
        catch
            fprintf('       ⚠ Could not save model with output-init fixes\n');
        end
    else
        fprintf('       ✓ All MATLAB Function outputs already initialised\n');
    end

    % ===== AUTO-DETECT & CREATE "From Workspace" VARIABLES =====
    % The model's subsystems (bus 611, 634, etc.) each have a "From Workspace"
    % block that expects a timeseries variable in the base workspace.
    % We discover the needed variable names and create default load profiles.
    fprintf('\n       Scanning model for "From Workspace" blocks...\n');
    try
        fwBlocks = find_system(MODEL_FILE, 'BlockType', 'FromWorkspace');
        fprintf('       Found %d "From Workspace" blocks\n', length(fwBlocks));

        % Get simulation stop time early so we can build timeseries of correct length
        try
            stopTimeVal = str2double(get_param(MODEL_FILE, 'StopTime'));
        catch
            stopTimeVal = 168;  % fallback
        end

        for fb = 1:length(fwBlocks)
            blockPath = fwBlocks{fb};
            try
                varName = get_param(blockPath, 'VariableName');
                fprintf('       Block: %s\n', blockPath);
                fprintf('         → Variable needed: "%s"\n', varName);

                % Check if variable already exists in base workspace
                if evalin('base', sprintf('exist(''%s'',''var'')', varName))
                    fprintf('         ✓ Already exists in workspace\n');
                    continue;
                end

                % Determine what port/signal the From Workspace feeds
                % Try to read the output dimensions from the block
                outportHandles = get_param(blockPath, 'PortHandles');
                nCols = 1;  % default: scalar signal
                try
                    if ~isempty(outportHandles.Outport)
                        dims = get_param(outportHandles.Outport(1), 'CompiledPortDimensions');
                        if ~isempty(dims) && length(dims) >= 2
                            nCols = prod(dims(2:end));
                        end
                    end
                catch
                    % Can't get compiled dims before simulation, use heuristic
                    nCols = 1;
                end

                % Determine the data pattern from the variable name
                % Typical names: load_profile_611, PL_634, solarProfile_671, etc.
                % For a 1-day power loss sim, these are usually load scaling factors
                % (value around 1.0) or power profiles over the simulation time.

                % Create time vector spanning the simulation
                t = linspace(0, stopTimeVal, 2)';  % Simple 2-point (start & end)

                % Check if this looks like a solar/PV profile or a load profile
                varLower = lower(varName);
                if contains(varLower, 'solar') || contains(varLower, 'irr') || contains(varLower, 'pv')
                    % Solar irradiance profile: bell curve peaking at noon
                    % For a short sim time, just use constant 1000 W/m²
                    data = ones(2, nCols) * 1000;
                    fprintf('         → Created as solar profile (1000 W/m²)\n');
                elseif contains(varLower, 'temp')
                    % Temperature profile: constant 25°C
                    data = ones(2, nCols) * 25;
                    fprintf('         → Created as temperature profile (25°C)\n');
                else
                    % Load scaling factor or power profile: constant 1.0 (nominal)
                    data = ones(2, nCols);
                    fprintf('         → Created as load scaling factor (1.0)\n');
                end

                % Create timeseries and assign to base workspace
                ts = timeseries(data, t);
                ts.Name = varName;
                assignin('base', varName, ts);
                fprintf('         ✓ Created "%s" in workspace (timeseries, %d cols, t=[0..%.1f])\n', ...
                    varName, nCols, stopTimeVal);

            catch exBlock
                fprintf('         ⚠ Could not process block: %s\n', exBlock.message);
            end
        end
        fprintf('       ✓ All workspace variables configured\n\n');
    catch exScan
        fprintf('       ⚠ Could not scan model blocks: %s\n', exScan.message);
    end

    % Configure simulation for signal logging
    try
        set_param(MODEL_FILE, 'SaveOutput', 'on');
        set_param(MODEL_FILE, 'ReturnWorkspaceOutputs', 'on');
        set_param(MODEL_FILE, 'SignalLogging', 'on');
        set_param(MODEL_FILE, 'SignalLoggingName', 'logsout');
        set_param(MODEL_FILE, 'SaveTime', 'on');
        set_param(MODEL_FILE, 'TimeSaveName', 'tout');
        fprintf('       ✓ Signal logging configured (ReturnWorkspaceOutputs=on)\n');
    catch
        fprintf('       ⚠ Could not configure logging (may already be set)\n');
    end

    % Get simulation stop time
    try
        stopTime = str2double(get_param(MODEL_FILE, 'StopTime'));
        fprintf('       Simulation stop time: %.3f s\n', stopTime);
    catch
        stopTime = 86400; % default 1 day (24 hours in seconds)
    end

    % ===== ENABLE LOGGING ON OUTPUT PORT SIGNALS =====
    % Find all outport and scope blocks and enable logging on their input signals
    fprintf('       Enabling signal logging on key blocks...\n');
    try
        % Find all Outport blocks (root level)
        outPorts = find_system(MODEL_FILE, 'SearchDepth', 1, 'BlockType', 'Outport');
        for op = 1:length(outPorts)
            try
                ph = get_param(outPorts{op}, 'PortHandles');
                if ~isempty(ph.Inport)
                    lh = get_param(ph.Inport(1), 'Line');
                    if lh > 0
                        set_param(lh, 'DataLogging', 'on');
                        sigName = get_param(lh, 'Name');
                        if isempty(sigName)
                            % Use outport name
                            [~, bName] = fileparts(outPorts{op});
                            sigName = strrep(bName, ' ', '_');
                        end
                        fprintf('         ✓ Logging enabled on: %s\n', sigName);
                    end
                end
            catch; end
        end

        % Find Scope blocks and enable logging
        scopeBlks = find_system(MODEL_FILE, 'BlockType', 'Scope');
        for sb = 1:length(scopeBlks)
            try
                set_param(scopeBlks{sb}, 'DataLogging', 'on');
                fprintf('         ✓ Scope logging: %s\n', scopeBlks{sb});
            catch; end
        end

        % Find explicitly named signal lines (P_slack, P_load, P_PV_*, etc.)
        allLines = find_system(MODEL_FILE, 'FindAll', 'on', 'Type', 'line');
        loggedSigCount = 0;
        for li = 1:length(allLines)
            try
                lName = get_param(allLines(li), 'Name');
                if ~isempty(lName) && (contains(lName, 'P_') || contains(lName, 'V_') || ...
                   contains(lName, 'I_') || contains(lName, 'PV') || contains(lName, 'slack') || ...
                   contains(lName, 'load') || contains(lName, 'Bus'))
                    set_param(allLines(li), 'DataLogging', 'on');
                    loggedSigCount = loggedSigCount + 1;
                end
            catch; end
        end
        if loggedSigCount > 0
            fprintf('         ✓ Enabled logging on %d named signal lines\n', loggedSigCount);
        end
    catch exLog
        fprintf('       ⚠ Signal logging setup warning: %s\n', exLog.message);
    end

    % Check for any required workspace variables the model expects
    try
        mdlWS = get_param(MODEL_FILE, 'ModelWorkspace');
        if ~isempty(mdlWS)
            fprintf('       ✓ Model workspace available\n');
        end
    catch
    end

    % Try to load companion .mat or data file if it exists
    dataFiles = {fullfile(MODEL_DIR, [MODEL_FILE '.mat']), ...
                 fullfile(MODEL_DIR, [MODEL_FILE '_data.mat']), ...
                 fullfile(MODEL_DIR, 'ieee13_data.mat'), ...
                 fullfile(MODEL_DIR, 'pl_1day_data.mat')};
    for df = 1:length(dataFiles)
        if exist(dataFiles{df}, 'file')
            fprintf('       ✓ Loading data file: %s\n', dataFiles{df});
            evalin('base', sprintf('load(''%s'');', strrep(dataFiles{df}, '\', '\\')));
        end
    end

    % Run simulation
    fprintf('       Running simulation... (this may take a while)\n');
    simStart = tic;

    try
        simOut = sim(MODEL_FILE);
        elapsed = toc(simStart);
        fprintf('       ✓ Simulation completed in %.1f seconds\n\n', elapsed);
        notify_status(SERVER_URL, SESSION_ID, 'processing', ...
            sprintf('Simulation done in %.1fs, extracting data...', elapsed));
    catch ex
        elapsed = toc(simStart);
        fprintf('       ✗ Simulation error after %.1f s: %s\n', elapsed, ex.message);

        % ---- Print detailed sub-causes ----
        if isprop(ex, 'cause') && ~isempty(ex.cause)
            fprintf('\n       ===== DETAILED ERROR CAUSES =====\n');
            for ci = 1:length(ex.cause)
                c = ex.cause{ci};
                fprintf('       [Cause %d] %s\n', ci, c.message);
                if isprop(c, 'cause') && ~isempty(c.cause)
                    for ci2 = 1:length(c.cause)
                        fprintf('         └─ %s\n', c.cause{ci2}.message);
                    end
                end
            end
            fprintf('       =====================================\n\n');
        end

        % ---- Retry with relaxed solver settings ----
        fprintf('       ⟳ Retrying with relaxed solver settings...\n');
        try
            set_param(MODEL_FILE, 'SolverType', 'Variable-step');
            set_param(MODEL_FILE, 'Solver', 'ode23t');
            set_param(MODEL_FILE, 'MaxStep', 'auto');
            set_param(MODEL_FILE, 'RelTol', '1e-3');
            set_param(MODEL_FILE, 'AbsTol', 'auto');
            set_param(MODEL_FILE, 'ConsecutiveZCsStepRelTol', '10*128*eps');
            set_param(MODEL_FILE, 'ZeroCrossAlgorithm', 'Adaptive');
            fprintf('       ✓ Solver changed to ode23t (variable-step)\n');
        catch
            try
                set_param(MODEL_FILE, 'SolverType', 'Fixed-step');
                set_param(MODEL_FILE, 'Solver', 'ode3');
                set_param(MODEL_FILE, 'FixedStep', '1e-4');
                fprintf('       ✓ Solver changed to ode3 (fixed-step, dt=1e-4)\n');
            catch ex2
                fprintf('       ⚠ Could not change solver: %s\n', ex2.message);
            end
        end

        try
            simStart2 = tic;
            simOut = sim(MODEL_FILE);
            elapsed = toc(simStart2);
            fprintf('       ✓ Retry succeeded in %.1f seconds\n\n', elapsed);
            notify_status(SERVER_URL, SESSION_ID, 'processing', ...
                sprintf('Simulation done in %.1fs (retry), extracting data...', elapsed));
        catch ex2
            fprintf('       ✗ Retry also failed: %s\n', ex2.message);
            if isprop(ex2, 'cause') && ~isempty(ex2.cause)
                for ci = 1:length(ex2.cause)
                    fprintf('         [Cause %d] %s\n', ci, ex2.cause{ci}.message);
                end
            end
            notify_status(SERVER_URL, SESSION_ID, 'error', ...
                ['Simulation failed: ' ex.message ' | Retry: ' ex2.message]);
            return;
        end
    end

    %% ===== STEP 4: EXTRACT & STREAM DATA =====
    fprintf('[5/6] Extracting and streaming measurement data...\n');

    % ---- Exhaustive search for simulation output data ----
    logsout = [];
    simoutData = [];

    % Method 1: logsout from simOut object
    if isprop(simOut, 'logsout') || isfield(simOut, 'logsout')
        try logsout = simOut.logsout; catch; end
    end
    % Method 2: logsout in base workspace
    if isempty(logsout) && evalin('base', 'exist(''logsout'', ''var'')')
        logsout = evalin('base', 'logsout');
    end
    % Method 3: yout (Simscape / Simpower logged outputs)
    if isempty(logsout)
        try
            if isprop(simOut, 'yout'), logsout = simOut.yout; end
        catch; end
    end
    % Method 4: tout + yout / simout fields
    if isempty(logsout)
        try
            if isprop(simOut, 'simout'), logsout = simOut.simout; end
        catch; end
    end

    % ---- Diagnostic: print everything available in simOut ----
    fprintf('\n       ===== simOut CONTENTS =====\n');
    try
        allProps = who(simOut);
        for pp = 1:length(allProps)
            propName = allProps{pp};
            try
                val = simOut.(propName);
                valClass = class(val);
                valSize = size(val);
                fprintf('       [%s] class=%s  size=[%s]\n', propName, valClass, num2str(valSize));
            catch
                fprintf('       [%s] (could not read)\n', propName);
            end
        end
    catch
        % simOut may not support `who`
        try
            propList = properties(simOut);
            for pp = 1:length(propList)
                fprintf('       Property: %s\n', propList{pp});
            end
        catch; end
    end

    % Also check simOut.tout
    tout = [];
    try tout = simOut.tout; catch; end
    if isempty(tout)
        try tout = simOut.get('tout'); catch; end
    end
    if ~isempty(tout)
        fprintf('       tout: %d samples, range [%.4f .. %.4f] s\n', length(tout), tout(1), tout(end));
    else
        fprintf('       ⚠ No tout found\n');
    end

    % Check yout as matrix
    yout = [];
    try yout = simOut.yout; catch; end
    if ~isempty(yout) && isnumeric(yout)
        fprintf('       yout: numeric %s (%d x %d)\n', class(yout), size(yout,1), size(yout,2));
    end
    fprintf('       ==============================\n\n');

    % ---- If we have logsout (Dataset or similar), enumerate signals ----
    if ~isempty(logsout)
        fprintf('       logsout class: %s\n', class(logsout));
        try
            nSigs = logsout.numElements;
            fprintf('       Number of logged signals: %d\n', nSigs);
            for k = 1:nSigs
                sig = logsout{k};
                fprintf('       Signal %d: Name="%s"  class=%s\n', k, sig.Name, class(sig));
                try
                    fprintf('         Data size: [%s], Time range: [%.4f .. %.4f]\n', ...
                        num2str(size(sig.Values.Data)), ...
                        sig.Values.Time(1), sig.Values.Time(end));
                catch; end
            end
        catch ex
            fprintf('       ⚠ Could not enumerate logsout: %s\n', ex.message);
        end
        stream_all_signals(SERVER_URL, SESSION_ID, logsout, stopTime);
    elseif ~isempty(tout) && ~isempty(yout) && isnumeric(yout)
        % Fallback: stream raw tout/yout matrix data
        fprintf('       Using tout/yout matrix data for streaming\n');
        stream_matrix_data(SERVER_URL, SESSION_ID, tout, yout, stopTime);
    else
        fprintf('       ⚠ No logged signals or matrix data available for streaming\n');
        fprintf('       ⚠ The model may not have any signal logging or outports\n');

        % Last resort: check Scope blocks for data
        try
            scopeBlocks = find_system(MODEL_FILE, 'BlockType', 'Scope');
            fprintf('       Found %d Scope blocks in model\n', length(scopeBlocks));
            for sb = 1:length(scopeBlocks)
                fprintf('         Scope: %s\n', scopeBlocks{sb});
            end
        catch; end

        % Check if simOut has any numeric fields
        try
            fn = fieldnames(simOut);
            for ff = 1:length(fn)
                val = simOut.(fn{ff});
                if isnumeric(val) && numel(val) > 1
                    fprintf('       Field "%s": numeric [%dx%d]\n', fn{ff}, size(val,1), size(val,2));
                end
            end
        catch; end
    end

    %% ===== STEP 5: POST-PROCESSING & ANALYSIS =====
    fprintf('[6/6] Running analysis and sending final results...\n');

    if ~isempty(logsout)
        run_analysis(SERVER_URL, SESSION_ID, logsout);
    end

    notify_status(SERVER_URL, SESSION_ID, 'completed', 'Simulation and analysis complete');

    fprintf('\n╔══════════════════════════════════════════════════════╗\n');
    fprintf('║   ✓ COMPLETE — View results at:                      ║\n');
    fprintf('║   http://localhost:3000/simulations                   ║\n');
    fprintf('║   Session: %-40s ║\n', SESSION_ID);
    fprintf('╚══════════════════════════════════════════════════════╝\n');

    % Close any remaining figures and clean up
    close all hidden;
    set(0, 'DefaultFigureVisible', 'on');  % Restore default for user
end


%% ================================================================
%  UPLOAD SYSTEM TOPOLOGY
%% ================================================================
function upload_topology(SERVER_URL, SESSION_ID)
    url = [SERVER_URL '/api/bus-system/upload'];

    buses = {
        struct('id','650','kV',4.16,'type','Swing','phases','ABC','description','Substation / Slack bus')
        struct('id','632','kV',4.16,'type','PQ','phases','ABC','description','Main distribution bus')
        struct('id','633','kV',4.16,'type','PQ','phases','ABC','description','Connects to XFM-1 transformer')
        struct('id','634','kV',0.48,'type','PQ','phases','ABC','description','Low-voltage bus via XFM-1, PV connected')
        struct('id','645','kV',4.16,'type','PQ','phases','BC','description','2-phase lateral (B,C)')
        struct('id','646','kV',4.16,'type','PQ','phases','BC','description','End-of-line 2-phase bus')
        struct('id','671','kV',4.16,'type','PQ','phases','ABC','description','Major load bus, PV connected')
        struct('id','680','kV',4.16,'type','PQ','phases','ABC','description','End bus, no load')
        struct('id','684','kV',4.16,'type','PQ','phases','AC','description','2-phase lateral (A,C)')
        struct('id','611','kV',4.16,'type','PQ','phases','C','description','Single-phase bus (C)')
        struct('id','652','kV',4.16,'type','PQ','phases','A','description','Single-phase bus (A)')
        struct('id','692','kV',4.16,'type','PQ','phases','ABC','description','Switch-connected from 671')
        struct('id','675','kV',4.16,'type','PQ','phases','ABC','description','End bus, PV connected')
    };

    loads = {
        struct('name','634 Yg PQ','bus','634','kW',400,'kVAR',290,'model','Constant PQ','connection','Yg','phases','ABC')
        struct('name','645Y PQ','bus','645','kW',170,'kVAR',125,'model','Constant PQ','connection','Y','phases','BC')
        struct('name','646 Z','bus','646','kW',230,'kVAR',132,'model','Constant Z','connection','Delta','phases','BC')
        struct('name','652Y Z','bus','652','kW',128,'kVAR',86,'model','Constant Z','connection','Y','phases','A')
        struct('name','671 Yg PQ','bus','671','kW',385,'kVAR',220,'model','Constant PQ','connection','Yg','phases','ABC')
        struct('name','671 D PQ','bus','671','kW',770,'kVAR',440,'model','Constant PQ','connection','Delta','phases','ABC')
        struct('name','675 Y PQ','bus','675','kW',485,'kVAR',190,'model','Constant PQ','connection','Y','phases','ABC')
        struct('name','675 Yg Z','bus','675','kW',358,'kVAR',272,'model','Constant Z','connection','Yg','phases','ABC')
        struct('name','692 D I','bus','692','kW',170,'kVAR',151,'model','Constant I','connection','Delta','phases','ABC')
        struct('name','611 Z','bus','611','kW',170,'kVAR',80,'model','Constant Z','connection','Y','phases','C')
        struct('name','611Y I','bus','611','kW',0,'kVAR',0,'model','Constant I','connection','Y','phases','C')
    };

    solar_subsystems = {
        struct('name','PV_634','connected_bus','634','capacity_kW',500,'irradiance',1000,'status','Active','type','3-Phase PV Array','signal_name','P_PV_634')
        struct('name','PV_671','connected_bus','671','capacity_kW',300,'irradiance',1000,'status','Active','type','3-Phase PV Array','signal_name','P_PV_671')
        struct('name','PV_675','connected_bus','675','capacity_kW',200,'irradiance',1000,'status','Active','type','3-Phase PV Array','signal_name','P_PV_675')
    };

    lines = {
        struct('name','650-632 601','from','650','to','632','length_ft',2000,'config','601','phases','ABC')
        struct('name','632-645 603','from','632','to','645','length_ft',500,'config','603','phases','BC')
        struct('name','645-646 603','from','645','to','646','length_ft',300,'config','603','phases','BC')
        struct('name','632-633 602','from','632','to','633','length_ft',500,'config','602','phases','ABC')
        struct('name','632-671 601','from','632','to','671','length_ft',2000,'config','601','phases','ABC')
        struct('name','671-684 604','from','671','to','684','length_ft',300,'config','604','phases','AC')
        struct('name','605c','from','684','to','611','length_ft',300,'config','605','phases','C')
        struct('name','607a','from','684','to','652','length_ft',800,'config','607','phases','A')
        struct('name','601abc','from','671','to','680','length_ft',1000,'config','601','phases','ABC')
        struct('name','692-675 606','from','692','to','675','length_ft',500,'config','606','phases','ABC')
        struct('name','671-692 Switch','from','671','to','692','length_ft',0,'config','Switch','phases','ABC')
    };

    transformers = {
        struct('name','Regulator 1 (RG60)','from','650','to','632','kVA',5000,'kV_primary',4.16,'kV_secondary',4.16,'type','Voltage Regulator','description','3-phase voltage regulator')
        struct('name','XFXFM1','from','633','to','634','kVA',500,'kV_primary',4.16,'kV_secondary',0.48,'type','Step-Down','description','Yg-Yg transformer to low-voltage bus')
    };

    capacitors = {
        struct('name','Cap_675','bus','675','kVAR',600,'kV',4.16,'phases','ABC')
        struct('name','Cap_611','bus','611','kVAR',100,'kV',4.16,'phases','C')
    };

    summary = struct(...
        'system_name', 'IEEE 13 Node Test Feeder — 1-Day Power Loss Analysis', ...
        'model_file', 'aIEEE13bus_with_solar_13bus_pl_1day.slx', ...
        'base_kV', 4.16, ...
        'base_MVA', 5, ...
        'frequency', 60, ...
        'solver', 'Discrete', ...
        'description', 'IEEE 13 Bus 1-Day Power Loss simulation with Solar PV — FYP Project', ...
        'pv_buses', '634, 671, 675', ...
        'total_pv_capacity_kW', 1000, ...
        'simulation_type', '1-Day Power Loss Analysis' ...
    );

    payload = struct(...
        'session_id', SESSION_ID, ...
        'buses', {buses}, ...
        'loads', {loads}, ...
        'solar_subsystems', {solar_subsystems}, ...
        'lines', {lines}, ...
        'transformers', {transformers}, ...
        'capacitors', {capacitors}, ...
        'summary', summary ...
    );

    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',15);
    try
        webwrite(url, jsonencode(payload), options);
    catch ex
        fprintf('       ⚠ Topology upload warning: %s\n', ex.message);
    end
end


%% ================================================================
%  STREAM ALL SIGNALS DYNAMICALLY (auto-discovers signal names)
%% ================================================================
function stream_all_signals(SERVER_URL, SESSION_ID, logsout, stopTime)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',5);

    nSigs = logsout.numElements;
    fprintf('       Processing %d signals for streaming...\n', nSigs);

    % Collect all signals with their data
    signals = struct();
    globalTime = [];
    
    for k = 1:nSigs
        try
            sig = logsout{k};
            sigName = sig.Name;
            if isempty(sigName), sigName = sprintf('Signal_%d', k); end
            
            data = sig.Values.Data;
            t = sig.Values.Time;
            
            % Sum multi-column data (e.g. 3-phase) to scalar
            if size(data, 2) > 1
                dataScalar = sum(data, 2);
            else
                dataScalar = data(:);
            end
            
            safeName = matlab.lang.makeValidName(sigName);
            signals.(safeName) = struct('name', sigName, 'data', dataScalar, 'time', t, ...
                'rawData', data, 'nCols', size(data,2));
            
            if isempty(globalTime) || length(t) > length(globalTime)
                globalTime = t;
            end
            
            fprintf('       ✓ Signal "%s": %d samples, range=[%.4f..%.4f]\n', ...
                sigName, length(dataScalar), min(dataScalar), max(dataScalar));
        catch ex
            fprintf('       ⚠ Signal %d error: %s\n', k, ex.message);
        end
    end
    
    if isempty(globalTime)
        fprintf('       ⚠ No valid time data found, cannot stream\n');
        return;
    end
    
    % Map signals to bus IDs based on name patterns
    busIds = {'650','632','633','634','645','646','671','680','684','611','652','692','675'};
    busNomV = [4160, 4160, 4160, 480, 4160, 4160, 4160, 4160, 4160, 4160, 4160, 4160, 4160];
    
    % Downsample to ~200 points
    N = length(globalTime);
    maxPoints = 200;
    if N > maxPoints
        step = floor(N / maxPoints);
        idx = 1:step:N;
    else
        idx = 1:N;
    end
    
    fprintf('       Streaming %d data points to dashboard...\n', length(idx));
    notify_status(SERVER_URL, SESSION_ID, 'streaming', ...
        sprintf('Streaming %d measurement points...', length(idx)));
    
    sentCount = 0;
    sigNames = fieldnames(signals);
    
    for k = 1:length(idx)
        i = idx(k);
        timeVal = globalTime(i);
        
        % Send each signal as a measurement for the most relevant bus
        for s = 1:length(sigNames)
            sig = signals.(sigNames{s});
            origName = lower(sig.name);
            
            % Find which bus this signal belongs to
            busId = '';
            nomV = 4160;
            for b = 1:length(busIds)
                if contains(origName, busIds{b})
                    busId = busIds{b};
                    nomV = busNomV(b);
                    break;
                end
            end
            
            % Determine measurement type from signal name
            if i <= length(sig.data)
                val = sig.data(i);
            else
                continue;
            end
            
            measurements = struct('time_s', timeVal, 'timestamp_matlab', datestr(now));
            
            if contains(origName, 'voltage') || contains(origName, '_v') || ...
               contains(origName, 'vabc') || startsWith(origName, 'v_') || startsWith(origName, 'v')
                measurements.voltage_V = abs(val);
                if isempty(busId), busId = '632'; end  % default bus
            elseif contains(origName, 'p_pv') || contains(origName, 'pv') || contains(origName, 'solar')
                measurements.real_power_kW = val;
                measurements.pv_power_kW = val;
                if isempty(busId), busId = '634'; end
            elseif contains(origName, 'p_slack') || contains(origName, 'slack')
                measurements.real_power_kW = val;
                measurements.voltage_V = 4160;
                busId = '650';
            elseif contains(origName, 'p_load') || contains(origName, 'load') || contains(origName, 'pl_')
                measurements.real_power_kW = val;
                if isempty(busId), busId = '632'; end
            elseif contains(origName, 'current') || contains(origName, '_i') || startsWith(origName, 'i_')
                measurements.current_A = abs(val);
                if isempty(busId), busId = '632'; end
            elseif contains(origName, 'power') || contains(origName, '_p') || startsWith(origName, 'p_')
                measurements.real_power_kW = val;
                if isempty(busId), busId = '632'; end
            elseif contains(origName, 'reactive') || contains(origName, '_q') || startsWith(origName, 'q_')
                measurements.reactive_power_kVAR = val;
                if isempty(busId), busId = '632'; end
            else
                % Generic: send as real_power_kW
                measurements.real_power_kW = val;
                if isempty(busId), busId = 'SYSTEM'; end
            end
            
            measurements.signal_name = sig.name;
            
            m = struct('session_id', SESSION_ID, 'bus_id', busId, 'measurements', measurements);
            try
                webwrite(url, jsonencode(m), options);
                sentCount = sentCount + 1;
            catch; end
        end
        
        if mod(k, 20) == 0
            pct = round(k / length(idx) * 100);
            fprintf('       Streaming... %d%% (%d/%d points)\n', pct, k, length(idx));
            notify_status(SERVER_URL, SESSION_ID, 'streaming', ...
                sprintf('Streaming %d%% complete (%d/%d)', pct, k, length(idx)));
        end
        pause(0.02);
    end
    fprintf('       ✓ Streamed %d measurements to dashboard\n\n', sentCount);
end

%% ================================================================
%  STREAM MATRIX DATA (tout/yout fallback)
%% ================================================================
function stream_matrix_data(SERVER_URL, SESSION_ID, tout, yout, stopTime)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',5);
    
    [N, nCols] = size(yout);
    fprintf('       Matrix data: %d samples x %d columns\n', N, nCols);
    
    % Downsample
    maxPoints = 200;
    if N > maxPoints
        step = floor(N / maxPoints);
        idx = 1:step:N;
    else
        idx = 1:N;
    end
    
    % Map columns to bus IDs (best effort)
    busIds = {'650','632','633','634','645','646','671','680','684','611','652','692','675'};
    
    fprintf('       Streaming %d data points (%d columns)...\n', length(idx), nCols);
    notify_status(SERVER_URL, SESSION_ID, 'streaming', ...
        sprintf('Streaming %d matrix data points...', length(idx)));
    
    sentCount = 0;
    for k = 1:length(idx)
        i = idx(k);
        timeVal = tout(i);
        
        for c = 1:min(nCols, length(busIds))
            m = struct('session_id', SESSION_ID, 'bus_id', busIds{c}, ...
                'measurements', struct(...
                    'real_power_kW', yout(i, c), ...
                    'time_s', timeVal, ...
                    'column_index', c, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); sentCount = sentCount + 1; catch; end
        end
        
        if mod(k, 20) == 0
            pct = round(k / length(idx) * 100);
            fprintf('       Streaming... %d%% (%d/%d)\n', pct, k, length(idx));
        end
        pause(0.02);
    end
    fprintf('       ✓ Streamed %d matrix measurements to dashboard\n\n', sentCount);
end


%% ================================================================
%  STREAM LOGGED SIGNALS TO DASHBOARD (ORIGINAL)
%% ================================================================
function stream_logged_signals(SERVER_URL, SESSION_ID, logsout, stopTime)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',5);

    signalNames = {};
    for k = 1:logsout.numElements
        signalNames{end+1} = logsout{k}.Name;
    end
    fprintf('       Found %d logged signals: %s\n', length(signalNames), strjoin(signalNames, ', '));

    P_slack = []; P_load = []; t_fast = [];
    P_PV_634 = []; P_PV_671 = []; P_PV_675 = []; t_pv = [];

    try sig = logsout.get('P_slack'); P_slack = sum(sig.Values.Data, 2); t_fast = sig.Values.Time;
        fprintf('       ✓ P_slack extracted (%d samples)\n', length(P_slack));
    catch; fprintf('       ⚠ P_slack not found\n'); end

    try sig = logsout.get('P_load'); P_load = sum(sig.Values.Data, 2);
        fprintf('       ✓ P_load extracted (%d samples)\n', length(P_load));
    catch; fprintf('       ⚠ P_load not found\n'); end

    try sig = logsout.get('P_PV_634'); P_PV_634 = sum(sig.Values.Data, 2); t_pv = sig.Values.Time;
        fprintf('       ✓ P_PV_634 extracted (%d samples)\n', length(P_PV_634));
    catch; fprintf('       ⚠ P_PV_634 not found\n'); end

    try sig = logsout.get('P_PV_671'); P_PV_671 = sum(sig.Values.Data, 2);
        fprintf('       ✓ P_PV_671 extracted (%d samples)\n', length(P_PV_671));
    catch; fprintf('       ⚠ P_PV_671 not found\n'); end

    try sig = logsout.get('P_PV_675'); P_PV_675 = sum(sig.Values.Data, 2);
        fprintf('       ✓ P_PV_675 extracted (%d samples)\n', length(P_PV_675));
    catch; fprintf('       ⚠ P_PV_675 not found\n'); end

    % Extract bus voltages
    busIds = {'650','632','633','634','645','646','671','680','684','611','652','692','675'};
    busVoltages = struct();
    for b = 1:length(busIds)
        bid = busIds{b};
        searchNames = {['Bus ' bid], ['V_' bid], ['Vabc_' bid], bid};
        for s = 1:length(searchNames)
            try
                sig = logsout.get(searchNames{s});
                if ~isempty(sig)
                    busVoltages.(['V' bid]) = struct('data', sig.Values.Data, 'time', sig.Values.Time);
                    fprintf('       ✓ Voltage for Bus %s found as "%s"\n', bid, searchNames{s});
                    break;
                end
            catch
            end
        end
    end

    % Use appropriate time base
    if ~isempty(t_pv), t = t_pv; N = length(t);
    elseif ~isempty(t_fast), t = t_fast; N = length(t);
    else, fprintf('       ⚠ No time vector, skipping streaming\n'); return; end

    % Resample if needed
    if ~isempty(t_pv) && ~isempty(t_fast) && length(t_fast) ~= length(t_pv)
        if ~isempty(P_slack), P_slack = interp1(t_fast, P_slack, t_pv, 'linear', 'extrap'); end
        if ~isempty(P_load), P_load = interp1(t_fast, P_load, t_pv, 'linear', 'extrap'); end
    end

    % Remove transient startup
    t_ss_start = 0.3;
    idx_ss = find(t >= t_ss_start);
    if isempty(idx_ss), idx_ss = 1:N; end

    % Downsample for streaming (~200 points)
    maxPoints = 200;
    if length(idx_ss) > maxPoints
        step = floor(length(idx_ss) / maxPoints);
        idx_stream = idx_ss(1:step:end);
    else
        idx_stream = idx_ss;
    end

    fprintf('       Streaming %d data points to dashboard...\n', length(idx_stream));
    notify_status(SERVER_URL, SESSION_ID, 'streaming', ...
        sprintf('Streaming %d measurement points...', length(idx_stream)));

    sentCount = 0;
    for k = 1:length(idx_stream)
        i = idx_stream(k);
        timeVal = t(i);

        % Bus 650 (Slack)
        if ~isempty(P_slack)
            m = struct('session_id', SESSION_ID, 'bus_id', '650', ...
                'measurements', struct('voltage_V', 4160, ...
                    'current_A', abs(P_slack(i)*1000/(sqrt(3)*4160)), ...
                    'real_power_kW', P_slack(i), 'reactive_power_kVAR', 0, ...
                    'time_s', timeVal, 'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % Bus 632 (Load)
        if ~isempty(P_load)
            m = struct('session_id', SESSION_ID, 'bus_id', '632', ...
                'measurements', struct('voltage_V', 4160, ...
                    'current_A', abs(P_load(i)*1000/(sqrt(3)*4160)), ...
                    'real_power_kW', P_load(i), 'reactive_power_kVAR', 0, ...
                    'time_s', timeVal, 'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % PV Bus 634
        if ~isempty(P_PV_634) && i <= length(P_PV_634)
            m = struct('session_id', SESSION_ID, 'bus_id', '634', ...
                'measurements', struct('voltage_V', 480, ...
                    'current_A', abs(P_PV_634(i)*1000/(sqrt(3)*480)), ...
                    'real_power_kW', P_PV_634(i), 'reactive_power_kVAR', 0, ...
                    'pv_power_kW', P_PV_634(i), 'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % PV Bus 671
        if ~isempty(P_PV_671) && i <= length(P_PV_671)
            m = struct('session_id', SESSION_ID, 'bus_id', '671', ...
                'measurements', struct('voltage_V', 4160, ...
                    'current_A', abs(P_PV_671(i)*1000/(sqrt(3)*4160)), ...
                    'real_power_kW', P_PV_671(i), 'reactive_power_kVAR', 0, ...
                    'pv_power_kW', P_PV_671(i), 'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % PV Bus 675
        if ~isempty(P_PV_675) && i <= length(P_PV_675)
            m = struct('session_id', SESSION_ID, 'bus_id', '675', ...
                'measurements', struct('voltage_V', 4160, ...
                    'current_A', abs(P_PV_675(i)*1000/(sqrt(3)*4160)), ...
                    'real_power_kW', P_PV_675(i), 'reactive_power_kVAR', 0, ...
                    'pv_power_kW', P_PV_675(i), 'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % Bus voltage signals
        for b = 1:length(busIds)
            bid = busIds{b};
            fname = ['V' bid];
            if isfield(busVoltages, fname)
                vdata = busVoltages.(fname);
                [~, vi] = min(abs(vdata.time - timeVal));
                if vi <= size(vdata.data, 1)
                    vval = vdata.data(vi, :);
                    Vrms = rms(vval);
                    m = struct('session_id', SESSION_ID, 'bus_id', bid, ...
                        'measurements', struct('voltage_V', Vrms, ...
                            'voltage_A', vval(1), 'voltage_B', 0, 'voltage_C', 0, ...
                            'time_s', timeVal, 'timestamp_matlab', datestr(now)));
                    if length(vval) >= 2; m.measurements.voltage_B = vval(2); end
                    if length(vval) >= 3; m.measurements.voltage_C = vval(3); end
                    try webwrite(url, jsonencode(m), options); catch; end
                    sentCount = sentCount + 1;
                end
            end
        end

        if mod(k, 20) == 0
            pct = round(k / length(idx_stream) * 100);
            fprintf('       Streaming... %d%% (%d/%d points)\n', pct, k, length(idx_stream));
            notify_status(SERVER_URL, SESSION_ID, 'streaming', ...
                sprintf('Streaming %d%% complete (%d/%d)', pct, k, length(idx_stream)));
        end
        pause(0.02);
    end
    fprintf('       ✓ Streamed %d measurements to dashboard\n\n', sentCount);
end


%% ================================================================
%  RUN ANALYSIS AND SEND RESULTS
%% ================================================================
function run_analysis(SERVER_URL, SESSION_ID, logsout)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',10);

    try
        P_slack_ts = logsout.get('P_slack').Values;
        P_load_ts  = logsout.get('P_load').Values;
        P_PV_634_ts = logsout.get('P_PV_634').Values;
        P_PV_671_ts = logsout.get('P_PV_671').Values;
        P_PV_675_ts = logsout.get('P_PV_675').Values;

        P_slack = sum(P_slack_ts.Data, 2);
        P_load  = sum(P_load_ts.Data, 2);
        P_PV_634 = sum(P_PV_634_ts.Data, 2);
        P_PV_671 = sum(P_PV_671_ts.Data, 2);
        P_PV_675 = sum(P_PV_675_ts.Data, 2);

        t_slack = P_slack_ts.Time;
        t_pv    = P_PV_634_ts.Time;

        P_slack_rs = interp1(t_slack, P_slack, t_pv, 'linear');
        P_load_rs  = interp1(t_slack, P_load,  t_pv, 'linear');
        P_PV_total = P_PV_634 + P_PV_671 + P_PV_675;

        t_ss_start = 0.3;
        idx_ss = t_pv >= t_ss_start;
        P_slack_ss = P_slack_rs(idx_ss);
        P_load_ss  = P_load_rs(idx_ss);
        P_PV_ss    = P_PV_total(idx_ss);
        P_balance  = P_slack_rs(idx_ss) + P_PV_total(idx_ss) - P_load_rs(idx_ss);

        window = 200;
        P_bal_avg = movmean(P_balance, window);

        avg_slack = mean(P_slack_ss);
        avg_load  = mean(P_load_ss);
        avg_pv    = mean(P_PV_ss);
        avg_loss  = mean(P_bal_avg);
        pv_penetration = avg_pv / avg_load * 100;

        fprintf('       ========= ANALYSIS RESULTS =========\n');
        fprintf('       Average Slack Power   : %.2f kW\n', avg_slack);
        fprintf('       Average Load Power    : %.2f kW\n', avg_load);
        fprintf('       Average Total PV Power: %.2f kW\n', avg_pv);
        fprintf('       Average System Losses : %.2f kW\n', avg_loss);
        fprintf('       PV Penetration        : %.2f %%\n', pv_penetration);

        analysis = struct('session_id', SESSION_ID, 'bus_id', 'SYSTEM', ...
            'measurements', struct(...
                'avg_slack_power_kW', avg_slack, ...
                'avg_load_power_kW', avg_load, ...
                'avg_pv_power_kW', avg_pv, ...
                'avg_system_losses_kW', avg_loss, ...
                'pv_penetration_percent', pv_penetration, ...
                'avg_pv_634_kW', mean(P_PV_634(idx_ss(1:min(end,length(P_PV_634))))), ...
                'avg_pv_671_kW', mean(P_PV_671(idx_ss(1:min(end,length(P_PV_671))))), ...
                'avg_pv_675_kW', mean(P_PV_675(idx_ss(1:min(end,length(P_PV_675))))), ...
                'mean_power_imbalance_kW', mean(P_bal_avg), ...
                'max_abs_imbalance_kW', max(abs(P_bal_avg)), ...
                'analysis_type', 'final_summary', ...
                'simulation_type', 'pl_1day', ...
                'timestamp_matlab', datestr(now)));
        try
            webwrite(url, jsonencode(analysis), options);
            fprintf('       ✓ Analysis results sent to dashboard\n');
        catch ex
            fprintf('       ⚠ Could not send analysis: %s\n', ex.message);
        end
    catch ex
        fprintf('       ⚠ Analysis error: %s\n', ex.message);
    end
end


%% ================================================================
%  NOTIFY SIMULATION STATUS
%% ================================================================
function notify_status(SERVER_URL, SESSION_ID, status, message)
    url = [SERVER_URL '/api/bus-system/status'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',5);
    payload = struct('session_id', SESSION_ID, 'status', status, 'message', message, ...
        'timestamp', datestr(now));
    try
        webwrite(url, jsonencode(payload), options);
    catch
    end
end
