%% ============================================================
%  IEEE 13-BUS SYSTEM WITH SOLAR PV
%  COMPLETE POST-PROCESSING & ANALYSIS SCRIPT
% ============================================================

clc; close all;

%% ============================================================
% 1. EXTRACT LOGGED SIGNALS
%% ============================================================

% Slack and Load (fast time base)
P_slack_ts = logsout.get('P_slack').Values;
P_load_ts  = logsout.get('P_load').Values;

% PV systems (slow time base)
P_PV_634_ts = logsout.get('P_PV_634').Values;
P_PV_671_ts = logsout.get('P_PV_671').Values;
P_PV_675_ts = logsout.get('P_PV_675').Values;

% Sum three phases (if applicable)
P_slack = sum(P_slack_ts.Data, 2);   % kW
P_load  = sum(P_load_ts.Data,  2);   % kW

P_PV_634 = sum(P_PV_634_ts.Data, 2); % kW
P_PV_671 = sum(P_PV_671_ts.Data, 2); % kW
P_PV_675 = sum(P_PV_675_ts.Data, 2); % kW

% Time vectors
t_slack = P_slack_ts.Time;
t_pv    = P_PV_634_ts.Time;

%% ============================================================
% 2. MULTI-RATE ALIGNMENT (CRITICAL)
%% ============================================================

% Resample fast signals to PV (slow) time base
P_slack_rs = interp1(t_slack, P_slack, t_pv, 'linear');
P_load_rs  = interp1(t_slack, P_load,  t_pv, 'linear');

%% ============================================================
% 3. TOTAL PV POWER
%% ============================================================

P_PV_total = P_PV_634 + P_PV_671 + P_PV_675;

%% ============================================================
% 4. INSTANTANEOUS POWER BALANCE
% (includes losses + stored energy effects)
%% ============================================================

P_balance = P_slack_rs + P_PV_total - P_load_rs;

%% ============================================================
% 5. REMOVE STARTUP TRANSIENTS
%% ============================================================

t_ss_start = 0.3;               % seconds (adjust if needed)
idx_ss = t_pv >= t_ss_start;

t_ss = t_pv(idx_ss);

P_slack_ss = P_slack_rs(idx_ss);
P_load_ss  = P_load_rs(idx_ss);
P_PV_ss    = P_PV_total(idx_ss);
P_bal_ss   = P_balance(idx_ss);

%% ============================================================
% 6. MOVING-AVERAGE FILTER (STEADY-STATE POWER)
%% ============================================================

window = 200;   % ~10 ms window
P_bal_avg   = movmean(P_bal_ss, window);
P_loss_avg  = P_bal_avg;   % mismatch = losses (steady state)

%% ============================================================
% 7. NUMERICAL RESULTS
%% ============================================================

fprintf('\n========= NUMERICAL RESULTS =========\n');
fprintf('Average Slack Power      : %.2f kW\n', mean(P_slack_ss));
fprintf('Average Load Power       : %.2f kW\n', mean(P_load_ss));
fprintf('Average Total PV Power   : %.2f kW\n', mean(P_PV_ss));
fprintf('Average System Losses    : %.2f kW\n', mean(P_loss_avg));

PV_penetration = mean(P_PV_ss) / mean(P_load_ss) * 100;
fprintf('PV Penetration           : %.2f %%\n', PV_penetration);

fprintf('Mean Power Imbalance     : %.6f kW\n', mean(P_bal_avg));
fprintf('Max Abs Power Imbalance  : %.2f kW\n', max(abs(P_bal_avg)));

%% ============================================================
% 8. PLOTS
%% ============================================================

% ---- 8.1 Instantaneous Power Balance (EMT)
figure;
plot(t_pv, P_balance, 'LineWidth', 1);
yline(0,'--k');
grid on;
xlabel('Time (s)');
ylabel('Power mismatch (kW)');
title('Instantaneous Power Balance (Including Switching Effects)');

% ---- 8.2 Steady-State Power Balance (Transient Removed)
figure;
plot(t_ss, P_bal_ss, 'LineWidth', 1);
yline(0,'--k');
grid on;
xlabel('Time (s)');
ylabel('Power mismatch (kW)');
title('Steady-State Power Balance');

% ---- 8.3 Averaged Power Balance (Report-Quality)
figure;
plot(t_ss, P_bal_avg, 'LineWidth', 2);
yline(0,'--k');
grid on;
xlabel('Time (s)');
ylabel('Average power mismatch (kW)');
title('Averaged Power Balance (Loss-Dominated)');

% ---- 8.4 Slack vs Load vs PV
figure;
plot(t_ss, P_slack_ss, 'LineWidth', 1.5); hold on;
plot(t_ss, P_load_ss,  'LineWidth', 1.5);
plot(t_ss, P_PV_ss,    'LineWidth', 1.5);
grid on;
legend('Slack Power','Load Power','Total PV Power');
xlabel('Time (s)');
ylabel('Power (kW)');
title('Slack, Load, and PV Power');

% ---- 8.5 Individual PV Contributions
figure;
plot(t_pv, P_PV_634, 'LineWidth', 1.5); hold on;
plot(t_pv, P_PV_671, 'LineWidth', 1.5);
plot(t_pv, P_PV_675, 'LineWidth', 1.5);
grid on;
legend('PV @ Bus 634','PV @ Bus 671','PV @ Bus 675');
xlabel('Time (s)');
ylabel('Power (kW)');
title('Individual PV Outputs');

% ---- 8.6 System Losses
figure;
plot(t_ss, P_loss_avg, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Losses (kW)');
title('Total System Losses');

% ---- 8.7 Slack Power Reduction Due to PV
figure;
plot(t_ss, P_slack_ss, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Slack Power (kW)');
title('Substation Power Demand with PV Integration');

%% ============================================================
% 9. SUMMARY TABLE (FOR REPORT)
%% ============================================================

Results = table( ...
    mean(P_slack_ss), ...
    mean(P_load_ss), ...
    mean(P_PV_ss), ...
    mean(P_loss_avg), ...
    PV_penetration, ...
    'VariableNames', ...
    {'Avg_Slack_kW','Avg_Load_kW','Avg_PV_kW','Avg_Loss_kW','PV_Penetration_percent'} );

disp(' ');
disp('========= SUMMARY TABLE =========');
disp(Results);