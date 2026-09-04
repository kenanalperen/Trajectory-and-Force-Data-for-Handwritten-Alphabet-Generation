%% ============================================================
%  Data_Analysis.m
%  Trajectory and Force Data for Handwritten Alphabet Generation
%
%  HOW TO USE IN LIVE EDITOR:
%    1. Open MATLAB -> Home tab -> Open -> select this file
%    2. MATLAB will ask to convert to Live Script -> click "Convert"
%    3. Run Section 1 ONCE to load all CSVs into exp_data struct
%    4. Edit USER SETTINGS then run Section 2 to browse a character
%    5. Run Section 3 for full dataset statistics
%
%  Struct format after loading:
%    exp_data.<Letter>_<Case>.P<n>_<rep>.{x, y, t, f}
%  Example:
%    exp_data.L_Lowercase.P7_1.x
% =============================================================

%% ============================================================
%  USER SETTINGS  <- EDIT HERE
% =============================================================

VIS_CHARACTER = 'B';          % Character letter  (string)
VIS_CASE      = 'Uppercase';  % 'Uppercase' or 'Lowercase'
VIS_MODE      = 2;            % 1 = three 2D panels  |  2 = 3D view

% =============================================================
%  (No need to edit below this line)
% =============================================================

%% -- SECTION 1: LOAD ALL CSVs --------------------------------
%  Skips reload if exp_data is already in workspace.
%  To reload: type   clear exp_data   then re-run.

CSV_FOLDER = 'Experiment_Character_Data_csv';

if ~isfolder(CSV_FOLDER)
    error('Folder not found: %s\nMake sure it is in your MATLAB working directory.', CSV_FOLDER);
end

if ~exist('exp_data', 'var') || ~isstruct(exp_data)

    fprintf('=== Loading CSVs from %s/ ===\n', CSV_FOLDER);
    csvFiles = dir(fullfile(CSV_FOLDER, '*.csv'));

    if isempty(csvFiles)
        error('No CSV files found in %s/', CSV_FOLDER);
    end

    exp_data = struct();
    nLoaded  = 0;

    for k = 1:numel(csvFiles)
        fname   = csvFiles(k).name;
        chField = regexprep(fname(1:end-4), '[^a-zA-Z0-9_]', '_');

        T = readtable(fullfile(CSV_FOLDER, fname), 'TextType', 'string');
        nLoaded = nLoaded + 1;
        fprintf('  [%2d]  %-22s  %5d rows\n', nLoaded, fname, height(T));

        pNums = unique(T.participant);
        for pi = 1:numel(pNums)
            pNum  = pNums(pi);
            pMask = T.participant == pNum;
            rNums = unique(T.repetition(pMask));

            for ri = 1:numel(rNums)
                rNum   = rNums(ri);
                rMask  = pMask & T.repetition == rNum;
                pField = sprintf('P%d_%d', pNum, rNum);

                exp_data.(chField).(pField).x = double(T.x_mm(rMask));
                exp_data.(chField).(pField).y = double(T.y_mm(rMask));
                exp_data.(chField).(pField).t = double(T.time(rMask));
                exp_data.(chField).(pField).f = double(T.force_N(rMask));
            end
        end
    end

    fprintf('\nexp_data ready -- %d character CSV(s) loaded.\n\n', nLoaded);

else
    fprintf('=== exp_data already loaded -- skipping reload ===\n');
    fprintf('    (clear exp_data  to force a fresh load)\n\n');
end

%% -- SECTION 2: INTERACTIVE BROWSER --------------------------

chField2 = [VIS_CHARACTER '_' VIS_CASE];
if ~isfield(exp_data, chField2)
    error('No data found for %s_%s.\nCheck VIS_CHARACTER and VIS_CASE.', ...
          VIS_CHARACTER, VIS_CASE);
end

