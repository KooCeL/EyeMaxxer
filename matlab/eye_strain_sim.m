%% Eye Strain Aid - LED-Based Alert Model
% Logic:
% 1) Amber LED blinks if distance < 30 cm
% 2) Red LED blinks if ESRS >= threshold
% 3) Green LED stays ON if ESRS == 0
% 4) Dry and noisy environments increase ESRS accumulation rate
% 5) ESRS decreases when distance > 100 cm

clear; clc; close all;

%% General settings
dt = 1;                      % seconds
riskThreshold = 70;          % ESRS threshold for red LED
dryHumidityThreshold = 40;   % below this is dry
highNoiseThreshold = 0.6;    % above this is noisy
riskMin = 0;
riskMax = 100;

% ESRS change rates in points/min
rate_under30 = 15.0;
rate_30_40   = 4.5;
rate_40_60   = 2.0;
rate_60_100  = 0.1;
rate_over100 = -6.0;

% Environmental multipliers
dryMultiplier = 1.30;        % dry air increases strain gain
noiseMultiplier = 1.20;      % noisy environment increases strain gain

%% Run scenarios
runScenario('Scenario 1 - Immediate Under 30 cm', 15, dt, ...
    @(tmin) s1_distance(tmin), @(tmin) s1_humidity(tmin), @(tmin) s1_noise(tmin), ...
    riskThreshold, dryHumidityThreshold, highNoiseThreshold, ...
    rate_under30, rate_30_40, rate_40_60, rate_60_100, rate_over100, ...
    dryMultiplier, noiseMultiplier, riskMin, riskMax);

runScenario('Scenario 2 - 35 cm Dry Environment', 35, dt, ...
    @(tmin) s2_distance(tmin), @(tmin) s2_humidity(tmin), @(tmin) s2_noise(tmin), ...
    riskThreshold, dryHumidityThreshold, highNoiseThreshold, ...
    rate_under30, rate_30_40, rate_40_60, rate_60_100, rate_over100, ...
    dryMultiplier, noiseMultiplier, riskMin, riskMax);

runScenario('Scenario 3 - 35 cm Humid Environment', 35, dt, ...
    @(tmin) s3_distance(tmin), @(tmin) s3_humidity(tmin), @(tmin) s3_noise(tmin), ...
    riskThreshold, dryHumidityThreshold, highNoiseThreshold, ...
    rate_under30, rate_30_40, rate_40_60, rate_60_100, rate_over100, ...
    dryMultiplier, noiseMultiplier, riskMin, riskMax);

runScenario('Scenario 4 - 50 cm Humid and Noisy Environment', 60, dt, ...
    @(tmin) s4_distance(tmin), @(tmin) s4_humidity(tmin), @(tmin) s4_noise(tmin), ...
    riskThreshold, dryHumidityThreshold, highNoiseThreshold, ...
    rate_under30, rate_30_40, rate_40_60, rate_60_100, rate_over100, ...
    dryMultiplier, noiseMultiplier, riskMin, riskMax);

runScenario('Scenario 5 - Recovery Above 100 cm', 50, dt, ...
    @(tmin) s5_distance(tmin), @(tmin) s5_humidity(tmin), @(tmin) s5_noise(tmin), ...
    riskThreshold, dryHumidityThreshold, highNoiseThreshold, ...
    rate_under30, rate_30_40, rate_40_60, rate_60_100, rate_over100, ...
    dryMultiplier, noiseMultiplier, riskMin, riskMax);

%% ===================== LOCAL FUNCTIONS =====================

