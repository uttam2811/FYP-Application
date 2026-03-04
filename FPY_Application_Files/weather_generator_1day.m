%% ===================================================
% REAL WEATHER DATA - MARCH 6 (IST CORRECTED)
% Location: Amrita Ettimadai
% 1 sec = 1 hour (Compressed time)
%% ===================================================

clear; clc; close all;

fprintf('\n=== REAL WEATHER DATA: MARCH 6 (IST) ===\n');

%% ===================================================
%% 1. LOCATION
%% ===================================================

lat = 10.9027;
lon = 76.9000;

%% ===================================================
%% 2. DATE (MARCH 6)
%% ===================================================

start_date = '2024-03-06';
end_date   = '2024-03-06';

%% ===================================================
%% 3. DOWNLOAD DATA (TIMEZONE FIX ADDED)
%% ===================================================

url = sprintf(['https://archive-api.open-meteo.com/v1/archive?', ...
    'latitude=%.4f&longitude=%.4f', ...
    '&start_date=%s&end_date=%s', ...
    '&hourly=temperature_2m,shortwave_radiation', ...
    '&timezone=Asia/Kolkata'], ...
    lat, lon, start_date, end_date);

options = weboptions('Timeout', 60);

data = webread(url, options);

fprintf('Download successful.\n');

%% ===================================================
%% 4. EXTRACT DATA SAFELY
%% ===================================================

solar = data.hourly.shortwave_radiation;
temperature = data.hourly.temperature_2m;
timeStrings = data.hourly.time;

% Convert to column vectors (IMPORTANT)
solar = solar(:);
temperature = temperature(:);

% Replace missing values
solar(isnan(solar)) = 0;
temperature(isnan(temperature)) = 25;

% Convert time to datetime (IST already)
timeVec = datetime(timeStrings, 'InputFormat','yyyy-MM-dd''T''HH:mm');

% Ensure consistent length
N = min(length(solar), length(temperature));
solar = solar(1:N);
temperature = temperature(1:N);

fprintf('Total hours received: %d\n', N);

%% ===================================================
%% 5. REMOVE VERY SMALL EARLY/LATE NOISE (OPTIONAL)
%% ===================================================

solar(solar < 20) = 0;

%% ===================================================
%% 6. CREATE SIMULINK PROFILES
%% 1 sec = 1 hour
%% ===================================================

time_seconds = (0:N-1)';

irradiance_profile  = [time_seconds solar];
temperature_profile = [time_seconds temperature];

%% ===================================================
%% 7. SAVE FILE
%% ===================================================

save('weather_real_March6_IST.mat', ...
     'irradiance_profile', ...
     'temperature_profile');

fprintf('\nSaved successfully as weather_real_March6_IST.mat\n');

%% ===================================================
%% 8. VISUALIZATION (NOW CORRECT TIME)
%% ===================================================

figure;

subplot(2,1,1)
plot(timeVec, solar,'LineWidth',1.5)
title('Solar Irradiance - March 6 (IST)')
ylabel('W/m^2')
grid on

subplot(2,1,2)
plot(timeVec, temperature,'LineWidth',1.5)
title('Temperature - March 6 (IST)')
ylabel('°C')
grid on

%% ===================================================
%% 9. SIMULINK SETTINGS
%% ===================================================

fprintf('\n=== SIMULINK SETTINGS ===\n');
fprintf('Stop time = %d\n', N);
fprintf('Fixed step = 5e-6\n');
fprintf('From Workspace sample time = -1\n');