% Build sorted list of all available (participant, repetition) entries
available = {};
pFields_all = fieldnames(exp_data.(chField2));
for k = 1:numel(pFields_all)
    tokens = regexp(pFields_all{k}, '^P(\d+)_(\d+)$', 'tokens');
    if ~isempty(tokens)
        available = [available; {str2double(tokens{1}{1}), str2double(tokens{1}{2})}]; %#ok<AGROW>
    end
end
available = sortrows(available, [1 2]);

if isempty(available)
    error('No entries found for %s', chField2);
end

fprintf('Found %d entries for %s.\n', size(available,1), chField2);
browseExpData(exp_data, chField2, available, VIS_MODE);


%% -- SECTION 3: DATASET STATISTICS ---------------------------

fprintf('\n');
fprintf('========================================================\n');
fprintf('  DATASET STATISTICS\n');
fprintf('========================================================\n\n');

charFields = fieldnames(exp_data);
nChars     = numel(charFields);

all_durations   = [];
all_nPoints     = [];
all_force_mean  = [];
all_force_max   = [];
all_force_min   = [];
all_path_length = [];
totalEntries    = 0;

fprintf('%-18s  %5s  %6s  %7s  %7s  %7s  %8s\n', ...
        'Character', 'N', 'Dur(s)', 'Fmean', 'Fmax', 'Fmin', 'PathLen');
fprintf('%s\n', repmat('-', 1, 72));

for ci = 1:nChars
    chF     = charFields{ci};
    pFields = fieldnames(exp_data.(chF));
    nEnt    = numel(pFields);
    totalEntries = totalEntries + nEnt;

    ch_dur = zeros(nEnt,1); ch_pts = zeros(nEnt,1);
    ch_fmn = zeros(nEnt,1); ch_fmx = zeros(nEnt,1);
    ch_fmi = zeros(nEnt,1); ch_pl  = zeros(nEnt,1);

    for pi = 1:nEnt
        e = exp_data.(chF).(pFields{pi});
        t = e.t - min(e.t);
        f = e.f; x = e.x; y = e.y;

        ch_dur(pi) = max(t);
        ch_pts(pi) = numel(t);
        ch_fmn(pi) = mean(f);
        ch_fmx(pi) = max(f);
        ch_fmi(pi) = min(f);
        dx = diff(x); dy = diff(y);
        ch_pl(pi)  = sum(sqrt(dx.^2 + dy.^2));
    end

    all_durations   = [all_durations;   ch_dur]; %#ok<AGROW>
    all_nPoints     = [all_nPoints;     ch_pts]; %#ok<AGROW>
    all_force_mean  = [all_force_mean;  ch_fmn]; %#ok<AGROW>
    all_force_max   = [all_force_max;   ch_fmx]; %#ok<AGROW>
    all_force_min   = [all_force_min;   ch_fmi]; %#ok<AGROW>
    all_path_length = [all_path_length; ch_pl];  %#ok<AGROW>

    fprintf('%-18s  %5d  %6.2f  %7.3f  %7.3f  %7.3f  %8.2f\n', ...
            chF, nEnt, mean(ch_dur), mean(ch_fmn), ...
            mean(ch_fmx), mean(ch_fmi), mean(ch_pl));
end

fprintf('%s\n', repmat('-', 1, 72));

fprintf('\n-- Overall Dataset Summary ------------------------------\n');
fprintf('  Characters (letter/case pairs) : %d\n',    nChars);
fprintf('  Total entries (demonstrations) : %d\n',    totalEntries);
fprintf('  Avg entries per character      : %.1f\n',  totalEntries / nChars);

fprintf('\n  Trajectory duration:\n');
fprintf('    Mean : %.3f s   Std : %.3f s   Min : %.3f s   Max : %.3f s\n', ...
        mean(all_durations), std(all_durations), ...
        min(all_durations),  max(all_durations));

