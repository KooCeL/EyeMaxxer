function fig = EyeMaxxerDashboard(port, baud)
%EYEMAXXERDASHBOARD  Live graphical UI for EyeMaxxer.
%   EyeMaxxerDashboard()                 simulated demo - no hardware needed
%   EyeMaxxerDashboard("COM5")           live data from the Arduino on COM5
%   EyeMaxxerDashboard("/dev/ttyACM0", 115200)
%
%   Shows the real-time Eye Strain Risk Score (gauge + trend), the screen
%   distance with the danger/close zones, the environmental readings and
%   multiplier, and a mirror of the four LEDs on the device.
%
%   In live mode the Arduino streams lines of the form
%       D,t_ms,distance_cm,noise,humidity_pct,temp_c,multiplier,esrs,zone,level,prox
%   (see firmware/EyeMaxxer/EyeMaxxer.ino). The "Reset ESRS" button sends 'r'
%   to the board. In simulated mode the same esrsStep used by the scenario
%   tests drives the UI from a scripted study session.
%
%   Find your port with:  serialportlist("available")
%   Requires MATLAB R2020a or newer (uifigure, uigauge, uilamp, serialport).

    if nargin < 1 || isempty(port), port = ""; end
    if nargin < 2, baud = 115200; end
    live = strlength(string(port)) > 0;

    p = esrsParams();
    windowS = 600;                       % width of the trend plots (s)

    % ---------------------------------------------------------------- state
    H = struct('t', [], 'score', [], 'dist', [], 'level', []);
    sp = [];                             % serialport (live mode)
    simState = esrsInit();
    simT = 0;  simNoise = 0;  simSpeed = 20;
    demo = demoSession();
    lastBlink = false;

    C.green  = [0.18 0.70 0.30];
    C.yellow = [0.98 0.75 0.10];
    C.red    = [0.86 0.20 0.18];
    C.prox   = [0.20 0.45 0.95];
    C.off    = [0.30 0.30 0.30];
    zoneNames  = ["Away / on a break", "DANGER - too close", "Too close", "Healthy distance"];
    levelNames = ["Low risk", "Rising risk", "High risk - take a break", "Break overdue!"];

    % ---------------------------------------------------------------- layout
    fig = uifigure('Name', 'EyeMaxxer - Live ESRS Dashboard', ...
                   'Position', [80 80 1180 720], 'Color', [0.97 0.97 0.98]);
    g = uigridlayout(fig, [3 3]);
    g.RowHeight = {'1x', '1x', 40};
    g.ColumnWidth = {300, '1x', 260};

    % ESRS gauge
    gp = uipanel(g, 'Title', 'Eye Strain Risk Score', 'FontWeight', 'bold');
    gp.Layout.Row = 1; gp.Layout.Column = 1;
    gl = uigridlayout(gp, [2 1]); gl.RowHeight = {'1x', 30};
    gauge = uigauge(gl, 'circular', 'Limits', [0 p.esrsMax], ...
        'ScaleColors', [C.green; C.yellow; C.red], ...
        'ScaleColorLimits', [0 p.levelYellow; p.levelYellow p.levelRed; p.levelRed p.esrsMax]);
    levelLbl = uilabel(gl, 'Text', levelNames(1), 'HorizontalAlignment', 'center', ...
                       'FontSize', 16, 'FontWeight', 'bold');

    % LED mirror
    lp = uipanel(g, 'Title', 'Device LEDs', 'FontWeight', 'bold');
    lp.Layout.Row = 2; lp.Layout.Column = 1;
    ll = uigridlayout(lp, [4 2]); ll.ColumnWidth = {40, '1x'};
    lampG = uilamp(ll, 'Color', C.off); uilabel(ll, 'Text', 'Green - low risk (< 40)');
    lampY = uilamp(ll, 'Color', C.off); uilabel(ll, 'Text', 'Yellow - rising (40-70)');
    lampR = uilamp(ll, 'Color', C.off); uilabel(ll, 'Text', 'Red - take a break (> 70)');
    lampP = uilamp(ll, 'Color', C.off); uilabel(ll, 'Text', 'Proximity - closer than 30 cm');

    % Trend plots
    axS = uiaxes(g); axS.Layout.Row = 1; axS.Layout.Column = 2;
    title(axS, 'ESRS over time'); ylabel(axS, 'ESRS'); xlabel(axS, 'time (min)');
    ylim(axS, [0 p.esrsMax + 5]); grid(axS, 'on'); hold(axS, 'on');
    plot(axS, [0 1e6], p.levelYellow * [1 1], '--', 'Color', C.yellow);
    plot(axS, [0 1e6], p.levelRed * [1 1], '--', 'Color', C.red);
    scoreLine = plot(axS, NaN, NaN, 'k-', 'LineWidth', 2);

    axD = uiaxes(g); axD.Layout.Row = 2; axD.Layout.Column = 2;
    title(axD, 'Screen distance'); ylabel(axD, 'distance (cm)'); xlabel(axD, 'time (min)');
    ylim(axD, [0 p.awayCm + 20]); grid(axD, 'on'); hold(axD, 'on');
    plot(axD, [0 1e6], p.dangerCm * [1 1], '-', 'Color', C.red, 'LineWidth', 1.2);
    plot(axD, [0 1e6], p.closeCm * [1 1], '--', 'Color', C.yellow, 'LineWidth', 1.2);
    plot(axD, [0 1e6], p.awayCm * [1 1], ':', 'Color', C.off);
    distLine = plot(axD, NaN, NaN, '-', 'Color', C.prox, 'LineWidth', 1.5);

    % Readings
    rp = uipanel(g, 'Title', 'Live readings', 'FontWeight', 'bold');
    rp.Layout.Row = [1 2]; rp.Layout.Column = 3;
    rl = uigridlayout(rp, [8 1]);
    distLbl  = uilabel(rl, 'FontSize', 22, 'FontWeight', 'bold', 'Text', '-- cm');
    zoneLbl  = uilabel(rl, 'FontSize', 14, 'Text', '');
    noiseLbl = uilabel(rl, 'FontSize', 14, 'Text', 'Noise: --');
    humLbl   = uilabel(rl, 'FontSize', 14, 'Text', 'Humidity: --');
    tempLbl  = uilabel(rl, 'FontSize', 14, 'Text', 'Temperature: --');
    multLbl  = uilabel(rl, 'FontSize', 14, 'FontWeight', 'bold', 'Text', 'ESRS multiplier: x1.00');
    uilabel(rl, 'Text', '');
    srcLbl   = uilabel(rl, 'FontColor', [0.4 0.4 0.4], 'WordWrap', 'on');

    % Bottom bar
    bb = uigridlayout(g, [1 4]); bb.Layout.Row = 3; bb.Layout.Column = [1 3];
    bb.ColumnWidth = {140, 140, 200, '1x'}; bb.Padding = [0 0 0 0];
    uibutton(bb, 'Text', 'Reset ESRS', 'ButtonPushedFcn', @(~, ~) onReset());
    uibutton(bb, 'Text', 'Clear plots', 'ButtonPushedFcn', @(~, ~) clearHistory());
    if live
        uilabel(bb, 'Text', '');
    else
        speedDd = uidropdown(bb, 'Items', {'1x real time', '5x', '20x', '60x'}, ...
            'ItemsData', [1 5 20 60], 'Value', simSpeed, ...
            'ValueChangedFcn', @(dd, ~) setSpeed(dd.Value)); %#ok<NASGU>
    end
    statusLbl = uilabel(bb, 'Text', '', 'FontColor', [0.4 0.4 0.4]);

    % ---------------------------------------------------------------- source
    if live
        try
            sp = serialport(port, baud, 'Timeout', 0.5);
            configureTerminator(sp, "CR/LF");
            flush(sp);
            srcLbl.Text = sprintf('Source: Arduino on %s @ %d baud', port, baud);
        catch err
            uialert(fig, sprintf('Could not open %s:\n%s', port, err.message), 'Serial error');
            srcLbl.Text = 'Source: not connected';
        end
    else
        srcLbl.Text = 'Source: simulated study session (run with a port name for live data)';
    end

    tmr = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, ...
                'BusyMode', 'drop', 'TimerFcn', @(~, ~) onTick());
    fig.CloseRequestFcn = @(~, ~) onClose();
    start(tmr);

    % =================================================================== logic
    function onTick()
        if ~isvalid(fig), return; end
        try
            if live
                readSerial();
            else
                stepSimulation();
            end
            refreshBlink();
        catch err
            statusLbl.Text = ['Error: ' err.message];
        end
    end

    function readSerial()
        if isempty(sp), return; end
        newest = [];
        while sp.NumBytesAvailable > 0
            ln = readline(sp);
            if isempty(ln), break; end          % timed out on a partial line
            ln = strtrim(ln);
            if startsWith(ln, "D,")
                v = str2double(split(extractAfter(ln, 2), ","));
                if numel(v) == 10 && all(~isnan(v))
                    newest = v;
                    push(v(1) / 1000, v(7), v(2), v(9));
                end
            elseif strlength(ln) > 0
                statusLbl.Text = char(ln);   % firmware comments / acks
            end
        end
        if ~isempty(newest)
            % t, dist, noise, hum, temp, mult, esrs, zone, level, prox
            render(newest(2), newest(3), newest(4), newest(5), newest(6), ...
                   newest(7), newest(8), newest(9), newest(10));
        end
    end

    function stepSimulation()
        nSteps = max(1, round(simSpeed * 0.1 / p.tickS));
        for k = 1:nSteps
            [d, noiseRaw, hum] = demoInputs(simT);
            simNoise = simNoise + 0.15 * (noiseRaw - simNoise);
            [simState, o] = esrsStep(simState, d, simNoise, hum, p.tickS, p);
            simT = simT + p.tickS;
        end
        push(simT, o.score, d, o.level);
        render(d, simNoise, hum, 21.5, o.multiplier, o.score, o.zone, o.level, o.prox);
    end

    function push(t, score, dist, level)
        H.t(end+1) = t; H.score(end+1) = score; H.dist(end+1) = dist; H.level(end+1) = level;
        keep = H.t >= t - windowS;
        H.t = H.t(keep); H.score = H.score(keep); H.dist = H.dist(keep); H.level = H.level(keep);
    end

    function render(dist, noise, hum, temp, mult, score, zone, level, prox)
        gauge.Value = score;
        levelLbl.Text = levelNames(level + 1);
        levelColours = [C.green; C.yellow * 0.8; C.red; C.red];
        levelLbl.FontColor = levelColours(level + 1, :);

        lampG.Color = ifelse(level == 0, C.green, C.off);
        lampY.Color = ifelse(level == 1, C.yellow, C.off);
        lampR.Color = ifelse(level == 2 || (level == 3 && lastBlink), C.red, C.off);
        lampP.Color = ifelse(prox, C.prox, C.off);
        lampR.UserData = level;

        if dist > 0, distLbl.Text = sprintf('%.1f cm', dist); else, distLbl.Text = 'no echo'; end
        zoneLbl.Text = zoneNames(zone + 1);
        noiseLbl.Text = sprintf('Noise: %.0f %s', noise, ifelse(noise > p.noiseThreshold, '(loud x1.25)', '(quiet)'));
        if hum >= 0
            humLbl.Text = sprintf('Humidity: %.0f %% %s', hum, ifelse(hum < p.humidityLowPct, '(dry x1.30)', ''));
        else
            humLbl.Text = 'Humidity: waiting for sensor';
        end
        tempLbl.Text = sprintf('Temperature: %.1f %sC', temp, char(176));
        multLbl.Text = sprintf('ESRS multiplier: x%.2f', mult);

        tm = (H.t - H.t(end)) / 60;      % minutes, "now" at 0
        d = H.dist; d(d <= 0) = NaN;
        set(scoreLine, 'XData', tm, 'YData', H.score);
        set(distLine,  'XData', tm, 'YData', d);
        xlim(axS, [-windowS/60 0]); xlim(axD, [-windowS/60 0]);
        statusLbl.Text = sprintf('t = %s', char(duration(0, 0, H.t(end), 'Format', 'hh:mm:ss')));
    end

    function refreshBlink()
        % toggle every half blink period (firmware BLINK_PERIOD_MS = 400)
        lastBlink = mod(floor(posixtime(datetime('now')) * 1000 / 200), 2) == 1;
        if isequal(lampR.UserData, 3)
            lampR.Color = ifelse(lastBlink, C.red, C.off);
        end
    end

    function onReset()
        if live && ~isempty(sp)
            write(sp, 'r', 'char');
        else
            simState = esrsInit();
        end
    end

    function clearHistory()
        H = struct('t', [], 'score', [], 'dist', [], 'level', []);
    end

    function setSpeed(v)
        simSpeed = v;
    end

    function onClose()
        try, stop(tmr); delete(tmr); catch, end
        try, delete(sp); catch, end
        delete(fig);
    end

    % ------------------------------------------------------- simulated input
    function [d, noise, hum] = demoInputs(t)
        tt = mod(t, demo.total);
        i = find(tt < demo.ends, 1);
        seg = demo.seg(i, :);
        d = seg(2);
        if d > 0, d = d + 1.5 * sin(t * 1.7) + 0.8 * sin(t * 5.3); end
        noise = seg(3) + 15 * sin(t * 3.1);
        hum = seg(4);
    end
end

% ============================================================================
function demo = demoSession()
    % [duration_s, distance_cm, noise, humidity] - loops forever
    demo.seg = [ ...
        8*60,  62,  60, 50;   % healthy posture
        5*60,  42,  60, 50;   % drifting closer
        2*60,  25, 320, 32;   % leaning in, noisy dry room
          25,   0,  60, 50;   % short break
        6*60,  60, 320, 32;   % back to work in a noisy, dry library
          40,   0,  60, 50];  % proper break
    demo.ends = cumsum(demo.seg(:, 1));
    demo.total = demo.ends(end);
end

function out = ifelse(c, a, b)
    if c, out = a; else, out = b; end
end
