%% ============================================================
%  AUTO-RUN IEEE 13 BUS (GA-WP) SIMULATION & LIVE MONITORING
%  -----------------------------------------------------------
%  This script:
%    1. Generates real weather data (solar irradiance + temperature)
%    2. Defines required power-system parameters
%    3. Opens the GA-WP Simulink model
%    4. Runs the simulation
%    5. Streams live measurement data to the web dashboard
%    6. Runs post-processing analysis (power balance)
%    7. Sends final summary results
%
%  USAGE:
%    >> run_ga_wp_auto
%    OR from Node.js: matlab -r "run('D:/FYP Application/matlab/run_ga_wp_auto.m')"
%
%  REQUIREMENTS:
%    - Web server running at http://localhost:3000
%    - Model: aIEEE13bus_with_solar_13bus_GA_wp.slx
%    - Script: weather_generator_1day.m
%% ============================================================

function run_ga_wp_auto()
    clc;
    fprintf('==============================================================\n');
    fprintf('   IEEE 13 Bus System (GA-WP) -- Auto Simulation + Monitor\n');
    fprintf('==============================================================\n\n');

    %% ===== CONFIGURATION =====
    MODEL_DIR   = 'D:\FPY Application_Files';
    MODEL_FILE  = 'aIEEE13bus_with_solar_13bus_GA_wp';
    MODEL_PATH  = fullfile(MODEL_DIR, [MODEL_FILE '.slx']);

    %% ===== STEP 1: GENERATE WEATHER DATA FIRST =====
    % (weather_generator_1day.m starts with 'clear' which wipes all vars)
    fprintf('[1/7] Generating weather data...\n');
    addpath(MODEL_DIR);
    cd(MODEL_DIR);

    weatherScript = fullfile(MODEL_DIR, 'weather_generator_1day.m');
    if ~exist(weatherScript, 'file')
        weatherScript = fullfile(MODEL_DIR, 'weather_generator_1day (1).m');
    end
    if ~exist(weatherScript, 'file')
        error('Weather script not found in %s', MODEL_DIR);
    end

    try
        run(weatherScript);
        fprintf('       OK - Weather data generated\n\n');
    catch ex
        fprintf('       ERROR generating weather data: %s\n', ex.message);
        return;
    end

    %% ===== STEP 2: RE-DEFINE CONFIGURATION (after clear) =====
    % All variables were cleared by weather script, so re-define them now
    SERVER_URL  = 'http://localhost:3000';
    MODEL_DIR   = 'D:\FPY Application_Files';
    MODEL_FILE  = 'aIEEE13bus_with_solar_13bus_GA_wp';
    MODEL_PATH  = fullfile(MODEL_DIR, [MODEL_FILE '.slx']);
    SESSION_ID  = ['ga_wp_' datestr(now, 'yyyy_mm_dd_HHMMSS')];

    fprintf('[2/7] Checking web server connection...\n');
    try
        webread([SERVER_URL '/api/bus-system/sim-status']);
        fprintf('       OK - Server is reachable at %s\n\n', SERVER_URL);
    catch
        fprintf('       WARNING - Server may not be reachable, continuing anyway\n\n');
    end

    fprintf('[3/7] Verifying required files...\n');
    if ~exist(MODEL_PATH, 'file')
        error('Model file not found: %s', MODEL_PATH);
    end
    fprintf('       OK - Model: %s\n\n', MODEL_PATH);

    %% ===== STEP 3: NOTIFY STARTING =====
    notify_status(SERVER_URL, SESSION_ID, 'running', 'GA-WP simulation starting...');

    %% ===== STEP 4: DEFINE POWER SYSTEM PARAMETERS =====
    fprintf('[4/7] Setting simulation parameters...\n');

    % These are required by the Simulink model blocks
    Ts_Power   = 5e-5;    % Power system discrete sample time
    Ts_Control = 1e-4;    % Control system sample time

    % Also assign in base workspace for Simulink to pick up
    assignin('base', 'Ts_Power',   Ts_Power);
    assignin('base', 'Ts_Control', Ts_Control);

    % Re-add model directory to path (it may have been cleared)
    addpath(MODEL_DIR);
    cd(MODEL_DIR);

    % Load weather data from saved .mat file (original vars were cleared)
    matFile = fullfile(MODEL_DIR, 'weather_real_March6_IST.mat');
    if exist(matFile, 'file')
        wdata = load(matFile);
        irradiance_profile  = wdata.irradiance_profile;
        temperature_profile = wdata.temperature_profile;
        assignin('base', 'irradiance_profile',  irradiance_profile);
        assignin('base', 'temperature_profile', temperature_profile);
        fprintf('       OK - Weather profiles loaded from .mat and assigned\n');
    else
        fprintf('       WARNING - weather_real_March6_IST.mat not found!\n');
    end

    fprintf('       Ts_Power   = %g\n', Ts_Power);
    fprintf('       Ts_Control = %g\n', Ts_Control);
    fprintf('       OK - Parameters set\n\n');

    %% ===== STEP 6: UPLOAD TOPOLOGY =====
    fprintf('[5/7] Uploading system topology to dashboard...\n');
    upload_topology(SERVER_URL, SESSION_ID);
    fprintf('       OK - Topology uploaded (Session: %s)\n\n', SESSION_ID);

    %% ===== STEP 7: LOAD & RUN SIMULATION =====
    fprintf('[6/7] Loading and running Simulink model...\n');
    fprintf('       Model: %s\n', MODEL_FILE);

    notify_status(SERVER_URL, SESSION_ID, 'running', 'Loading Simulink model...');

    try
        load_system(MODEL_PATH);
        fprintf('       OK - Model loaded successfully\n');
    catch ex
        fprintf('       ERROR loading model: %s\n', ex.message);
        notify_status(SERVER_URL, SESSION_ID, 'error', ['Model load error: ' ex.message]);
        return;
    end

    % Configure signal logging
    try
        set_param(MODEL_FILE, 'SaveOutput', 'on');
        set_param(MODEL_FILE, 'SignalLogging', 'on');
        set_param(MODEL_FILE, 'SignalLoggingName', 'logsout');
        fprintf('       OK - Signal logging configured\n');
    catch
        fprintf('       NOTE - Could not configure logging (may already be set)\n');
    end

    % Set stop time to 24 seconds (1 sec = 1 hour compressed time)
    % The weather profile goes from 0 to 23 seconds (24 hours mapped)
    stopTime = 24;
    try
        set_param(MODEL_FILE, 'StopTime', num2str(stopTime));
        fprintf('       Stop time set to %d s (1 sec = 1 hour)\n', stopTime);
    catch ex
        fprintf('       WARNING - Could not set stop time: %s\n', ex.message);
    end

    % Run simulation
    fprintf('       Running simulation... (this may take a while)\n');
    notify_status(SERVER_URL, SESSION_ID, 'running', ...
        sprintf('Simulation running (stop time = %.1f s)...', stopTime));

    simStart = tic;
    try
        simOut = sim(MODEL_FILE);
        elapsed = toc(simStart);
        fprintf('       OK - Simulation completed in %.1f seconds\n\n', elapsed);
        notify_status(SERVER_URL, SESSION_ID, 'processing', ...
            sprintf('Simulation done in %.1fs, extracting data...', elapsed));
    catch ex
        elapsed = toc(simStart);
        fprintf('       ERROR - Simulation failed after %.1f s: %s\n', elapsed, ex.message);
        notify_status(SERVER_URL, SESSION_ID, 'error', ex.message);
        return;
    end

    %% ===== STEP 8: EXTRACT & STREAM DATA =====
    fprintf('[7/7] Extracting and streaming measurement data...\n');

    % Get logsout from simulation output
    logsout = [];
    if isprop(simOut, 'logsout') || isfield(simOut, 'logsout')
        logsout = simOut.logsout;
    elseif evalin('base', 'exist(''logsout'', ''var'')')
        logsout = evalin('base', 'logsout');
    end

    if ~isempty(logsout)
        stream_logged_signals(SERVER_URL, SESSION_ID, logsout, stopTime);
        run_analysis(SERVER_URL, SESSION_ID, logsout);
    else
        fprintf('       WARNING - No logsout found, trying workspace variables...\n');
        % Try to use simOut fields directly
        try_direct_extraction(SERVER_URL, SESSION_ID, simOut);
    end

    %% ===== DONE =====
    notify_status(SERVER_URL, SESSION_ID, 'completed', 'GA-WP simulation and analysis complete');

    fprintf('\n==============================================================\n');
    fprintf('   COMPLETE - View results at:\n');
    fprintf('   http://localhost:3000/simulations\n');
    fprintf('   Session: %s\n', SESSION_ID);
    fprintf('==============================================================\n');
