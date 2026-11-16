function fig = EyeMaxxerDashboard(port, baud)
%EYEMAXXERDASHBOARD  "THE EyeMaxxer" live MATLAB GUI.
%   EyeMaxxerDashboard               open the GUI; type the port and press Connect
%   EyeMaxxerDashboard("COM4")       open and connect straight away
%   EyeMaxxerDashboard("COM4", 9600)
%
%   Live mode - the Arduino handles all sensor logic, MATLAB visualises.
%   The board streams lines of the form
%       D,t_ms,distance_cm,humidity_pct,noise,temp_c,rate_per_min,esrs,zone,green,amber,red
%   (see ../firmware/EyeMaxxer/EyeMaxxer.ino). Without hardware, press
%   "Simulate" to drive the GUI from esrsStep with a scripted study session.
%
%   Find your port with:  serialportlist("available")
%   Requires MATLAB R2020a or newer (uifigure, uigauge, uilamp, serialport).

    if nargin < 1, port = "COM4"; autoConnect = false; else, autoConnect = true; end
    if nargin < 2, baud = 9600; end

    p = esrsParams();
    windowS = 60;                                   % width of the live plots (s)

    % ------------------------------------------------------------------ style
    C.bg     = [0.07 0.08 0.11];  C.panel = [0.09 0.10 0.14];
    C.text   = [0.85 0.88 0.92];  C.dim   = [0.50 0.55 0.62];
    C.accent = [0.55 0.75 1.00];
    C.green  = [0.20 0.85 0.30];  C.amber = [1.00 0.70 0.15];
    C.red    = [0.95 0.25 0.20];  C.off   = [0.22 0.22 0.25];
    C.blue   = [0.35 0.65 1.00];
    zoneNames  = ["Immediate Danger", "Fast Strain", "Moderate Strain", "Mild Strain", "Recovery"];
    zoneColors = [C.red; 1 0.5 0.2; 1 0.85 0.2; C.green; C.blue];

    % ------------------------------------------------------------------ state
    H = struct('t', [], 'esrs', [], 'dist', []);
    sp = [];  mode = "idle";                        % "idle" | "live" | "sim"
    simEsrs = 0;  simT = 0;  simNoise = 0;  simSpeed = 30;
    demo = demoSession();
    st = struct('green', true, 'amber', false, 'red', false);

    % ------------------------------------------------------------------ layout
    fig = uifigure('Name', 'THE EyeMaxxer', 'Position', [60 60 1280 760], 'Color', C.bg);
    root = uigridlayout(fig, [3 3], 'BackgroundColor', C.bg);
    root.RowHeight = {60, '1x', 24};
    root.ColumnWidth = {'1x', '1x', '1.1x'};

    hdr = uigridlayout(root, [2 1], 'BackgroundColor', C.bg, 'Padding', [4 0 0 0], 'RowSpacing', 0);
    hdr.Layout.Row = 1; hdr.Layout.Column = [1 3];
    uilabel(hdr, 'Text', 'THE EyeMaxxer', 'FontSize', 26, 'FontWeight', 'bold', 'FontColor', C.accent);
    subLbl = uilabel(hdr, 'Text', 'Not connected', 'FontColor', C.dim);

    % ---- left column: connection, readings, zones
    left = uigridlayout(root, [3 1], 'BackgroundColor', C.bg, 'Padding', [0 0 0 0]);
    left.Layout.Row = 2; left.Layout.Column = 1;
    left.RowHeight = {120, '1x', '1x'};

    pc = darkPanel(left, 'CONNECTION');
    gc = uigridlayout(pc, [2 3], 'BackgroundColor', C.panel);
    gc.ColumnWidth = {'1x', '1x', '1x'};
    portFld = uieditfield(gc, 'text', 'Value', char(port));
    connLbl = uilabel(gc, 'Text', 'Disconnected', 'FontColor', C.red, 'FontWeight', 'bold');
    uibutton(gc, 'Text', 'Simulate', 'BackgroundColor', [0.25 0.30 0.45], 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~, ~) startSim());
    uibutton(gc, 'Text', 'Connect', 'BackgroundColor', [0.15 0.55 0.30], 'FontColor', 'w', ...
        'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) connect());
    uibutton(gc, 'Text', 'Disconnect', 'BackgroundColor', [0.55 0.17 0.17], 'FontColor', 'w', ...
        'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) disconnect());
    uibutton(gc, 'Text', 'Reset ESRS', 'ButtonPushedFcn', @(~, ~) resetEsrs());

    pr = darkPanel(left, 'LIVE SENSOR READINGS');
    gr = uigridlayout(pr, [5 2], 'BackgroundColor', C.panel);
    gr.ColumnWidth = {110, '1x'};
    distV  = readingRow(gr, 'Distance:');
    humV   = readingRow(gr, 'Humidity:');
    soundV = readingRow(gr, 'Sound:');
    zoneV  = readingRow(gr, 'Zone:');
    rateV  = readingRow(gr, 'ESRS rate:');

    pz = darkPanel(left, 'PROXIMITY ZONES');
    gz = uigridlayout(pz, [5 1], 'BackgroundColor', C.panel);
    zoneText = { ...
        sprintf('<  30 cm      Immediate Danger  (+%.1f/min, amber blinks)', p.rate_under30), ...
        sprintf('30-40 cm     Fast Strain  (+%.1f/min)', p.rate_30_40), ...
        sprintf('40-60 cm     Moderate Strain  (+%.1f/min)', p.rate_40_60), ...
        sprintf('60-100 cm   Mild Strain  (+%.1f/min)', p.rate_60_100), ...
        sprintf('> 100 cm     Recovery  (%.1f/min)', p.rate_over100)};
    for z = 1:5
        uilabel(gz, 'Text', ['■  ' zoneText{z}], 'FontColor', zoneColors(z, :));
    end

    % ---- middle column: gauge + LEDs
    mid = uigridlayout(root, [2 1], 'BackgroundColor', C.bg, 'Padding', [0 0 0 0]);
    mid.Layout.Row = 2; mid.Layout.Column = 2;
    mid.RowHeight = {'1.2x', '1x'};

    pg = darkPanel(mid, 'EYE STRAIN RISK SCORE');
    gg = uigridlayout(pg, [3 1], 'BackgroundColor', C.panel);
    gg.RowHeight = {'1x', 36, 28};
    gauge = uigauge(gg, 'semicircular', 'Limits', [p.riskMin p.riskMax], ...
        'BackgroundColor', C.panel, 'FontColor', C.text, ...
        'ScaleColors', [C.green; 1 0.85 0.2; C.red], ...
        'ScaleColorLimits', [0 35; 35 p.riskThreshold; p.riskThreshold p.riskMax]);
    scoreLbl = uilabel(gg, 'Text', '0', 'FontSize', 30, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'FontColor', C.green);
    stateLbl = uilabel(gg, 'Text', 'SAFE', 'FontSize', 18, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'FontColor', C.green);

    po = darkPanel(mid, 'OUTPUT INDICATORS');
    go = uigridlayout(po, [3 3], 'BackgroundColor', C.panel);
    go.RowHeight = {24, 60, '1x'};
    for nm = ["GREEN", "AMBER", "RED"]
        uilabel(go, 'Text', nm, 'HorizontalAlignment', 'center', 'FontColor', C.text);
    end
    lampG = uilamp(go, 'Color', C.green);
    lampA = uilamp(go, 'Color', C.off);
    lampR = uilamp(go, 'Color', C.off);
    lastLine = uilabel(go, 'Text', 'Last serial line:', 'FontColor', C.dim, 'FontSize', 10);
    lastLine.Layout.Column = [1 3];

    % ---- right column: live plots
    pd = darkPanel(root, 'LIVE DATA');
    pd.Layout.Row = 2; pd.Layout.Column = 3;
    gd = uigridlayout(pd, [2 1], 'BackgroundColor', C.panel);
    axD = darkAxes(gd, 'Distance (cm)', 'cm', [0 150]);
    for b = [p.dangerCm p.fastCm p.moderateCm p.mildCm]
        plot(axD, [-windowS 0], [b b], ':', 'Color', C.dim);
    end
    distLine = plot(axD, NaN, NaN, '-', 'Color', C.blue, 'LineWidth', 1.8);
    axE = darkAxes(gd, 'ESRS', 'Score', [0 105]);
    plot(axE, [-windowS 0], p.riskThreshold * [1 1], '--', 'Color', C.red);
    text(axE, -windowS + 1, p.riskThreshold + 5, 'RED LED', 'Color', C.red, 'FontSize', 9);
    esrsLine = plot(axE, NaN, NaN, '-', 'Color', C.amber, 'LineWidth', 1.8);

    footer = uilabel(root, 'Text', 'Live mode - Arduino handles all sensor logic, MATLAB visualises', ...
        'FontColor', C.dim, 'FontSize', 10);
    footer.Layout.Row = 3; footer.Layout.Column = [1 3];

    tmr = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, 'BusyMode', 'drop', ...
                'TimerFcn', @(~, ~) onTick());
    fig.CloseRequestFcn = @(~, ~) onClose();
    start(tmr);
    if autoConnect, connect(); end

    % ================================================================== logic
    function connect()
        disconnect();
        try
            sp = serialport(portFld.Value, baud, 'Timeout', 0.5);
            configureTerminator(sp, "CR/LF");
            flush(sp);
            mode = "live"; clearHistory();
            connLbl.Text = 'Connected'; connLbl.FontColor = C.green;
            subLbl.Text = sprintf('LIVE - reading sensors from Arduino on %s', portFld.Value);
            footer.Text = 'Live mode - Arduino handles all sensor logic, MATLAB visualises';
        catch err
            uialert(fig, sprintf('Could not open %s:\n%s', portFld.Value, err.message), 'Serial error');
        end
    end

    function disconnect()
        if ~isempty(sp), try, delete(sp); catch, end, end
        sp = []; mode = "idle";
        connLbl.Text = 'Disconnected'; connLbl.FontColor = C.red;
        subLbl.Text = 'Not connected';
    end

    function startSim()
        disconnect();
        mode = "sim"; simEsrs = 0; simT = 0; clearHistory();
        connLbl.Text = 'Simulating'; connLbl.FontColor = C.amber;
        subLbl.Text = sprintf('SIMULATION - scripted study session at %dx speed (esrsStep)', simSpeed);
        footer.Text = 'Simulation mode - same ESRS logic as the firmware and the Simulink model';
    end

    function resetEsrs()
        if mode == "live", write(sp, 'r', 'char'); else, simEsrs = 0; end
    end

    function onTick()
        if ~isvalid(fig), return; end
        try
            switch mode
                case "live", readSerial();
                case "sim",  stepSimulation();
            end
            blink();
        catch err
            lastLine.Text = ['Error: ' err.message];
        end
    end

    function readSerial()
        newest = [];
        while ~isempty(sp) && sp.NumBytesAvailable > 0
            ln = readline(sp);
            if isempty(ln), break; end                % timed out on a partial line
            ln = strtrim(ln);
            lastLine.Text = "Last serial line: " + ln;
            if startsWith(ln, "D,")
                v = str2double(split(extractAfter(ln, 2), ","));
                if numel(v) == 11 && all(~isnan(v))
                    newest = v;
                    push(v(1) / 1000, v(7), v(2));
                end
            end
        end
        if ~isempty(newest)
            % t, dist, hum, noise, temp, rate, esrs, zone(0-4), green, amber, red
            render(newest(2), newest(3), newest(4), newest(6), newest(7), ...
                   newest(8) + 1, newest(9), newest(10), newest(11));
        end
    end

    function stepSimulation()
        for k = 1:round(simSpeed * 0.1)              % 1 s ESRS steps
            [d, hum, noiseRaw] = demoInputs(simT);
            simNoise = simNoise + 0.3 * (noiseRaw - simNoise);
            [simEsrs, o] = esrsStep(simEsrs, d, hum, simNoise, 1, p);
            simT = simT + 1;
        end
        push(simT, simEsrs, d);
        render(d, hum, simNoise, o.ratePerMin, simEsrs, o.zone, o.green, o.amber, o.red);
    end

    function push(t, esrs, dist)
        H.t(end+1) = t; H.esrs(end+1) = esrs; H.dist(end+1) = dist;
        keep = H.t >= t - windowS * ifelse(mode == "sim", simSpeed / 10, 1);
        H.t = H.t(keep); H.esrs = H.esrs(keep); H.dist = H.dist(keep);
    end

    function render(dist, hum, noise, rate, esrs, zone, green, amber, red)
        distV.Text  = sprintf('%.1f cm', dist);
        humV.Text   = sprintf('%.0f %%  (%s)', hum, ifelse(hum < p.dryHumidityThreshold, 'Dry', 'Normal'));
        soundV.Text = ifelse(noise >= p.highNoiseThreshold, 'Noisy', 'Quiet');
        soundV.FontColor = ifelse(noise >= p.highNoiseThreshold, C.amber, C.green);
        zoneV.Text  = char(zoneNames(zone));
        zoneV.FontColor = zoneColors(zone, :);
        rateV.Text  = sprintf('%+.2f / min', rate);

        gauge.Value = esrs;
        scoreLbl.Text = sprintf('%.0f', esrs);
        if red,       s = 'TAKE A BREAK'; c = C.red;
        elseif amber, s = 'TOO CLOSE';    c = C.amber;
        elseif esrs >= 35, s = 'RISING';  c = [1 0.85 0.2];
        else,         s = 'SAFE';         c = C.green;
        end
        stateLbl.Text = s; stateLbl.FontColor = c; scoreLbl.FontColor = c;
        st = struct('green', logical(green), 'amber', logical(amber), 'red', logical(red));

        tt = H.t - H.t(end);
        if mode == "sim", tt = tt / (simSpeed / 10); end    % compress to the 60 s window
        set(distLine, 'XData', tt, 'YData', min(H.dist, 150));
        set(esrsLine, 'XData', tt, 'YData', H.esrs);
    end

    function blink()
        on = mod(floor(posixtime(datetime('now')) * 4), 2) == 1;   % 2 Hz, like the LEDs
        lampG.Color = ifelse(st.green, C.green, C.off);
        lampA.Color = ifelse(st.amber && on, C.amber, C.off);
        lampR.Color = ifelse(st.red && on, C.red, C.off);
    end

    function clearHistory()
        H = struct('t', [], 'esrs', [], 'dist', []);
    end

    function onClose()
        try, stop(tmr); delete(tmr); catch, end
        disconnect();
        delete(fig);
    end

    % ------------------------------------------------------- UI helpers
    function pnl = darkPanel(parent, titleText)
        pnl = uipanel(parent, 'Title', titleText, 'FontWeight', 'bold', ...
            'BackgroundColor', C.panel, 'ForegroundColor', C.accent, 'BorderType', 'line');
    end

    function v = readingRow(g, name)
        uilabel(g, 'Text', name, 'FontColor', C.text);
        v = uilabel(g, 'Text', '--', 'FontColor', C.blue, 'FontSize', 15, 'FontWeight', 'bold');
    end

    function ax = darkAxes(parent, ttl, yl, lims)
        ax = uiaxes(parent, 'Color', [0.12 0.13 0.17], 'XColor', C.dim, 'YColor', C.dim);
        ax.Title.String = ttl; ax.Title.Color = C.text;
        ylabel(ax, yl); xlabel(ax, 'Time (s)');
        xlim(ax, [-windowS 0]); ylim(ax, lims); grid(ax, 'on'); hold(ax, 'on');
    end

    % ------------------------------------------------------- simulated input
    function [d, hum, noise] = demoInputs(t)
        tt = mod(t / 60, demo.total);
        s = demo.seg(find(tt < demo.ends, 1), :);
        d = s(2); if d <= 100, d = d + 1.5 * sin(t / 7); end
        hum = s(3);
        noise = s(4) + 0.05 * sin(t / 3);
    end
end

% ============================================================================
function demo = demoSession()
    % [duration_min, distance_cm, humidity_pct, noise] - loops forever
    demo.seg = [ ...
        3   70  50  0.2;    % healthy distance
        6   35  28  0.2;    % leaning in, dry room -> fast strain
        2   25  28  0.2;    % danger zone -> amber blinks, red soon after
        6   120 50  0.2;    % break: recovery
        8   50  55  0.8;    % noisy library at 50 cm
        5   120 50  0.2];   % break
    demo.ends = cumsum(demo.seg(:, 1));
    demo.total = demo.ends(end);
end

function out = ifelse(c, a, b)
    if c, out = a; else, out = b; end
end
