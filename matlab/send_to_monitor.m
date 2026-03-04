%% MATLAB Helper Script — Send simulation data to FYP MATLAB Monitor
%% Place this file in your MATLAB working directory
%% 
%% USAGE:
%%   1. Call send_to_monitor() from your simulation to POST data via HTTP
%%   2. Or save output files to the server/matlab-output/ directory
%%
%% OPTION 1: HTTP API (recommended for real-time)

function send_to_monitor(simulation_name, data, metadata)
    % SEND_TO_MONITOR  Sends simulation data to the FYP Monitor dashboard
    %
    %   send_to_monitor('my_simulation', struct('x', 1:10, 'y', rand(1,10)))
    %   send_to_monitor('my_simulation', data_struct, metadata_struct)
    
    if nargin < 3
        metadata = struct();
    end
    
    url = 'http://localhost:3000/api/matlab/push';
    
    payload = struct(...
        'simulation_name', simulation_name, ...
        'data', data, ...
        'metadata', metadata ...
    );
    
    jsonPayload = jsonencode(payload);
    
    options = weboptions(...
        'MediaType', 'application/json', ...
        'RequestMethod', 'post', ...
        'Timeout', 10 ...
    );
    
    try
        response = webwrite(url, jsonPayload, options);
        fprintf('[Monitor] Data sent: %s (ID: %d)\n', simulation_name, response.id);
    catch ex
        fprintf('[Monitor] Error sending data: %s\n', ex.message);
    end
end

%% OPTION 2: File-based (drop JSON files into the watched folder)
% 
% Example:
%   data = struct('x', 1:100, 'y', sin(1:100));
%   jsonStr = jsonencode(data);
%   fid = fopen('D:\FYP Application\server\matlab-output\my_sim.json', 'w');
%   fprintf(fid, '%s', jsonStr);
%   fclose(fid);

%% EXAMPLE — Continuous simulation sending data every second:
%
%   for t = 1:100
%       data = struct('time', t, 'value', sin(t/10), 'noise', randn());
%       send_to_monitor('sine_wave', data);
%       pause(1);
%   end