fprintf('\n  Data points per trajectory:\n');
fprintf('    Mean : %.1f   Std : %.1f   Min : %d   Max : %d\n', ...
        mean(all_nPoints), std(all_nPoints), ...
        min(all_nPoints),  max(all_nPoints));

fprintf('\n  Applied force (N):\n');
fprintf('    Mean of means : %.3f N   Std : %.3f N\n', ...
        mean(all_force_mean), std(all_force_mean));
fprintf('    Overall min   : %.3f N   Overall max : %.3f N\n', ...
        min(all_force_min), max(all_force_max));

fprintf('\n  Trajectory path length (mm):\n');
fprintf('    Mean : %.2f mm   Std : %.2f mm   Min : %.2f mm   Max : %.2f mm\n', ...
        mean(all_path_length), std(all_path_length), ...
        min(all_path_length),  max(all_path_length));

fprintf('\n  Workspace area (all data combined):\n');
all_x = []; all_y = [];
for ci = 1:nChars
    chF = charFields{ci};
    for pF = fieldnames(exp_data.(chF))'
        all_x = [all_x; exp_data.(chF).(pF{1}).x]; %#ok<AGROW>
        all_y = [all_y; exp_data.(chF).(pF{1}).y]; %#ok<AGROW>
    end
end
fprintf('    X range : %.2f - %.2f mm  (span: %.2f mm)\n', ...
        min(all_x), max(all_x), max(all_x)-min(all_x));
fprintf('    Y range : %.2f - %.2f mm  (span: %.2f mm)\n', ...
        min(all_y), max(all_y), max(all_y)-min(all_y));

fprintf('\n========================================================\n\n');


%% ============================================================
%  HELPER FUNCTIONS
%% ============================================================

