function [ESRS_next, out] = esrsStep(ESRS_prev, distance_cm, humidity_pct, noise_level, dt, p)
%ESRSSTEP  One update of the Eye Strain Risk Score.
%   [ESRS_next, out] = esrsStep(ESRS_prev, distance_cm, humidity_pct, noise_level, dt, p)
%
%   Same logic as the ESRS_Update MATLAB Function block in
%   ../simulink/simulink_eyestrain.slx, with the time step dt (seconds) and
%   the constants p (from esrsParams) passed in instead of hard-coded, plus
%   the three LED outputs that the Simulink model computes with Compare blocks.
%
%   out.ratePerMin  rate applied this step (after multipliers)
%   out.zone        1 <30 | 2 30-40 | 3 40-60 | 4 60-100 | 5 >100 cm
%   out.amber       distance < 30 cm      (Immediate_Alert, blinks)
%   out.red         ESRS >= 70            (ESRS Alert, blinks)
%   out.green       ESRS == 0             (RestDone)

    isDry   = humidity_pct < p.dryHumidityThreshold;
    isNoisy = noise_level >= p.highNoiseThreshold;

    if distance_cm < p.dangerCm
        deltaPerMin = p.rate_under30;  zone = 1;
    elseif distance_cm < p.fastCm
        deltaPerMin = p.rate_30_40;    zone = 2;
    elseif distance_cm < p.moderateCm
        deltaPerMin = p.rate_40_60;    zone = 3;
    elseif distance_cm <= p.mildCm
        deltaPerMin = p.rate_60_100;   zone = 4;
    else
        deltaPerMin = p.rate_over100;  zone = 5;
    end

    % Dryness and noise increase build-up only below 60 cm
    if distance_cm < p.moderateCm
        if isDry,   deltaPerMin = deltaPerMin * p.dryMultiplier;   end
        if isNoisy, deltaPerMin = deltaPerMin * p.noiseMultiplier; end
    end

    ESRS_next = ESRS_prev + deltaPerMin * (dt / 60);
    ESRS_next = min(max(ESRS_next, p.riskMin), p.riskMax);

    out.ratePerMin = deltaPerMin;
    out.zone  = zone;
    out.amber = distance_cm < p.dangerCm;
    out.red   = ESRS_next >= p.riskThreshold;
    out.green = ESRS_next == p.riskMin;
    out.dry   = isDry;
    out.noisy = isNoisy;
end