end


%% ================================================================
%  UPLOAD SYSTEM TOPOLOGY (IEEE 13 Bus with GA-WP Solar PV)
%% ================================================================
function upload_topology(SERVER_URL, SESSION_ID)
    url = [SERVER_URL '/api/bus-system/upload'];

    buses = {
        struct('id','650','kV',4.16,'type','Swing','phases','ABC','description','Substation / Slack bus')
        struct('id','632','kV',4.16,'type','PQ','phases','ABC','description','Main distribution bus')
        struct('id','633','kV',4.16,'type','PQ','phases','ABC','description','Connects to XFM-1 transformer')
        struct('id','634','kV',0.48,'type','PQ','phases','ABC','description','Low-voltage bus via XFM-1, PV connected (GA-WP)')
        struct('id','645','kV',4.16,'type','PQ','phases','BC','description','2-phase lateral (B,C)')
        struct('id','646','kV',4.16,'type','PQ','phases','BC','description','End-of-line 2-phase bus')
        struct('id','671','kV',4.16,'type','PQ','phases','ABC','description','Major load bus, PV connected (GA-WP)')
        struct('id','680','kV',4.16,'type','PQ','phases','ABC','description','End bus, no load')
        struct('id','684','kV',4.16,'type','PQ','phases','AC','description','2-phase lateral (A,C)')
        struct('id','611','kV',4.16,'type','PQ','phases','C','description','Single-phase bus (C)')
        struct('id','652','kV',4.16,'type','PQ','phases','A','description','Single-phase bus (A)')
        struct('id','692','kV',4.16,'type','PQ','phases','ABC','description','Switch-connected from 671')
        struct('id','675','kV',4.16,'type','PQ','phases','ABC','description','End bus, PV connected (GA-WP)')
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
    };

    solar_subsystems = {
        struct('name','PV_634','connected_bus','634','capacity_kW',500,'irradiance',1000,'status','Active','type','3-Phase PV Array (GA Optimized)','signal_name','P_PV_634')
        struct('name','PV_671','connected_bus','671','capacity_kW',300,'irradiance',1000,'status','Active','type','3-Phase PV Array (GA Optimized)','signal_name','P_PV_671')
        struct('name','PV_675','connected_bus','675','capacity_kW',200,'irradiance',1000,'status','Active','type','3-Phase PV Array (GA Optimized)','signal_name','P_PV_675')
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
        'system_name', 'IEEE 13 Node Test Feeder with Solar PV (GA-WP)', ...
        'model_file', 'aIEEE13bus_with_solar_13bus_GA_wp.slx', ...
        'base_kV', 4.16, ...
        'base_MVA', 5, ...
        'frequency', 60, ...
        'solver', 'Discrete', ...
        'description', 'IEEE 13 Bus System with 3 GA-Optimized Solar PV (Weather Profile) at buses 634, 671, 675', ...
        'pv_buses', '634, 671, 675', ...
        'total_pv_capacity_kW', 1000, ...
        'simulation_type', 'EMT (Electromagnetic Transient) with GA Optimization', ...
        'Ts_Power', 5e-5, ...
        'Ts_Control', 1e-4 ...
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
        fprintf('       WARNING - Topology upload: %s\n', ex.message);
    end
end


%% ================================================================
%  STREAM LOGGED SIGNALS TO DASHBOARD
%% ================================================================
function stream_logged_signals(SERVER_URL, SESSION_ID, logsout, stopTime)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',5);

    % Extract available signal names
    signalNames = {};
    for k = 1:logsout.numElements
        signalNames{end+1} = logsout{k}.Name; %#ok<AGROW>
    end
    fprintf('       Found %d logged signals: %s\n', length(signalNames), strjoin(signalNames, ', '));

    % Extract power signals
    P_slack = []; P_load = []; t_fast = [];
    P_PV_634 = []; P_PV_671 = []; P_PV_675 = []; t_pv = [];

    % Slack power
    try
        sig = logsout.get('P_slack');
        P_slack = sum(sig.Values.Data, 2);
        t_fast = sig.Values.Time;
        fprintf('       OK - P_slack extracted (%d samples)\n', length(P_slack));
    catch; fprintf('       WARNING - P_slack not found\n'); end

    % Load power
    try
        sig = logsout.get('P_load');
        P_load = sum(sig.Values.Data, 2);
        fprintf('       OK - P_load extracted (%d samples)\n', length(P_load));
    catch; fprintf('       WARNING - P_load not found\n'); end

    % PV powers
    try
        sig = logsout.get('P_PV_634');
        P_PV_634 = sum(sig.Values.Data, 2);
        t_pv = sig.Values.Time;
        fprintf('       OK - P_PV_634 extracted (%d samples)\n', length(P_PV_634));
    catch; fprintf('       WARNING - P_PV_634 not found\n'); end

    try
        sig = logsout.get('P_PV_671');
        P_PV_671 = sum(sig.Values.Data, 2);
        fprintf('       OK - P_PV_671 extracted (%d samples)\n', length(P_PV_671));
    catch; fprintf('       WARNING - P_PV_671 not found\n'); end

    try
        sig = logsout.get('P_PV_675');
        P_PV_675 = sum(sig.Values.Data, 2);
        fprintf('       OK - P_PV_675 extracted (%d samples)\n', length(P_PV_675));
    catch; fprintf('       WARNING - P_PV_675 not found\n'); end

    % Extract bus voltage signals
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
                    fprintf('       OK - Voltage for Bus %s found as "%s"\n', bid, searchNames{s});
                    break;
                end
            catch
            end
        end
    end

    % Use PV time base if available
    if ~isempty(t_pv)
        t = t_pv;
    elseif ~isempty(t_fast)
        t = t_fast;
    else
        fprintf('       WARNING - No time vector available, skipping streaming\n');
        return;
    end
    N = length(t);

    % Resample fast signals to slow time base if needed
    if ~isempty(t_pv) && ~isempty(t_fast) && length(t_fast) ~= length(t_pv)
        if ~isempty(P_slack)
            P_slack = interp1(t_fast, P_slack, t_pv, 'linear', 'extrap');
        end
        if ~isempty(P_load)
            P_load = interp1(t_fast, P_load, t_pv, 'linear', 'extrap');
        end
    end

    % Remove startup transient
    t_ss_start = 0.3;
    idx_ss = find(t >= t_ss_start);
    if isempty(idx_ss)
        idx_ss = 1:N;
    end

    % Downsample for streaming (~200 points max)
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

        % Bus 632 (Load)
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

        % PV Bus 634
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

        % PV Bus 671
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

        % PV Bus 675
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

        % Stream bus voltage signals
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

        pause(0.02);
    end

    fprintf('       OK - Streamed %d measurements to dashboard\n\n', sentCount);
end


%% ================================================================
%  RUN ANALYSIS AND SEND RESULTS
%% ================================================================
function run_analysis(SERVER_URL, SESSION_ID, logsout)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',10);

    try
        P_slack_ts  = logsout.get('P_slack').Values;
        P_load_ts   = logsout.get('P_load').Values;
        P_PV_634_ts = logsout.get('P_PV_634').Values;
        P_PV_671_ts = logsout.get('P_PV_671').Values;
        P_PV_675_ts = logsout.get('P_PV_675').Values;

        P_slack  = sum(P_slack_ts.Data, 2);
        P_load   = sum(P_load_ts.Data, 2);
        P_PV_634 = sum(P_PV_634_ts.Data, 2);
        P_PV_671 = sum(P_PV_671_ts.Data, 2);
        P_PV_675 = sum(P_PV_675_ts.Data, 2);

        t_slack = P_slack_ts.Time;
        t_pv    = P_PV_634_ts.Time;

        % Resample fast signals to PV time base
        P_slack_rs = interp1(t_slack, P_slack, t_pv, 'linear');
        P_load_rs  = interp1(t_slack, P_load,  t_pv, 'linear');
        P_PV_total = P_PV_634 + P_PV_671 + P_PV_675;

        % Remove startup transient
        t_ss_start = 0.3;
        idx_ss = t_pv >= t_ss_start;
        P_slack_ss = P_slack_rs(idx_ss);
        P_load_ss  = P_load_rs(idx_ss);
        P_PV_ss    = P_PV_total(idx_ss);
        P_balance  = P_slack_rs(idx_ss) + P_PV_total(idx_ss) - P_load_rs(idx_ss);

        % Moving average
        window = 200;
        P_bal_avg = movmean(P_balance, window);

        % Compute results
        avg_slack = mean(P_slack_ss);
        avg_load  = mean(P_load_ss);
        avg_pv    = mean(P_PV_ss);
        avg_loss  = mean(P_bal_avg);
        pv_penetration = avg_pv / avg_load * 100;

        fprintf('\n       ========= GA-WP ANALYSIS RESULTS =========\n');
        fprintf('       Average Slack Power   : %.2f kW\n', avg_slack);
        fprintf('       Average Load Power    : %.2f kW\n', avg_load);
        fprintf('       Average Total PV Power: %.2f kW\n', avg_pv);
        fprintf('       Average System Losses : %.2f kW\n', avg_loss);
        fprintf('       PV Penetration        : %.2f %%\n', pv_penetration);

        % Send analysis to dashboard
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
                'analysis_type', 'ga_wp_final_summary', ...
                'timestamp_matlab', datestr(now)));
        try
            webwrite(url, jsonencode(analysis), options);
            fprintf('       OK - Analysis results sent to dashboard\n');
        catch ex
            fprintf('       WARNING - Could not send analysis: %s\n', ex.message);
        end
    catch ex
        fprintf('       WARNING - Analysis error: %s\n', ex.message);
    end
