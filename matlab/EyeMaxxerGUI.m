function fig = EyeMaxxerGUI(port)
%EYEMAXXERGUI  "THE EyeMaxxer" - live MATLAB GUI for the EyeMaxxer device.
%   EyeMaxxerGUI              open the GUI, type the port (e.g. COM4), press Connect
%   EyeMaxxerGUI("COM4")      open and connect straight away
%   EyeMaxxerGUI("demo")      no hardware: play a scripted session through the GUI
%
%   Live mode - the Arduino handles all sensor logic, MATLAB visualises.
%   Once per second the board (../firmware/EyeMaxxer/EyeMaxxer.ino) sends
%       DIST:45.2,HUM:38,SOUND:0,ZONE:2,INC:2.6,ESRS:512.4,LED:1,BLINK:0,VIB:0,MODE:0
%   and the GUI shows the readings, the 0-1000 Eye Strain Risk Score, the
%   LED / vibration motor states and 60 s of live distance and ESRS history.
%
%   Find your port with:  serialportlist("available")
%   Requires MATLAB R2020a or newer.

    if nargin < 1, port = ""; end
    port = string(port);
    BAUD = 9600;
    WINDOW = 60;                                % seconds of history on the plots

    % ------------------------------------------------------------- appearance
    C.bg    = [0.07 0.08 0.11];   C.panel = [0.09 0.10 0.14];
    C.text  = [0.80 0.84 0.90];   C.dim   = [0.45 0.50 0.58];
    C.title = [0.55 0.75 1.00];   C.value = [0.35 0.70 1.00];
    C.green = [0.15 0.85 0.25];   C.amber = [1.00 0.72 0.10];
    C.red   = [0.95 0.22 0.18];   C.off   = [0.22 0.22 0.25];
    zoneName  = ["Immediate Danger (+blink)", "Fast Strain (+4)", "Moderate Strain (+2)", ...
                 "Mild Strain (+1)", "Recovery (" + char(8722) + "3)"];
    zoneRange = ["< 30 cm", "30" + char(8211) + "40 cm", "40" + char(8211) + "60 cm", ...
                 "60" + char(8211) + "100 cm", char(8805) + " 100 cm"];
    zoneColor = [0.95 0.25 0.20; 1.00 0.50 0.15; 1.00 0.85 0.20; 0.30 0.85 0.35; 0.35 0.65 1.00];
    modeName  = ["LED + Vibrate", "LED only", "Vibrate only"];

    % ------------------------------------------------------------------ state
    sp = [];  demo = false;  demoState = [];
    H = struct('t', zeros(0, 1), 'dist', zeros(0, 1), 'esrs', zeros(0, 1));
    t0 = tic;  blinkRed = false;  vibOn = false;

    % ================================================================= layout
    fig = uifigure('Name', 'THE EyeMaxxer', 'Position', [60 60 1300 780], 'Color', C.bg);
    root = uigridlayout(fig, [3 3], 'BackgroundColor', C.bg, 'Padding', [24 12 24 12]);
    root.RowHeight = {64, '1x', 22};
    root.ColumnWidth = {'1x', '1x', '1.05x'};

    head = uigridlayout(root, [2 1], 'BackgroundColor', C.bg, 'Padding', [0 0 0 0], 'RowSpacing', 2);
    head.Layout.Row = 1; head.Layout.Column = [1 3];
    uilabel(head, 'Text', 'THE EyeMaxxer', 'FontSize', 26, 'FontWeight', 'bold', 'FontColor', C.title);
    subtitle = uilabel(head, 'Text', 'Not connected', 'FontColor', C.dim);

    % ---------------- column 1: connection / readings / zones
    col1 = column(1, {130, '1x', '1x'});

    g = panelGrid(col1, 'CONNECTION', [2 3]);
    g.ColumnWidth = {50, '1x', '1x'};
    uilabel(g, 'Text', 'Port:', 'FontColor', C.text);
    portField = uieditfield(g, 'text', 'Value', char(ifelse(port == "demo", "", port)));
    statusLbl = uilabel(g, 'Text', 'Disconnected', 'FontColor', C.red, 'FontWeight', 'bold');
    btn = uibutton(g, 'Text', 'Connect', 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', 'w', ...
        'BackgroundColor', [0.16 0.55 0.32], 'ButtonPushedFcn', @(~, ~) connect());
    btn.Layout.Row = 2; btn.Layout.Column = [1 2];
    btn2 = uibutton(g, 'Text', 'Disconnect', 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', 'w', ...
        'BackgroundColor', [0.55 0.17 0.17], 'ButtonPushedFcn', @(~, ~) disconnect());
    btn2.Layout.Row = 2; btn2.Layout.Column = 3;

    g = panelGrid(col1, 'LIVE SENSOR READINGS', [5 2]);
    g.ColumnWidth = {110, '1x'};
    vDist  = reading(g, 'Distance:');
    vHum   = reading(g, 'Humidity:');
    vSound = reading(g, 'Sound:');
    vZone  = reading(g, 'Zone:');
    vMode  = reading(g, 'Alert mode:');

    g = panelGrid(col1, 'PROXIMITY ZONES', [5 1]);
    for z = 1:5
        uilabel(g, 'Text', char(9632) + "  " + zoneRange(z) + "    " + zoneName(z), ...
            'FontColor', zoneColor(z, :));
    end

    % ---------------- column 2: gauge / output indicators
    col2 = column(2, {'1.15x', '1x'});

    g = panelGrid(col2, 'EYE STRAIN RISK SCORE', [3 1]);
    g.RowHeight = {'1x', 40, 30};
    gauge = uigauge(g, 'semicircular', 'Limits', [0 1000], 'MajorTicks', 0:100:1000, ...
        'BackgroundColor', C.panel, 'FontColor', C.text, ...
        'ScaleColors', [C.green; 1 0.85 0.15; 1 0.45 0.10; C.red], ...
        'ScaleColorLimits', [0 300; 300 500; 500 700; 700 1000]);
    scoreLbl = uilabel(g, 'Text', '0', 'FontSize', 32, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'FontColor', C.green);
    stateLbl = uilabel(g, 'Text', 'SAFE', 'FontSize', 20, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'FontColor', C.green);

    g = panelGrid(col2, 'OUTPUT INDICATORS', [6 3]);
    g.RowHeight = {22, 50, 22, 50, 22, 22};
    for nm = ["GREEN", "AMBER", "RED"]
        uilabel(g, 'Text', nm, 'HorizontalAlignment', 'center', 'FontColor', C.text);
    end
    lampG = uilamp(g, 'Color', C.off);
    lampA = uilamp(g, 'Color', C.off);
    lampR = uilamp(g, 'Color', C.off);
    l = uilabel(g, 'Text', 'VIBRATION MOTOR', 'HorizontalAlignment', 'center', 'FontColor', C.text);
    l.Layout.Row = 3; l.Layout.Column = [1 3];
    lampV = uilamp(g, 'Color', C.off); lampV.Layout.Row = 4; lampV.Layout.Column = 2;
    alertLbl = uilabel(g, 'Text', '', 'HorizontalAlignment', 'center', 'FontColor', C.green);
    alertLbl.Layout.Row = 5; alertLbl.Layout.Column = [1 3];
    lastLine = uilabel(g, 'Text', 'Last serial line:', 'FontColor', C.dim, 'FontSize', 10);
    lastLine.Layout.Row = 6; lastLine.Layout.Column = [1 3];

    % ---------------- column 3: live data plots
    g = panelGrid(root, 'LIVE DATA', [2 1], 2, 3);
    axD = darkAxes(g, 'Distance (cm)', 'cm', [0 400]);
    bands = [0 30; 30 40; 40 60; 60 100];
    for b = 1:4
        patch(axD, [0 WINDOW WINDOW 0], bands(b, [1 1 2 2]), zoneColor(b, :), ...
            'FaceAlpha', 0.12, 'EdgeColor', 'none');
    end
    distLine = plot(axD, NaN, NaN, '-', 'Color', C.value, 'LineWidth', 2);
    axE = darkAxes(g, 'ESRS', 'Score', [0 1100]);
    plot(axE, [0 WINDOW], [1000 1000], '--', 'Color', C.red, 'LineWidth', 1.2);
    text(axE, WINDOW - 0.5, 1040, 'MAX', 'Color', C.red, 'HorizontalAlignment', 'right');
    esrsLine = plot(axE, NaN, NaN, '-', 'Color', C.amber, 'LineWidth', 2);

    footer = uilabel(root, 'Text', ['Live mode ' char(8212) ' Arduino handles all sensor logic, MATLAB visualises'], ...
        'FontColor', C.dim, 'FontSize', 10);
    footer.Layout.Row = 3; footer.Layout.Column = [1 3];

    showLine('DIST:400.0,HUM:0,SOUND:0,ZONE:4,INC:-3,ESRS:0,LED:0,BLINK:0,VIB:0,MODE:2');

    tmr = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, 'BusyMode', 'drop', ...
                'TimerFcn', @(~, ~) onTimer());
    fig.CloseRequestFcn = @(~, ~) onClose();
    start(tmr);
    if port == "demo", startDemo(); elseif strlength(port) > 0, connect(); end

    % ============================================================ connection
    function connect()
        disconnect();
        try
            sp = serialport(portField.Value, BAUD, 'Timeout', 0.5);
            configureTerminator(sp, "CR/LF");
            flush(sp);
            clearHistory();
            statusLbl.Text = 'Connected'; statusLbl.FontColor = C.green;
            subtitle.Text = ['LIVE ' char(8212) ' reading sensors from Arduino'];
        catch err
            sp = [];
            uialert(fig, sprintf('Could not open "%s":\n%s', portField.Value, err.message), ...
                'Connection failed');
        end
    end

    function disconnect()
        if ~isempty(sp), try, delete(sp); catch, end, end
        sp = []; demo = false;
        statusLbl.Text = 'Disconnected'; statusLbl.FontColor = C.red;
        subtitle.Text = 'Not connected';
    end

    function startDemo()
        disconnect();
        demo = true; demoState = struct('esrs', 0, 't', 0, 'next', 0); clearHistory();
        statusLbl.Text = 'Demo'; statusLbl.FontColor = C.amber;
        subtitle.Text = ['DEMO ' char(8212) ' scripted session, no hardware connected'];
    end

    % ================================================================ timer
    function onTimer()
        if ~isvalid(fig), return; end
        try
            if ~isempty(sp)
                while sp.NumBytesAvailable > 0
                    ln = readline(sp);
                    if isempty(ln), break; end      % partial line, wait for the rest
                    showLine(strtrim(ln));
                end
            elseif demo && toc(t0) >= demoState.next
                demoState.next = toc(t0) + 1;       % one tick per second, like the board
                showLine(demoTick());
            end
            animate();
        catch err
            lastLine.Text = ['Error: ' err.message];
        end
    end

    % ============================================================ rendering
    function showLine(ln)
        lastLine.Text = "Last serial line: " + ln;
        tok = regexp(char(ln), '([A-Z]+):(-?[\d.]+)', 'tokens');
        if isempty(tok), return; end
        s = struct();
        for k = 1:numel(tok), s.(tok{k}{1}) = str2double(tok{k}{2}); end
        if ~all(isfield(s, {'DIST', 'ESRS', 'ZONE', 'LED'})), return; end
        s = defaults(s);

        % readings
        vDist.Text = sprintf('%.1f cm', s.DIST);
        if s.HUM > 0 && s.HUM < 40
            vHum.Text = sprintf('%d %%  (Dry)', s.HUM);   vHum.FontColor = C.amber;
        else
            vHum.Text = sprintf('%d  (Normal)', s.HUM);   vHum.FontColor = C.value;
        end
        vSound.Text = ifelse(s.SOUND, 'Loud', 'Quiet');
        vSound.FontColor = ifelse(s.SOUND, C.amber, C.green);
        vZone.Text = zoneName(s.ZONE + 1);  vZone.FontColor = zoneColor(s.ZONE + 1, :);
        vMode.Text = modeName(s.MODE + 1);  vMode.FontColor = C.green;

        % score
        gauge.Value = min(s.ESRS, 1000);
        scoreLbl.Text = sprintf('%.0f', s.ESRS);
        if s.BLINK,        txt = 'TOO CLOSE!';   col = C.red;
        elseif s.LED == 2, txt = 'TAKE A BREAK'; col = C.red;
        elseif s.LED == 1, txt = 'WARNING';      col = C.amber;
        else,              txt = 'SAFE';         col = C.green;
        end
        stateLbl.Text = txt; stateLbl.FontColor = col; scoreLbl.FontColor = col;

        % LEDs (the danger-zone blink is animated in animate())
        ledsOn = s.MODE ~= 2;
        lampG.Color = ifelse(s.LED == 0 && ~s.BLINK, C.green, C.off);
        lampA.Color = ifelse(ledsOn && s.LED == 1 && ~s.BLINK, C.amber, C.off);
        lampR.Color = ifelse(ledsOn && s.LED == 2 && ~s.BLINK, C.red, C.off);
        blinkRed = ledsOn && s.BLINK;
        vibOn = logical(s.VIB);
        alertLbl.Text = "Alert: " + modeName(s.MODE + 1);

        % history
        t = toc(t0);
        H.t(end+1, 1) = t; H.dist(end+1, 1) = s.DIST; H.esrs(end+1, 1) = s.ESRS;
        keep = H.t > t - WINDOW;
        H.t = H.t(keep); H.dist = H.dist(keep); H.esrs = H.esrs(keep);
        x = H.t - (t - WINDOW);              % newest sample at the right edge
        set(distLine, 'XData', x, 'YData', H.dist);
        set(esrsLine, 'XData', x, 'YData', H.esrs);
    end

    function animate()
        phase = mod(floor(toc(t0) * 4), 2) == 1;        % 2 Hz, like the board
        if blinkRed, lampR.Color = ifelse(phase, C.red, C.off); end
        lampV.Color = ifelse(vibOn && phase, [0.75 0.45 1.00], C.off);
    end

    function clearHistory()
        H = struct('t', zeros(0, 1), 'dist', zeros(0, 1), 'esrs', zeros(0, 1));
        set(distLine, 'XData', NaN, 'YData', NaN);
        set(esrsLine, 'XData', NaN, 'YData', NaN);
    end

    function onClose()
        try, stop(tmr); delete(tmr); catch, end
        disconnect();
        delete(fig);
    end

    % ============================================================== demo mode
    % Plays the same rules as the firmware (esrs.h) over a scripted session
    % and feeds the result through showLine(), exactly like serial data.
    function ln = demoTick()
        % [until_s, distance_cm, humidity_pct, loud]
        script = [ 8 400 45 0;  20 70 45 0;  40 45 45 0;  70 35 32 0;
                  80 25 32 1;  110 35 32 1;  150 400 45 0;  165 65 45 0];
        tt = mod(demoState.t, script(end, 1));
        row = script(find(tt < script(:, 1), 1), :);
        d = row(2); if d < 400, d = d + 2 * sin(demoState.t / 3); end
        inc = [6 4 2 1 -3];
        zone = 1 + (d >= 30) + (d >= 40) + (d >= 60) + (d >= 100);
        step = inc(zone);
        if zone < 5 && d < 60
            if row(3) < 40, step = step * 1.3; end
            if row(4),      step = step * 1.2; end
        end
        demoState.esrs = min(max(demoState.esrs + step * 8, 0), 1000);   % x8: demo speed
        demoState.t = demoState.t + 1;
        e = demoState.esrs;
        led = (e >= 300) + (e >= 700);
        blink = zone == 1;
        ln = sprintf('DIST:%.1f,HUM:%d,SOUND:%d,ZONE:%d,INC:%.1f,ESRS:%.1f,LED:%d,BLINK:%d,VIB:%d,MODE:0', ...
            d, row(3), row(4), zone - 1, step, e, led, blink, blink || led == 2);
    end

    % ============================================================ UI helpers
    function c = column(n, heights)
        c = uigridlayout(root, [numel(heights) 1], 'BackgroundColor', C.bg, 'Padding', [0 0 0 0]);
        c.Layout.Row = 2; c.Layout.Column = n; c.RowHeight = heights;
    end

    function g = panelGrid(parent, ttl, sz, row, col)
        p = uipanel(parent, 'Title', ttl, 'FontWeight', 'bold', 'FontSize', 14, ...
            'BackgroundColor', C.panel, 'ForegroundColor', C.title, 'BorderType', 'line');
        if nargin > 3, p.Layout.Row = row; p.Layout.Column = col; end
        g = uigridlayout(p, sz, 'BackgroundColor', C.panel);
    end

    function v = reading(g, name)
        uilabel(g, 'Text', name, 'FontColor', C.text);
        v = uilabel(g, 'Text', '--', 'FontColor', C.value, 'FontSize', 16, 'FontWeight', 'bold');
    end

    function ax = darkAxes(parent, ttl, yl, lims)
        ax = uiaxes(parent, 'Color', [0.12 0.13 0.17], 'XColor', C.dim, 'YColor', C.dim);
        title(ax, ttl, 'Color', C.text);
        xlabel(ax, 'Time (s)'); ylabel(ax, yl);
        xlim(ax, [0 WINDOW]); ylim(ax, lims); hold(ax, 'on'); box(ax, 'off');
    end
end

% ============================================================================
function s = defaults(s)
    f = {'HUM', 'SOUND', 'INC', 'BLINK', 'VIB', 'MODE'};
    for k = 1:numel(f)
        if ~isfield(s, f{k}) || isnan(s.(f{k})), s.(f{k}) = 0; end
    end
end

function out = ifelse(c, a, b)
    if c, out = a; else, out = b; end
end
