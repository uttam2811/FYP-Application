%% SEND_BUS_SYSTEM — Extract IEEE 13 Bus System data and push to FYP Monitor
%% 
%% USAGE:
%%   1. Open your IEEE 13 Bus Simulink model
%%   2. Run this script (or call the functions below)
%%   3. The dashboard at http://localhost:3000/bus-system will update instantly
%%
%% This script has TWO modes:
%%   A) Define your system data manually and push
%%   B) After simulation, stream measurements in real-time

function send_bus_system(session_id)
    % SEND_BUS_SYSTEM  Upload the full IEEE 13 Bus topology to the monitor
    %
    %   send_bus_system('session_2026_03_01')
    
    if nargin < 1
        session_id = ['sim_' datestr(now, 'yyyy_mm_dd_HHMMSS')];
    end
    
    url = 'http://localhost:3000/api/bus-system/upload';
    
    %% ===== DEFINE YOUR BUS SYSTEM HERE =====
    %% Modify these to match YOUR simulation setup
    
    % --- Buses ---
    buses = {
        struct('id', '650',  'kV', 4.16,  'type', 'Swing',  'phases', 'ABC')
        struct('id', '632',  'kV', 4.16,  'type', 'PQ',     'phases', 'ABC')
        struct('id', '633',  'kV', 4.16,  'type', 'PQ',     'phases', 'ABC')
        struct('id', '634',  'kV', 0.48,  'type', 'PQ',     'phases', 'ABC')
        struct('id', '645',  'kV', 4.16,  'type', 'PQ',     'phases', 'BC')
        struct('id', '646',  'kV', 4.16,  'type', 'PQ',     'phases', 'BC')
        struct('id', '671',  'kV', 4.16,  'type', 'PQ',     'phases', 'ABC')
        struct('id', '680',  'kV', 4.16,  'type', 'PQ',     'phases', 'ABC')
        struct('id', '684',  'kV', 4.16,  'type', 'PQ',     'phases', 'AC')
        struct('id', '611',  'kV', 4.16,  'type', 'PQ',     'phases', 'C')
        struct('id', '652',  'kV', 4.16,  'type', 'PQ',     'phases', 'A')
        struct('id', '692',  'kV', 4.16,  'type', 'PQ',     'phases', 'ABC')
        struct('id', '675',  'kV', 4.16,  'type', 'PQ',     'phases', 'ABC')
    };
    
    % --- Loads (matching exact Simulink block names) ---
    loads = {
        struct('name', '634 Yg PQ',  'bus', '634', 'kW', 400,  'kVAR', 290,  'model', 'Constant PQ')
        struct('name', '645Y PQ',    'bus', '645', 'kW', 170,  'kVAR', 125,  'model', 'Constant PQ')
        struct('name', '646 Z',      'bus', '646', 'kW', 230,  'kVAR', 132,  'model', 'Constant Z')
        struct('name', '652Y Z',     'bus', '652', 'kW', 128,  'kVAR', 86,   'model', 'Constant Z')
        struct('name', '671 Yg PQ',  'bus', '671', 'kW', 385,  'kVAR', 220,  'model', 'Constant PQ')
        struct('name', '671 D PQ',   'bus', '671', 'kW', 770,  'kVAR', 440,  'model', 'Constant PQ')
        struct('name', '675 Y PQ',   'bus', '675', 'kW', 485,  'kVAR', 190,  'model', 'Constant PQ')
        struct('name', '675 Yg Z',   'bus', '675', 'kW', 358,  'kVAR', 272,  'model', 'Constant Z')
        struct('name', '692 D I',    'bus', '692', 'kW', 170,  'kVAR', 151,  'model', 'Constant I')
        struct('name', '611 Z',      'bus', '611', 'kW', 170,  'kVAR', 80,   'model', 'Constant Z')
        struct('name', '611Y I',     'bus', '611', 'kW', 0,    'kVAR', 0,    'model', 'Constant I')
    };
    
    % --- Solar Subsystems (connected at buses 634, 671, 675 per your model) ---
    solar_subsystems = {
        struct('name', 'PV_634',  'connected_bus', '634', 'capacity_kW', 500,  'irradiance', 1000, 'status', 'Active')
        struct('name', 'PV_671',  'connected_bus', '671', 'capacity_kW', 300,  'irradiance', 1000, 'status', 'Active')
        struct('name', 'PV_675',  'connected_bus', '675', 'capacity_kW', 200,  'irradiance', 1000, 'status', 'Active')
    };
    
    % --- Lines (matching exact Simulink block names) ---
    lines = {
        struct('name', '650-632 601',   'from', '650', 'to', '632', 'length', 2000, 'config', '601')
        struct('name', '632-645 603',   'from', '632', 'to', '645', 'length', 500,  'config', '603')
        struct('name', '645-646 603',   'from', '645', 'to', '646', 'length', 300,  'config', '603')
        struct('name', '632-633 602',   'from', '632', 'to', '633', 'length', 500,  'config', '602')
        struct('name', '632-671 601',   'from', '632', 'to', '671', 'length', 2000, 'config', '601')
        struct('name', '671-684 604',   'from', '671', 'to', '684', 'length', 300,  'config', '604')
        struct('name', '605c',          'from', '684', 'to', '611', 'length', 300,  'config', '605')
        struct('name', '607a',          'from', '684', 'to', '652', 'length', 800,  'config', '607')
        struct('name', '601abc',        'from', '671', 'to', '680', 'length', 1000, 'config', '601')
        struct('name', '692-675 606',   'from', '692', 'to', '675', 'length', 500,  'config', '606')
        struct('name', '671-692 Switch','from', '671', 'to', '692', 'length', 0,    'config', 'Switch')
    };
    
    % --- Transformers ---
    transformers = {
        struct('name', 'Regulator 1 (RG60)', 'from', '650', 'to', '632', 'kVA', 5000, 'kV_primary', 4.16, 'kV_secondary', 4.16)
        struct('name', 'XFXFM1',             'from', '633', 'to', '634', 'kVA', 500,  'kV_primary', 4.16, 'kV_secondary', 0.48)
    };
    
    % --- Capacitors ---
    capacitors = {
        struct('name', 'Cap_675',  'bus', '675', 'kVAR', 600,  'kV', 4.16)
        struct('name', 'Cap_611',  'bus', '611', 'kVAR', 100,  'kV', 4.16)
    };
    
    % --- Summary ---
    summary = struct(...
        'system_name', 'IEEE 13 Node Test Feeder with Solar PV', ...
        'model_file', 'aIEEE13bus_with_solar_13bus_pso_position.slx', ...
        'base_kV', 4.16, ...
        'base_MVA', 5, ...
        'frequency', 60, ...
        'description', 'IEEE 13 Bus with Solar PV at buses 634, 671, 675 — FYP Project' ...
    );
    
    %% ===== BUILD AND SEND PAYLOAD =====
    payload = struct(...
        'session_id', session_id, ...
        'buses', {buses}, ...
        'loads', {loads}, ...
        'solar_subsystems', {solar_subsystems}, ...
        'lines', {lines}, ...
        'transformers', {transformers}, ...
        'capacitors', {capacitors}, ...
        'summary', summary ...
    );
    
    jsonPayload = jsonencode(payload);
    
    options = weboptions(...
        'MediaType', 'application/json', ...
        'RequestMethod', 'post', ...
        'Timeout', 15 ...
    );
    
    try
        response = webwrite(url, jsonPayload, options);
        fprintf('[Monitor] Bus system uploaded! Session: %s\n', session_id);
        fprintf('[Monitor] Open http://localhost:3000/bus-system to view\n');
    catch ex
        fprintf('[Monitor] Error uploading bus system: %s\n', ex.message);
    end
