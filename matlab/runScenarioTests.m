function results = runScenarioTests(makePlots)
%RUNSCENARIOTESTS  Validate the ESRS algorithm against realistic study sessions.
%   results = runScenarioTests()       runs every scenario, checks the expected
%                                      behaviour and plots the results.
%   results = runScenarioTests(false)  same, without plotting.
%
%   Each scenario is a sequence of segments [duration_s, distance_cm,
%   noise_level, humidity_pct]. The simulator feeds them through esrsStep at
%   the firmware tick rate (with a little ultrasonic measurement noise) and
%   records the score, zone and LED level, exactly as the Arduino would.
%
%   Works in MATLAB and GNU Octave.

    if nargin < 1, makePlots = true; end
    p = esrsParams();

    quiet = 60;  loud = 350;   % mic peak-to-peak levels
    humid = 50;  dryAir = 30;  % relative humidity (%)

    sc = {};
    sc{end+1} = struct('name', 'Good posture, 30 min, no breaks', ...
        'segments', [30*60, 60, quiet, humid]);
    sc{end+1} = struct('name', 'Leaning in (25 cm) for 5 min', ...
        'segments', [5*60, 25, quiet, humid]);
    sc{end+1} = struct('name', 'Noisy, dry library, 30 min', ...
        'segments', [30*60, 60, loud, dryAir]);
    sc{end+1} = struct('name', '20-20-20 rule: 20 min work + 20 s break', ...
        'segments', repmat([20*60, 60, quiet, humid; 20, 0, quiet, humid], 3, 1));
    sc{end+1} = struct('name', 'Glances away (1 s) do not count as breaks', ...
        'segments', repmat([29, 60, quiet, humid; 1, 0, quiet, humid], 50, 1));
    sc{end+1} = struct('name', 'Mixed session: drift closer, then break', ...
        'segments', [8*60, 60, quiet, humid; 6*60, 40, quiet, humid; ...
                     3*60, 26, loud, dryAir; 60, 0, quiet, humid; 5*60, 60, quiet, humid]);

    results = cell(size(sc));
    for k = 1:numel(sc)
        results{k} = simulate(sc{k}, p, k);
    end

    % --- expected behaviour ---------------------------------------------------
    fprintf('\nEyeMaxxer ESRS scenario tests\n%s\n', repmat('-', 1, 60));
    nFail = 0;
    r = results{1};
    nFail = nFail + check(abs(firstTime(r, r.level >= 2)/60 - 70/p.rateOk/60) < 0.5, ...
        sprintf('Good posture: red LED after %.1f min (expected ~%.1f)', ...
        firstTime(r, r.level >= 2)/60, 70/p.rateOk/60));
    nFail = nFail + check(~any(r.prox), 'Good posture: proximity LED never lit');

    r = results{2};
    nFail = nFail + check(all(r.prox(r.t > 1)), 'Leaning in: proximity LED lit immediately');
    nFail = nFail + check(firstTime(r, r.level >= 2) < 3.5*60, ...
        sprintf('Leaning in: red LED after %.1f min', firstTime(r, r.level >= 2)/60));

    r = results{3};
    tExpected = 70 / (p.rateOk * p.noiseMult * p.humidityMult);
    nFail = nFail + check(abs(firstTime(r, r.level >= 2) - tExpected) < 30, ...
        sprintf('Noisy + dry: red LED after %.1f min (%.0f%% sooner than quiet room)', ...
        firstTime(r, r.level >= 2)/60, 100*(1 - tExpected/(70/p.rateOk))));

    r = results{4};
    nFail = nFail + check(max(r.score) < p.levelRed, ...
        sprintf('20-20-20: score peaks at %.1f, never reaches red', max(r.score)));

    r5 = results{5}; r1 = results{1};
    nFail = nFail + check(r5.score(end) > 0.9 * interp1(r1.t, r1.score, r5.t(end)), ...
        'Glances: 1 s look-aways are debounced, score keeps building');

    r = results{6};
    nFail = nFail + check(any(r.level >= 2) && r.level(end) == 0, ...
        'Mixed: reaches red when leaning in, back to green after a break');

    fprintf('%s\n%s (%d failure(s))\n', repmat('-', 1, 60), ...
        ternary(nFail == 0, 'ALL SCENARIOS PASSED', 'SCENARIO FAILURES'), nFail);

    if makePlots
        plotResults(sc, results, p);
    end
    if nFail > 0
        error('EyeMaxxer:scenarioFailure', '%d ESRS scenario check(s) failed', nFail);
    end