end


%% ================================================================
%  TRY DIRECT EXTRACTION (FALLBACK)
%% ================================================================
function try_direct_extraction(SERVER_URL, SESSION_ID, simOut)
    url = [SERVER_URL '/api/bus-system/measurements'];
    options = weboptions('MediaType','application/json','RequestMethod','post','Timeout',10);

    fprintf('       Attempting direct extraction from simOut...\n');
    try
        % List available fields
        if isobject(simOut)
            props = properties(simOut);
            fprintf('       simOut properties: %s\n', strjoin(props, ', '));
        end

        % Try to get yout or tout
        if isprop(simOut, 'tout')
            fprintf('       Found tout with %d samples\n', length(simOut.tout));
        end
        if isprop(simOut, 'yout')
            fprintf('       Found yout\n');
        end

        % Send whatever we have as a basic result
        result = struct('session_id', SESSION_ID, 'bus_id', 'SYSTEM', ...
            'measurements', struct(...
                'analysis_type', 'ga_wp_basic', ...
                'simulation_completed', true, ...
                'timestamp_matlab', datestr(now)));
        try webwrite(url, jsonencode(result), options); catch; end
        fprintf('       OK - Basic result sent\n');
    catch ex
        fprintf('       WARNING - Direct extraction failed: %s\n', ex.message);
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
