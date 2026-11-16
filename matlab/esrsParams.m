function p = esrsParams()
%ESRSPARAMS  Eye Strain Risk Score (ESRS) constants.
%   p = esrsParams() returns the constants used by the team's scenario
%   script (eye_strain_sim.m) and the ESRS_Update block of the Simulink model
%   (../simulink/simulink_eyestrain.slx). The firmware uses the same values
%   in ../firmware/EyeMaxxer/config.h - keep all three in sync.

    % Distance zone boundaries (cm)
    p.dangerCm   = 30;    % d <  30          immediate danger (amber LED)
    p.fastCm     = 40;    % 30 <= d <  40    fast strain
    p.moderateCm = 60;    % 40 <= d <  60    moderate strain
    p.mildCm     = 100;   % 60 <= d <= 100   mild strain;  d > 100 recovery

    % ESRS change rates (points per minute)
    p.rate_under30 = 15.0;
    p.rate_30_40   = 4.5;
    p.rate_40_60   = 2.0;
    p.rate_60_100  = 0.1;
    p.rate_over100 = -6.0;

    % Environmental multipliers (applied only when closer than 60 cm)
    p.dryHumidityThreshold = 40;    % humidity below this is dry
    p.highNoiseThreshold   = 0.6;   % normalised noise at/above this is noisy
    p.dryMultiplier        = 1.30;
    p.noiseMultiplier      = 1.20;

    % Limits and alert threshold
    p.riskMin       = 0;
    p.riskMax       = 100;
    p.riskThreshold = 70;           % red LED
end
