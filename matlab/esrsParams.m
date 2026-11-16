function p = esrsParams()
%ESRSPARAMS  Eye Strain Risk Score (ESRS) tuning constants.
%   p = esrsParams() returns a struct with the same constants as
%   firmware/EyeMaxxer/config.h. Keep the two files in sync so the MATLAB
%   scenario tests describe exactly what the hardware does.

    % Distance zones (cm)
    p.dangerCm       = 30;    % closer than this = immediate danger zone
    p.closeCm        = 50;    % 30-50 cm = too close
    p.awayCm         = 120;   % further than this (or no echo) = user away
    p.awayDebounceS  = 2;     % away this long before recovery starts

    % Base increments (score points per second) and recovery
    p.rateOk         = 0.05;
    p.rateClose      = 0.12;
    p.rateDanger     = 0.40;
    p.rateRecovery   = 3.50;   % a 20 s break after 20 min (20-20-20 rule) ~resets the score

    % Environmental multipliers
    p.noiseThreshold = 200;   % smoothed mic peak-to-peak (ADC counts)
    p.noiseMult      = 1.25;
    p.humidityLowPct = 40;
    p.humidityMult   = 1.30;

    % LED thresholds
    p.esrsMax        = 100;
    p.levelYellow    = 40;
    p.levelRed       = 70;
    p.levelOverdue   = 90;
    p.hysteresis     = 3;

    % Timing
    p.tickS          = 0.1;   % firmware update period
end
