function [state, out] = esrsStep(state, distanceCm, noiseLevel, humidityPct, dt, p)
%ESRSSTEP  Advance the Eye Strain Risk Score by one time step.
%   [state, out] = esrsStep(state, distanceCm, noiseLevel, humidityPct, dt, p)
%
%   state  struct with fields score, awayTime, level (use esrsInit to create)
%   distanceCm   screen distance; <= 0 means no echo
%   noiseLevel   smoothed microphone peak-to-peak (ADC counts)
%   humidityPct  relative humidity; < 0 means no valid reading yet
%   dt           time step in seconds
%   p            parameters from esrsParams
%
%   out    struct with fields score, multiplier, zone, level, prox, noisy, dry
%          zone : 0 = away, 1 = danger, 2 = close, 3 = ok
%          level: 0 = green, 1 = yellow, 2 = red, 3 = red blinking (overdue)
%
%   This is a line-for-line port of firmware/EyeMaxxer/esrs.h. It uses only
%   scalar maths and structs, so it can also be dropped into a Simulink
%   MATLAB Function block and code-generated for the Arduino.

    % --- 1. classify distance -------------------------------------------------
    if distanceCm <= 0 || distanceCm > p.awayCm
        zone = 0;
    elseif distanceCm < p.dangerCm
        zone = 1;
    elseif distanceCm < p.closeCm
        zone = 2;
    else
        zone = 3;
    end

    % --- 2. environmental multiplier -----------------------------------------
    noisy = noiseLevel > p.noiseThreshold;
    dry   = humidityPct >= 0 && humidityPct < p.humidityLowPct;
    mult  = 1;
    if noisy, mult = mult * p.noiseMult;    end
    if dry,   mult = mult * p.humidityMult; end

    % --- 3. integrate the score -----------------------------------------------
    if zone == 0
        state.awayTime = state.awayTime + dt;
        if state.awayTime >= p.awayDebounceS
            state.score = state.score - p.rateRecovery * dt;
        end
    else
        state.awayTime = 0;
        rates = [p.rateDanger, p.rateClose, p.rateOk];
        state.score = state.score + rates(zone) * mult * dt;
    end
    state.score = min(max(state.score, 0), p.esrsMax);

    % --- 4. LED level with hysteresis ----------------------------------------
    s = state.score;
    if s >= p.levelOverdue
        raw = 3;
    elseif s >= p.levelRed
        raw = 2;
    elseif s >= p.levelYellow
        raw = 1;
    else
        raw = 0;
    end

    enter = [p.levelYellow, p.levelRed, p.levelOverdue];  % thresholds for levels 1..3
    lvl = state.level;
    if raw >= lvl
        lvl = raw;
    else
        while lvl > raw && s < enter(lvl) - p.hysteresis
            lvl = lvl - 1;
        end
    end
    state.level = lvl;

    out.score      = state.score;
    out.multiplier = mult;
    out.zone       = zone;
    out.level      = lvl;
    out.prox       = (zone == 1);
    out.noisy      = noisy;
    out.dry        = dry;
end