function browseExpData(exp_data, chField2, available, visMode)
% Interactive browser: Next/Previous buttons and keyboard arrows.

    fig = figure('Name', sprintf('Data Browser -- %s', chField2), ...
                 'Color', 'w', 'Position', [100 100 1200 720], ...
                 'WindowKeyPressFcn', @keyPressed);

    % ── Axes layout (mirrors reference script exactly) ────────
    if visMode == 1
        ax1 = axes('Parent', fig, 'Units', 'normalized', ...
                   'Position', [0.10 0.55 0.55 0.35]);
        ax2 = axes('Parent', fig, 'Units', 'normalized', ...
                   'Position', [0.10 0.30 0.55 0.20]);
        ax3 = axes('Parent', fig, 'Units', 'normalized', ...
                   'Position', [0.10 0.05 0.55 0.20]);
        axesHandles = {ax1, ax2, ax3};
    else
        ax = axes('Parent', fig, 'Units', 'normalized', ...
                  'Position', [0.10 0.15 0.55 0.75]);
        axesHandles = ax;
    end

    % ── Buttons ───────────────────────────────────────────────
    btnW = 0.12; btnH = 0.06; btnY = 0.03;
    uicontrol('Style','pushbutton','String','Next', ...
              'Units','normalized','Position',[0.65 btnY btnW btnH], ...
              'FontSize',11,'Callback',@nextCallback);
    uicontrol('Style','pushbutton','String','Previous', ...
              'Units','normalized','Position',[0.45 btnY btnW btnH], ...
              'FontSize',11,'Callback',@prevCallback);

    % ── Status text ───────────────────────────────────────────
    txtStatus = uicontrol('Style','text','String','', ...
                          'Units','normalized', ...
                          'Position',[0.05 0.93 0.60 0.04], ...
                          'HorizontalAlignment','center', ...
                          'FontSize',12,'FontWeight','bold');

    % ── Info panel (right side) ───────────────────────────────
    uicontrol('Style','text','Units','normalized', ...
              'Position',[0.72 0.85 0.25 0.08], ...
              'BackgroundColor','w','FontSize',11,'FontWeight','bold', ...
              'HorizontalAlignment','left', ...
              'String', sprintf('Character: %s', strrep(chField2,'_',' ')));

    txtInfo = uicontrol('Style','text','Units','normalized', ...
                        'Position',[0.72 0.30 0.25 0.54], ...
                        'BackgroundColor','w','FontSize',10, ...
                        'HorizontalAlignment','left','String','');

    uicontrol('Style','text','Units','normalized', ...
              'Position',[0.72 0.20 0.25 0.06], ...
              'BackgroundColor','w','FontSize',9, ...
              'ForegroundColor',[0.45 0.45 0.45], ...
              'String','Keyboard: left / right arrows');

    % ── Store user data ───────────────────────────────────────
    userData             = struct();
    userData.exp_data    = exp_data;
    userData.chField2    = chField2;
    userData.available   = available;
    userData.idx         = 1;
    userData.axesHandles = axesHandles;
    userData.fig         = fig;
    userData.txtStatus   = txtStatus;
    userData.txtInfo     = txtInfo;
    userData.cmap        = blueRedCmap(256);
    userData.visMode     = visMode;

    guidata(fig, userData);

    % First plot
    updatePlot(guidata(fig));

    if visMode == 2
        rotate3d(fig, 'on');
        datacursormode(fig, 'off');
    end

    % ── Nested callbacks ──────────────────────────────────────
    function nextCallback(~, ~)
        ud = guidata(fig);
        if ud.idx < size(ud.available, 1)
            ud.idx = ud.idx + 1;
            guidata(fig, ud);
            updatePlot(ud);
            if ud.visMode == 2
                rotate3d(fig, 'on');
            end
        else
            set(ud.txtStatus, 'String', 'Already at last entry');
            pause(0.5);
            set(ud.txtStatus, 'String', '');
        end
    end

    function prevCallback(~, ~)
        ud = guidata(fig);
        if ud.idx > 1
            ud.idx = ud.idx - 1;
            guidata(fig, ud);
            updatePlot(ud);
            if ud.visMode == 2
                rotate3d(fig, 'on');
            end
        else
            set(ud.txtStatus, 'String', 'Already at first entry');
            pause(0.5);
            set(ud.txtStatus, 'String', '');
        end
    end

    function keyPressed(~, evt)
        switch evt.Key
            case 'rightarrow', nextCallback([], []);
            case 'leftarrow',  prevCallback([], []);
        end
    end

    function updatePlot(ud)
        p     = ud.available{ud.idx, 1};
        r     = ud.available{ud.idx, 2};
        field = sprintf('P%d_%d', p, r);
        e     = ud.exp_data.(ud.chField2).(field);

        x = e.x; y = e.y;
        t = e.t - min(e.t);
        f = e.f;

        fNorm = (f - min(f)) ./ (max(f) - min(f) + eps);
        cIdx  = max(1, round(fNorm * 255) + 1);
        cols  = ud.cmap(cIdx, :);

        if ud.visMode == 1
            % ── Mode 1: three 2D subplots ─────────────────────
            axXY = ud.axesHandles{1};
            axXt = ud.axesHandles{2};
            axYt = ud.axesHandles{3};

            cla(axXY);
            scatter(axXY, x, y, 25, cols, 'filled', ...
                    'MarkerEdgeColor','none','MarkerFaceAlpha',0.85);
            xlabel(axXY,'X (mm)'); ylabel(axXY,'Y (mm)');
            title(axXY, sprintf('%s  |  P%d  Rep%d  (XY)', ...
                  strrep(ud.chField2,'_',' '), p, r));
            axis(axXY,'equal'); grid(axXY,'on');
            colormap(axXY, ud.cmap); caxis(axXY, [min(f) max(f)]);

            cla(axXt);
            scatter(axXt, t, x, 25, cols, 'filled', ...
                    'MarkerEdgeColor','none','MarkerFaceAlpha',0.85);
            xlabel(axXt,'Time (s)'); ylabel(axXt,'X (mm)');
            title(axXt,'X over Time');
            grid(axXt,'on');
            colormap(axXt, ud.cmap); caxis(axXt, [min(f) max(f)]);

            cla(axYt);
            scatter(axYt, t, y, 25, cols, 'filled', ...
                    'MarkerEdgeColor','none','MarkerFaceAlpha',0.85);
            xlabel(axYt,'Time (s)'); ylabel(axYt,'Y (mm)');
            title(axYt,'Y over Time');
            grid(axYt,'on');
            colormap(axYt, ud.cmap); caxis(axYt, [min(f) max(f)]);

            % Single colorbar — create once, update limits after
            if isempty(findobj(fig, 'Type', 'ColorBar'))
                cb = colorbar(axYt, 'Location', 'eastoutside');
                cb.Label.String   = 'Force (N)';
                cb.Label.FontSize = 11;
            else
                cb        = findobj(fig, 'Type', 'ColorBar');
                cb.Limits = [min(f) max(f)];
                colormap(ud.cmap);
            end

        else
            % ── Mode 2: 3D plot ───────────────────────────────
            ax = ud.axesHandles;
            cla(ax);
            scatter3(ax, x, y, t, 45, cols, 'filled', ...
                     'MarkerEdgeColor','none','MarkerFaceAlpha',0.85);
            xlabel(ax,'X (mm)','FontSize',12);
            ylabel(ax,'Y (mm)','FontSize',12);
            zlabel(ax,'Time (s)','FontSize',12);
            title(ax, sprintf('%s  |  P%d  Rep%d', ...
                  strrep(ud.chField2,'_',' '), p, r), ...
                  'FontSize',13,'FontWeight','bold');
            colormap(ax, ud.cmap);
            caxis(ax, [min(f) max(f)]);

            % Create colorbar once, update limits after
            if isempty(findobj(fig, 'Type', 'ColorBar'))
                cb = colorbar(ax);
                cb.Label.String   = 'Force (N)';
                cb.Label.FontSize = 11;
            else
                cb        = findobj(fig, 'Type', 'ColorBar');
                cb.Limits = [min(f) max(f)];
            end

            grid(ax,'on');
            view(ax, 0, 90);
            xlim(ax,[0 37.59]); ylim(ax,[0 37.59]);
            ax.ZDir = 'reverse';
        end

        % ── Info panel ────────────────────────────────────────
        dx = diff(x); dy = diff(y);
        pathLen = sum(sqrt(dx.^2 + dy.^2));
        infoStr = sprintf([ ...
            'Participant : %d\n'   ...
            'Repetition  : %d\n'   ...
            '------------------\n' ...
            'Points      : %d\n'   ...
            'Duration    : %.3f s\n' ...
            '------------------\n' ...
            'Force mean  : %.3f N\n' ...
            'Force max   : %.3f N\n' ...
            'Force min   : %.3f N\n' ...
            '------------------\n' ...
            'Path length : %.2f mm\n' ...
            'X range : %.1f-%.1f\n'  ...
            'Y range : %.1f-%.1f'],  ...
            p, r, numel(x), max(t), ...
            mean(f), max(f), min(f), ...
            pathLen, min(x), max(x), min(y), max(y));
        set(ud.txtInfo, 'String', infoStr);

        set(ud.txtStatus, 'String', ...
            sprintf('Entry %d of %d  |  Participant %d  |  Rep %d', ...
                    ud.idx, size(ud.available,1), p, r));
    end

end % browseExpData


function cmap = blueRedCmap(n)
    if nargin < 1, n = 256; end
    keys = [0 0 1; 0 0.5 1; 0 1 1; 0.5 1 0.5; 1 1 0; 1 0.5 0; 1 0 0];
    xi   = linspace(0, 1, size(keys,1));
    xq   = linspace(0, 1, n);
    cmap = min(max(interp1(xi, keys, xq, 'pchip'), 0), 1);
end