function runScenario(name, durationMin, dt, distanceFcn, humidityFcn, noiseFcn, ...
    riskThreshold, dryHumidityThreshold, highNoiseThreshold, ...
    rate_under30, rate_30_40, rate_40_60, rate_60_100, rate_over100, ...
    dryMultiplier, noiseMultiplier, riskMin, riskMax)

    t = 0:dt:(durationMin * 60);
    tmin = t / 60;
    N = numel(t);

    distance = zeros(1, N);
    humidity = zeros(1, N);
    noise = zeros(1, N);
    ESRS = zeros(1, N);

    amberLED = false(1, N);
    redLED = false(1, N);
    greenLED = false(1, N);

    for k = 1:N
        distance(k) = distanceFcn(tmin(k));
        humidity(k) = humidityFcn(tmin(k));
        noise(k) = noiseFcn(tmin(k));

        isDry = humidity(k) < dryHumidityThreshold;
        isNoisy = noise(k) >= highNoiseThreshold;

        % Previous score
        if k == 1
            prevScore = 0;
        else
            prevScore = ESRS(k-1);
        end

        % Score rate by distance zone
        if distance(k) < 30
            deltaPerMin = rate_under30;
        elseif distance(k) >= 30 && distance(k) < 40
            deltaPerMin = rate_30_40;
        elseif distance(k) >= 40 && distance(k) < 60
            deltaPerMin = rate_40_60;
        elseif distance(k) >= 60 && distance(k) <= 100
            deltaPerMin = rate_60_100;
        else
            deltaPerMin = rate_over100;
        end

        % Dryness and noise increase buildup only below 60 cm
        if distance(k) < 60
            if isDry
                deltaPerMin = deltaPerMin * dryMultiplier;
            end
            if isNoisy
                deltaPerMin = deltaPerMin * noiseMultiplier;
            end
        end

        % Update score
        delta = deltaPerMin * (dt / 60);
        ESRS(k) = prevScore + delta;
        ESRS(k) = min(max(ESRS(k), riskMin), riskMax);

        % LED logic
        amberLED(k) = distance(k) < 30;
        redLED(k) = ESRS(k) >= riskThreshold;
        greenLED(k) = (ESRS(k) == 0);
    end

    % Report
    fprintf('\n=============================\n');
    fprintf('%s\n', name);
    fprintf('=============================\n');

    idxAmber = find(amberLED, 1, 'first');
    idxRed = find(redLED, 1, 'first');
    idxGreenOff = find(~greenLED, 1, 'first');

    if isempty(idxAmber)
        fprintf('Amber LED (<30 cm): none\n');
    else
        fprintf('Amber LED first active at %.2f min\n', tmin(idxAmber));
    end

    if isempty(idxRed)
        fprintf('Red LED (ESRS >= %.0f): none\n', riskThreshold);
    else
        fprintf('Red LED first active at %.2f min\n', tmin(idxRed));
    end

    if isempty(idxGreenOff)
        fprintf('Green LED stayed ON throughout\n');
    else
        fprintf('Green LED first turned OFF at %.2f min\n', tmin(idxGreenOff));
    end

    % Plots
    figure('Name', name, 'NumberTitle', 'off');

    subplot(5,1,1);
    plot(tmin, distance, 'LineWidth', 1.5); hold on;
    yline(30, '--');
    yline(40, '--');
    yline(60, '--');
    yline(100, '--');
    ylabel('Distance (cm)');
    title(name);
    grid on;

    subplot(5,1,2);
    plot(tmin, humidity, 'LineWidth', 1.5); hold on;
    yline(dryHumidityThreshold, '--');
    ylabel('Humidity (%)');
    grid on;

    subplot(5,1,3);
    plot(tmin, noise, 'LineWidth', 1.5); hold on;
    yline(highNoiseThreshold, '--');
    ylabel('Noise');
    grid on;

    subplot(5,1,4);
    plot(tmin, ESRS, 'LineWidth', 1.5); hold on;
    yline(riskThreshold, '--');
    yline(100, '--');
    ylabel('ESRS');
    grid on;

    subplot(5,1,5);
    stairs(tmin, amberLED, 'LineWidth', 1.5); hold on;
    stairs(tmin, redLED, 'LineWidth', 1.5);
    stairs(tmin, greenLED, 'LineWidth', 1.5);
    ylim([-0.1 1.1]);
    xlabel('Time (min)');
    ylabel('LED state');
    legend('Amber', 'Red', 'Green', 'Location', 'best');
    grid on;
end

%% ===================== Scenario Definitions =====================

function d = s1_distance(tmin)
    if tmin < 2
        d = 70;
    elseif tmin < 5
        d = 25;
    else
        d = 75;
    end
end

function h = s1_humidity(~)
    h = 50;
end

function n = s1_noise(~)
    n = 0.2;
end

function d = s2_distance(tmin)
    if tmin < 5
        d = 70;
    elseif tmin < 25
        d = 35;
    else
        d = 75;
    end
end

function h = s2_humidity(~)
    h = 28;
end

function n = s2_noise(~)
    n = 0.2;
end

function d = s3_distance(tmin)
    if tmin < 5
        d = 70;
    elseif tmin < 25
        d = 35;
    else
        d = 75;
    end
end

function h = s3_humidity(~)
    h = 55;
end

function n = s3_noise(~)
    n = 0.2;
end

function d = s4_distance(tmin)
    if tmin < 5
        d = 75;
    elseif tmin < 55
        d = 50;
    else
        d = 75;
    end
end

function h = s4_humidity(~)
    h = 55;
end

function n = s4_noise(tmin)
    if tmin < 20
        n = 0.2;
    else
        n = 0.8;
    end
end

function d = s5_distance(tmin)
    if tmin < 12
        d = 35;
    elseif tmin < 22
        d = 45;
    elseif tmin < 35
        d = 120;
    else
        d = 70;
    end
end

function h = s5_humidity(tmin)
    if tmin < 20
        h = 30;
    else
        h = 50;
    end
end

function n = s5_noise(~)
    n = 0.2;
end