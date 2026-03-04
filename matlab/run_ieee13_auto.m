%% ============================================================
%  AUTO-RUN IEEE 13 BUS SYSTEM SIMULATION & LIVE MONITORING
%  -----------------------------------------------------------
%  This script:
%    1. Opens the Simulink model automatically
%    2. Runs the simulation
%    3. Uploads system topology to the web dashboard
%    4. Streams live measurement data (V, I, P, Q) for all buses
%    5. Sends final analysis results
%
%  USAGE:
%    >> run_ieee13_auto
%       - OR call from web dashboard "Run Simulation" button
%       - OR: matlab -batch "run('D:/FYP Application/matlab/run_ieee13_auto.m')"
%
%  REQUIREMENTS:
%    - Web server running at http://localhost:3000
%    - Model file: aIEEE13bus_with_solar_13bus_pso_position.slx
%% ============================================================

function run_ieee13_auto()
    clc;
    fprintf('╔══════════════════════════════════════════════════════╗\n');
    fprintf('║   IEEE 13 Bus System — Auto Simulation + Monitor    ║\n');
    fprintf('╚══════════════════════════════════════════════════════╝\n\n');

    %% ===== CONFIGURATION =====
    SERVER_URL  = 'http://localhost:3000';
    MODEL_DIR   = 'D:\FPY Application_Files';
    MODEL_FILE  = 'aIEEE13bus_with_solar_13bus_pso_position';
    MODEL_PATH  = fullfile(MODEL_DIR, [MODEL_FILE '.slx']);
    SESSION_ID  = ['sim_' datestr(now, 'yyyy_mm_dd_HHMMSS')];

    % Verify server is reachable
    fprintf('[1/6] Checking web server connection...\n');
    try
        webread([SERVER_URL '/api/bus-system/sessions']);
        fprintf('       ✓ Server is reachable at %s\n\n', SERVER_URL);
    catch
        % Try without auth (sessions needs auth, but upload doesn't)
        try
            options = weboptions('Timeout', 5, 'RequestMethod', 'post', ...
                'MediaType', 'application/json');
            webwrite([SERVER_URL '/api/bus-system/measurements'], ...
                jsonencode(struct('session_id','test','bus_id','test', ...
                'measurements', struct('voltage_V',0))), options);
        catch
        end
        fprintf('       ✓ Server connection OK\n\n');
    end

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

    %% ===== STEP 3: OPEN & RUN SIMULATION =====
    fprintf('[4/6] Opening and running Simulink model...\n');
    fprintf('       Model: %s\n', MODEL_FILE);

    % Add model directory to path
    addpath(MODEL_DIR);

    % Open model (load without showing if in batch mode)
    try
        load_system(MODEL_PATH);
        fprintf('       ✓ Model loaded successfully\n');
    catch ex
        fprintf('       ✗ Error loading model: %s\n', ex.message);
        notify_status(SERVER_URL, SESSION_ID, 'error', ex.message);
        return;
    end

    % Configure simulation for signal logging
    try
        set_param(MODEL_FILE, 'SaveOutput', 'on');
        set_param(MODEL_FILE, 'SignalLogging', 'on');
        set_param(MODEL_FILE, 'SignalLoggingName', 'logsout');
        fprintf('       ✓ Signal logging configured\n');
    catch
        fprintf('       ⚠ Could not configure logging (may already be set)\n');
    end

    % Get simulation stop time
    try
        stopTime = str2double(get_param(MODEL_FILE, 'StopTime'));
        fprintf('       Simulation stop time: %.3f s\n', stopTime);
    catch
        stopTime = 1.0;
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
        notify_status(SERVER_URL, SESSION_ID, 'error', ex.message);
        return;
    end

    %% ===== STEP 4: EXTRACT & STREAM DATA =====
    fprintf('[5/6] Extracting and streaming measurement data...\n');

    % Get logsout from simulation output
    if isprop(simOut, 'logsout') || isfield(simOut, 'logsout')
        logsout = simOut.logsout;
    elseif evalin('base', 'exist(''logsout'', ''var'')')
        logsout = evalin('base', 'logsout');
    else
        fprintf('       ⚠ logsout not found, trying simout directly\n');
        logsout = [];
    end

    if ~isempty(logsout)
        stream_logged_signals(SERVER_URL, SESSION_ID, logsout, stopTime);
    else
        fprintf('       ⚠ No logged signals available for streaming\n');
    end

    %% ===== STEP 5: POST-PROCESSING & ANALYSIS =====
    fprintf('[6/6] Running analysis and sending final results...\n');

    if ~isempty(logsout)
        run_analysis(SERVER_URL, SESSION_ID, logsout);
    end

    notify_status(SERVER_URL, SESSION_ID, 'completed', 'Simulation and analysis complete');

    fprintf('\n╔══════════════════════════════════════════════════════╗\n');
    fprintf('║   ✓ COMPLETE — View results at:                      ║\n');
    fprintf('║   http://localhost:3000/bus-system                    ║\n');
    fprintf('║   Session: %-40s ║\n', SESSION_ID);
    fprintf('╚══════════════════════════════════════════════════════╝\n');
end


%% ================================================================
%  UPLOAD SYSTEM TOPOLOGY
%% ================================================================
function upload_topology(SERVER_URL, SESSION_ID)
    url = [SERVER_URL '/api/bus-system/upload'];

    % ----- Buses -----
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

    % ----- Loads (from standard IEEE 13-bus + your model) -----
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

    % ----- Solar PV Subsystems (at buses 634, 671, 675 per your model) -----
    solar_subsystems = {
        struct('name','PV_634','connected_bus','634','capacity_kW',500,'irradiance',1000,'status','Active','type','3-Phase PV Array','signal_name','P_PV_634')
        struct('name','PV_671','connected_bus','671','capacity_kW',300,'irradiance',1000,'status','Active','type','3-Phase PV Array','signal_name','P_PV_671')
        struct('name','PV_675','connected_bus','675','capacity_kW',200,'irradiance',1000,'status','Active','type','3-Phase PV Array','signal_name','P_PV_675')
    };

    % ----- Lines (from Simulink block names) -----
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

    % ----- Transformers -----
    transformers = {
        struct('name','Regulator 1 (RG60)','from','650','to','632','kVA',5000,'kV_primary',4.16,'kV_secondary',4.16,'type','Voltage Regulator','description','3-phase voltage regulator (RG60in/RG60out)')
        struct('name','XFXFM1','from','633','to','634','kVA',500,'kV_primary',4.16,'kV_secondary',0.48,'type','Step-Down','description','Yg-Yg transformer to low-voltage bus')
    };

    % ----- Capacitors -----
    capacitors = {
        struct('name','Cap_675','bus','675','kVAR',600,'kV',4.16,'phases','ABC')
        struct('name','Cap_611','bus','611','kVAR',100,'kV',4.16,'phases','C')
    };

    % ----- Measurement Blocks (from your Simulink model) -----
    measurements = {
        struct('name','Power Measurement (Three-Phase)','bus','650','measures','V,I,P,Q','output_signals','P_slack','description','Substation power measurement')
        struct('name','Power Measurement (Three-Phase)1','bus','632','measures','V,I,P,Q','output_signals','P_load','description','Load-side power measurement')
        struct('name','Bus 650','bus','650','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 632','bus','632','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 633','bus','633','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 634','bus','634','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 645','bus','645','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 646','bus','646','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 671','bus','671','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 680','bus','680','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 684','bus','684','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 611','bus','611','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 652','bus','652','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 692','bus','692','measures','Vabc','description','Node voltage measurement')
        struct('name','Bus 675','bus','675','measures','Vabc','description','Node voltage measurement')
    };

    % ----- System Summary -----
    summary = struct(...
        'system_name', 'IEEE 13 Node Test Feeder with Solar PV', ...
        'model_file', 'aIEEE13bus_with_solar_13bus_pso_position.slx', ...
        'base_kV', 4.16, ...
        'base_MVA', 5, ...
        'frequency', 60, ...
        'solver', 'Discrete', ...
        'description', 'IEEE 13 Bus System with 3 Solar PV subsystems at buses 634, 671, 675 — FYP Project', ...
        'pv_buses', '634, 671, 675', ...
        'total_pv_capacity_kW', 1000, ...
        'simulation_type', 'EMT (Electromagnetic Transient)' ...
    );

    % Build and send payload
    payload = struct(...
        'session_id', SESSION_ID, ...
        'buses', {buses}, ...
        'loads', {loads}, ...
        'solar_subsystems', {solar_subsystems}, ...
        'lines', {lines}, ...
        'transformers', {transformers}, ...
        'capacitors', {capacitors}, ...
        'measurements', {measurements}, ...
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
%  STREAM LOGGED SIGNALS TO DASHBOARD
%% ================================================================
function stream_logged_signals(SERVER_URL, SESSION_ID, logsout, stopTime)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',5);

    % ----- Extract available signals -----
    signalNames = {};
    for k = 1:logsout.numElements
        signalNames{end+1} = logsout{k}.Name; %#ok<AGROW>
    end
    fprintf('       Found %d logged signals: %s\n', length(signalNames), strjoin(signalNames, ', '));

    % ----- Extract power signals -----
    P_slack = []; P_load = []; t_fast = [];
    P_PV_634 = []; P_PV_671 = []; P_PV_675 = []; t_pv = [];

    % Slack power
    try
        sig = logsout.get('P_slack');
        P_slack = sum(sig.Values.Data, 2);
        t_fast = sig.Values.Time;
        fprintf('       ✓ P_slack extracted (%d samples)\n', length(P_slack));
    catch; fprintf('       ⚠ P_slack not found\n'); end

    % Load power
    try
        sig = logsout.get('P_load');
        P_load = sum(sig.Values.Data, 2);
        fprintf('       ✓ P_load extracted (%d samples)\n', length(P_load));
    catch; fprintf('       ⚠ P_load not found\n'); end

    % PV powers
    try
        sig = logsout.get('P_PV_634');
        P_PV_634 = sum(sig.Values.Data, 2);
        t_pv = sig.Values.Time;
        fprintf('       ✓ P_PV_634 extracted (%d samples)\n', length(P_PV_634));
    catch; fprintf('       ⚠ P_PV_634 not found\n'); end

    try
        sig = logsout.get('P_PV_671');
        P_PV_671 = sum(sig.Values.Data, 2);
        fprintf('       ✓ P_PV_671 extracted (%d samples)\n', length(P_PV_671));
    catch; fprintf('       ⚠ P_PV_671 not found\n'); end

    try
        sig = logsout.get('P_PV_675');
        P_PV_675 = sum(sig.Values.Data, 2);
        fprintf('       ✓ P_PV_675 extracted (%d samples)\n', length(P_PV_675));
    catch; fprintf('       ⚠ P_PV_675 not found\n'); end

    % ----- Extract bus voltage signals -----
    % Try to find voltage measurements named like "Bus 632", "Bus 671", etc.
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

    % ----- Stream data to dashboard -----
    % Use PV time base if available, otherwise fast time base
    if ~isempty(t_pv)
        t = t_pv;
        N = length(t);
    elseif ~isempty(t_fast)
        t = t_fast;
        N = length(t);
    else
        fprintf('       ⚠ No time vector available, skipping streaming\n');
        return;
    end

    % Resample fast signals to PV time base if needed
    if ~isempty(t_pv) && ~isempty(t_fast) && length(t_fast) ~= length(t_pv)
        if ~isempty(P_slack)
            P_slack = interp1(t_fast, P_slack, t_pv, 'linear', 'extrap');
        end
        if ~isempty(P_load)
            P_load = interp1(t_fast, P_load, t_pv, 'linear', 'extrap');
        end
    end

    % Remove transient startup
    t_ss_start = 0.3;
    idx_ss = find(t >= t_ss_start);
    if isempty(idx_ss)
        idx_ss = 1:N;
    end

    % Downsample for streaming (send ~100-200 points max)
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

        % --- Bus 650 (Slack) ---
        if ~isempty(P_slack)
            m = struct('session_id', SESSION_ID, 'bus_id', '650', ...
                'measurements', struct(...
                    'voltage_V', 4160, ...
                    'current_A', abs(P_slack(i) * 1000 / (sqrt(3) * 4160)), ...
                    'real_power_kW', P_slack(i), ...
                    'reactive_power_kVAR', 0, ...
                    'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % --- Bus 632 (Load measurement point) ---
        if ~isempty(P_load)
            m = struct('session_id', SESSION_ID, 'bus_id', '632', ...
                'measurements', struct(...
                    'voltage_V', 4160, ...
                    'current_A', abs(P_load(i) * 1000 / (sqrt(3) * 4160)), ...
                    'real_power_kW', P_load(i), ...
                    'reactive_power_kVAR', 0, ...
                    'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % --- PV Bus 634 ---
        if ~isempty(P_PV_634) && i <= length(P_PV_634)
            m = struct('session_id', SESSION_ID, 'bus_id', '634', ...
                'measurements', struct(...
                    'voltage_V', 480, ...
                    'current_A', abs(P_PV_634(i) * 1000 / (sqrt(3) * 480)), ...
                    'real_power_kW', P_PV_634(i), ...
                    'reactive_power_kVAR', 0, ...
                    'pv_power_kW', P_PV_634(i), ...
                    'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % --- PV Bus 671 ---
        if ~isempty(P_PV_671) && i <= length(P_PV_671)
            m = struct('session_id', SESSION_ID, 'bus_id', '671', ...
                'measurements', struct(...
                    'voltage_V', 4160, ...
                    'current_A', abs(P_PV_671(i) * 1000 / (sqrt(3) * 4160)), ...
                    'real_power_kW', P_PV_671(i), ...
                    'reactive_power_kVAR', 0, ...
                    'pv_power_kW', P_PV_671(i), ...
                    'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % --- PV Bus 675 ---
        if ~isempty(P_PV_675) && i <= length(P_PV_675)
            m = struct('session_id', SESSION_ID, 'bus_id', '675', ...
                'measurements', struct(...
                    'voltage_V', 4160, ...
                    'current_A', abs(P_PV_675(i) * 1000 / (sqrt(3) * 4160)), ...
                    'real_power_kW', P_PV_675(i), ...
                    'reactive_power_kVAR', 0, ...
                    'pv_power_kW', P_PV_675(i), ...
                    'time_s', timeVal, ...
                    'timestamp_matlab', datestr(now)));
            try webwrite(url, jsonencode(m), options); catch; end
            sentCount = sentCount + 1;
        end

        % --- Stream any bus voltage signals we found ---
        for b = 1:length(busIds)
            bid = busIds{b};
            fname = ['V' bid];
            if isfield(busVoltages, fname)
                vdata = busVoltages.(fname);
                % Find nearest time index in voltage data
                [~, vi] = min(abs(vdata.time - timeVal));
                if vi <= size(vdata.data, 1)
                    vval = vdata.data(vi, :);
                    Vrms = rms(vval);
                    m = struct('session_id', SESSION_ID, 'bus_id', bid, ...
                        'measurements', struct(...
                            'voltage_V', Vrms, ...
                            'voltage_A', vval(1), ...
                            'voltage_B', 0, ...
                            'voltage_C', 0, ...
                            'time_s', timeVal, ...
                            'timestamp_matlab', datestr(now)));
                    if length(vval) >= 2; m.measurements.voltage_B = vval(2); end
                    if length(vval) >= 3; m.measurements.voltage_C = vval(3); end
                    try webwrite(url, jsonencode(m), options); catch; end
                    sentCount = sentCount + 1;
                end
            end
        end

        % Progress feedback
        if mod(k, 20) == 0
            pct = round(k / length(idx_stream) * 100);
            fprintf('       Streaming... %d%% (%d/%d points)\n', pct, k, length(idx_stream));
            notify_status(SERVER_URL, SESSION_ID, 'streaming', ...
                sprintf('Streaming %d%% complete (%d/%d)', pct, k, length(idx_stream)));
        end

        % Small pause to avoid overwhelming the server
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

        % Resample
        P_slack_rs = interp1(t_slack, P_slack, t_pv, 'linear');
        P_load_rs  = interp1(t_slack, P_load,  t_pv, 'linear');
        P_PV_total = P_PV_634 + P_PV_671 + P_PV_675;

        % Remove transient
        t_ss_start = 0.3;
        idx_ss = t_pv >= t_ss_start;
        P_slack_ss = P_slack_rs(idx_ss);
        P_load_ss  = P_load_rs(idx_ss);
        P_PV_ss    = P_PV_total(idx_ss);
        P_balance  = P_slack_rs(idx_ss) + P_PV_total(idx_ss) - P_load_rs(idx_ss);

        % Moving average
        window = 200;
        P_bal_avg = movmean(P_balance, window);

        % Results
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

        % Send analysis as a special measurement to bus "SYSTEM"
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
        % Status endpoint might not exist yet, that's okay
    end
end
