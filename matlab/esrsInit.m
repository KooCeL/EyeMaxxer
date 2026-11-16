function state = esrsInit()
%ESRSINIT  Initial (rested) ESRS state for esrsStep.
    state = struct('score', 0, 'awayTime', 0, 'level', 0);
end
