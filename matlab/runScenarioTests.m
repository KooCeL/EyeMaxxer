function results = runScenarioTests(makePlots)
%RUNSCENARIOTESTS  Automated regression check of the ESRS logic.
%   results = runScenarioTests()       runs the five scenarios from the team's
%                                      eye_strain_sim.m through esrsStep,
%                                      checks the LED timings and plots a summary.
%   results = runScenarioTests(false)  same, without plotting.
%
%   The expected timings are the ones printed by eye_strain_sim.m and shown in
%   the make-a-thon presentation. The firmware unit tests
%   (../tests/test_esrs.cpp) check the C++ port against the same numbers.
%   Works in MATLAB and GNU Octave; errors if any check fails.

    if nargin < 1, makePlots = true; end
    p = esrsParams();

    % name, duration (min), segments [until_min, distance_cm, humidity_pct, noise]
    sc = {
      'Scenario 1 - Immediate Under 30 cm', 15, ...
          [2 70 50 0.2; 5 25 50 0.2; inf 75 50 0.2]
      'Scenario 2 - 35 cm Dry Environment', 35, ...
          [5 70 28 0.2; 25 35 28 0.2; inf 75 28 0.2]
      'Scenario 3 - 35 cm Humid Environment', 35, ...
          [5 70 55 0.2; 25 35 55 0.2; inf 75 55 0.2]
      'Scenario 4 - 50 cm Humid and Noisy Environment', 60, ...
          [5 75 55 0.2; 20 50 55 0.2; 55 50 55 0.8; inf 75 55 0.8]
      'Scenario 5 - Recovery Above 100 cm', 50, ...
          [12 35 30 0.2; 20 45 30 0.2; 22 45 50 0.2; 35 120 50 0.2; inf 70 50 0.2]
    };

    results = cell(size(sc, 1), 1);
    for k = 1:size(sc, 1)
        results{k} = simulate(sc{k, 2}, sc{k, 3}, p);
    end

    fprintf('\nEyeMaxxer ESRS regression checks\n%s\n', repmat('-', 1, 60));
    nFail = 0;
    r = results{1};
    nFail = nFail + check(near(firstTime(r, r.amber), 2.00), 'S1: amber LED at 2.00 min');
    nFail = nFail + check(~any(r.red), 'S1: red LED never on');
    r = results{2};
    nFail = nFail + check(near(firstTime(r, r.red), 16.87), 'S2: red LED at 16.87 min (dry)');
    r = results{3};
    nFail = nFail + check(near(firstTime(r, r.red), 20.43), 'S3: red LED at 20.43 min (humid)');
    r = results{4};
    nFail = nFail + check(near(firstTime(r, r.red), 36.45), 'S4: red LED at 36.45 min (noisy)');
    r = results{5};
    tOff = firstTime(r, [false; r.red(1:end-1) & ~r.red(2:end)]);
    nFail = nFail + check(near(firstTime(r, r.red), 11.95), 'S5: red LED at 11.95 min');
    nFail = nFail + check(tOff > 22 && tOff < 35, ...
        sprintf('S5: red LED clears at %.2f min, during the > 100 cm break', tOff));
    fprintf('%s\n', repmat('-', 1, 60));

    if makePlots
        plotSummary(sc, results, p);
    end
    if nFail > 0
        error('EyeMaxxer:scenarioFailure', '%d ESRS check(s) failed', nFail);
    end
    fprintf('ALL CHECKS PASSED\n');
end

% =============================================================================
function r = simulate(durationMin, seg, p)
    % Same sampling as eye_strain_sim.m: t = 0:1:duration*60 seconds
    dt = 1;
    r.tmin = (0:dt:durationMin*60)' / 60;
    N = numel(r.tmin);
    [r.distance, r.esrs] = deal(zeros(N, 1));
    [r.amber, r.red, r.green] = deal(false(N, 1));
    esrs = 0;
    for k = 1:N
        s = seg(find(r.tmin(k) < seg(:, 1), 1), :);
        [esrs, o] = esrsStep(esrs, s(2), s(3), s(4), dt, p);
        r.distance(k) = s(2);
        r.esrs(k)  = esrs;
        r.amber(k) = o.amber;
        r.red(k)   = o.red;
        r.green(k) = o.green;
    end
end

function t = firstTime(r, mask)
    i = find(mask, 1);
    if isempty(i), t = NaN; else, t = r.tmin(i); end
end

function ok = near(a, b)
    ok = abs(a - b) < 0.006;
end

function failed = check(ok, msg)
    if ok, fprintf('  PASS  %s\n', msg); else, fprintf('  FAIL  %s\n', msg); end
    failed = ~ok;
end

function plotSummary(sc, results, p)
    cAmber = [0.96 0.62 0.10]; cRed = [0.86 0.20 0.18]; cGreen = [0.18 0.70 0.30];
    fig = figure('Name', 'EyeMaxxer ESRS scenarios', 'Color', 'w', ...
                 'Position', [50 50 1200 950]);
    n = size(sc, 1);
    for k = 1:n
        r = results{k};
        ax = subplot(n, 1, k); hold(ax, 'on');
        plot(ax, r.tmin, r.esrs, '-', 'LineWidth', 2, 'Color', [0.1 0.1 0.1]);
        plot(ax, [0 r.tmin(end)], p.riskThreshold * [1 1], '--', 'Color', cRed);
        % LED states as coloured bars under the curve
        bar_ = @(m, y, c) plot(ax, r.tmin, y * ifnan(m), '-', 'LineWidth', 5, 'Color', c);
        bar_(r.green, -8,  cGreen);
        bar_(r.amber, -16, cAmber);
        bar_(r.red,   -24, cRed);
        ylim(ax, [-30 105]); ylabel(ax, 'ESRS');
        xlim(ax, [0 r.tmin(end)]); grid(ax, 'on'); box(ax, 'on');
        title(ax, sc{k, 1});
        if k == n, xlabel(ax, 'time (min)'); end
    end
    annotation(fig, 'textbox', [0 0.965 1 0.035], 'String', ...
        ['black: ESRS   |   bars: green LED (ESRS = 0), ', ...
         'amber LED (< 30 cm), red LED (ESRS \geq 70)'], ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

function y = ifnan(mask)
    y = double(mask); y(y == 0) = NaN;
end