end


function send_bus_measurement(session_id, bus_id, voltage, current, real_power, reactive_power)
    % SEND_BUS_MEASUREMENT  Send real-time V, I, P, Q for a specific bus
    %
    %   send_bus_measurement('sim_001', '632', 4160, 125.3, 450.2, 210.5)
    
    url = 'http://localhost:3000/api/bus-system/measurements';
    
    payload = struct(...
        'session_id', session_id, ...
        'bus_id', bus_id, ...
        'measurements', struct(...
            'voltage_V', voltage, ...
            'current_A', current, ...
            'real_power_kW', real_power, ...
            'reactive_power_kVAR', reactive_power, ...
            'timestamp_matlab', datestr(now) ...
        ) ...
    );
    
    options = weboptions(...
        'MediaType', 'application/json', ...
        'RequestMethod', 'post', ...
        'Timeout', 5 ...
    );
    
    try
        webwrite(url, jsonencode(payload), options);
    catch ex
        fprintf('[Monitor] Measurement error (Bus %s): %s\n', bus_id, ex.message);
    end
end


function stream_all_buses(session_id, sim_time, bus_data)
    % STREAM_ALL_BUSES  Send measurements for all buses at once
    %
    %   bus_data is a struct array with fields: id, V, I, P, Q
    %   Example:
    %       bd(1) = struct('id','632','V',4150,'I',120,'P',400,'Q',200);
    %       bd(2) = struct('id','671','V',4100,'I',280,'P',1100,'Q',600);
    %       stream_all_buses('sim_001', 1.5, bd);
    
    for k = 1:length(bus_data)
        b = bus_data(k);
        send_bus_measurement(session_id, b.id, b.V, b.I, b.P, b.Q);
    end
end


%% ===== EXAMPLE: Full workflow =====
%
%   % 1. First, upload the system topology (do this once)
%   session = 'fyp_solar_test_1';
%   send_bus_system(session);
%
%   % 2. Run your Simulink simulation, then stream results:
%   % (Inside your simulation loop or after sim)
%   
%   simOut = sim('IEEE_13_Bus_Model');  % your model name
%   
%   % Extract signals from simOut (adjust variable names to your model)
%   t = simOut.tout;
%   V_632 = simOut.V_bus632.Data;
%   I_632 = simOut.I_bus632.Data;
%   P_632 = simOut.P_bus632.Data;
%   Q_632 = simOut.Q_bus632.Data;
%   
%   for k = 1:length(t)
%       send_bus_measurement(session, '632', V_632(k), I_632(k), P_632(k), Q_632(k));
%       pause(0.1);  % small delay so dashboard can render
%   end