end

% =============================================================================
function r = simulate(scenario, p, seed)
    seg = scenario.segments;
    dt = p.tickS;
    n = round(sum(seg(:, 1)) / dt);
    r.t = (1:n)' * dt;
    [r.distance, r.score, r.zone, r.level, r.prox, r.mult] = deal(zeros(n, 1));

    % deterministic pseudo-random measurement noise (+-1.5 cm), MATLAB & Octave
    lcg = mod(seed * 7919, 2^31);

    state = esrsInit();
    idx = 0;
    for s = 1:size(seg, 1)
        for i = 1:round(seg(s, 1) / dt)
            idx = idx + 1;
            lcg = mod(1103515245 * lcg + 12345, 2^31);
            d = seg(s, 2);
            if d > 0, d = d + 3 * (lcg / 2^31 - 0.5); end
            [state, out] = esrsStep(state, d, seg(s, 3), seg(s, 4), dt, p);
            r.distance(idx) = d;
            r.score(idx)    = out.score;
            r.zone(idx)     = out.zone;
            r.level(idx)    = out.level;
            r.prox(idx)     = out.prox;
            r.mult(idx)     = out.multiplier;
        end
    end
end

function t = firstTime(r, mask)
    i = find(mask, 1);
    if isempty(i), t = inf; else, t = r.t(i); end
end

function failed = check(ok, msg)
    if ok, fprintf('  PASS  %s\n', msg); else, fprintf('  FAIL  %s\n', msg); end
    failed = ~ok;
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end

function plotResults(sc, results, p)
    ledColours = [0.18 0.70 0.30; 0.98 0.75 0.10; 0.86 0.20 0.18; 0.55 0.05 0.05];
    fig = figure('Name', 'EyeMaxxer ESRS scenario tests', 'Color', 'w', ...
                 'Position', [50 50 1200 900]);
    nS = numel(sc);
    for k = 1:nS
        r = results{k};
        tm = r.t / 60;
        ax = subplot(ceil(nS/2), 2, k);
        hold(ax, 'on');
        % LED level as a coloured strip along the bottom
        for L = 0:3
            m = double(r.level == L); m(m == 0) = NaN;
            plot(ax, tm, -6 * m, '-', 'LineWidth', 6, 'Color', ledColours(L+1, :));
        end
        plot(ax, tm, r.score, 'k-', 'LineWidth', 1.8);
        plot(ax, [tm(1) tm(end)], p.levelYellow * [1 1], '--', 'Color', ledColours(2, :));
        plot(ax, [tm(1) tm(end)], p.levelRed * [1 1], '--', 'Color', ledColours(3, :));
        % proximity warnings as red ticks along the top
        pm = double(r.prox); pm(pm == 0) = NaN;
        plot(ax, tm, 104 * pm, '-', 'LineWidth', 4, 'Color', [0.2 0.4 0.95]);
        ylim(ax, [-10 108]); xlim(ax, [0 tm(end)]);
        title(ax, sc{k}.name);
        xlabel(ax, 'time (min)'); ylabel(ax, 'ESRS');
        grid(ax, 'on'); box(ax, 'on');
        hold(ax, 'off');
    end
    annotation(fig, 'textbox', [0 0.955 1 0.045], 'String', ...
        ['EyeMaxxer ESRS scenarios  |  black: score  |  bottom strip: LED level ', ...
         '(green/yellow/red/blink)  |  blue top bar: proximity warning (< 30 cm)'], ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
